import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import '../domain/narration.dart';
import 'acoustic_aligner.dart';
import 'supertonic_runtime.dart';

class NeuralWorker {
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _responses;
  StreamSubscription<dynamic>? _listener;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _id = 0;
  Future<void>? _starting;
  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    final root = RootIsolateToken.instance;
    if (root == null) throw StateError('Isolat Flutter principal manquant.');
    _responses = ReceivePort();
    final ready = Completer<void>();
    _listener = _responses!.listen((dynamic event) {
      if (event is SendPort) {
        _port = event;
        ready.complete();
        return;
      }
      if (event is Map) {
        final reply = Map<String, dynamic>.from(event);
        final future = _pending.remove(reply['id']);
        if (future == null) return;
        if (reply['error'] != null) {
          future.completeError(StateError(reply['error'] as String));
        } else {
          future.complete(reply);
        }
      }
    });
    _isolate = await Isolate.spawn(_run, [root, _responses!.sendPort]);
    await ready.future.timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> request(Map<String, Object?> message) async {
    await start();
    final id = ++_id;
    final future = Completer<Map<String, dynamic>>();
    _pending[id] = future;
    _port!.send({...message, 'id': id});
    try {
      return await future.future.timeout(const Duration(minutes: 10));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> reset() async {
    if (_port != null) await request({'op': 'reset'});
  }

  Future<void> close() async {
    if (_port != null) {
      await request({'op': 'close'});
    }
    await _listener?.cancel();
    _responses?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
    _starting = null;
  }
}

@pragma('vm:entry-point')
Future<void> _run(List<dynamic> args) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    args[0] as RootIsolateToken,
  );
  final parent = args[1] as SendPort;
  final input = ReceivePort();
  parent.send(input.sendPort);
  SupertonicRuntime? tts;
  AcousticAligner? aligner;
  String? alignerRevision;
  await for (final dynamic packet in input) {
    final j = Map<String, dynamic>.from(packet as Map);
    final id = j['id'] as int;
    try {
      if (j['op'] == 'reset' || j['op'] == 'close') {
        await aligner?.close();
        aligner = null;
        alignerRevision = null;
        await tts?.close();
        tts = null;
        parent.send({'id': id});
        if (j['op'] == 'close') {
          input.close();
          break;
        }
        continue;
      }
      final root = j['modelPath'] as String;
      tts ??= await SupertonicRuntime.load(root);
      final narration = NarrationText.fromJson(
        Map<String, dynamic>.from(j['narration'] as Map),
      );
      final audio = await tts.generate(
        narration.spoken,
        voice: j['voice'] as String,
        steps: j['steps'] as int,
      );
      var cues = <Map<String, int>>[];
      String? warning;
      if (j['alignmentPath'] != null) {
        try {
          if (alignerRevision != j['alignmentRevision']) {
            await aligner?.close();
            aligner = await AcousticAligner.load(j['alignmentPath'] as String);
            alignerRevision = j['alignmentRevision'] as String;
          }
          cues =
              (await aligner!.align(
                audio,
                tts.sampleRate,
                narration,
              )).map((c) => c.toJson()).toList();
          if (cues.isEmpty) {
            warning =
                'Alignement incertain : suivi par phrase pour ce passage.';
          }
        } catch (e) {
          warning = 'Alignement indisponible : suivi par phrase. $e';
        }
      }
      final path = j['wavePath'] as String;
      await writeWave(path, audio, tts.sampleRate);
      final result = {
        'path': path,
        'cues': cues,
        'durationMs': (audio.length / tts.sampleRate * 1000).round(),
        'warning': warning,
      };
      final metadata = File('$path.json.part');
      await metadata.writeAsString(jsonEncode(result), flush: true);
      await metadata.rename('$path.json');
      parent.send({'id': id, ...result});
    } catch (e) {
      parent.send({'id': id, 'error': '$e'});
    }
  }
}
