import 'package:flutter/material.dart';

import '../version.dart';

/// About screen — version info and legal.
/// Accessible from the auth screen (pre-login) so testers can verify
/// which build is installed.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.backendUrl});

  /// Backend URL the app was built with (passed from AppScope).
  final String? backendUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.storefront, size: 64),
          const SizedBox(height: 12),
          Text(
            kAppName,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Version $kAppVersion (build $kAppBuild)',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Divider(),
          if (backendUrl != null)
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Backend'),
              subtitle: Text(backendUrl!),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '© Baltic Systems AB',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
