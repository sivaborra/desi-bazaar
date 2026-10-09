import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'media.dart';
import 'models.dart';

/// Base URL resolution.
///
/// `--dart-define=API_URL=...` wins. Otherwise:
/// - web            -> http://localhost:8100 (same machine serves the build)
/// - Android        -> http://10.0.2.2:8100 (emulator loopback alias)
/// - iOS/desktop    -> http://localhost:8100
const _envBaseUrl = String.fromEnvironment('API_URL');

String resolveBaseUrl() {
  if (_envBaseUrl.isNotEmpty) {
    return _envBaseUrl;
  }
  if (kIsWeb) {
    return 'http://localhost:8100';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'http://10.0.2.2:8100';
    default:
      return 'http://localhost:8100';
  }
}

/// Typed client for the Desi Bazaar slice backend.
///
/// Dev auth: the `X-Principal` header carries the synthetic principal id
/// (e.g. buyer-rohan / seller-anaya / admin-1).
/// TODO(prod): replace X-Principal with the OTP session token from
/// POST /v1/auth/otp/verify once the backend issues real sessions.
abstract class DesiBazaarApi {
  Future<void> requestOtp(String identifier);
  Future<String> verifyOtp(String identifier, String code);

  Future<List<Listing>> listListings({String? q});
  Future<OrderDetail> reserveListing(String listingId);
  Future<OrderDetail> getOrder(String orderId);
  Future<CommandResult> command({
    required String orderId,
    required String operation,
    required int expectedOrderVersion,
    Map<String, dynamic> payload = const {},
    Map<String, dynamic> context = const {},
  });

  Future<String> createListing({
    required String category,
    required String condition,
    required String sizeText,
    String? defectDisclosure,
    required int priceSek,
    List<String> mediaIds = const [],
  });

  Future<Map<String, dynamic>> applySeller({
    required String name,
    required String phone,
    required String idDocumentRef,
    required List<String> categories,
    required bool trader,
    String? traderBasis,
    String? profile,
    String? swishRecipient,
  });

  Future<List<QueueApplication>> sellerQueue();
  Future<Map<String, dynamic>> decideSeller({
    required String sellerId,
    required String decision,
    required String checklistVersion,
    String? reason,
  });

  Future<Map<String, dynamic>> changeRecipient(String swishRecipient);
  Future<SellerPublicProfile> sellerProfile(String sellerId);
  Future<void> submitReview(String orderId, int rating, String text);

  // --- Media (media-ads-contract.md v1, SC-2) ---

  /// Ask the backend for a signed upload URL. Throws [ApiException] (422)
  /// when purpose/type/size is rejected — surfaced honestly by the UI.
  Future<MediaUploadTicket> requestMediaUploadUrl({
    required String purpose,
    required String contentType,
    required int contentLength,
  });

  /// PUT the bytes to the signed URL from the ticket.
  Future<void> uploadMediaBytes(
      String uploadUrl, Uint8List bytes, String contentType);

  /// Tell the backend the upload finished; returns accepted/rejected.
  Future<MediaCompleteResult> completeMediaUpload(
      String mediaId, String checksum);

  // --- Ads (media-ads-contract.md v1, SC-1) ---

  Future<AdsConfig> adsConfig();
  Future<Promotion> createPromotion(
      {required String listingId, required int days});
  Future<Promotion> payPromotion(String promotionId);
  Future<AdSlot> adSlot(String placement);

  /// Read URL for a media item (GET /v1/media/{id} serves bytes on slice).
  String mediaUrl(String mediaId);
}

class HttpApiClient implements DesiBazaarApi {
  HttpApiClient({String? baseUrl, String? principal})
      : baseUrl = baseUrl ?? resolveBaseUrl(),
        principal = principal ?? '';

