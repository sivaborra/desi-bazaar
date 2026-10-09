// Backend enforcement + FR-R1 eligibility against the REAL slice backend.
//
// These are plain `test()`s (NOT testWidgets): on this VM, real socket I/O
// hangs inside the testWidgets zone (verified with raw Socket.connect), so
// all live-backend assertions run in the real async zone. The UI half — that
// the app surfaces these exact outcomes — is proven with fakes in
// app_test.dart (labelled presentation-only) using the same error strings
// asserted here. Live-backend widget tests are deferred to a device/emulator
// run (see test/README.md).
//
// Requires the backend running fresh:
//   cd vertical-slice && .venv/bin/uvicorn app:app --port 8100
//
// NOTE (app gap, not fixed here): HttpApiClient.command() cannot pass
// `context`, so the seller's "Confirm payment" button can never satisfy the
// backend's swish_verified guard. This file drives confirm_payment with raw
// HTTP (with context) and the gap is logged — see BUG-009 in the bug log.
library;

import 'dart:convert';

import 'package:desi_bazaar/api/api_client.dart';
import 'package:desi_bazaar/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'test_setup.dart';

int _opSeq = 0;
String _opId() =>
    'test-op-${DateTime.now().microsecondsSinceEpoch}-${_opSeq++}';

Map<String, String> _h(String principal) => {
      'Content-Type': 'application/json',
      'X-Principal': principal,
    };

/// Raw command POST — the only way to send `context` (see note above).
Future<http.Response> _rawCommand({
  required String principal,
  required String orderId,
  required String operation,
  required int expectedVersion,
  Map<String, dynamic> context = const {},
}) {
  return http.post(
    Uri.parse('$testBackendBaseUrl/v1/commands'),
    headers: _h(principal),
    body: jsonEncode({
      'operation_id': _opId(),
      'order_id': orderId,
      'operation': operation,
      'expected_order_version': expectedVersion,
      'payload': {},
      'context': context,
    }),
  );
}

Future<String> _createListing() async {
  final r = await http.post(
    Uri.parse('$testBackendBaseUrl/v1/listings'),
    headers: _h('seller-anaya'),
    body: jsonEncode({
      'category': 'saree',
      'condition': 'new',
      'size_text': 'M',
      'price_sek': 100,
    }),
  );
  expect(r.statusCode, 201);
  return (jsonDecode(r.body) as Map)['id'] as String;
}

/// Fresh order at payment_unreported/stock_reserved. Returns (orderId, version).
Future<(String, int)> _freshOrder() async {
  final buyer =
      HttpApiClient(baseUrl: testBackendBaseUrl, principal: 'buyer-rohan');
  final listingId = await _createListing();
  final order = await buyer.reserveListing(listingId);
  return (order.id, order.orderVersion);
}

Future<int> _version(String orderId, String principal) =>
    HttpApiClient(baseUrl: testBackendBaseUrl, principal: principal)
        .getOrder(orderId)
        .then((o) => o.orderVersion);

void main() {
  setUpAll(() async {
    await ensureBackend();
  });
  tearDownAll(resetTestGlobals);

  test('finding 6: backend enforces dispatch-before-payment guard (real 422)',
      () async {
    useRealHttp();
    final (orderId, version) = await _freshOrder();
    final seller =
        HttpApiClient(baseUrl: testBackendBaseUrl, principal: 'seller-anaya');

    // The UI hides the dispatch button until payment is confirmed — call the
    // API directly to prove the BACKEND enforces the guard regardless.
    try {
      await seller.command(
          orderId: orderId,
          operation: 'dispatch',
          expectedOrderVersion: version);
      fail('backend must reject dispatch before payment confirmation');
    } on ApiException catch (e) {
      expect(e.status, 422);
      expect(e.message.toLowerCase(), contains('guard'));
    }

    // And the order is untouched by the rejected attempt.
    final fresh = await HttpApiClient(
            baseUrl: testBackendBaseUrl, principal: 'buyer-rohan')
        .getOrder(orderId);
    expect(fresh.dimensions.fulfilment, 'stock_reserved');
    expect(fresh.orderVersion, version);
  });

  test('finding 7 (positive): FR-R1 — backend accepts review on received order',
      () async {
    useRealHttp();
    final (orderId, _) = await _freshOrder();

    // Drive the order to receipt_confirmed through the real backend.
    var v = await _version(orderId, 'buyer-rohan');
    var r = await _rawCommand(
        principal: 'buyer-rohan',
        orderId: orderId,
        operation: 'report_payment',
        expectedVersion: v);
    expect(r.statusCode, 200);
    v = await _version(orderId, 'buyer-rohan');
    r = await _rawCommand(
        principal: 'seller-anaya',
        orderId: orderId,
        operation: 'confirm_payment',
        expectedVersion: v,
        context: {'swish_verified': true});
    expect(r.statusCode, 200, reason: r.body);
    final seller =
        HttpApiClient(baseUrl: testBackendBaseUrl, principal: 'seller-anaya');
    final buyer =
        HttpApiClient(baseUrl: testBackendBaseUrl, principal: 'buyer-rohan');
    v = await _version(orderId, 'seller-anaya');
    await seller.command(
        orderId: orderId, operation: 'dispatch', expectedOrderVersion: v);
    v = await _version(orderId, 'buyer-rohan');
    await buyer.command(
        orderId: orderId,
        operation: 'confirm_receipt',
        expectedOrderVersion: v);
    expect((await buyer.getOrder(orderId)).dimensions.fulfilment,
        'receipt_confirmed');

    // The real review endpoint accepts it.
    final rr = await http.post(
      Uri.parse('$testBackendBaseUrl/v1/orders/$orderId/review'),
      headers: _h('buyer-rohan'),
      body: jsonEncode({'rating': 5, 'text': 'Real backend review.'}),
    );
    expect(rr.statusCode, 201);

    // One review per order (FR-R1): a second one is rejected.
    final rr2 = await http.post(
      Uri.parse('$testBackendBaseUrl/v1/orders/$orderId/review'),
      headers: _h('buyer-rohan'),
      body: jsonEncode({'rating': 1, 'text': 'Second.'}),
    );
    expect(rr2.statusCode, 409);
  });

  test('finding 7 (negative): FR-R1 — backend 422s review on unreceived order',
      () async {
    useRealHttp();
    final (orderId, _) = await _freshOrder(); // stock_reserved, not received

    final r = await http.post(
      Uri.parse('$testBackendBaseUrl/v1/orders/$orderId/review'),
      headers: _h('buyer-rohan'),
      body: jsonEncode({'rating': 5, 'text': 'Too early.'}),
    );
    expect(r.statusCode, 422);
    expect(r.body, contains('not eligible to review'));
  });
}
