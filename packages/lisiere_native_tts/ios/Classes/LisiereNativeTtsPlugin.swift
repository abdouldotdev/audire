import Flutter
import AVFoundation

public final class LisiereNativeTtsPlugin: NSObject, FlutterPlugin,
    FlutterStreamHandler, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var sink: FlutterEventSink?
    private var identifiers: [ObjectIdentifier: String] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LisiereNativeTtsPlugin()
        instance.synthesizer.delegate = instance
        // audio_session owns the playback category and focus/interruption policy.
        instance.synthesizer.usesApplicationAudioSession = true
        let methods = FlutterMethodChannel(name: "lisiere/native_tts", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        FlutterEventChannel(name: "lisiere/native_tts/events", binaryMessenger: registrar.messenger())
            .setStreamHandler(instance)
    }
    private func localVoices() -> [AVSpeechSynthesisVoice] {
        // speechVoices enumerates available installed voices, not a cloud catalog.
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("fr") }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name < $1.name
            }
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "voices":
            result(localVoices().map { ["id": $0.identifier, "name": $0.name,
                "language": $0.language, "quality": $0.quality.rawValue] as [String: Any] })
        case "speak":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String, !text.isEmpty,
                  let id = args["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "Passage vide ou invalide.", details: nil)); return
            }
            let requested = args["voice"] as? String
            let voices = localVoices()
            let voice = requested == nil ? voices.first : voices.first { $0.identifier == requested }
            guard let voice = voice else {
                result(FlutterError(code: "NO_LOCAL_FRENCH_VOICE",
                    message: "Téléchargez une voix française dans Réglages > Accessibilité > Contenu énoncé > Voix, puis rechargez les voix.", details: nil)); return
            }
            synthesizer.stopSpeaking(at: .immediate)
            // The delegate may deliver old events later. Keep IDs per utterance.
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            let speed = (args["speed"] as? NSNumber)?.floatValue ?? 1
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed))
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0
            identifiers[ObjectIdentifier(utterance)] = id
            synthesizer.speak(utterance)
            result(nil)
        case "stop":
            synthesizer.stopSpeaking(at: .immediate); result(nil)
        case "excludeFromBackup":
            guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_PATH", message: "Chemin absent.", details: nil)); return
            }
            do {
                var url = URL(fileURLWithPath: path, isDirectory: true)
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try url.setResourceValues(values)
                result(nil)
            } catch {
                result(FlutterError(code: "BACKUP_FLAG", message: error.localizedDescription, details: nil))
            }
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func emit(_ type: String, _ utterance: AVSpeechUtterance, extra: [String: Any] = [:]) {
        guard let id = identifiers[ObjectIdentifier(utterance)] else { return }
        var event: [String: Any] = ["type": type, "id": id]
        event.merge(extra) { _, new in new }
        DispatchQueue.main.async { [weak self] in self?.sink?(event) }
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        emit("start", utterance)
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        emit("range", utterance, extra: ["start": characterRange.location,
            "end": NSMaxRange(characterRange)]) // NSRange and Dart offsets are UTF-16.
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        emit("done", utterance); identifiers.removeValue(forKey: ObjectIdentifier(utterance))
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        identifiers.removeValue(forKey: ObjectIdentifier(utterance))
    }
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