  final String baseUrl;
  String principal;
  final _uuid = const Uuid();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (principal.isNotEmpty) 'X-Principal': principal,
      };

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/v1$path').replace(queryParameters: query);

  Never _throwFor(http.Response r) {
    String detail;
    try {
      final body = jsonDecode(r.body);
      detail = (body is Map ? body['detail'] : null)?.toString() ?? r.body;
    } catch (_) {
      detail = r.body.isEmpty ? 'empty response' : r.body;
    }
    final message = switch (r.statusCode) {
      400 => 'Bad request — $detail',
      403 => 'Not allowed — $detail',
      404 => 'Not found — $detail',
      409 => 'Conflict — $detail',
      422 => 'Not allowed right now — $detail',
      429 => 'Too many attempts — please wait a few minutes and try again.',
      _ => 'Server error (${r.statusCode}) — $detail',
    };
    throw ApiException(r.statusCode, message);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final r = await http.get(uri, headers: _headers);
    if (r.statusCode != 200) _throwFor(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> body,
      {int ok = 200}) async {
    final r = await http.post(uri, headers: _headers, body: jsonEncode(body));
    if (r.statusCode != ok) _throwFor(r);
    if (r.body.isEmpty) return {};
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// PUT raw bytes (media upload to the signed URL). The signed URL is
  /// absolute and carries its own authorisation — no X-Principal header.
  Future<void> _putBytes(Uri uri, Uint8List bytes, String contentType) async {
    final r = await http.put(uri,
        headers: {'Content-Type': contentType}, body: bytes);
    if (r.statusCode != 200 && r.statusCode != 201) _throwFor(r);
  }

  @override
  Future<void> requestOtp(String identifier) async {
    // FR-B1: phone or email. The '@' decides which field the slice expects.
    final body = identifier.contains('@')
        ? {'email': identifier}
        : {'phone': identifier};
    await _postJson(_u('/auth/otp/request'), body);
  }

  @override
  Future<String> verifyOtp(String identifier, String code) async {
    final body = identifier.contains('@')
        ? {'email': identifier, 'code': code}
        : {'phone': identifier, 'code': code};
    final j = await _postJson(_u('/auth/otp/verify'), body);
    return (j['user_id'] ?? '') as String;
  }

  @override
  Future<List<Listing>> listListings({String? q}) async {
    final j = await _getJson(_u('/listings', {if (q != null && q.isNotEmpty) 'q': q}));
    final items = (j['items'] as List?) ?? const [];
    return items
        .map((e) => Listing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<OrderDetail> reserveListing(String listingId) async {
    // Reserve is a POST with an empty body on this slice.
    final uri = _u('/listings/$listingId/reserve');
    final r = await http.post(uri, headers: _headers);
    if (r.statusCode != 201) _throwFor(r);
    return OrderDetail.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  @override
  Future<OrderDetail> getOrder(String orderId) async {
    return OrderDetail.fromJson(await _getJson(_u('/orders/$orderId')));
  }

  @override
  Future<CommandResult> command({
    required String orderId,
    required String operation,
    required int expectedOrderVersion,
    Map<String, dynamic> payload = const {},
    Map<String, dynamic> context = const {},
  }) async {
    // Stable client-generated operation id (round-9 contract): same id +
    // same content replays safely; the backend 409s on id reuse with
    // different content, so every logical action mints a fresh id.
    final j = await _postJson(_u('/commands'), {
      'operation_id': _uuid.v4(),
      'order_id': orderId,
      'operation': operation,
      'expected_order_version': expectedOrderVersion,
      'payload': payload,
      'context': context,
    });
    return CommandResult.fromJson(j);
  }

  @override
  Future<String> createListing({
    required String category,
    required String condition,
    required String sizeText,
    String? defectDisclosure,
    required int priceSek,
    List<String> mediaIds = const [],
  }) async {
    final j = await _postJson(
      _u('/listings'),
      {
        'category': category,
        'condition': condition,
        'size_text': sizeText,
        if (defectDisclosure != null && defectDisclosure.isNotEmpty)
          'defect_disclosure': defectDisclosure,
        'price_sek': priceSek,
        if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
      },
      ok: 201,
    );
    return (j['id'] ?? '') as String;
  }

  @override
  Future<Map<String, dynamic>> applySeller({
    required String name,
    required String phone,
    required String idDocumentRef,
    required List<String> categories,
    required bool trader,
    String? traderBasis,
    String? profile,
    String? swishRecipient,
  }) async {
    return _postJson(
      _u('/sellers/applications'),
      {
        'name': name,
        'phone': phone,
        'id_document_ref': idDocumentRef,
        'categories': categories,
        'trader': trader,
        if (traderBasis case var tb) 'trader_basis': tb,
        if (profile case var p) 'profile': p,
        if (swishRecipient case var sr) 'swish_recipient': sr,
      },
      ok: 201,
    );
  }

  @override
  Future<List<QueueApplication>> sellerQueue() async {
    final j = await _getJson(_u('/admin/seller-queue'));
    final apps = (j['applications'] as List?) ?? const [];
    return apps
        .map((e) => QueueApplication.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> decideSeller({
    required String sellerId,
    required String decision,
    required String checklistVersion,
    String? reason,
  }) async {
    return _postJson(_u('/admin/sellers/$sellerId/decision'), {
      'decision': decision,
      'checklist_version': checklistVersion,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  @override
  Future<Map<String, dynamic>> changeRecipient(String swishRecipient) async {
    final uri = _u('/sellers/me/recipient');
    final r = await http.patch(uri,
        headers: _headers, body: jsonEncode({'swish_recipient': swishRecipient}));
    if (r.statusCode != 200) _throwFor(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<SellerPublicProfile> sellerProfile(String sellerId) async {
    return SellerPublicProfile.fromJson(await _getJson(_u('/sellers/$sellerId/profile')));
  }

  @override
  Future<void> submitReview(String orderId, int rating, String text) async {
    await _postJson(_u('/orders/$orderId/review'), {
      'rating': rating,
      'text': text,
    }, ok: 201);
  }

  // --- Media (media-ads-contract.md v1, SC-2) ---

  @override
  Future<MediaUploadTicket> requestMediaUploadUrl({
    required String purpose,
    required String contentType,
    required int contentLength,
  }) async {
    final j = await _postJson(
      _u('/media/upload-url'),
      {
        'purpose': purpose,
        'content_type': contentType,
        'content_length': contentLength,
      },
      ok: 201,
    );
    return MediaUploadTicket.fromJson(j);
  }

  @override
  Future<void> uploadMediaBytes(
      String uploadUrl, Uint8List bytes, String contentType) async {
    await _putBytes(Uri.parse(uploadUrl), bytes, contentType);
  }

  @override
  Future<MediaCompleteResult> completeMediaUpload(
      String mediaId, String checksum) async {
    final j = await _postJson(_u('/media/$mediaId/complete'), {
      'checksum': checksum,
    });
    return MediaCompleteResult.fromJson(j);
  }

  // --- Ads (media-ads-contract.md v1, SC-1) ---

  @override
  Future<AdsConfig> adsConfig() async =>
      AdsConfig.fromJson(await _getJson(_u('/ads/config')));

  @override
  Future<Promotion> createPromotion(
      {required String listingId, required int days}) async {
    final j = await _postJson(
      _u('/ads/promotions'),
      {'listing_id': listingId, 'days': days},
      ok: 201,
    );
    return Promotion.fromJson(j);
  }

  @override
  Future<Promotion> payPromotion(String promotionId) async {
    final j = await _postJson(_u('/ads/promotions/$promotionId/pay'), {});
    return Promotion.fromJson(j);
  }

  @override
  Future<AdSlot> adSlot(String placement) async =>
      AdSlot.fromJson(await _getJson(_u('/ads/slot', {'placement': placement})));

  @override
  String mediaUrl(String mediaId) => '$baseUrl/v1/media/$mediaId';
}

/// In-memory fake for widget tests. Records calls so tests can assert
/// behaviour without a backend.
class FakeApiClient implements DesiBazaarApi {
  FakeApiClient({
    this.listings = const [],
    this.order,
    this.commandError,
    this.reserveOrder,
  });

  final List<Listing> listings;
  final OrderDetail? order;
  final OrderDetail? reserveOrder;
  final ApiException? commandError;

  final List<String> calls = [];
  int? lastReviewRating;
  String? lastReviewText;
  List<String> lastCreateMediaIds = [];
  final List<Map<String, dynamic>> commandContexts = [];

  @override
  Future<void> requestOtp(String identifier) async => calls.add('requestOtp:$identifier');

  @override
  Future<String> verifyOtp(String identifier, String code) async {
    calls.add('verifyOtp:$identifier');
    if (code != '123456') throw ApiException(422, 'Not allowed right now — invalid or expired code');
    return 'buyer-demo';
  }

  @override
  Future<List<Listing>> listListings({String? q}) async {
    calls.add('listListings:${q ?? ''}');
    if (q == null || q.isEmpty) return listings;
    return listings.where((l) => l.category.toLowerCase().contains(q.toLowerCase())).toList();
  }

  @override
  Future<OrderDetail> reserveListing(String listingId) async {
    calls.add('reserveListing:$listingId');
    return reserveOrder ?? order!;
  }

  @override
  Future<OrderDetail> getOrder(String orderId) async {
    calls.add('getOrder:$orderId');
    return order!;
  }

  @override
  Future<CommandResult> command({
    required String orderId,
    required String operation,
    required int expectedOrderVersion,
    Map<String, dynamic> payload = const {},
    Map<String, dynamic> context = const {},
  }) async {
    calls.add('command:$operation');
    commandContexts.add(context);
    if (commandError != null) throw commandError!;
    final o = order!;
    return CommandResult(
      orderId: orderId,
      operationId: 'op-test',
      replayed: false,
      dimensions: o.dimensions,
      orderVersion: o.orderVersion + 1,
    );
  }

  @override
  Future<String> createListing({
    required String category,
    required String condition,
    required String sizeText,
    String? defectDisclosure,
    required int priceSek,
    List<String> mediaIds = const [],
  }) async {
    calls.add('createListing:$category:${mediaIds.length}media');
    lastCreateMediaIds = List.of(mediaIds);
    return 'listing-new';
  }

  @override
  Future<Map<String, dynamic>> applySeller({
    required String name,
    required String phone,
    required String idDocumentRef,
    required List<String> categories,
    required bool trader,
    String? traderBasis,
    String? profile,
    String? swishRecipient,
  }) async {
    calls.add('applySeller:$phone');
    return {'application_id': 'app-1', 'status': 'pending'};
  }

  @override
  Future<List<QueueApplication>> sellerQueue() async => [];

  @override
  Future<Map<String, dynamic>> decideSeller({
    required String sellerId,
    required String decision,
    required String checklistVersion,
    String? reason,
  }) async {
    calls.add('decideSeller:$sellerId:$decision');
    return {'seller_id': sellerId, 'decision': decision};
  }

  @override
  Future<Map<String, dynamic>> changeRecipient(String swishRecipient) async {
    calls.add('changeRecipient:$swishRecipient');
    return {'swish_recipient': swishRecipient, 'recipient_hold': true};
  }

  @override
  Future<SellerPublicProfile> sellerProfile(String sellerId) async {
    return SellerPublicProfile(sellerId: sellerId, name: 'Test Seller', status: 'approved');
  }

  @override
  Future<void> submitReview(String orderId, int rating, String text) async {
    calls.add('submitReview:$orderId');
    if (reviewError != null) throw reviewError!;
    lastReviewRating = rating;
    lastReviewText = text;
  }

  /// When set, submitReview throws this (e.g. backend 422 when the order
  /// is not in a reviewable state — FR-R1).
  ApiException? reviewError;

  // --- Media + ads fakes (media-ads-contract.md v1) ---

  /// When set, completeMediaUpload throws this instead of accepting.
  ApiException? completeError;

  /// When set, requestMediaUploadUrl throws this (e.g. a 422 for bad type).
  ApiException? uploadUrlError;

  int _mediaSeq = 0;

  @override
  Future<MediaUploadTicket> requestMediaUploadUrl({
    required String purpose,
    required String contentType,
    required int contentLength,
  }) async {
    calls.add('requestMediaUploadUrl:$purpose:$contentType');
    if (uploadUrlError != null) throw uploadUrlError!;
    _mediaSeq++;
    return MediaUploadTicket(
      mediaId: 'media-$_mediaSeq',
      uploadUrl: 'https://stub.invalid/upload/$_mediaSeq',
      expiresAt: '2030-01-01T00:00:00Z',
    );
  }

  @override
  Future<void> uploadMediaBytes(
      String uploadUrl, Uint8List bytes, String contentType) async {
    calls.add('uploadMediaBytes:${bytes.length}');
  }

  @override
  Future<MediaCompleteResult> completeMediaUpload(
      String mediaId, String checksum) async {
    calls.add('completeMediaUpload:$mediaId');
    if (completeError != null) throw completeError!;
    return MediaCompleteResult(status: 'accepted');
  }

  @override
  Future<AdsConfig> adsConfig() async {
    calls.add('adsConfig');
    return AdsConfig.fromJson({
      'currency': 'SEK',
      'prices': {'1': 29, '3': 69, '7': 129},
    });
  }

  Promotion? nextPromotion;

  @override
  Future<Promotion> createPromotion(
      {required String listingId, required int days}) async {
    calls.add('createPromotion:$listingId:$days');
    return nextPromotion ??
        Promotion(promotionId: 'promo-1', state: 'pending_payment', amountSek: 69);
  }

  @override
  Future<Promotion> payPromotion(String promotionId) async {
    calls.add('payPromotion:$promotionId');
    return Promotion(
        promotionId: promotionId, state: 'pending_review', amountSek: 69);
  }

  AdSlot? nextSlot;

  @override
  Future<AdSlot> adSlot(String placement) async {
    calls.add('adSlot:$placement');
    return nextSlot ?? AdSlot.empty();
  }

  @override
  String mediaUrl(String mediaId) => 'https://fake.invalid/media/$mediaId';
}
