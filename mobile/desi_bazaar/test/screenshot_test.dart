// Screenshot REGRESSION verification for the core screens.
//
// Capture:  flutter test test/screenshot_test.dart --update-goldens
// Verify:   flutter test test/screenshot_test.dart
// (see test/README.md for the acceptance criteria)
//
// Data: FakeApiClient seeded with REALISTIC synthetic data mirroring the
// slice backend's seed (saree 850 kr, kurti 220 kr, ID-verified badge).
// Real socket I/O hangs inside testWidgets on this VM (verified with raw
// Socket.connect: works in plain test(), hangs in testWidgets), so
// live-backend UI capture is deferred to a device/emulator run — the
// real-backend E2E proof lives in vertical-slice/demo.py (30 steps) and
// test/backend_enforcement_test.dart. These shots prove the UI renders,
// not the backend round-trip.
library;

import 'package:desi_bazaar/api/api_client.dart';
import 'package:desi_bazaar/api/models.dart';
import 'package:desi_bazaar/api/session.dart';
import 'package:desi_bazaar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

Listing _listing(String id, String category, int price) => Listing(
      id: id,
      category: category,
      condition: 'New',
      sizeText: 'M',
      priceSek: price,
      sellerBadgeScope: 'ID verified',
      sellerBadgeDate: '2026-10-01',
      sellerId: 'seller-anaya',
      unitsAvailable: 2,
    );

OrderDetail _reportedOrder() => OrderDetail(
      id: 'order-shot-1',
      dimensions: OrderDimensions(
        payment: 'payment_reported',
        fulfilment: 'stock_reserved',
        cancelRefund: 'no_cancel',
        dispute: 'dispute_none',
        ret: 'return_none',
      ),
      orderVersion: 2,
      buyerId: 'buyer-rohan',
      sellerId: 'seller-anaya',
      snapshot: {
        'listing': {
          'category': 'Saree',
          'condition': 'New',
          'size_text': '6.3m, blouse 38',
          'price_sek': 850,
        },
        'recipient': '+46700000101',
        'amount_sek': 850,
      },
    );

SessionState _session(String principal, String role, [String name = '']) =>
    SessionState()..signIn(principal: principal, role: role, displayName: name);

DesiBazaarApp _app(FakeApiClient fake, SessionState session) =>
    DesiBazaarApp(api: fake, session: session);

void main() {
  setUpAll(ensureTestFont);
  tearDownAll(resetTestGlobals);

  testWidgets('shots: auth screen', (tester) async {
    await tester.pumpWidget(_app(FakeApiClient(), SessionState()));
    await pumpSettled(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-auth.png'));
  });

  testWidgets('shots: buyer journey (browse, detail, checkout)', (tester) async {
    final fake = FakeApiClient(
      listings: [
        _listing('listing-saree', 'Saree', 850),
        _listing('listing-kurti', 'Kurti', 220)
      ],
      reserveOrder: _reportedOrder(),
      order: _reportedOrder(),
    );
    await tester.pumpWidget(
        _app(fake, _session('buyer-rohan', 'buyer', 'Rohan (demo buyer)')));
    await pumpSettled(tester);

    // 1. browse
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-browse.png'));

    // 2. listing detail — tap the first listing card
    await tester.tap(find.byType(ListTile).first);
    await pumpSettled(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-listing-detail.png'));

    // 3. checkout sheet — reserve opens it
    await tester.tap(find.text('Reserve this item'));
    await pumpSettled(tester);
    expect(find.text('Checkout — pay in your Swish app'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-checkout.png'));

    // 4. order tracker — back to browse, then the My orders tab
    Navigator.of(tester.element(find.text('Checkout — pay in your Swish app')))
        .pop(); // checkout sheet
    await pumpSettled(tester);
    await tester.pageBack(); // listing detail
    await pumpSettled(tester);
    await tester.tap(find.text('My orders'));
    await pumpSettled(tester);
    await tester.tap(find.byType(ListTile).first);
    await pumpSettled(tester);
    expect(find.text('Payment: payment_reported'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-order-tracker.png'));
  });

  testWidgets('shots: seller home', (tester) async {
    final fake =
        FakeApiClient(listings: [_listing('listing-saree', 'Saree', 850)]);
    await tester.pumpWidget(_app(
        fake, _session('seller-anaya', 'seller', 'Anaya (demo seller)')));
    await pumpSettled(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-seller-home.png'));
  });

  testWidgets('shots: admin queue', (tester) async {
    await tester.pumpWidget(
        _app(FakeApiClient(), _session('admin-1', 'admin', 'Ops Admin')));
    await pumpSettled(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/shot-admin-queue.png'));
  });
}
