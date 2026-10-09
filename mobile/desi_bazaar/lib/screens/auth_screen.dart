import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/widgets.dart';

/// Phone or email -> OTP sign-in (FR-B1). The backend slice only issues
/// synthetic codes (logged to its console, never SMS/email) — the debug
/// banner says so.
///
/// For the slice demo there are also one-tap dev sign-ins for the synthetic
/// principals. They are clearly labelled and must not ship.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  bool _useEmail = false;
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _validateIdentifier(String value) {
    if (value.isEmpty) {
      return _useEmail ? 'Enter your email first.' : 'Enter your phone number first.';
    }
    if (_useEmail && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return 'That does not look like an email address.';
    }
    return null;
  }

  Future<void> _request() async {
    final api = AppScope.of(context).api;
    final identifier = _identifier.text.trim();
    final problem = _validateIdentifier(identifier);
    if (problem != null) {
      showInfo(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.requestOtp(identifier);
      setState(() => _codeSent = true);
      if (mounted) {
        showInfo(context,
            'Code requested. Demo build: the backend prints the synthetic code to its own console.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final scope = AppScope.of(context);
    final identifier = _identifier.text.trim();
    final code = _code.text.trim();
    setState(() => _busy = true);
    try {
      final userId = await scope.api.verifyOtp(identifier, code);
      // Slice-1 has no session tokens yet; the verified user id becomes the
      // dev principal. New identifiers register as buyers (FR-B1).
      scope.session.signIn(principal: userId, role: 'buyer', displayName: identifier);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _devSignIn(String principal, String role, String name) {
    AppScope.of(context).session.signIn(
          principal: principal,
          role: role,
          displayName: name,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Desi Bazaar — sign in')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (kDebugMode)
            const Card(
              color: Color(0xFFFFF3E0),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'DEV BUILD — phone/email + OTP stub only (no BankID, per FR-B1). '
                  'Codes are synthetic and printed to the backend console, never sent.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Not just a bridge but a brand.',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('The marketplace for Indians & Bangladeshis in Sweden.'),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Phone'), icon: Icon(Icons.phone)),
              ButtonSegment(value: true, label: Text('Email'), icon: Icon(Icons.email)),
            ],
            selected: {_useEmail},
            onSelectionChanged: (s) {
              setState(() {
                _useEmail = s.first;
                _codeSent = false;
                _identifier.clear();
                _code.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _identifier,
            keyboardType:
                _useEmail ? TextInputType.emailAddress : TextInputType.phone,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _useEmail ? 'Email address' : 'Phone number',
              hintText: _useEmail ? 'name@example.se' : '+46700123456',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_codeSent) ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton(
            onPressed: _busy ? null : (_codeSent ? _verify : _request),
            child: Text(_busy
                ? 'Please wait…'
                : (_codeSent ? 'Verify code' : 'Send code')),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Demo quick sign-in (synthetic principals, dev only)',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _devSignIn('buyer-rohan', 'buyer', 'Rohan (demo buyer)'),
                child: const Text('Buyer: buyer-rohan'),
              ),
              OutlinedButton(
                onPressed: () => _devSignIn('seller-anaya', 'seller', 'Anaya (demo seller)'),
                child: const Text('Seller: seller-anaya'),
              ),
              OutlinedButton(
                onPressed: () => _devSignIn('admin-1', 'admin', 'Ops Admin'),
                child: const Text('Admin: admin-1'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
