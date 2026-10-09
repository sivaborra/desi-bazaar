import 'package:flutter/material.dart';

import '../api/models.dart';

/// Show a backend failure as a user-readable message. Never silent.
void showApiError(BuildContext context, Object e) {
  final message = e is ApiException ? e.message : 'Something went wrong — $e';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
  );
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

/// Seller badge: scope + date ONLY. The caption is deliberate — the badge is
/// an identity check, never a product guarantee (DB-TC-006).
class SellerBadge extends StatelessWidget {
  const SellerBadge({super.key, this.scope, this.date});

  final String? scope;
  final String? date;

  @override
  Widget build(BuildContext context) {
    if (scope == null || scope!.isEmpty) {
      return const Chip(
        label: Text('No verified badge'),
        visualDensity: VisualDensity.compact,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Chip(
          avatar: const Icon(Icons.verified_outlined, size: 18),
          label: Text('$scope${date != null && date!.isNotEmpty ? ' · $date' : ''}'),
          visualDensity: VisualDensity.compact,
        ),
        const Text(
          'Identity check only — not a product guarantee.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }
}

/// Defect disclosure, always prominent — never buried below the fold.
class DefectNotice extends StatelessWidget {
  const DefectNotice({super.key, this.defectDisclosure, this.condition});

  final String? defectDisclosure;
  final String? condition;

  @override
  Widget build(BuildContext context) {
    final text = (defectDisclosure ?? '').trim();
    final hasDefect = text.isNotEmpty;
    return Card(
      color: hasDefect ? Colors.amber.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasDefect ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: hasDefect ? Colors.amber.shade800 : Colors.green.shade800,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Condition: ${condition ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasDefect ? 'Known defects: $text' : 'No defects disclosed by the seller.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly labels for the five engine dimensions. Raw state strings are
/// shown too, so the UI never invents a nicer story than the backend has.
class DimensionChips extends StatelessWidget {
  const DimensionChips({super.key, required this.dimensions});

  final OrderDimensions dimensions;

  static const _labels = {
    'payment': 'Payment',
    'fulfilment': 'Fulfilment',
    'cancel_refund': 'Cancel / refund',
    'dispute': 'Dispute',
    'return': 'Return',
  };

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String, String>>[
      MapEntry('payment', dimensions.payment),
      MapEntry('fulfilment', dimensions.fulfilment),
      MapEntry('cancel_refund', dimensions.cancelRefund),
      MapEntry('dispute', dimensions.dispute),
      MapEntry('return', dimensions.ret),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in entries)
          Chip(
            label: Text('${_labels[e.key]}: ${e.value}'),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

/// One action button with a busy state; errors surface via [showApiError].
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style,
  });

  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final ButtonStyle? style;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: _busy
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(widget.icon ?? Icons.play_arrow),
      label: Text(widget.label),
      style: widget.style,
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onPressed();
              } catch (e) {
                if (context.mounted) showApiError(context, e);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}
