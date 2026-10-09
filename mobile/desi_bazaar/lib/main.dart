import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/session.dart';
import 'screens/admin_queue_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/buyer_orders_screen.dart';
import 'screens/seller_apply_screen.dart';
import 'screens/seller_home_screen.dart';

void main() {
  runApp(const DesiBazaarApp());
}

/// Inherited access to the API client + session, so widget tests can inject
/// a [FakeApiClient] without any backend.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.session,
    required super.child,
  });

  final DesiBazaarApi api;
  final SessionState session;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.api != api || oldWidget.session != session;
}

class DesiBazaarApp extends StatefulWidget {
  const DesiBazaarApp({super.key, this.api, this.session});

  final DesiBazaarApi? api;
  final SessionState? session;

  @override
  State<DesiBazaarApp> createState() => _DesiBazaarAppState();
}

class _DesiBazaarAppState extends State<DesiBazaarApp> {
  late final DesiBazaarApi _api;
  late final SessionState _session;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? HttpApiClient();
    _session = widget.session ?? SessionState();
    _syncPrincipal();
    _session.addListener(_syncPrincipal);
  }

  void _syncPrincipal() {
    if (_api is HttpApiClient) {
      _api.principal = _session.principal;
    }
  }

  @override
  void dispose() {
    _session.removeListener(_syncPrincipal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      api: _api,
      session: _session,
      child: MaterialApp(
        title: 'Desi Bazaar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
          useMaterial3: true,
        ),
        home: ListenableBuilder(
          listenable: _session,
          builder: (context, _) =>
              _session.signedIn ? const RoleHome() : const AuthScreen(),
        ),
      ),
    );
  }
}

/// Routes to the right home per role. Debug banner always visible in dev
/// builds so nobody mistakes the stub for production auth.
class RoleHome extends StatelessWidget {
  const RoleHome({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final role = session.role;
        return Scaffold(
          appBar: AppBar(
            title: Text('Desi Bazaar — ${_roleTitle(role)}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: session.signOut,
              ),
            ],
          ),
          body: Column(
            children: [
              if (kDebugMode)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.all(8),
                  child: const Text(
                    'DEV BUILD — OTP codes are stubs, signed in via X-Principal. Never ship this.',
                    style: TextStyle(fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(child: _homeFor(role)),
            ],
          ),
        );
      },
    );
  }

  String _roleTitle(String role) => switch (role) {
        'admin' => 'Admin',
        'seller' => 'Seller',
        _ => 'Buyer',
      };

  Widget _homeFor(String role) => switch (role) {
        'admin' => const AdminQueueScreen(),
        'seller' => const SellerHomeScreen(),
        _ => const BuyerHome(),
      };
}

class BuyerHome extends StatefulWidget {
  const BuyerHome({super.key});

  @override
  State<BuyerHome> createState() => _BuyerHomeState();
}

class _BuyerHomeState extends State<BuyerHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          BrowseScreen(),
          BuyerOrdersScreen(),
          SellerApplyScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'My orders'),
          NavigationDestination(icon: Icon(Icons.how_to_reg), label: 'Sell'),
        ],
      ),
    );
  }
}
