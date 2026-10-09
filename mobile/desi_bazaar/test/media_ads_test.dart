// Media (SC-2) + ads (SC-1) widget tests.
//
// Uses FakeApiClient + FakeMediaPicker: no backend, no platform channels.
// Image bytes are generated in-memory with package:image (pure Dart).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desi_bazaar/api/api_client.dart';
import 'package:desi_bazaar/api/media.dart';
import 'package:desi_bazaar/api/models.dart';
import 'package:desi_bazaar/api/session.dart';
import 'package:desi_bazaar/main.dart';
import 'package:desi_bazaar/media/media_service.dart';
import 'package:desi_bazaar/screens/browse_screen.dart';
import 'package:desi_bazaar/screens/listing_detail_screen.dart';
import 'package:desi_bazaar/screens/seller_home_screen.dart';
import 'package:desi_bazaar/widgets/media_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

//// Photo-like high-entropy fixture: 16x16 random blocks (busy fabric) with/// per-pixel jitter and a gradient. ~13MB at JPEG q100 — large and realistic,
/// and it does NOT compress trivially (pure noise would be pathological;
/// this has the spatial correlation of a real photo).
Uint8List _photoLikeFixture() {
  final rng = math.Random(7);
  final im = img.Image(width: 3000, height: 2000);
  const block = 16;
  for (var by = 0; by < im.height ~/ block; by++) {
    for (var bx = 0; bx < im.width ~/ block; bx++) {
      final r = rng.nextInt(256), g = rng.nextInt(256), b = rng.nextInt(256);
      for (var y = by * block; y < (by + 1) * block; y++) {
        for (var x = bx * block; x < (bx + 1) * block; x++) {
          final j = rng.nextInt(24) - 12;
          im.setPixel(x, y, img.ColorRgb8(
              (r + j + y ~/ 12) % 256, (g + j) % 256, (b - j) % 256));
        }
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 100));
}

/// Small flat fixture for picker-limit tests (compresses trivially —
/// that is fine here; compression is covered by the dedicated test below).
Uint8List _testJpg() {
  final im = img.Image(width: 48, height: 48);
  img.fill(im, color: img.ColorRgb8(200, 100, 50));
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
      unitsAvailable: 1,
      promoted: promoted,
      media: media,
    );

SessionState _sellerSession() =>
    SessionState()..signIn(principal: 'seller-anaya', role: 'seller');

SessionState _buyerSession() =>
    SessionState()..signIn(principal: 'buyer-rohan', role: 'buyer');

Widget _scoped(DesiBazaarApi api, SessionState session, Widget child) =>
    MaterialApp(
      home: AppScope(api: api, session: session, child: Scaffold(body: child)),
    );

Future<void> _fillCreateForm(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Category'), 'Saree');
  await tester.enterText(find.widgetWithText(TextField, 'Condition'), 'New');
  await tester.enterText(find.widgetWithText(TextField, 'Size'), 'M');
  await tester.enterText(
      find.widgetWithText(TextField, 'Price (SEK)'), '499');
}

/// The submit button lives below the fold of a lazily-built ListView, and
/// the AppBar carries the same title text — so scroll until the *button*
/// (not the title) is built, then tap it unambiguously.
Future<void> _tapSubmit(WidgetTester tester) async {
  final button = find.widgetWithText(ElevatedButton, 'Create listing');
  for (var i = 0; i < 6 && button.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
  }
  // Scroll it fully into view: a partially-visible button's center can
  // miss the hit test after a raw drag.
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(FakeMediaStore.clear);

  testWidgets('lost media from interrupted capture is recovered (Android)', (tester) async {
    final fake = FakeApiClient();
    final picker = _LosingPicker();
    await tester.pumpWidget(_scoped(
        fake, _sellerSession(), CreateListingScreen(mediaPicker: picker)));
    await tester.pumpAndSettle();
    // The screen recovers the photo Android kept across process death.
    expect(find.text('Photos (1/8)'), findsOneWidget);
  });

  testWidgets('9th photo is blocked at 8 (SC-2 limit)', (tester) async {
    final fake = FakeApiClient();
    final picker = FakeMediaPicker(images: List.generate(9, (_) => _testJpg()));
    await tester.pumpWidget(_scoped(
        fake, _sellerSession(), CreateListingScreen(mediaPicker: picker)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    // Only 8 attached despite 9 offered.
    expect(find.text('Photos (8/8)'), findsOneWidget);
    expect(find.text('Photo limit reached (8).'), findsOneWidget);

    // Let the snackbar dismiss so the next tap isn't blocked by it, then
    // trying again explains the limit instead of silently ignoring.
    await tester.pump(const Duration(seconds: 5));
    await tester.ensureVisible(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum 8 photos per listing.'), findsOneWidget);
  });

  testWidgets('create listing uploads media then attaches media_ids',
      (tester) async {
    final fake = FakeApiClient();
    final picker = FakeMediaPicker(images: [_testJpg()]);
    await tester.pumpWidget(_scoped(
        fake, _sellerSession(), CreateListingScreen(mediaPicker: picker)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Photos (1/8)'), findsOneWidget);

    await _fillCreateForm(tester);
    await _tapSubmit(tester);

    // Contract flow asserted as a SEQUENCE, not just presence: the filtered
    // call log must read exactly
    //   requestMediaUploadUrl -> uploadMediaBytes -> completeMediaUpload -> createListing
    // in that order (indices strictly increasing, each exactly once).
    final seq = fake.calls
        .where((c) =>
            c.startsWith('requestMediaUploadUrl:') ||
            c.startsWith('uploadMediaBytes:') ||
            c.startsWith('completeMediaUpload:') ||
            c.startsWith('createListing:'))
        .map((c) => c.split(':').first)
        .toList();
    expect(seq, [
      'requestMediaUploadUrl',
      'uploadMediaBytes',
      'completeMediaUpload',
      'createListing',
    ]);
    expect(fake.lastCreateMediaIds, ['media-1']);
  });

  testWidgets('media 422 rejection surfaces honestly', (tester) async {
    final fake = FakeApiClient()
      ..completeError =
          ApiException(422, 'Not allowed right now — rejected: bad content');
    final picker = FakeMediaPicker(images: [_testJpg()]);
    await tester.pumpWidget(_scoped(
        fake, _sellerSession(), CreateListingScreen(mediaPicker: picker)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await _fillCreateForm(tester);
    await _tapSubmit(tester);

    // The rejection reason reaches the user; the listing is NOT created.
    expect(find.textContaining('rejected: bad content'), findsOneWidget);
    expect(
        fake.calls.any((c) => c.startsWith('createListing:')), isFalse);
  });

  testWidgets('Sponsored label only on promoted listings (DB-TC-189)',
      (tester) async {
    final fake = FakeApiClient(listings: [
      _listing('l1', 'Saree', promoted: true),
      _listing('l2', 'Kurti', promoted: false),
    ]);
    await tester.pumpWidget(
        _scoped(fake, _buyerSession(), const BrowseScreen()));
    await tester.pumpAndSettle();

    // Exactly one Sponsored label — the promoted one.
    expect(find.text('Sponsored'), findsOneWidget);
    // The sponsored slot is empty from the fake -> renders nothing.
    expect(find.text('Sponsored pick'), findsNothing);
  });

  testWidgets('sponsored slot renders when the backend serves one',
      (tester) async {
    final fake = FakeApiClient(listings: [_listing('l1', 'Saree')])
      ..nextSlot = AdSlot(
          type: 'promotion',
          listingId: 'l1',
          headline: 'Handloom sarees — festive picks');
    await tester.pumpWidget(
        _scoped(fake, _buyerSession(), const BrowseScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Handloom sarees — festive picks'), findsOneWidget);
    expect(fake.calls, contains('adSlot:feed'));
  });

  testWidgets('promote flow: config -> pay (stub) -> pending admin review',
      (tester) async {
    final fake = FakeApiClient(listings: [_listing('l1', 'Saree')]);
    // AppScope OUTSIDE MaterialApp (like the real app): bottom-sheet routes
    // sit above MaterialApp's Navigator, so they must still see AppScope.
    await tester.pumpWidget(AppScope(
      api: fake,
      session: _sellerSession(),
      child: const MaterialApp(home: Scaffold(body: SellerHomeScreen())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Promote'));
    await tester.pumpAndSettle();

    // Day options with prices from /v1/ads/config.
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget);
    expect(find.text('Pay 29 SEK (stub)'), findsOneWidget);

    await tester.tap(find.text('3 days'));
    await tester.pumpAndSettle();
    expect(find.text('Pay 69 SEK (stub)'), findsOneWidget);

    await tester.tap(find.text('Pay 69 SEK (stub)'));
    await tester.pumpAndSettle();

    expect(fake.calls, contains('createPromotion:l1:3'));
    expect(fake.calls, contains('payPromotion:promo-1'));
    // Honest state: paying does not buy placement by itself.
    expect(find.text('Pending admin review'), findsOneWidget);
  });

  testWidgets('detail carousel shows photos and a video tile', (tester) async {
    final fake = FakeApiClient();
    final listing = _listing('l1', 'Saree', media: [
      MediaItem(mediaId: 'm1', kind: MediaKind.image),
      MediaItem(mediaId: 'm2', kind: MediaKind.image),
      MediaItem(mediaId: 'm3', kind: MediaKind.video),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: AppScope(
        api: fake,
        session: _buyerSession(),
        child: Scaffold(
          body: ListingDetailScreen(listing: listing),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Carousel present; images render via the injected builder (no network).
    expect(find.byType(ListingMediaCarousel), findsOneWidget);
    // The video item is on the last page — fling until its tile builds.
    // It renders a tap-to-play tile without touching platform channels.
    final videoText = find.text('Video — tap to play');
    for (var i = 0; i < 3 && videoText.evaluate().isEmpty; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 800);
      await tester.pumpAndSettle();
    }
    expect(videoText, findsOneWidget);
  });

  test('image compression meets the NFR-P1 1MB goal on a hard fixture',
      () async {
    // ~13MB photo-like high-entropy fixture: must come back JPEG and at or
    // under the 1MB client-side goal (targetImageBytes), not merely "smaller".
    final raw = _photoLikeFixture();
    expect(raw.length, greaterThan(10 * 1024 * 1024),
        reason: 'fixture must be realistically large');
    final processor = MediaProcessor();
    final prepared = await processor.prepareImage(PickedMedia(
        file: XFile.fromData(raw, name: 'fabric.jpg', mimeType: 'image/jpeg'),
        kind: MediaKind.image));
    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.bytes.length, lessThan(raw.length));
    expect(prepared.bytes.length, lessThanOrEqualTo(targetImageBytes),
        reason:
            'NFR-P1: compressed image must be <= 1MB (was ${prepared.bytes.length} bytes)');
  });
}

/// Fake picker that simulates Android process death: recoverLostMedia
/// returns a photo the OS kept for us.
class _LosingPicker extends FakeMediaPicker {
  @override
  Future<List<PickedMedia>> recoverLostMedia() async =>
      [PickedMedia(file: XFile.fromData(_testJpg(), name: 'lost.jpg', mimeType: 'image/jpeg'), kind: MediaKind.image)];
}
