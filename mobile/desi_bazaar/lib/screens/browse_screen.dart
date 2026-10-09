import 'package:flutter/material.dart';

import '../api/media.dart';
import '../api/models.dart';
import '../main.dart';
import '../widgets/media_widgets.dart';
import '../widgets/widgets.dart';
import 'listing_detail_screen.dart';

/// Buyer browse / search (FR-B2). Listings show the seller badge chip inline.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _search = TextEditingController();
  List<Listing> _items = [];
  bool _loading = true;
  String? _error;
  Future<AdSlot>? _slotFuture;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([String? q]) async {
    setState(() {
      _loading = true;
      _error = null;
      // Cache the slot future per load so rebuilds don't refetch.
      _slotFuture = AppScope.of(context).api.adSlot('feed').catchError(
            (_) => AdSlot.empty(),
          );
    });
    try {
      final items = await AppScope.of(context).api.listListings(q: q);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Could not load listings — $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) => _load(q),
            decoration: InputDecoration(
              hintText: 'Search saree, kurti…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  _load();
                },
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _load(_search.text),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No listings found.'));
    }
    return RefreshIndicator(
      onRefresh: () => _load(_search.text),
      child: ListView.builder(
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          // Position 0 is the sponsored feed slot: it renders the slot
          // content when the backend serves one, otherwise nothing.
          if (i == 0) {
            return FutureBuilder<AdSlot>(
              future: _slotFuture,
              builder: (context, snap) =>
                  SponsoredSlot(slot: snap.data ?? AdSlot.empty()),
            );
          }
          return _card(_items[i - 1]);
        },
      ),
    );
  }

  Widget _card(Listing l) {
    // SC-1: promoted listings get the "Sponsored" label and a distinct
    // card. The label renders exactly when the backend says promoted —
    // never otherwise (DB-TC-189).
    final promoted = l.promoted;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: promoted ? Colors.amber.shade50 : null,
      shape: promoted
          ? RoundedRectangleBorder(
              side: BorderSide(color: Colors.amber.shade300),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        title: Text('${l.category} · ${l.condition}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Size: ${l.sizeText}'),
            const SizedBox(height: 4),
            if (promoted) ...[
              const SponsoredLabel(),
              const SizedBox(height: 4),
            ],
            SellerBadge(scope: l.sellerBadgeScope, date: l.sellerBadgeDate),
          ],
        ),
        trailing: Text(
          '${l.priceSek} kr',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        isThreeLine: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: l)),
        ),
      ),
    );
  }
}
