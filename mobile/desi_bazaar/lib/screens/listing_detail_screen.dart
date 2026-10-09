import 'package:flutter/material.dart';

import '../api/models.dart';
import '../main.dart';
import '../widgets/media_widgets.dart';
import '../widgets/widgets.dart';
import 'order_tracker_screen.dart';

/// Listing detail: badge scope+date shown, defect disclosure prominent,
/// reserve -> checkout sheet (recipient + amount, pay-in-Swish instructions).
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listing});

  final Listing listing;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  bool _reserving = false;
  SellerPublicProfile? _seller;
  bool _sellerLoading = false;

  Future<void> _loadSeller() async {
    final sellerId = widget.listing.sellerId;
    if (sellerId == null || sellerId.isEmpty || _sellerLoading) return;
    setState(() => _sellerLoading = true);
    try {
      final p = await AppScope.of(context).api.sellerProfile(sellerId);
      if (mounted) setState(() => _seller = p);
    } catch (_) {
      // Seller profile is nice-to-have; the listing stands on its own.
    } finally {
      if (mounted) setState(() => _sellerLoading = false);
    }
  }

  Future<void> _reserve() async {
    setState(() => _reserving = true);
    try {
      final order =
          await AppScope.of(context).api.reserveListing(widget.listing.id);
      if (!mounted) return;
      AppScope.of(context).session.rememberOrder(order.id);
      setState(() => _reserving = false);
      await _showCheckout(order);
    } catch (e) {
      if (mounted) {
        setState(() => _reserving = false);
        showApiError(context, e);
      }
    }
  }

  /// Checkout sheet: immutable snapshot (recipient + amount) + honest
  /// pay-in-your-Swish-app instructions. Nothing is charged by the app.
  Future<void> _showCheckout(OrderDetail order) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(child: CheckoutSheet(order: order)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    return Scaffold(
      appBar: AppBar(title: Text('${l.category} · ${l.condition}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // SC-2: photo carousel + video tiles (empty when no media).
          ListingMediaCarousel(
            media: l.media,
            resolveUrl: (m) => AppScope.of(context).api.mediaUrl(m.mediaId),
          ),
          if (l.media.isNotEmpty) const SizedBox(height: 12),
          Text(
            '${l.priceSek} kr',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          if (l.promoted) ...[
            const SizedBox(height: 4),
            const SponsoredLabel(),
          ],
          const SizedBox(height: 8),
          Text('Category: ${l.category}'),
          Text('Size: ${l.sizeText}'),
          if (l.unitsAvailable > 0) Text('Units available: ${l.unitsAvailable}'),
          const SizedBox(height: 12),
          DefectNotice(defectDisclosure: l.defectDisclosure, condition: l.condition),
          const SizedBox(height: 12),
          const Text('Seller', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SellerBadge(scope: l.sellerBadgeScope, date: l.sellerBadgeDate),
          const SizedBox(height: 8),
          if (_seller == null)
            TextButton(
              onPressed: _loadSeller,
              child: Text(_sellerLoading ? 'Loading seller…' : 'View seller profile'),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_seller!.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Status: ${_seller!.status}'),
                    const SizedBox(height: 4),
                    const Text(
                      'Fulfilment history (evidenced vs unconfirmed shown separately):',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Text(
                      'Evidenced: ${_seller!.evidenced} · '
                      'Unconfirmed: ${_seller!.unconfirmed} · '
                      'In progress: ${_seller!.inProgress}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _reserving ? null : _reserve,
              child: Text(_reserving ? 'Reserving…' : 'Reserve this item'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Reserving locks the item for you and creates the order. '
            'You then pay the seller directly in your Swish app — Desi Bazaar never holds your money.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({super.key, required this.order});

  final OrderDetail order;

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  bool _reporting = false;

  Future<void> _reportPayment() async {
    setState(() => _reporting = true);
    try {
      final result = await AppScope.of(context).api.command(
            orderId: widget.order.id,
            operation: 'report_payment',
            expectedOrderVersion: widget.order.orderVersion,
          );
      if (!mounted) return;
      Navigator.of(context).pop(); // close sheet
      showInfo(
        context,
        result.replayed
            ? 'Already recorded — showing your order.'
            : 'Payment reported. The seller confirms once the Swish has actually arrived.',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackerScreen(orderId: widget.order.id),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _reporting = false);
        showApiError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Checkout — pay in your Swish app',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Pay to (Swish)', order.snapshotRecipient),
                    const SizedBox(height: 8),
                    _row('Amount', '${order.snapshotAmountSek} kr'),
                    const SizedBox(height: 8),
                    _row('Item', order.snapshotCategory),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'How to pay:\n'
              '1. Open your Swish app.\n'
              '2. Send the exact amount to the recipient above.\n'
              '3. Come back here and tap “I have paid”.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Desi Bazaar never touches your money — the payment goes directly to the seller.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _reporting ? null : _reportPayment,
                child: Text(_reporting ? 'Reporting…' : 'I have paid — report payment'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('I’ll pay later — track the order'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
