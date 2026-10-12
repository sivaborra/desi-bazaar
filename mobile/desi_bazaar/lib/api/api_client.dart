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
  Future<void> requestOtp(String phone);
  Future<String> verifyOtp(String phone, String code);

  /// FR-B1d: verify + learn whether registration is needed.
  Future<OtpVerifyResult> verifyOtpResult(String phone, String code);
  Future<void> requestEmailOtp(String email);
  Future<String> verifyEmailOtp(String email, String code);

  /// FR-B1d: verify + learn whether registration is needed.
  Future<OtpVerifyResult> verifyEmailOtpResult(String email, String code);

  /// FR-B1d: complete registration after OTP verification.
  Future<String> register({
    String? phone,
    String? email,
    String? displayName,
    required bool consentAccepted,
    required String consentVersion,
    required bool marketingOptIn,
    required bool ageConfirmed,
  });

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
    String? thumbnailMediaId,
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
  Future<List<AdminUser>> adminUsers();
  Future<Map<String, dynamic>> setUserRole({
    required String userId,
    required String role,
  });
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

  /// DAC7 threshold monitoring (SC-5, FR-D4–D8). Returns null when disabled.
  Future<Dac7Status?> dac7Status();
  Future<String> submitTin(String tin);
  Future<List<Dac7SellerRow>> dac7AdminSellers();
  Future<bool> setDac7Enabled(bool enabled);
  Future<void> setDac7SellerPaused(String sellerId, bool paused, String reason);
}

/// DAC7 seller threshold status (FR-D4).
class Dac7Status {
  Dac7Status({
    required this.monitoringEnabled,
    this.year = 0,
    this.transactions = 0,
    this.transactionsThreshold = 30,
    this.eur = 0.0,
    this.eurThreshold = 2000.0,
    this.tier = 'none',
    this.tinProvided = false,
    this.tinLast4,
    this.paused = false,
    this.pauseReason,
  });

  final bool monitoringEnabled;
  final int year;
  final int transactions;
  final int transactionsThreshold;
  final double eur;
  final double eurThreshold;
  final String tier;
  final bool tinProvided;
  final String? tinLast4;
  final bool paused;
  final String? pauseReason;

  factory Dac7Status.fromJson(Map<String, dynamic> j) => Dac7Status(
        monitoringEnabled: (j['monitoring_enabled'] ?? false) as bool,
        year: (j['year'] ?? 0) as int,
        transactions: (j['transactions'] ?? 0) as int,
        transactionsThreshold: (j['transactions_threshold'] ?? 30) as int,
        eur: ((j['eur'] ?? 0) as num).toDouble(),
        eurThreshold: ((j['eur_threshold'] ?? 2000) as num).toDouble(),
        tier: (j['tier'] ?? 'none') as String,
        tinProvided: (j['tin_provided'] ?? false) as bool,
        tinLast4: j['tin_last4'] as String?,
        paused: (j['paused'] ?? false) as bool,
        pauseReason: j['pause_reason'] as String?,
      );
}

/// One row of the admin DAC7 proximity view (FR-D8).
class Dac7SellerRow {
  Dac7SellerRow({
    required this.sellerId,
    required this.transactions,
    required this.eur,
    required this.tier,
    required this.proximity,
    required this.tinProvided,
    required this.paused,
  });

  final String sellerId;
  final int transactions;
  final double eur;
  final String tier;
  final double proximity;
  final bool tinProvided;
  final bool paused;

  factory Dac7SellerRow.fromJson(Map<String, dynamic> j) => Dac7SellerRow(
        sellerId: (j['seller_id'] ?? '') as String,
        transactions: (j['transactions'] ?? 0) as int,
        eur: ((j['eur'] ?? 0) as num).toDouble(),
        tier: (j['tier'] ?? 'none') as String,
        proximity: ((j['proximity'] ?? 0) as num).toDouble(),
        tinProvided: (j['tin_provided'] ?? false) as bool,
        paused: (j['paused'] ?? false) as bool,
      );
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

