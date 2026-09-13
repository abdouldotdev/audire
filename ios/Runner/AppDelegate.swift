import Flutter
import AVFoundation
import MLXAudioCore
import MLXAudioTTS
import TranslateKit
import UIKit

@available(iOS 17.0, *)
private actor QwenVoiceRuntime {
  static let shared = QwenVoiceRuntime()

  private var model: SpeechGenerationModel?
  private var loadedPath: String?
  private let speakers = Set([
    "Vivian", "Serena", "Aiden", "Ryan", "Dylan", "Eric", "Uncle Fu", "Ono Anna", "Sohee"
  ])

  func generate(
    modelPath: String,
    text: String,
    speaker: String,
    language: String,
    wavePath: String
  ) async throws -> [String: Any] {
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanText.isEmpty, cleanText.utf16.count <= 4_000 else {
      throw runtimeError("Le passage est vide ou trop long.")
    }
    guard speakers.contains(speaker) else {
      throw runtimeError("Cette voix Qwen n’est pas disponible.")
    }
    guard language == "french" || language == "english" else {
      throw runtimeError("Cette langue n’est pas disponible dans Audire.")
    }
    try requireAppContainerPath(modelPath)
    try requireAppContainerPath(wavePath)
    let manager = FileManager.default
    for relative in [
      "config.json", "model.safetensors", "vocab.json", "merges.txt",
      "speech_tokenizer/config.json", "speech_tokenizer/model.safetensors"
    ] where !manager.fileExists(atPath: (modelPath as NSString).appendingPathComponent(relative)) {
      throw runtimeError("Le pack Qwen Studio est incomplet.")
    }

    if model == nil || loadedPath != modelPath {
      model = nil
      model = try await TTS.loadModel(
        modelRepo: modelPath,
        modelType: "qwen3_tts"
      )
      loadedPath = modelPath
    }
    guard let model else { throw runtimeError("Qwen Studio n’a pas pu démarrer.") }
    let modelSpeaker = speaker.lowercased().replacingOccurrences(of: " ", with: "_")
    var samples = [Float]()
    for try await chunk in model.generateSamplesStream(
      text: cleanText,
      voice: modelSpeaker,
      refAudio: nil,
      refText: nil,
      language: language == "french" ? "French" : "English",
      streamingInterval: 1.0
    ) {
      samples.append(contentsOf: chunk)
    }
    guard !samples.isEmpty else {
      throw runtimeError("Qwen Studio a produit un fichier audio vide.")
    }
    let target = URL(fileURLWithPath: wavePath)
    let partial = URL(fileURLWithPath: wavePath + ".part")
    try manager.createDirectory(
      at: target.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if manager.fileExists(atPath: partial.path) { try manager.removeItem(at: partial) }
    try AudioUtils.writeWavFile(
      samples: samples,
      sampleRate: model.sampleRate,
      fileURL: partial
    )
    let rendered = try AVAudioFile(forReading: partial)
    let durationMs = Int((Double(rendered.length) / rendered.fileFormat.sampleRate * 1_000).rounded())
    let bytes = (try manager.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.intValue ?? 0
    guard durationMs > 0, bytes > 44 else {
      try? manager.removeItem(at: partial)
      throw runtimeError("Qwen Studio a produit un fichier audio vide.")
    }
    if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
    try manager.moveItem(at: partial, to: target)
    return ["path": wavePath, "durationMs": durationMs]
  }

  func validate(modelPath: String) async throws -> [String: Any] {
    let validationPath = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("audire-qwen-validation-\(UUID().uuidString).wav")
    defer {
      try? FileManager.default.removeItem(atPath: validationPath)
      model = nil
      loadedPath = nil
    }
    let generated = try await generate(
      modelPath: modelPath,
      text: "Bonjour, la lecture peut commencer.",
      speaker: "Vivian",
      language: "french",
      wavePath: validationPath
    )
    return ["valid": true, "durationMs": generated["durationMs"] as? Int ?? 0]
  }

  func reset() {
    model = nil
    loadedPath = nil
  }

  private func requireAppContainerPath(_ path: String) throws {
    let resolved = canonicalContainerPath(path)
    let allowedRoots = [
      canonicalContainerPath(NSHomeDirectory()),
      canonicalContainerPath(NSTemporaryDirectory()),
    ]
    guard allowedRoots.contains(where: {
      resolved == $0 || resolved.hasPrefix($0 + "/")
    }) else {
      throw runtimeError("Chemin Qwen Studio non autorisé.")
    }
  }

  private func canonicalContainerPath(_ path: String) -> String {
    let resolved = URL(fileURLWithPath: path)
      .standardizedFileURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path

    // Flutter may expose iOS container paths as /private/var/... while
    // Foundation reports the same container as /var/....
    if resolved == "/private/var" {
      return "/var"
    }
    if resolved.hasPrefix("/private/var/") {
      return String(resolved.dropFirst("/private".count))
    }
    return resolved
  }

  private func runtimeError(_ message: String) -> NSError {
    NSError(
      domain: "app.lisiere.qwen_tts",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let translationQueue = DispatchQueue(
    label: "app.lisiere.translation",
    qos: .userInitiated
  )
  private var translationKit: TranslateKit?
  private var translationModel: TranslationModel?
  private var translationModelPath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "lisiere/translation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleTranslation(call, result: result)
    }
    let qwenChannel = FlutterMethodChannel(
      name: "lisiere/qwen_tts",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    qwenChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleQwen(call, result: result)
    }
  }

  private func handleQwen(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 17.0, *) else {
      result(FlutterError(
        code: "QWEN_UNAVAILABLE",
        message: "Qwen Studio nécessite iOS 17 ou plus récent.",
        details: nil
      ))
      return
    }
    let memory = ProcessInfo.processInfo.physicalMemory
    let enoughMemory = memory >= 6 * 1_024 * 1_024 * 1_024
    if call.method == "status" {
      result([
        "available": enoughMemory,
        "physicalMemoryBytes": memory,
        "message": enoughMemory
          ? ""
          : "Qwen Studio nécessite un iPhone récent avec au moins 6 Go de mémoire."
      ])
      return
    }
    guard enoughMemory else {
      result(FlutterError(
        code: "QWEN_MEMORY",
        message: "Cet appareil n’a pas assez de mémoire pour Qwen Studio.",
        details: nil
      ))
      return
    }
    if call.method == "reset" {
      Task {
        await QwenVoiceRuntime.shared.reset()
        await MainActor.run { result(nil) }
      }
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let modelPath = arguments["modelPath"] as? String
    else {
      result(FlutterError(code: "INVALID_MODEL", message: "Pack Qwen Studio invalide.", details: nil))
      return
    }
    Task {
      do {
        let response: [String: Any]
        if call.method == "validateModel" {
          response = try await QwenVoiceRuntime.shared.validate(modelPath: modelPath)
        } else if call.method == "generate",
                  let text = arguments["text"] as? String,
                  let speaker = arguments["speaker"] as? String,
                  let language = arguments["language"] as? String,
                  let wavePath = arguments["wavePath"] as? String {
          response = try await QwenVoiceRuntime.shared.generate(
            modelPath: modelPath,
            text: text,
            speaker: speaker,
            language: language,
            wavePath: wavePath
          )
        } else {
          await MainActor.run { result(FlutterMethodNotImplemented) }
          return
        }
        await MainActor.run { result(response) }
      } catch {
        await MainActor.run {
          result(FlutterError(
            code: "QWEN_GENERATION_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private func handleTranslation(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "translationStatus":
      translationQueue.async { [weak self] in
        guard let self else { return }
        do {
          if self.translationKit == nil {
            self.translationKit = try TranslateKit()
          }
          DispatchQueue.main.async {
            result(["available": true, "message": ""])
          }
        } catch {
          DispatchQueue.main.async {
            result(["available": false, "message": "La traduction locale n’est pas disponible."])
          }
        }
      }
    case "translateEnFr":
      guard
        let arguments = call.arguments as? [String: Any],
        let text = arguments["text"] as? String,
        let modelPath = arguments["modelPath"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(FlutterError(code: "INVALID_INPUT", message: "Passage vide ou invalide.", details: nil))
        return
      }
      translationQueue.async { [weak self] in
        guard let self else { return }
        do {
          let translated = try self.translate(text, withModelAt: modelPath)
          DispatchQueue.main.async { result(translated) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "TRANSLATION_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    case "validateEnFrModel":
      guard
        let arguments = call.arguments as? [String: Any],
        let modelPath = arguments["modelPath"] as? String
      else {
        result(FlutterError(code: "INVALID_MODEL", message: "Modèle de traduction invalide.", details: nil))
        return
      }
      translationQueue.async { [weak self] in
        guard let self else { return }
        do {
          let translated = try self.translate(
            "The book is open.",
            withModelAt: modelPath
          )
          DispatchQueue.main.async { result(translated) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "MODEL_VALIDATION_FAILED",
              message: "Le modèle téléchargé ne peut pas être utilisé sur cet appareil.",
              details: error.localizedDescription
            ))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func translate(_ text: String, withModelAt modelPath: String) throws -> String {
    let manager = FileManager.default
    let model = (modelPath as NSString).appendingPathComponent("model.bin")
    let vocab = (modelPath as NSString).appendingPathComponent("vocab.spm")
    let lexicon = (modelPath as NSString).appendingPathComponent("lex.bin")
    guard manager.fileExists(atPath: model),
          manager.fileExists(atPath: vocab),
          manager.fileExists(atPath: lexicon) else {
      throw NSError(
        domain: "app.lisiere.translation",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Pack de traduction incomplet."]
      )
    }
    if translationKit == nil {
      translationKit = try TranslateKit()
    }
    if translationModel == nil || translationModelPath != modelPath {
      translationModel?.close()
      translationModel = try translationKit!.loadModel(
        ModelSpec(
          sourceLang: "en",
          targetLang: "fr",
          modelPath: model,
          vocabPaths: [vocab],
          shortlistPath: lexicon,
          numWorkers: 1
        )
      )
      translationModelPath = modelPath
    }
    return try translationModel!.translate(text, isHtml: false).text
  }
}
