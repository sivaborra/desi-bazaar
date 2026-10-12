import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../main.dart';
import '../version.dart';
import '../widgets/widgets.dart';
import 'about_screen.dart';
import 'registration_screen.dart';

/// Phone or email -> OTP sign-in (FR-B1, FR-B1a–c). The backend slice only
/// issues synthetic codes (logged to its console, never SMS/email) — the
/// debug banner says so.
///
/// For the slice demo there are also one-tap dev sign-ins for the synthetic
/// principals. They are clearly labelled and must not ship.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _useEmail = false;

  static const _channelKey = 'desi_auth_channel';

  @override
  void initState() {
    super.initState();
    _restoreChannel();
  }

  Future<void> _restoreChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final channel = prefs.getString(_channelKey);
    if (channel == 'email' && mounted) {
      setState(() => _useEmail = true);
    }
  }

  Future<void> _saveChannel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_channelKey, _useEmail ? 'email' : 'phone');
  }

  /// Simplified RFC 5322 email validation (FR-B1c).
  static bool isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      if (_useEmail) {
        final email = _email.text.trim();
        if (email.isEmpty) {
          showInfo(context, 'Enter your email address first.');
          return;
        }
        if (!isValidEmail(email)) {
          showInfo(context, 'That email address does not look valid.');
          return;
        }
        await api.requestEmailOtp(email);
      } else {
        final phone = _phone.text.trim();
        if (phone.isEmpty) {
          showInfo(context, 'Enter your phone number first.');
          return;
        }
        await api.requestOtp(phone);
      }
      await _saveChannel();
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
    final code = _code.text.trim();
    setState(() => _busy = true);
    try {
      final OtpVerifyResult result;
      final String displayName;
      if (_useEmail) {
        final email = _email.text.trim();
        result = await scope.api.verifyEmailOtpResult(email, code);
        displayName = email;
      } else {
        final phone = _phone.text.trim();
        result = await scope.api.verifyOtpResult(phone, code);
        displayName = phone;
      }
      if (!mounted) return;
      setState(() => _busy = false);
      if (result.isNewUser) {
        // FR-B1d: first-time user → Registration screen with GDPR consent.
        // Account is created only after explicit consent.
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RegistrationScreen(
              phone: _useEmail ? null : _phone.text.trim(),
              email: _useEmail ? _email.text.trim() : null,
            ),
          ),
        );
        // If the user backed out without registering, stay on auth screen
        // (CC3 — no account created, no orphaned record).
        return;
      }
      // Returning user — sign in directly.
      // Slice-1 has no session tokens yet; the verified user id becomes the
      // dev principal.
      scope.session
          .signIn(principal: result.userId!, role: 'buyer', displayName: displayName);
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
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
                  'DEV BUILD — phone + OTP stub only (no BankID, per FR-B1). '
                  'Codes are synthetic and printed to the backend console, never sent by SMS.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/logo.webp',
              width: 120,
              height: 120,
              fit: BoxFit.cover,
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
              ButtonSegment(value: false, label: Text('Phone')),
              ButtonSegment(value: true, label: Text('Email')),
            ],
            selected: {_useEmail},
            onSelectionChanged: (selection) {
              setState(() {
                _useEmail = selection.first;
                _codeSent = false;
              });
            },
          ),
          const SizedBox(height: 12),
          if (_useEmail)
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.se',
                border: OutlineInputBorder(),
              ),
            )
          else
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+46700123456',
                border: OutlineInputBorder(),
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
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              child: Text(
                'v$kAppVersion ($kAppBuild) — About',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
