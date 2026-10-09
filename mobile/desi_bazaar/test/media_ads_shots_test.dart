// Screenshots for the SC-1/SC-2 review: create-listing with media
// attached, and the browse feed with a Sponsored listing + slot.
//
// FakeApiClient + FakeMediaPicker: no backend, no platform channels.
//
// Capture:  flutter test test/media_ads_shots_test.dart --update-goldens
// Verify:   flutter test test/media_ads_shots_test.dart
// (see test/README.md for the acceptance criteria)
library;

import 'dart:typed_data';

import 'package:desi_bazaar/api/api_client.dart';
import 'package:desi_bazaar/api/media.dart';
import 'package:desi_bazaar/api/models.dart';
import 'package:desi_bazaar/api/session.dart';
import 'package:desi_bazaar/main.dart';
import 'package:desi_bazaar/media/media_service.dart';
import 'package:desi_bazaar/screens/browse_screen.dart';
import 'package:desi_bazaar/screens/seller_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'test_setup.dart';

Uint8List _testJpg(int r, int g, int b) {
  final im = img.Image(width: 96, height: 96);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(im));
}

Listing _listing(String id, String category,
    {bool promoted = false, List<MediaItem> media = const []}) =>
    Listing(
      id: id,
      category: category,
      condition: 'New',
      sizeText: 'M',
      priceSek: 499,
      sellerBadgeScope: 'ID verified',
      sellerBadgeDate: '2026-10-08',
      sellerId: 'seller-anaya',
      unitsAvailable: 2,
      promoted: promoted,
      media: media,
    );

void main() {
  setUpAll(ensureTestFont);
  tearDownAll(resetTestGlobals);
  setUp(FakeMediaStore.clear);

  testWidgets('shot: create listing with media attached', (tester) async {
    final fake = FakeApiClient();
    final picker = FakeMediaPicker(images: [_testJpg(200, 100, 50), _testJpg(50, 120, 200)]);
    await tester.pumpWidget(MaterialApp(
      home: AppScope(
        api: fake,
        session: SessionState()
          ..signIn(principal: 'seller-anaya', role: 'seller'),
        child: Scaffold(body: CreateListingScreen(mediaPicker: picker)),
      ),
    ));
    await pumpSettled(tester);

    await tester.tap(find.text('Gallery'));
    await pumpSettled(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Category'), 'Saree');
    await tester.enterText(find.widgetWithText(TextField, 'Price (SEK)'), '499');

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/08-create-with-media.png'));
  });

  testWidgets('shot: browse feed with Sponsored listing + slot',
      (tester) async {
    final fake = FakeApiClient(listings: [
      _listing('l1', 'Saree', promoted: true, media: [
        MediaItem(mediaId: 'm1', kind: MediaKind.image),
      ]),
      _listing('l2', 'Kurti'),
    ])
      ..nextSlot = AdSlot(
          type: 'promotion',
          listingId: 'l1',
          headline: 'Festive handloom sarees');
    await tester.pumpWidget(MaterialApp(
      home: AppScope(
        api: fake,
        session: SessionState()
          ..signIn(principal: 'buyer-rohan', role: 'buyer'),
        child: const Scaffold(body: BrowseScreen()),
      ),
    ));
    await pumpSettled(tester);

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/09-sponsored-feed.png'));
  });
}
