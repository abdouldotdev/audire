package app.lisiere.native_tts

import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Only voices advertised by Android as installed and not requiring a network. */
class LisiereNativeTtsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready: Boolean? = null
    private var sink: EventChannel.EventSink? = null
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val waiting = mutableListOf<Pair<MethodCall, MethodChannel.Result>>()
    private var attached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = true
        methods = MethodChannel(binding.binaryMessenger, "lisiere/native_tts")
        events = EventChannel(binding.binaryMessenger, "lisiere/native_tts/events")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        tts = TextToSpeech(binding.applicationContext) { status ->
            // Posting also avoids using tts before its constructor has returned.
            main.post {
                if (!attached) return@post
                ready = status == TextToSpeech.SUCCESS
                if (ready == true) {
                    tts?.setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(id: String?) = emit("start", id)
                        override fun onDone(id: String?) = emit("done", id)
                        @Deprecated("Android API requires this override")
                        override fun onError(id: String?) = emit("error", id,
                            mapOf("message" to "La synthèse vocale a échoué."))
                        override fun onError(id: String?, errorCode: Int) = emit("error", id,
                            mapOf("message" to "Erreur de voix système ($errorCode)."))
                        override fun onRangeStart(id: String?, start: Int, end: Int, frame: Int) =
                            emit("range", id, mapOf("start" to start, "end" to end))
                    })
                }
                val queued = waiting.toList(); waiting.clear()
                queued.forEach { (call, result) -> onMethodCall(call, result) }
            }
        }
    }

    private fun localVoices(): List<Voice> = tts?.voices.orEmpty().filter {
        it.locale.language == "fr" && !it.isNetworkConnectionRequired &&
            !it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
    }.sortedWith(compareByDescending<Voice> { it.quality }.thenBy { it.name })

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // stop must not queue behind a slow engine initialization.
        if (call.method == "stop") { tts?.stop(); result.success(null); return }
        if (call.method == "excludeFromBackup") { result.success(null); return }
        if (ready == null) { waiting.add(call to result); return }
        if (ready != true) {
            result.error("TTS_UNAVAILABLE", "Aucun moteur vocal système n’est disponible.", null)
            return
        }
        when (call.method) {
            "voices" -> result.success(localVoices().map {
                mapOf("id" to it.name, "name" to it.name,
                    "language" to it.locale.toLanguageTag(), "quality" to it.quality)
            })
            "speak" -> {
                val id = call.argument<String>("id")
                val text = call.argument<String>("text")
                val requested = call.argument<String>("voice")
                if (id.isNullOrBlank() || text.isNullOrBlank() || text.length > TextToSpeech.getMaxSpeechInputLength()) {
                    result.error("INVALID_INPUT", "Le passage à lire est vide ou trop long.", null); return
                }
                val available = localVoices()
                val voice = if (requested == null) available.firstOrNull()
                    else available.firstOrNull { it.name == requested }
                if (voice == null) {
                    result.error("NO_LOCAL_FRENCH_VOICE",
                        "Installez une voix française hors ligne dans les réglages de synthèse vocale Android, puis rechargez les voix.", null)
                    return
                }
                val speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(.65f, 1.7f)
                val engine = tts!!
                if (engine.setVoice(voice) != TextToSpeech.SUCCESS ||
                    engine.setSpeechRate(speed) != TextToSpeech.SUCCESS) {
                    result.error("VOICE_REJECTED", "Cette voix locale ne peut pas être activée.", null); return
                }
                val status = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
                if (status == TextToSpeech.SUCCESS) result.success(null)
                else result.error("SPEAK_FAILED", "La synthèse n’a pas pu démarrer.", null)
            }
            else -> result.notImplemented()
        }
    }
    private fun emit(type: String, id: String?, extra: Map<String, Any> = emptyMap()) {
        if (id == null) return
        main.post { if (attached) sink?.success(mapOf("type" to type, "id" to id) + extra) }
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
        waiting.forEach { (_, result) -> result.error("DETACHED", "Moteur arrêté.", null) }
        waiting.clear(); tts?.stop(); tts?.shutdown(); tts = null; sink = null
    }
}
