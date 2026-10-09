import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/media.dart';
import '../api/models.dart';
import '../main.dart';
import '../media/media_service.dart';
import '../widgets/media_widgets.dart';
import '../widgets/widgets.dart';
import 'order_tracker_screen.dart';

/// Seller home: my listings + create, incoming orders, Swish recipient.
class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({super.key});

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          _ListingsTab(),
          _SellerOrdersTab(),
          _RecipientTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory), label: 'Listings'),
          NavigationDestination(icon: Icon(Icons.inbox), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.account_balance), label: 'Recipient'),
        ],
      ),
    );
  }
}

class _ListingsTab extends StatefulWidget {
  const _ListingsTab();

  @override
  State<_ListingsTab> createState() => _ListingsTabState();
}

class _ListingsTabState extends State<_ListingsTab> {
  List<Listing> _items = [];
  bool _loading = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // BUG-005 fixed: the API now returns seller_id, so this is a true
      // "my listings" list filtered to the signed-in seller's principal.
      final all = await AppScope.of(context).api.listListings();
      final mine = all
          .where((l) => l.sellerId == AppScope.of(context).session.principal)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = mine;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  void _openPromote(BuildContext context, Listing l) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: _PromoteSheet(listing: l)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create listing'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CreateListingScreen()))
                  .then((_) => _load()),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('No listings yet. Create your first one!'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final l = _items[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text('${l.category} · ${l.condition}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Size: ${l.sizeText}'),
                                if (l.promoted) ...[
                                  const SizedBox(height: 4),
                                  const SponsoredLabel(),
                                ],
                              ],
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${l.priceSek} kr',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () =>
                                      _openPromote(context, l),
                                  child: const Text('Promote'),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key, this.mediaPicker});

  /// Injected for widget tests (fake picker, no platform channels).
  final MediaPicker? mediaPicker;

  @override
  State<CreateListingScreen> createState() => CreateListingScreenState();
}

class CreateListingScreenState extends State<CreateListingScreen> {
  final _category = TextEditingController();
  final _condition = TextEditingController();
  final _size = TextEditingController();
  final _defects = TextEditingController();
  final _price = TextEditingController();
  bool _busy = false;
  String? _progress;

  final List<PickedMedia> _photos = [];
  final List<PickedMedia> _videos = [];

  MediaPicker get _picker => widget.mediaPicker ?? ImagePickerMediaPicker();

