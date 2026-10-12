import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/widgets.dart';

/// Current privacy notice / terms version (must match backend CONSENT_VERSION).
const String kConsentVersion = 'v1';

/// First-time registration with GDPR consent (FR-B1d §3.3.1).
/// Shown after OTP verification when the backend returns is_new_user=true.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    this.phone,
    this.email,
  });

  final String? phone;
  final String? email;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _name = TextEditingController();
  bool _termsAccepted = false;
  bool _ageConfirmed = false;
  bool _marketingOptIn = false; // never pre-ticked (G2)
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit => _termsAccepted && _ageConfirmed && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    try {
      final userId = await AppScope.of(context).api.register(
            phone: widget.phone,
            email: widget.email,
            displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
            consentAccepted: _termsAccepted,
            consentVersion: kConsentVersion,
            marketingOptIn: _marketingOptIn,
            ageConfirmed: _ageConfirmed,
          );
      if (!mounted) return;
      final displayName = _name.text.trim().isEmpty
          ? (widget.email ?? widget.phone ?? 'Buyer')
          : _name.text.trim();
      AppScope.of(context).session.signIn(
            principal: userId,
            role: 'buyer',
            displayName: displayName,
          );
      // Pop the registration screen so the ListenableBuilder in main.dart
      // switches from AuthScreen to RoleHome now that we're signed in.
      if (mounted) {
        Navigator.of(context).pop();
      }
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

  @override
  Widget build(BuildContext context) {
    final identifier = widget.email ?? widget.phone ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome! You signed in with $identifier.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            const Text(
              'How we handle your data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '• We store your sign-in details (phone/email) to keep your account secure.\n'
              '• We store your orders and listings so the marketplace works.\n'
              '• We use your data to prevent fraud and meet legal obligations.\n'
              '• You can access, correct, or delete your data at any time via Settings.\n'
              '• We never sell your personal data.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () => _showDocument('Privacy Notice'),
                  child: const Text('Full Privacy Notice'),
                ),
                TextButton(
                  onPressed: () => _showDocument('Terms of Service'),
                  child: const Text('Terms of Service'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
                hintText: 'What should buyers and sellers call you?',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _termsAccepted,
              onChanged: (v) => setState(() => _termsAccepted = v ?? false),
              title: const Text(
                'I have read and accept the Privacy Notice and Terms of Service.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _ageConfirmed,
              onChanged: (v) => setState(() => _ageConfirmed = v ?? false),
              title: const Text('I confirm I am 18 years or older.'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _marketingOptIn,
              onChanged: (v) => setState(() => _marketingOptIn = v ?? false),
              title: const Text(
                'Send me offers and updates about Desi Bazaar. (Optional — you can change this anytime in Settings.)',
              ),
              subtitle: const Text('We will never share your details with advertisers.'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create account'),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can withdraw your consent at any time via Settings → Delete my account.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showDocument(String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            title == 'Privacy Notice'
                ? 'Desi Bazaar Privacy Notice ($kConsentVersion)\n\n'
                    'Data controller: Baltic Systems AB.\n\n'
                    'We collect: your phone/email (account identity), display name (optional), '
                    'listings, orders, and messages needed to run the marketplace.\n\n'
                    'Legal basis: contract (running your account), legal obligation '
                    '(accounting, DAC7), legitimate interest (fraud prevention).\n\n'
                    'Your rights: access, correction, deletion, portability, '
                    'objection, and withdrawing consent at any time.\n\n'
                    'Contact: privacy@balticitsystems.com.'
                : 'Desi Bazaar Terms of Service ($kConsentVersion)\n\n'
                    '1. You must be 18 or older to use Desi Bazaar.\n'
                    '2. Listings must be accurate; defects must be disclosed.\n'
                    '3. Payment happens directly between buyer and seller.\n'
                    '4. Prohibited: counterfeit goods, illegal items, misleading listings.\n'
                    '5. We may remove listings or suspend accounts that breach these terms.\n'
                    '6. Disputes are handled per the dispute policy; unresolved disputes '
                    'may be referred to the Swedish National Board for Consumer Disputes (ARN).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
