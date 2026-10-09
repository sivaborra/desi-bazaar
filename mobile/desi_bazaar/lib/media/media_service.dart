// Media picking, client-side compression (NFR-P1) and the signed-URL
// upload flow (media-ads-contract.md v1, SC-2).
//
// Picking is behind [MediaPicker] so widget tests can inject a fake without
// touching platform channels. Image compression is pure Dart (package:image)
// so it also runs in widget tests; video duration is probed natively and
// compression attempted with video_compress (graceful fallback — see
// [MediaProcessor.prepareVideo]).
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:video_compress/video_compress.dart';

import '../api/api_client.dart';
import '../api/media.dart';
import '../api/models.dart';
import 'video_probe.dart';

/// Client-side limits (contract: max 8 images + max 2 videos per listing).
const maxListingImages = 8;
const maxListingVideos = 2;

/// NFR-P1: images are compressed to roughly this size before upload.
const targetImageBytes = 1024 * 1024;

/// Contract: video duration cap (also re-checked server-side on complete).
const maxVideoSeconds = 60;

/// Contract: video upload size cap (server 422s above this).
const maxVideoBytes = 100 * 1024 * 1024;

/// A file the user picked, before compression/upload. Carries the XFile so
/// bytes can be read on any platform (web included) without dart:io.
class PickedMedia {
  PickedMedia({required this.file, required this.kind});

  final XFile file;
  final MediaKind kind;

  String get path => file.path;
  String get fileName => file.name;
}

/// Bytes ready to upload.
class PreparedMedia {
  PreparedMedia({
    required this.bytes,
    required this.kind,
    required this.contentType,
    required this.fileName,
  });

  final Uint8List bytes;
  final MediaKind kind;
  final String contentType;
  final String fileName;
}

/// Picking behind an interface: the real implementation uses image_picker,
/// tests inject [FakeMediaPicker].
abstract class MediaPicker {
  /// Up to [max] images from the gallery.
  Future<List<PickedMedia>> pickImages({required int max});

  /// One photo from the camera.
  Future<PickedMedia?> takePhoto();

  /// One video from the gallery.
  Future<PickedMedia?> pickVideo();

  /// Recovers media lost when Android killed the activity during an external
  /// camera/gallery intent (Gemini Android review, 2026-10-09). Call when the
  /// create-listing screen (re)initialises; no-op on other platforms.
  Future<List<PickedMedia>> recoverLostMedia();
}

class ImagePickerMediaPicker implements MediaPicker {
  ImagePickerMediaPicker([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<PickedMedia>> pickImages({required int max}) async {
    final files = await _picker.pickMultiImage(limit: max);
    return files.map((f) => PickedMedia(file: f, kind: MediaKind.image)).toList();
  }

  @override
  Future<PickedMedia?> takePhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera);
    if (f == null) return null;
    return PickedMedia(file: f, kind: MediaKind.image);
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f == null) return null;
    return PickedMedia(file: f, kind: MediaKind.video);
  }

  @override
  Future<List<PickedMedia>> recoverLostMedia() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty || response.file == null) return const [];
    final kind = response.type == RetrieveType.video
        ? MediaKind.video
        : MediaKind.image;
    return [PickedMedia(file: response.file!, kind: kind)];
  }
}

/// Fake picker for widget tests: serves in-memory files, no platform
/// channels.
class FakeMediaPicker implements MediaPicker {
  @override
  Future<List<PickedMedia>> recoverLostMedia() async => const [];
  FakeMediaPicker({this.images = const [], this.video});

  /// Raw image bytes (any decodable format) served per pickImages call.
  final List<Uint8List> images;
  final Uint8List? video;

  int _imageCalls = 0;

  @override
  Future<List<PickedMedia>> pickImages({required int max}) async {
    _imageCalls++;
    return images.take(max).toList().asMap().entries.map((e) {
      final name = 'test-$_imageCalls-${e.key}.jpg';
      FakeMediaStore.register(name, e.value);
      return PickedMedia(
          file: XFile.fromData(e.value, name: name, mimeType: 'image/jpeg'),
          kind: MediaKind.image);
    }).toList();
  }

  @override
  Future<PickedMedia?> takePhoto() async {
    if (images.isEmpty) return null;
    FakeMediaStore.register('camera.jpg', images.first);
    return PickedMedia(
        file: XFile.fromData(images.first,
            name: 'camera.jpg', mimeType: 'image/jpeg'),
        kind: MediaKind.image);
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    if (video == null) return null;
    FakeMediaStore.register('clip.mp4', video!);
    return PickedMedia(
        file: XFile.fromData(video!, name: 'clip.mp4', mimeType: 'video/mp4'),
        kind: MediaKind.video);
  }
}

/// Test-only byte store so the fake picker can hand bytes to the processor
/// without touching the filesystem.
class FakeMediaStore {
  static final _store = <String, Uint8List>{};

  static void register(String key, Uint8List bytes) => _store[key] = bytes;
  static Uint8List? take(String key) => _store[key];
  static void clear() => _store.clear();
}

