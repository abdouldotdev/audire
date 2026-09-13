import Flutter
import AVFoundation
import UIKit
import Vision

public final class LisiereNativeTtsPlugin: NSObject, FlutterPlugin,
    FlutterStreamHandler, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var sink: FlutterEventSink?
    private var identifiers: [ObjectIdentifier: String] = [:]
    private var preparationTasks: [Int: UIBackgroundTaskIdentifier] = [:]

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
    private func localVoices(language: String? = nil) -> [AVSpeechSynthesisVoice] {
        // speechVoices enumerates available installed voices, not a cloud catalog.
        AVSpeechSynthesisVoice.speechVoices().filter {
            let code = String($0.language.lowercased().prefix(2))
            return (code == "fr" || code == "en") && (language == nil || code == language)
        }
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
        case "translateEnFr":
            result(FlutterError(code: "BERGAMOT_NOT_LINKED",
                message: "Le pipeline Flutter est prêt, mais le runtime Bergamot/Marian natif doit encore être lié à cette build iOS.", details: nil))
        case "translationStatus":
            result([
                "available": false,
                "message": "La traduction anglais → français nécessite le runtime Bergamot/Marian, qui n’est pas inclus dans cette build. La lecture reste disponible avec une voix anglaise locale."
            ])
        case "speak":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String, !text.isEmpty,
                  let id = args["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "Passage vide ou invalide.", details: nil)); return
            }
            let requested = args["voice"] as? String
            let language = args["language"] as? String ?? "fr"
            let voices = localVoices(language: language)
            let voice = requested == nil ? voices.first : voices.first { $0.identifier == requested }
            guard let voice = voice else {
                let label = language == "en" ? "anglaise" : "française"
                result(FlutterError(code: "NO_LOCAL_VOICE",
                    message: "Téléchargez une voix \(label) dans Réglages > Accessibilité > Contenu énoncé > Voix, puis rechargez les voix.", details: nil)); return
            }
            if args["enqueue"] as? Bool != true {
                synthesizer.stopSpeaking(at: .immediate)
            }
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
        case "pause":
            result(synthesizer.pauseSpeaking(at: .word))
        case "resume":
            result(synthesizer.continueSpeaking())
        case "beginAudioPreparation":
            var task = UIBackgroundTaskIdentifier.invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "Reading preparation") { [weak self] in
                self?.endPreparation(task.rawValue)
            }
            if task != .invalid { preparationTasks[task.rawValue] = task }
            result(task == .invalid ? nil : task.rawValue)
        case "endAudioPreparation":
            if let args = call.arguments as? [String: Any], let task = args["task"] as? Int {
                endPreparation(task)
            }
            result(nil)
        case "excludeFromBackup":
            guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_PATH", message: "Chemin absent.", details: nil)); return
            }
            do {
                var url = URL(fileURLWithPath: path, isDirectory: true)
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try url.setResourceValues(values)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: path)
                result(nil)
            } catch {
                result(FlutterError(code: "BACKUP_FLAG", message: error.localizedDescription, details: nil))
            }
        case "recognizeText":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String, !path.isEmpty else {
                result(FlutterError(code: "INVALID_IMAGE", message: "Image OCR absente.", details: nil)); return
            }
            let languages = args["languages"] as? [String] ?? ["fr-FR", "en-US"]
            recognizeText(path: path, languages: languages, result: result)
        case "powerStatus":
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            result([
                "batteryLevel": level < 0 ? 1.0 : Double(level),
                "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "thermal": ProcessInfo.processInfo.thermalState.rawValue
            ])
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func recognizeText(path: String, languages: [String], result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let supported = try request.supportedRecognitionLanguages()
                request.recognitionLanguages = languages.filter { supported.contains($0) }
                let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:])
                try handler.perform([request])
                let observations = (request.results ?? []).sorted {
                    let rowDifference = abs($0.boundingBox.midY - $1.boundingBox.midY)
                    if rowDifference > 0.015 { return $0.boundingBox.midY > $1.boundingBox.midY }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                let text = observations.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                DispatchQueue.main.async { result(text) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    private func endPreparation(_ identifier: Int) {
        if let task = preparationTasks.removeValue(forKey: identifier) {
            UIApplication.shared.endBackgroundTask(task)
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