  bool _recovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Android process death during camera/gallery intent: recover anything
    // the OS kept for us (Gemini Android review, 2026-10-09).
    if (!_recovered) {
      _recovered = true;
      _picker.recoverLostMedia().then((lost) {
        if (!mounted || lost.isEmpty) return;
        setState(() {
          for (final m in lost) {
            if (m.kind == MediaKind.video) {
              if (_videos.length < maxListingVideos) _videos.add(m);
            } else if (_photos.length < maxListingImages) {
              _photos.add(m);
            }
          }
        });
        showInfo(context, 'Recovered ${lost.length} photo(s)/video(s) from the interrupted capture.');
      });
    }
  }

  @override
  void dispose() {
    _category.dispose();
    _condition.dispose();
    _size.dispose();
    _defects.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    if (_photos.length >= maxListingImages) {
      showInfo(context, 'Maximum $maxListingImages photos per listing.');
      return;
    }
    try {
      final picked =
          await _picker.pickImages(max: maxListingImages - _photos.length);
      if (!mounted) return;
      setState(() => _photos.addAll(picked));
      if (_photos.length >= maxListingImages) {
        showInfo(context, 'Photo limit reached ($maxListingImages).');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= maxListingImages) {
      showInfo(context, 'Maximum $maxListingImages photos per listing.');
      return;
    }
    try {
      final picked = await _picker.takePhoto();
      if (!mounted || picked == null) return;
      setState(() => _photos.add(picked));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _addVideo() async {
    if (_videos.length >= maxListingVideos) {
      showInfo(
          context, 'Maximum $maxListingVideos videos per listing (60s each).');
      return;
    }
    try {
      final picked = await _picker.pickVideo();
      if (!mounted || picked == null) return;
      setState(() => _videos.add(picked));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _submit() async {
    final price = int.tryParse(_price.text.trim());
    if (_category.text.trim().isEmpty ||
        _condition.text.trim().isEmpty ||
        _size.text.trim().isEmpty ||
        price == null ||
        price < 1) {
      showInfo(
          context, 'Fill category, condition, size and a price of at least 1 kr.');
      return;
    }
    setState(() {
      _busy = true;
      _progress = _photos.isEmpty && _videos.isEmpty
          ? 'Creating listing…'
          : 'Compressing media…';
    });
    try {
      final api = AppScope.of(context).api;
      final processor = MediaProcessor();
      final prepared = <PreparedMedia>[];
      for (final p in _photos) {
        setState(() => _progress = 'Compressing ${p.fileName}…');
        prepared.add(await processor.prepareImage(p));
      }
      for (final v in _videos) {
        setState(() => _progress = 'Processing ${v.fileName}…');
        prepared.add(await processor.prepareVideo(v));
      }
      List<String> mediaIds = const [];
      if (prepared.isNotEmpty) {
        final uploader = MediaUploader(api);
        mediaIds = await uploader.uploadAll(
          prepared,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _progress = 'Uploading $done of $total…');
            }
          },
        );
      }
      if (!mounted) return;
      setState(() => _progress = 'Creating listing…');
      final id = await api.createListing(
        category: _category.text.trim(),
        condition: _condition.text.trim(),
        sizeText: _size.text.trim(),
        defectDisclosure:
            _defects.text.trim().isEmpty ? null : _defects.text.trim(),
        priceSek: price,
        mediaIds: mediaIds,
      );
      if (!mounted) return;
      showInfo(context, 'Listing created ($id).');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
        // 422s (too big, wrong type, server rejection) surface honestly.
        showApiError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create listing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_category, 'Category', 'e.g. Saree'),
          _field(_condition, 'Condition', 'e.g. New, Like new, Good'),
          _field(_size, 'Size', 'e.g. M, Free size'),
          _field(_defects, 'Defect disclosure (honest, prominent later)',
              'e.g. Small stain on the border — or leave empty',
              maxLines: 2),
          _field(_price, 'Price (SEK)', 'e.g. 499', numeric: true),
          const SizedBox(height: 8),
          _MediaSection(
            title: 'Photos',
            count: _photos.length,
            max: maxListingImages,
            hint: 'Up to $maxListingImages photos. Compressed on your phone before upload (NFR-P1).',
            onAddGallery: _addPhotos,
            onAddCamera: _takePhoto,
            items: _photos,
            onRemove: (p) => setState(() => _photos.remove(p)),
          ),
          const SizedBox(height: 8),
          _MediaSection(
            title: 'Videos',
            count: _videos.length,
            max: maxListingVideos,
            hint:
                'Up to $maxListingVideos videos, $maxVideoSeconds seconds each (checked here and again on the server).',
            onAddGallery: _addVideo,
            onAddCamera: null,
            items: _videos,
            onRemove: (v) => setState(() => _videos.remove(v)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Clothes only in Phase 1. Your defect disclosure is shown prominently to buyers.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          if (_busy && _progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_progress!)),
                ],
              ),
            ),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Working…' : 'Create listing'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {bool numeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
      ),
    );
  }
}

