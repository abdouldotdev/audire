import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'speech_engine.dart';

class AudioCacheEntry {
  const AudioCacheEntry({
    required this.id,
    required this.digest,
    required this.chapter,
    required this.segment,
    required this.durationMs,
    required this.bytes,
    required this.quality,
    required this.updatedAt,
  });

  final String id;
  final String digest;
  final int chapter;
  final int segment;
  final int durationMs;
  final int bytes;
  final SyncQuality quality;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'id': id,
    'digest': digest,
    'chapter': chapter,
    'segment': segment,
    'durationMs': durationMs,
    'bytes': bytes,
    'quality': quality.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory AudioCacheEntry.fromJson(Map<String, dynamic> json) {
    return AudioCacheEntry(
      id: json['id'] as String,
      digest: json['digest'] as String,
      chapter: (json['chapter'] as num? ?? -1).toInt(),
      segment: (json['segment'] as num? ?? -1).toInt(),
      durationMs: (json['durationMs'] as num? ?? 0).toInt(),
      bytes: (json['bytes'] as num? ?? 0).toInt(),
      quality: SyncQuality.values.firstWhere(
        (value) => value.name == json['quality'],
        orElse: () => SyncQuality.estimatedWord,
      ),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class AudioPlaybackCheckpoint {
  const AudioPlaybackCheckpoint({
    required this.bookId,
    required this.entryId,
    required this.chapter,
    required this.segment,
    required this.position,
    required this.duration,
    required this.audioSignature,
    required this.updatedAt,
  });

  final String bookId;
  final String entryId;
  final int chapter;
  final int segment;
  final Duration position;
  final Duration duration;
  final String audioSignature;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'bookId': bookId,
    'entryId': entryId,
    'chapter': chapter,
    'segment': segment,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'audioSignature': audioSignature,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory AudioPlaybackCheckpoint.fromJson(Map<String, dynamic> json) {
    return AudioPlaybackCheckpoint(
      bookId: json['bookId'] as String,
      entryId: json['entryId'] as String,
      chapter: (json['chapter'] as num? ?? -1).toInt(),
      segment: (json['segment'] as num? ?? -1).toInt(),
      position: Duration(
        milliseconds: (json['positionMs'] as num? ?? 0).toInt(),
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num? ?? 0).toInt(),
      ),
      audioSignature: json['audioSignature'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class AudioBookCacheInfo {
  const AudioBookCacheInfo({
    required this.bookId,
    required this.pinned,
    required this.passages,
    required this.bytes,
    required this.duration,
    required this.updatedAt,
    this.checkpoint,
  });

  final String bookId;
  final bool pinned;
  final int passages;
  final int bytes;
  final Duration duration;
  final DateTime updatedAt;
  final AudioPlaybackCheckpoint? checkpoint;
}

class _AudioBookManifest {
  _AudioBookManifest({
    required this.bookId,
    this.pinned = false,
    DateTime? updatedAt,
    Map<String, AudioCacheEntry>? entries,
    this.checkpoint,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc(),
       entries = entries ?? <String, AudioCacheEntry>{};

  final String bookId;
  bool pinned;
  DateTime updatedAt;
  final Map<String, AudioCacheEntry> entries;
  AudioPlaybackCheckpoint? checkpoint;

  Map<String, Object?> toJson() => {
    'version': 1,
    'bookId': bookId,
    'pinned': pinned,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'entries': entries.values.map((entry) => entry.toJson()).toList(),
    'checkpoint': checkpoint?.toJson(),
  };

  factory _AudioBookManifest.fromJson(Map<String, dynamic> json) {
    final values =
        (json['entries'] as List<dynamic>? ?? const [])
            .map(
              (value) => AudioCacheEntry.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList();
    final checkpoint = json['checkpoint'];
    return _AudioBookManifest(
      bookId: json['bookId'] as String,
      pinned: json['pinned'] == true,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      entries: {for (final entry in values) entry.id: entry},
      checkpoint:
          checkpoint is Map
              ? AudioPlaybackCheckpoint.fromJson(
                Map<String, dynamic>.from(checkpoint),
              )
              : null,
    );
  }
}

/// Persistent ownership index for generated speech files.
///
/// Audio blobs are content-addressed and may be shared by multiple books. The
/// manifest keeps cache deletion safe and gives the controller enough data to
/// restore an exact passage after process termination.
class AudioCacheManifestStore {
  AudioCacheManifestStore(this.root);

  final Directory root;
  Future<void> _writes = Future<void>.value();

  Directory get _manifestDirectory => Directory('${root.path}/manifests');

  String _manifestName(String bookId) {
    return sha256.convert(utf8.encode(bookId)).toString();
  }

  File _manifestFile(String bookId) {
    return File('${_manifestDirectory.path}/${_manifestName(bookId)}.json');
  }

  Future<_AudioBookManifest> _load(String bookId) async {
    final file = _manifestFile(bookId);
    if (!await file.exists()) return _AudioBookManifest(bookId: bookId);
    try {
      final json = jsonDecode(await file.readAsString());
      final manifest = _AudioBookManifest.fromJson(
        Map<String, dynamic>.from(json as Map),
      );
      if (manifest.bookId == bookId) return manifest;
    } catch (_) {
      // A damaged index must never make an otherwise valid audio cache fatal.
    }
    return _AudioBookManifest(bookId: bookId);
  }

  Future<void> _save(_AudioBookManifest manifest) async {
    await _manifestDirectory.create(recursive: true);
    final destination = _manifestFile(manifest.bookId);
    final part = File('${destination.path}.part');
    await part.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    if (await destination.exists()) await destination.delete();
    await part.rename(destination.path);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writes = _writes.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> record(String bookId, AudioCacheEntry entry) {
    return _serial(() async {
      final manifest = await _load(bookId);
      manifest.entries[entry.id] = entry;
      manifest.updatedAt = DateTime.now().toUtc();
      await _save(manifest);
    });
  }

  Future<void> saveCheckpoint(AudioPlaybackCheckpoint checkpoint) {
    return _serial(() async {
      final manifest = await _load(checkpoint.bookId);
      manifest.checkpoint = checkpoint;
      manifest.updatedAt = checkpoint.updatedAt;
      await _save(manifest);
    });
  }

  Future<AudioPlaybackCheckpoint?> checkpoint(String bookId) async {
    await _writes;
    return (await _load(bookId)).checkpoint;
  }

  Future<void> setPinned(String bookId, bool pinned) {
    return _serial(() async {
      final manifest = await _load(bookId);
      manifest.pinned = pinned;
      manifest.updatedAt = DateTime.now().toUtc();
      await _save(manifest);
    });
  }

  Future<AudioBookCacheInfo> info(String bookId) async {
    await _writes;
    final manifest = await _load(bookId);
    return _info(manifest);
  }

  Future<List<AudioBookCacheInfo>> list() async {
    await _writes;
    if (!await _manifestDirectory.exists()) return const [];
    final result = <AudioBookCacheInfo>[];
    await for (final entity in _manifestDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final manifest = _AudioBookManifest.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(await entity.readAsString()) as Map,
          ),
        );
        result.add(_info(manifest));
      } catch (_) {
        // Ignore a single damaged manifest when listing the rest of the cache.
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  AudioBookCacheInfo _info(_AudioBookManifest manifest) {
    var bytes = 0;
    var durationMs = 0;
    for (final entry in manifest.entries.values) {
      bytes += entry.bytes;
      durationMs += entry.durationMs;
    }
    return AudioBookCacheInfo(
      bookId: manifest.bookId,
      pinned: manifest.pinned,
      passages: manifest.entries.length,
      bytes: bytes,
      duration: Duration(milliseconds: durationMs),
      updatedAt: manifest.updatedAt,
      checkpoint: manifest.checkpoint,
    );
  }

  Future<Set<String>> referencedDigests({bool pinnedOnly = false}) async {
    await _writes;
    if (!await _manifestDirectory.exists()) return <String>{};
    final result = <String>{};
    await for (final entity in _manifestDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final manifest = _AudioBookManifest.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(await entity.readAsString()) as Map,
          ),
        );
        if (!pinnedOnly || manifest.pinned) {
          result.addAll(manifest.entries.values.map((entry) => entry.digest));
        }
      } catch (_) {
        // Best effort: queue files are independently protected by the engine.
      }
    }
    return result;
  }

  Future<void> removeBook(String bookId) {
    return _serial(() async {
      final manifest = await _load(bookId);
      final destination = _manifestFile(bookId);
      if (await destination.exists()) await destination.delete();
      final stillReferenced = await _referencedDigestsUnsafe();
      for (final digest in manifest.entries.values.map(
        (entry) => entry.digest,
      )) {
        if (stillReferenced.contains(digest)) continue;
        final wave = File('${root.path}/$digest.wav');
        final metadata = File('${wave.path}.json');
        if (await wave.exists()) await wave.delete();
        if (await metadata.exists()) await metadata.delete();
      }
    });
  }

  Future<void> forgetDigests(Set<String> digests) {
    if (digests.isEmpty) return Future<void>.value();
    return _serial(() async {
      if (!await _manifestDirectory.exists()) return;
      await for (final entity in _manifestDirectory.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final manifest = _AudioBookManifest.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(await entity.readAsString()) as Map,
            ),
          );
          final before = manifest.entries.length;
          manifest.entries.removeWhere(
            (_, entry) => digests.contains(entry.digest),
          );
          if (manifest.entries.length != before) {
            manifest.updatedAt = DateTime.now().toUtc();
            await _save(manifest);
          }
        } catch (_) {
          // A corrupt record is unrelated to the cache files being evicted.
        }
      }
    });
  }

  Future<Set<String>> _referencedDigestsUnsafe() async {
    if (!await _manifestDirectory.exists()) return <String>{};
    final result = <String>{};
    await for (final entity in _manifestDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final manifest = _AudioBookManifest.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(await entity.readAsString()) as Map,
          ),
        );
        result.addAll(manifest.entries.values.map((entry) => entry.digest));
      } catch (_) {
        // Ignore corrupt ownership records.
      }
    }
    return result;
  }
}
