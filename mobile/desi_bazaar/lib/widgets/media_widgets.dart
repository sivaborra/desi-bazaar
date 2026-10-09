// Media + ads widgets (SC-1, SC-2).
//
// - "Sponsored" label appears exactly when the backend marks a listing
//   promoted — never otherwise (DB-TC-189).
// - ListingMediaCarousel shows photos + videos; image rendering is injected
//   so widget tests never touch the network.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/media.dart';

/// "Sponsored" label chip (SC-1). Shown only on promoted listings.
class SponsoredLabel extends StatelessWidget {
  const SponsoredLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: const Text('Sponsored',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.amber.shade100,
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.campaign_outlined, size: 16),
    );
  }
}

/// Sponsored feed slot (SC-1): renders the slot content when the backend
/// serves one, otherwise collapses to nothing — never an empty box.
class SponsoredSlot extends StatelessWidget {
  const SponsoredSlot({super.key, required this.slot, this.onTap});

  final AdSlot slot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!slot.hasContent) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        title: Text(slot.headline ?? 'Sponsored pick'),
        subtitle: const SponsoredLabel(),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Photo carousel + video tiles for a listing (SC-2).
///
/// [imageBuilder] renders one image item; defaults to a network image.
/// Tests inject a fake so no HTTP happens in the test harness.
class ListingMediaCarousel extends StatelessWidget {
  const ListingMediaCarousel({
    super.key,
    required this.media,
    required this.resolveUrl,
    this.imageBuilder,
    this.height = 240,
  });

  final List<MediaItem> media;
  final String Function(MediaItem) resolveUrl;
  final Widget Function(BuildContext, MediaItem)? imageBuilder;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: PageView.builder(
        itemCount: media.length,
        itemBuilder: (context, i) {
          final m = media[i];
          if (m.kind == MediaKind.video) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VideoTile(url: resolveUrl(m)),
              ),
            );
          }
          final img = imageBuilder != null
              ? imageBuilder!(context, m)
              : Image.network(resolveUrl(m), fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _ImageFallback());
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: img),
          );
        },
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE0E0E0),
      child: Center(child: Icon(Icons.image_not_supported_outlined)),
    );
  }
}

/// Video tile: shows a play affordance first and only initialises the
/// player on tap — so lists stay cheap and widget tests never touch
/// platform channels unless they tap. Failures are shown honestly.
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.url, this.compact = false});

  final String url;
  final bool compact;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_controller != null) {
      await _controller!.play();
      setState(() {});
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Couldn’t load this video.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null && _controller!.value.isInitialized) {
      return GestureDetector(
        onTap: () async {
          if (_controller!.value.isPlaying) {
            await _controller!.pause();
          } else {
            await _controller!.play();
          }
          setState(() {});
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(_controller!),
            if (!_controller!.value.isPlaying)
              const Center(
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child:
                      Icon(Icons.play_arrow, color: Colors.white, size: 32),
                ),
              ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _loading ? null : _play,
      child: Container(
        color: Colors.black87,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.play_arrow,
                              color: Colors.white, size: 32),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.compact ? 'Video' : 'Video — tap to play',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
