import 'package:desi_bazaar/api/api_client.dart';
import 'package:desi_bazaar/api/models.dart';
import 'package:desi_bazaar/api/session.dart';
import 'package:desi_bazaar/main.dart';
import 'package:desi_bazaar/screens/browse_screen.dart';
import 'package:desi_bazaar/screens/listing_detail_screen.dart';
import 'package:desi_bazaar/screens/order_tracker_screen.dart';
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
      sellerBadgeDate: '2026-10-08',
      sellerId: 'seller-anaya',
      unitsAvailable: 1,
    );

OrderDetail _order(
        {String payment = 'payment_unreported',
        String fulfilment = 'stock_reserved'}) =>
    OrderDetail(
      id: 'order-1',
      dimensions: OrderDimensions(
        payment: payment,
        fulfilment: fulfilment,
        cancelRefund: 'no_cancel',
        dispute: 'dispute_none',
        ret: 'return_none',
      ),
      orderVersion: 1,
      buyerId: 'buyer-rohan',
      sellerId: 'seller-anaya',
      snapshot: {
        'listing': {
          'category': 'Saree',
          'condition': 'New',
          'size_text': 'Free size',
          'price_sek': 499,
        },
        'recipient': '0701234567',
        'amount_sek': 499,
      },
    );

SessionState _buyerSession() =>
    SessionState()..signIn(principal: 'buyer-rohan', role: 'buyer');

Future<void> _pumpBrowse(WidgetTester tester) async {
  final fake = FakeApiClient(listings: [
    _listing('listing-saree', 'Saree', 499),
    _listing('listing-kurti', 'Kurti', 299),
  ]);
  await tester.pumpWidget(
    MaterialApp(
      home: AppScope(
        api: fake,
        session: _buyerSession(),
        child: const Scaffold(body: BrowseScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(WidgetTester tester, SessionState session) async {
  final fake = FakeApiClient(reserveOrder: _order());
  await tester.pumpWidget(
    MaterialApp(
      home: AppScope(
        api: fake,
        session: session,
        child: Scaffold(
            body:
                ListingDetailScreen(listing: _listing('listing-saree', 'Saree', 499))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Reviewer checklist: the app must read the backend URL from
  // --dart-define=API_URL=... . Run this file with a non-default value to
  // verify, e.g.:
  //   flutter test --dart-define=API_URL=http://10.0.2.2:8100 test/app_test.dart
  test('API_URL dart-define overrides the default base URL', () {
    const defined = String.fromEnvironment('API_URL');
    if (defined.isNotEmpty) {
      expect(resolveBaseUrl(), defined);
    } else {
      // No define passed: documented default fallback (localhost:8100).
      expect(resolveBaseUrl(), isNotEmpty);
    }
  });

  // Key buyer screens run at two real phone viewports (finding 5) — layout
  // must hold on both, not just the default 800x600 test surface.
  group('phone viewports', () {
    for (final vp in phoneViewports) {
      testWidgets('browse renders listings @ ${vp.width}x${vp.height}',
          (tester) async {
        await withPhoneViewport(tester, vp, () async {
          await _pumpBrowse(tester);
          expect(find.text('Saree · New'), findsOneWidget);
          expect(find.text('Kurti · New'), findsOneWidget);
          expect(find.text('499 kr'), findsOneWidget);
          expect(find.textContaining('ID verified'), findsWidgets);
          expect(
              find.text('Identity check only — not a product guarantee.'),
              findsWidgets);
        });
      });

      testWidgets('reserve -> checkout shows recipient and amount'
          ' @ ${vp.width}x${vp.height}', (tester) async {
        await withPhoneViewport(tester, vp, () async {
          final session = _buyerSession();
          await _pumpDetail(tester, session);
          await tester.tap(find.text('Reserve this item'));
          await tester.pumpAndSettle();
          expect(
              find.text('Checkout — pay in your Swish app'), findsOneWidget);
          expect(find.text('0701234567'), findsOneWidget);
          expect(find.text('499 kr'), findsWidgets);
          expect(find.textContaining('Open your Swish app'), findsOneWidget);
          expect(session.knownOrderIds, contains('order-1'));
        });
      });
    }
  });

  testWidgets('order tracker reflects the five dimensions', (tester) async {
    final fake = FakeApiClient(order: _order(payment: 'payment_reported'));
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          api: fake,
          session: _buyerSession(),
          child: const Scaffold(body: OrderTrackerScreen(orderId: 'order-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment: payment_reported'), findsOneWidget);
    expect(find.text('Fulfilment: stock_reserved'), findsOneWidget);
    expect(find.text('Cancel / refund: no_cancel'), findsOneWidget);
    expect(find.text('Dispute: dispute_none'), findsOneWidget);
    expect(find.text('Return: return_none'), findsOneWidget);
  });

  // PRESENTATION-ONLY: proves the UI surfaces a 422 honestly. Backend
  // enforcement of the guard itself is proven in
  // backend_enforcement_test.dart against the real backend (finding 6).
  testWidgets('guard error presentation surfaces on illegal action',
      (tester) async {
    final fake = FakeApiClient(
      order: _order(),
      commandError: ApiException(
          422, 'Not allowed right now — GUARD_FAILED: dispatch before payment'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          api: fake,
          session: _buyerSession(),
          child: const Scaffold(body: OrderTrackerScreen(orderId: 'order-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report payment'));
    await tester.pumpAndSettle();
    // The 422 guard failure is user-visible, never silent.
    expect(find.textContaining('Not allowed right now'), findsOneWidget);
    expect(fake.calls, contains('command:report_payment'));
  });

  // FR-R1 positive (presentation): review submits on a received order.
  // The backend-eligibility counterpart (real 201 / real 422) lives in
  // backend_enforcement_test.dart (finding 7).
  testWidgets('review submits with rating and text on received order',
      (tester) async {
    final fake = FakeApiClient(order: _order(fulfilment: 'receipt_confirmed'));
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          api: fake,
          session: _buyerSession(),
          child: const Scaffold(body: OrderTrackerScreen(orderId: 'order-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The review card sits at the bottom of the tracker ListView — bring it
    // into view before interacting.
    await tester.ensureVisible(find.byTooltip('4 stars'));
    await tester.pumpAndSettle();
    // Pick 4 stars via the star picker.
    await tester.tap(find.byTooltip('4 stars'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Review text'), 'Beautiful saree, fast handover.');
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();
    expect(fake.lastReviewRating, 4);
    expect(fake.lastReviewText, 'Beautiful saree, fast handover.');
    expect(fake.calls, contains('submitReview:order-1'));
    expect(find.text('Review submitted for moderation.'), findsOneWidget);
  });

  // FR-R1 negative (presentation): the review UI is always visible, so an
  // ineligible order must fail honestly, not silently.
  testWidgets('review on unreceived order surfaces the 422', (tester) async {
    final fake = FakeApiClient(order: _order())
      ..reviewError = ApiException(422, 'Not allowed right now — not eligible to review (FR-R1)');
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          api: fake,
          session: _buyerSession(),
          child: const Scaffold(body: OrderTrackerScreen(orderId: 'order-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('5 stars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not eligible to review'), findsOneWidget);
    expect(find.text('Review submitted for moderation.'), findsNothing);
  });
}