/// Photo/video picker section with thumbnails and remove buttons.
class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.title,
    required this.count,
    required this.max,
    required this.hint,
    required this.onAddGallery,
    required this.onAddCamera,
    required this.items,
    required this.onRemove,
  });

  final String title;
  final int count;
  final int max;
  final String hint;
  final VoidCallback onAddGallery;
  final VoidCallback? onAddCamera;
  final List<PickedMedia> items;
  final void Function(PickedMedia) onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title ($count/$max)',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(hint,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(title == 'Photos' ? 'Gallery' : 'Add video'),
                  onPressed: onAddGallery,
                ),
                if (onAddCamera != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                    onPressed: onAddCamera,
                  ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.map((p) => _thumb(context, p)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context, PickedMedia p) {
    return Stack(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.black12,
          ),
          clipBehavior: Clip.antiAlias,
          child: p.kind == MediaKind.video
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_outlined),
                    Text('Video', style: TextStyle(fontSize: 10)),
                  ],
                )
              : FutureBuilder<Uint8List>(
                  future: p.file.readAsBytes(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    return Image.memory(snap.data!, fit: BoxFit.cover);
                  },
                ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: GestureDetector(
            onTap: () => onRemove(p),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Incoming orders: orders this device knows about where the session
/// principal is the seller. (Slice-1 has no seller order inbox endpoint;
/// the app is honest about this being device-local tracking.)
class _SellerOrdersTab extends StatelessWidget {
  const _SellerOrdersTab();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final ids = session.knownOrderIds;
        if (ids.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No orders on this device yet.\nOrders appear here once a buyer reserves one of your listings on this device.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (context, i) => FutureBuilder<OrderDetail>(
            future: AppScope.of(context).api.getOrder(ids[i]),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const ListTile(title: Text('Loading…'));
              }
              final o = snap.data!;
              if (o.sellerId != session.principal) {
                return const SizedBox.shrink();
              }
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text('${o.snapshotCategory} · ${o.snapshotAmountSek} kr'),
                  subtitle: Text(
                      'Payment: ${o.dimensions.payment}\nFulfilment: ${o.dimensions.fulfilment}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OrderTrackerScreen(orderId: o.id))),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Swish recipient change (FR-S6): fresh-OTP gate, hold + admin re-verify.
class _RecipientTab extends StatefulWidget {
  const _RecipientTab();

  @override
  State<_RecipientTab> createState() => _RecipientTabState();
}

class _RecipientTabState extends State<_RecipientTab> {
  final _recipient = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final value = _recipient.text.trim();
    if (value.isEmpty) {
      showInfo(context, 'Enter the new Swish recipient (phone number).');
      return;
    }
    setState(() => _busy = true);
    try {
      final j = await AppScope.of(context).api.changeRecipient(value);
      if (!mounted) return;
      setState(() => _busy = false);
      showInfo(
        context,
        (j['message'] ??
                'Recipient updated. New orders are blocked until an admin re-verifies.')
            .toString(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showApiError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Swish recipient',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Card(
          color: Color(0xFFFFF3E0),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Security (FR-S6): changing the recipient requires a fresh OTP '
              'verification first. The change puts new orders on hold until an '
              'admin re-verifies — this protects you and your buyers.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _recipient,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'New Swish recipient',
            hintText: '+46700123456',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy ? null : _change,
          child: Text(_busy ? 'Updating…' : 'Change recipient'),
        ),
      ],
    );
  }
}

/// Promote a listing (SC-1): day picker with prices from /v1/ads/config,
/// stub payment, then the honest "pending admin review" state.
///
/// A promotion only goes live after an admin approves it — paying does not
/// buy placement by itself.
class _PromoteSheet extends StatefulWidget {
  const _PromoteSheet({required this.listing});

  final Listing listing;

  @override
  State<_PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends State<_PromoteSheet> {
  AdsConfig? _config;
  int? _days;
  bool _loading = true;
  bool _busy = false;
  Promotion? _promotion;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope.of(context) is illegal in initState (same BUG-002 class).
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final c = await AppScope.of(context).api.adsConfig();
      if (!mounted) return;
      setState(() {
        _config = c;
        _days = c.dayOptions.isEmpty ? null : c.dayOptions.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
      Navigator.of(context).pop();
    }
  }

  Future<void> _pay() async {
    if (_days == null) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      var promo =
          await api.createPromotion(listingId: widget.listing.id, days: _days!);
      if (promo.pendingPayment) {
        // Slice stub: payment is a stub call. Production: Swish Företag to
        // Baltic Systems AB (platform revenue, separate from marketplace
        // payments) — never the buyer's money.
        promo = await api.payPromotion(promo.promotionId);
      }
      if (!mounted) return;
      setState(() {
        _promotion = promo;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showApiError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Promote “${widget.listing.category} · ${widget.listing.condition}”',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_promotion != null)
              _doneCard()
            else
              _picker(),
          ],
        ),
      ),
    );
  }

  Widget _picker() {
    final c = _config!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Promoted listings rank first and carry a “Sponsored” label. '
          'Payment here is platform revenue — it never touches buyer money.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        RadioGroup<int>(
          groupValue: _days,
          onChanged: (v) => setState(() => _days = v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in c.dayOptions)
                RadioListTile<int>(
                  title: Text('$d ${d == 1 ? 'day' : 'days'}'),
                  secondary: Text('${c.prices[d]} ${c.currency}'),
                  value: d,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy || _days == null ? null : _pay,
            child: Text(_busy
                ? 'Processing…'
                : 'Pay ${c.prices[_days]} ${c.currency} (stub)'),
          ),
        ),
      ],
    );
  }

  Widget _doneCard() {
    final p = _promotion!;
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.pendingReview
                  ? 'Pending admin review'
                  : 'Promotion ${p.state}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your promotion goes live only after an admin approves it. '
              'You’ll see the “Sponsored” label on your listing once it is active.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
