import 'package:flutter/material.dart';

import '../api/models.dart';
import '../main.dart';
import '../widgets/widgets.dart';

/// Order tracker: the five dimensions shown honestly, plus the actions each
/// role may take from the current state. Guard failures (422), conflicts
/// (409) and denials (403) surface as readable messages — never silent.
class OrderTrackerScreen extends StatefulWidget {
  const OrderTrackerScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderTrackerScreen> createState() => _OrderTrackerScreenState();
}

class _OrderTrackerScreenState extends State<OrderTrackerScreen> {
  OrderDetail? _order;
  bool _loading = true;
  String? _error;
  int _rating = 5;
  final _reviewText = TextEditingController();
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
    _reviewText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order =
          await AppScope.of(context).api.getOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Could not load order — $e';
      });
    }
  }

  Future<void> _run(String operation,
      {Map<String, dynamic> payload = const {},
      Map<String, dynamic> cmdContext = const {},
      String? doneMessage}) async {
    final scope = AppScope.of(context);
    final order = _order;
    if (order == null) return;
    final result = await scope.api.command(
      orderId: order.id,
      operation: operation,
      expectedOrderVersion: order.orderVersion,
      payload: payload,
      context: cmdContext,
    );
    // Refresh from the authoritative result; replayed results are still
    // applied so the tracker never shows a stale private guess.
    final fresh = await scope.api.getOrder(order.id);
    if (!mounted) return;
    setState(() => _order = fresh);
    if (doneMessage != null && mounted) {
      showInfo(
        context,
        result.replayed ? 'Already recorded — refreshed.' : doneMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order tracker')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _tracker(context),
    );
  }

  Widget _tracker(BuildContext context) {
    final order = _order!;
    final role = AppScope.of(context).session.role;
    final d = order.dimensions;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Order ${order.id}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              '${order.snapshotCategory} · ${order.snapshotAmountSek} kr → ${order.snapshotRecipient}'),
          const SizedBox(height: 12),
          const Text('Status — five dimensions',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DimensionChips(dimensions: d),
          const SizedBox(height: 20),
          const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _actionsFor(role, d),
          ),
          const SizedBox(height: 20),
          const Text('Review', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _reviewSection(),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(String role, OrderDimensions d) {
    final actions = <Widget>[];
    void add(String label, String operation,
        {IconData icon = Icons.play_arrow,
        Map<String, dynamic> payload = const {},
        Map<String, dynamic> cmdContext = const {},
        String? doneMessage}) {
      actions.add(ActionButton(
        label: label,
        icon: icon,
        onPressed: () => _run(operation,
            payload: payload, cmdContext: cmdContext, doneMessage: doneMessage),
      ));
    }

    if (role == 'buyer') {
      if (d.payment == 'payment_unreported') {
        add('Report payment', 'report_payment',
            icon: Icons.payments,
            doneMessage: 'Payment reported. The seller confirms once the Swish has arrived.');
      }
      if (d.fulfilment == 'dispatched' ||
          d.fulfilment == 'delivery_unconfirmed' ||
          d.fulfilment == 'delivery_evidenced') {
        add('Confirm receipt', 'confirm_receipt',
            icon: Icons.check_circle,
            doneMessage: 'Receipt confirmed. Thank you!');
      }
      if (d.cancelRefund == 'no_cancel') {
        add('Request cancellation', 'request_cancellation',
            icon: Icons.cancel_outlined,
            doneMessage: 'Cancellation requested.');
      }
      if (d.ret == 'return_none' &&
          (d.fulfilment == 'receipt_confirmed' ||
              d.fulfilment == 'delivery_evidenced')) {
        add('Request return', 'request_return',
            icon: Icons.undo,
            doneMessage: 'Return requested. The seller authorises it next.');
      }
      if (d.dispute == 'dispute_none') {
        add('Open dispute', 'open_dispute',
            icon: Icons.gavel,
            doneMessage: 'Dispute opened. An admin will decide.');
      }
      if (d.cancelRefund == 'refund_reported') {
        add('Acknowledge refund', 'acknowledge_refund',
            icon: Icons.thumb_up,
            doneMessage: 'Refund acknowledged.');
        add('Contest refund', 'contest_refund',
            icon: Icons.thumb_down,
            doneMessage: 'Refund contested.');
      }
    }

    if (role == 'seller') {
      if (d.payment == 'payment_reported') {
        // Honest label: the seller must only confirm after the Swish money
        // has actually arrived in their account.
        add('Confirm payment (only after the Swish has actually arrived)',
            'confirm_payment',
            icon: Icons.verified,
            cmdContext: const {'swish_verified': true},
            doneMessage: 'Payment confirmed.');
      }
      if (d.fulfilment == 'stock_reserved' &&
          d.payment == 'payment_seller_confirmed') {
        add('Dispatch item', 'dispatch',
            icon: Icons.local_shipping,
            doneMessage: 'Marked as dispatched.');
      }
      if (d.cancelRefund == 'refund_requested') {
        add('Report refund sent', 'report_refund',
            icon: Icons.money_off,
            doneMessage: 'Refund reported as sent.');
      }
      if (d.ret == 'return_requested') {
        add('Authorise return', 'authorise_return',
            icon: Icons.undo,
            doneMessage: 'Return authorised.');
      }
      if (d.ret == 'goods_sent_back') {
        add('Confirm return receipt', 'confirm_return_receipt',
            icon: Icons.inbox,
            doneMessage: 'Return receipt confirmed.');
      }
    }

    if (actions.isEmpty) {
      return [
        const Text(
          'No actions available for you in the current state.',
          style: TextStyle(color: Colors.black54),
        )
      ];
    }
    return actions;
  }

  Widget _reviewSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('One review per order (FR-R1). Reviews are AI-moderated.'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Rating: '),
                for (int r = 1; r <= 5; r++)
                  IconButton(
                    icon: Icon(r <= _rating ? Icons.star : Icons.star_border),
                    color: Colors.amber.shade700,
                    tooltip: '$r star${r == 1 ? '' : 's'}',
                    onPressed: () => setState(() => _rating = r),
                  ),
              ],
            ),
            TextField(
              controller: _reviewText,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Review text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ActionButton(
              label: 'Submit review',
              icon: Icons.rate_review,
              onPressed: () async {
                final api = AppScope.of(context).api;
                await api.submitReview(
                  widget.orderId,
                  _rating,
                  _reviewText.text.trim(),
                );
                if (mounted) {
                  showInfo(context, 'Review submitted for moderation.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
