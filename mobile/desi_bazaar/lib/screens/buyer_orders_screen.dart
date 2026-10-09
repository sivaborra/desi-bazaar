import 'package:flutter/material.dart';

import '../api/models.dart';
import '../main.dart';
import 'order_tracker_screen.dart';

/// Buyer's orders. Slice-1 has no server-side "my orders" listing, so this
/// shows the orders created on this device (the app tracks reserved order
/// ids locally) and says so honestly.
class BuyerOrdersScreen extends StatefulWidget {
  const BuyerOrdersScreen({super.key});

  @override
  State<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends State<BuyerOrdersScreen> {
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
                'No orders on this device yet.\nReserve a listing from Browse to start one.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (context, i) => _tile(ids[i]),
        );
      },
    );
  }

  Widget _tile(String orderId) {
    return FutureBuilder<OrderDetail>(
      future: AppScope.of(context).api.getOrder(orderId),
      builder: (context, snap) {
        final title = snap.hasData
            ? '${snap.data!.snapshotCategory} · ${snap.data!.snapshotAmountSek} kr'
            : 'Order ${orderId.substring(0, 8)}…';
        final subtitle = snap.hasData
            ? 'Payment: ${snap.data!.dimensions.payment}'
            : (snap.hasError ? 'Could not load' : 'Loading…');
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => OrderTrackerScreen(orderId: orderId)))
                .then((_) => setState(() {})),
          ),
        );
      },
    );
  }
}
