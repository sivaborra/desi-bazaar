import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/widgets.dart';

/// Seller application (FR-S1). New applications enter `pending` and cannot
/// list until approved (FR-S2). 422 keeps the form editable (DB-TC-002).
class SellerApplyScreen extends StatefulWidget {
  const SellerApplyScreen({super.key});

  @override
  State<SellerApplyScreen> createState() => _SellerApplyScreenState();
}

class _SellerApplyScreenState extends State<SellerApplyScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _docRef = TextEditingController();
  final _categories = TextEditingController();
  final _profile = TextEditingController();
  final _traderBasis = TextEditingController();
  final _swish = TextEditingController();
  bool _trader = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _docRef.dispose();
    _categories.dispose();
    _profile.dispose();
    _traderBasis.dispose();
    _swish.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final categories = _categories.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    setState(() => _busy = true);
    try {
      final j = await AppScope.of(context).api.applySeller(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            idDocumentRef: _docRef.text.trim(),
            categories: categories,
            trader: _trader,
            traderBasis:
                _trader && _traderBasis.text.trim().isNotEmpty ? _traderBasis.text.trim() : null,
            profile: _profile.text.trim().isEmpty ? null : _profile.text.trim(),
            swishRecipient: _swish.text.trim().isEmpty ? null : _swish.text.trim(),
          );
      if (!mounted) return;
      setState(() => _busy = false);
      showInfo(
        context,
        'Application received (${j['application_id']}). Status: ${j['status']} — '
        'you cannot list items until approved.',
      );
    } catch (e) {
      // 422 keeps the form editable; nothing is lost.
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
        const Text('Become a seller',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Sellers are manually approved from known, verified people. '
          'Buyers always shop for free.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        _field(_name, 'Full name'),
        _field(_phone, 'Phone', keyboard: TextInputType.phone),
        _field(_docRef, 'ID document reference',
            hint: 'Opaque reference from your ID check — never paste raw document bytes'),
        _field(_categories, 'Categories (comma separated)', hint: 'Saree, Kurti'),
        _field(_profile, 'Profile text (optional)', maxLines: 2),
        _field(_swish, 'Swish recipient (your Swish number)', keyboard: TextInputType.phone),
        SwitchListTile(
          title: const Text('I sell as a trader (business)'),
          value: _trader,
          onChanged: (v) => setState(() => _trader = v),
        ),
        if (_trader) _field(_traderBasis, 'Trader basis', hint: 'e.g. enskild firma, org.nr …'),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Submitting…' : 'Submit application'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