  /// Network calls time out after 15s so the UI never hangs on a dead
  /// backend — the auth screen shows "Please wait…" while _busy is true.
  static const _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) _throwFor(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> body,
      {Set<int> okStatuses = const {200}}) async {
    final r = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (!okStatuses.contains(r.statusCode)) _throwFor(r);
    if (r.body.isEmpty) return {};
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patchJson(
      Uri uri, Map<String, dynamic> body) async {
    final r = await http
        .patch(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (r.statusCode != 200) _throwFor(r);
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
  Future<void> requestOtp(String phone) async {
    await _postJson(_u('/auth/otp/request'), {'phone': phone});
  }

  @override
  Future<String> verifyOtp(String phone, String code) async {
    final r = await verifyOtpResult(phone, code);
    return r.userId ?? '';
  }

  @override
  Future<OtpVerifyResult> verifyOtpResult(String phone, String code) async {
    final j = await _postJson(_u('/auth/otp/verify'), {
      'phone': phone,
      'code': code,
    });
    return OtpVerifyResult(
      userId: j['user_id'] as String?,
      isNewUser: (j['is_new_user'] ?? false) as bool,
    );
  }

  @override
  Future<void> requestEmailOtp(String email) async {
    await _postJson(_u('/auth/otp/request'), {'email': email});
  }

  @override
  Future<String> verifyEmailOtp(String email, String code) async {
    final r = await verifyEmailOtpResult(email, code);
    return r.userId ?? '';
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtpResult(String email, String code) async {
    final j = await _postJson(_u('/auth/otp/verify'), {
      'email': email,
      'code': code,
    });
    return OtpVerifyResult(
      userId: j['user_id'] as String?,
      isNewUser: (j['is_new_user'] ?? false) as bool,
    );
  }

  @override
  Future<String> register({
    String? phone,
    String? email,
    String? displayName,
    required bool consentAccepted,
    required String consentVersion,
    required bool marketingOptIn,
    required bool ageConfirmed,
  }) async {
    final j = await _postJson(
      _u('/auth/register'),
      {
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
        'consent_accepted': consentAccepted,
        'consent_version': consentVersion,
        'marketing_opt_in': marketingOptIn,
        'age_confirmed': ageConfirmed,
      },
      okStatuses: const {200, 201},
    );
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
    String? thumbnailMediaId,
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
        if (thumbnailMediaId != null) 'thumbnail_media_id': thumbnailMediaId,
      },
      okStatuses: const {200, 201},
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
      okStatuses: const {200, 201},
    );
  }

  @override
  Future<List<AdminUser>> adminUsers() async {
    final j = await _getJson(_u('/admin/users'));
    final users = (j['users'] as List?) ?? const [];
    return users
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> setUserRole({
    required String userId,
    required String role,
  }) async {
    return _patchJson(_u('/admin/users/$userId'), {'role': role});
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
    }, okStatuses: const {200, 201});
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
      okStatuses: const {200, 201},
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
      okStatuses: const {200, 201},
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

  @override
  Future<Dac7Status?> dac7Status() async {
    final j = await _getJson(_u('/dac7/status'));
    if ((j['monitoring_enabled'] ?? false) != true) return null;
    return Dac7Status.fromJson(j);
  }

  @override
  Future<String> submitTin(String tin) async {
    final j = await _postJson(_u('/dac7/tin'), {'tin': tin});
    return (j['tin_last4'] ?? '') as String;
  }

  @override
  Future<List<Dac7SellerRow>> dac7AdminSellers() async {
    final j = await _getJson(_u('/admin/dac7/sellers'));
    final items = (j['sellers'] as List?) ?? const [];
    return items
        .map((e) => Dac7SellerRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<bool> setDac7Enabled(bool enabled) async {
    final j =
        await _postJson(_u('/admin/dac7/config'), {'monitoring_enabled': enabled});
    return (j['monitoring_enabled'] ?? false) as bool;
  }

  @override
  Future<void> setDac7SellerPaused(
      String sellerId, bool paused, String reason) async {
    await _postJson(_u('/admin/dac7/sellers/$sellerId/pause'), {
      'paused': paused,
      'reason': reason,
    });
  }
}

/// In-memory fake for widget tests. Records calls so tests can assert
/// behaviour without a backend.
class FakeApiClient implements DesiBazaarApi {
  FakeApiClient({
    this.listings = const [],
    this.order,
    this.commandError,
    this.reserveOrder,
    this.stubAdminUsers = const [],
  });

  final List<Listing> listings;
  final OrderDetail? order;
  final OrderDetail? reserveOrder;
  final ApiException? commandError;

  /// FR-A4: stubbed admin user list.
  final List<AdminUser> stubAdminUsers;

  final List<String> calls = [];
  int? lastReviewRating;
  String? lastReviewText;
  List<String> lastCreateMediaIds = [];
  String? lastCreateThumbnailId;
  final List<Map<String, dynamic>> commandContexts = [];

  @override
  Future<void> requestOtp(String phone) async => calls.add('requestOtp:$phone');

  @override
  Future<String> verifyOtp(String phone, String code) async {
    calls.add('verifyOtp:$phone');
    if (code != '123456') throw ApiException(422, 'Not allowed right now — invalid or expired code');
    return 'buyer-demo';
  }

  @override
  Future<OtpVerifyResult> verifyOtpResult(String phone, String code) async {
    final userId = await verifyOtp(phone, code);
    return OtpVerifyResult(userId: userId, isNewUser: fakeIsNewUser);
  }

  @override
  Future<void> requestEmailOtp(String email) async =>
      calls.add('requestEmailOtp:$email');

  @override
  Future<String> verifyEmailOtp(String email, String code) async {
    calls.add('verifyEmailOtp:$email');
    if (code != '123456') throw ApiException(422, 'Not allowed right now — invalid or expired code');
    return 'buyer-demo';
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtpResult(String email, String code) async {
    final userId = await verifyEmailOtp(email, code);
    return OtpVerifyResult(userId: userId, isNewUser: fakeIsNewUser);
  }

  /// FR-B1d test hook: make the next verify return isNewUser=true.
  bool fakeIsNewUser = false;

  @override
  Future<String> register({
    String? phone,
    String? email,
    String? displayName,
    required bool consentAccepted,
    required String consentVersion,
    required bool marketingOptIn,
    required bool ageConfirmed,
  }) async {
    calls.add('register:${email ?? phone}');
    lastRegisterConsent = consentAccepted;
    lastRegisterMarketing = marketingOptIn;
    lastRegisterVersion = consentVersion;
    if (!consentAccepted) throw ApiException(422, 'consent required');
    if (!ageConfirmed) throw ApiException(422, 'age confirmation required');
    return 'buyer-new';
  }

  bool? lastRegisterConsent;
  bool? lastRegisterMarketing;
  String? lastRegisterVersion;

  @override
  Future<List<AdminUser>> adminUsers() async => stubAdminUsers;

  @override
  Future<Map<String, dynamic>> setUserRole({
    required String userId,
    required String role,
  }) async {
    calls.add('setUserRole:$userId:$role');
    return {'ok': true, 'user_id': userId, 'new_role': role};
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
    String? thumbnailMediaId,
  }) async {
    calls.add('createListing:$category:${mediaIds.length}media');
    lastCreateMediaIds = List.of(mediaIds);
    lastCreateThumbnailId = thumbnailMediaId;
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

  Dac7Status? nextDac7Status;

  @override
  Future<Dac7Status?> dac7Status() async {
    calls.add('dac7Status');
    return nextDac7Status;
  }

  @override
  Future<String> submitTin(String tin) async {
    calls.add('submitTin');
    return '••••${tin.substring(tin.length - 4)}';
  }

  List<Dac7SellerRow> nextDac7Rows = const [];

  @override
  Future<List<Dac7SellerRow>> dac7AdminSellers() async {
    calls.add('dac7AdminSellers');
    return nextDac7Rows;
  }

  @override
  Future<bool> setDac7Enabled(bool enabled) async {
    calls.add('setDac7Enabled:$enabled');
    return enabled;
  }

  @override
  Future<void> setDac7SellerPaused(
      String sellerId, bool paused, String reason) async {
    calls.add('setDac7SellerPaused:$sellerId:$paused');
  }
}