/// Client-side processing: compression (NFR-P1) + validation.
class MediaProcessor {
  /// Decode + resize (max 1920px on the long edge) + JPEG encode, stepping
  /// quality down until under [targetImageBytes]. Always returns JPEG bytes.
  Future<PreparedMedia> prepareImage(PickedMedia picked) async {
    final raw = await _readBytes(picked);
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw ApiException(
          422, 'Could not read “${picked.fileName}” as an image.');
    }
    var work = decoded;
    if (work.width > 1920 || work.height > 1920) {
      work = img.copyResize(work,
          width: work.width >= work.height ? 1920 : null,
          height: work.height > work.width ? 1920 : null);
    }
    var quality = 85;
    var out = Uint8List.fromList(img.encodeJpg(work, quality: quality));
    while (out.length > targetImageBytes && quality > 50) {
      quality -= 10;
      out = Uint8List.fromList(img.encodeJpg(work, quality: quality));
    }
    if (out.length > targetImageBytes) {
      final smaller = img.copyResize(work,
          width: (work.width * 0.75).round(),
          height: (work.height * 0.75).round());
      out = Uint8List.fromList(img.encodeJpg(smaller, quality: 60));
    }
    return PreparedMedia(
      bytes: out,
      kind: MediaKind.image,
      contentType: 'image/jpeg',
      fileName: picked.fileName,
    );
  }

  /// Enforce the 60s cap client-side where probing is supported (native);
  /// on web the probe is unsupported and the server re-checks on complete.
  Future<void> checkVideoDuration(PickedMedia picked) async {
    try {
      final duration = await probeVideoDuration(picked.path);
      if (duration.inSeconds > maxVideoSeconds) {
        throw ApiException(422,
            '“${picked.fileName}” is ${duration.inSeconds}s — videos are limited to $maxVideoSeconds seconds.');
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      // Probing unsupported on this platform — the backend re-checks on
      // complete (contract). The UI states the 60s limit up front.
    }
  }

  /// Best-effort compression via video_compress. Returns compressed bytes,
  /// or null when compression is unavailable on this platform — the caller
  /// then uploads the original if it is within limits (stated honestly).
  Future<Uint8List?> compressVideo(PickedMedia picked) async {
    try {
      final info = await VideoCompress.compressVideo(
        picked.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      final file = info?.file;
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Full client-side prepare for a video: duration cap, then compress (or
  /// fall back to the original within the 100MB contract limit). Only MP4
  /// survives — anything else is rejected honestly before upload.
  Future<PreparedMedia> prepareVideo(PickedMedia picked) async {
    await checkVideoDuration(picked);
    final compressed = await compressVideo(picked);
    if (compressed != null) {
      if (compressed.length > maxVideoBytes) {
        throw ApiException(422,
            '“${picked.fileName}” is still too large after compression.');
      }
      return PreparedMedia(
        bytes: compressed,
        kind: MediaKind.video,
        contentType: 'video/mp4',
        fileName: picked.fileName,
      );
    }
    final raw = await _readBytes(picked);
    final type = lookupMimeType(picked.fileName) ?? '';
    final isMp4 =
        type == 'video/mp4' || picked.fileName.toLowerCase().endsWith('.mp4');
    if (!isMp4) {
      throw ApiException(422,
          '“${picked.fileName}” is not MP4 — only MP4 videos are supported.');
    }
    if (raw.length > maxVideoBytes) {
      throw ApiException(422, '“${picked.fileName}” exceeds 100 MB.');
    }
    return PreparedMedia(
      bytes: raw,
      kind: MediaKind.video,
      contentType: 'video/mp4',
      fileName: picked.fileName,
    );
  }

  Future<Uint8List> _readBytes(PickedMedia picked) async {
    // Test fakes register bytes by file name; real files read via XFile
    // (works on every platform, web included).
    final fake = FakeMediaStore.take(picked.fileName);
    if (fake != null) return fake;
    return picked.file.readAsBytes();
  }
}

/// Orchestrates the contract's signed-URL flow per item:
/// upload-url → PUT bytes → complete → media_id. 422s surface honestly.
class MediaUploader {
  MediaUploader(this.api);

  final DesiBazaarApi api;

  /// Uploads prepared items in order, returning their media_ids.
  /// Throws [ApiException] on the first failure — the UI shows which file
  /// failed and why; nothing is silently dropped.
  Future<List<String>> uploadAll(
    List<PreparedMedia> items, {
    void Function(int done, int total)? onProgress,
  }) async {
    final ids = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final purpose =
          item.kind == MediaKind.image ? 'listing_image' : 'listing_video';
      final ticket = await api.requestMediaUploadUrl(
        purpose: purpose,
        contentType: item.contentType,
        contentLength: item.bytes.length,
      );
      await api.uploadMediaBytes(
          ticket.uploadUrl, item.bytes, item.contentType);
      final checksum = sha256.convert(item.bytes).toString();
      final done = await api.completeMediaUpload(ticket.mediaId, checksum);
      if (!done.accepted) {
        throw ApiException(422,
            '“${item.fileName}” was rejected: ${done.reason ?? 'failed server validation'}');
      }
      ids.add(ticket.mediaId);
      onProgress?.call(i + 1, items.length);
    }
    return ids;
  }
}
