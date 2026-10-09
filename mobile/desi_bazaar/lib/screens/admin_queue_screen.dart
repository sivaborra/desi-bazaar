import 'package:flutter/material.dart';

import '../api/models.dart';
import '../main.dart';
import '../widgets/widgets.dart';

/// Admin: seller approval queue (FR-A1/A2). Approve/reject records reviewer
/// identity + timestamp (FR-S3); rejections require a reason.
class AdminQueueScreen extends StatefulWidget {
  const AdminQueueScreen({super.key});

  @override
  State<AdminQueueScreen> createState() => _AdminQueueScreenState();
}

class _AdminQueueScreenState extends State<AdminQueueScreen> {
  List<QueueApplication> _apps = [];
  bool _loading = true;
  String? _error;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await AppScope.of(context).api.sellerQueue();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Could not load queue — $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_apps.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(child: Text('Queue is empty. Nothing waiting for review.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _apps.length,
        itemBuilder: (context, i) => _card(_apps[i]),
      ),
    );
  }

  Widget _card(QueueApplication a) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seller ${a.sellerId}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Phone: ${a.phone}'),
            Text('Categories: ${a.categories.join(', ')}'),
            if (a.trader)
              Text('Trader — basis: ${a.traderBasis ?? 'not stated'}'),
            Text('Submitted: ${a.submittedAt}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(a, 'approve'),
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rejectDialog(a),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(QueueApplication a, String decision, {String? reason}) async {
    try {
      final j = await AppScope.of(context).api.decideSeller(
            sellerId: a.sellerId,
            decision: decision,
            checklistVersion: 'checklist-2026-10',
            reason: reason,
          );
      if (!mounted) return;
      showInfo(
        context,
        '${decision == 'approve' ? 'Approved' : 'Rejected'} ${j['seller_id']} '
        'by ${j['reviewer_id'] ?? 'admin'} at ${j['decided_at'] ?? 'now'}.',
      );
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _rejectDialog(QueueApplication a) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject application'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reject')),
        ],
      ),
    );
    if (ok == true) {
      if (reason.text.trim().isEmpty) {
        if (mounted) showInfo(context, 'A reason is required for rejection.');
        return;
      }
      await _decide(a, 'reject', reason: reason.text.trim());
    }
    reason.dispose();
  }
}
