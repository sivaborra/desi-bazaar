import 'dart:io';

import 'package:video_player/video_player.dart';

/// Probe duration of a local video file. Throws on failure — the caller
/// surfaces it honestly.
Future<Duration> probeVideoDuration(String path) async {
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    return controller.value.duration;
  } finally {
    await controller.dispose();
  }
}
