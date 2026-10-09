import 'package:flutter/foundation.dart';

/// Minimal session state: who is acting (dev X-Principal id) and in what
/// role. Production will replace the raw principal id with an OTP session
/// token (see TODO in api_client.dart).
class SessionState extends ChangeNotifier {
  String? _principal;
  String _role = 'buyer';
  String _displayName = '';

  /// Order ids this device knows about (reserve returns them; there is no
  /// server-side "my orders" listing in slice-1, so the app tracks them
  /// locally and says so honestly).
  final List<String> knownOrderIds = [];

  bool get signedIn => _principal != null;
  String get principal => _principal ?? '';
  String get role => _role;
  String get displayName => _displayName.isEmpty ? _principal ?? '' : _displayName;

  void signIn({required String principal, required String role, String displayName = ''}) {
    _principal = principal;
    _role = role;
    _displayName = displayName;
    notifyListeners();
  }

  void rememberOrder(String orderId) {
    if (!knownOrderIds.contains(orderId)) {
      knownOrderIds.add(orderId);
      notifyListeners();
    }
  }

  void signOut() {
    _principal = null;
    _role = 'buyer';
    _displayName = '';
    knownOrderIds.clear();
    notifyListeners();
  }
}
