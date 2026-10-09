// Media + ads models (media-ads-contract.md v1, SC-1, SC-2).
//
// Field names mirror the backend JSON (snake_case) via explicit fromJson
// mapping so the wire contract stays visible in one place.
library;

enum MediaKind { image, video }

MediaKind mediaKindFrom(String s) => s == 'video' ? MediaKind.video : MediaKind.image;

/// One accepted media item attached to a listing.
class MediaItem {
  MediaItem({required this.mediaId, required this.kind, this.thumbUrl});

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        mediaId: (j['media_id'] ?? '') as String,
        kind: mediaKindFrom((j['kind'] ?? 'image') as String),
        thumbUrl: j['thumb_url'] as String?,
      );

  final String mediaId;
  final MediaKind kind;
  final String? thumbUrl;
}

/// Ticket from POST /v1/media/upload-url.
class MediaUploadTicket {
  MediaUploadTicket({
    required this.mediaId,
    required this.uploadUrl,
    required this.expiresAt,
  });

  factory MediaUploadTicket.fromJson(Map<String, dynamic> j) =>
      MediaUploadTicket(
        mediaId: (j['media_id'] ?? '') as String,
        uploadUrl: (j['upload_url'] ?? '') as String,
        expiresAt: (j['expires_at'] ?? '') as String,
      );

  final String mediaId;
  final String uploadUrl;
  final String expiresAt;
}

/// Result of POST /v1/media/{id}/complete.
class MediaCompleteResult {
  MediaCompleteResult({required this.status, this.reason});

  factory MediaCompleteResult.fromJson(Map<String, dynamic> j) =>
      MediaCompleteResult(
        status: (j['status'] ?? '') as String,
        reason: j['reason'] as String?,
      );

  final String status; // accepted | rejected
  final String? reason;

  bool get accepted => status == 'accepted';
}

/// GET /v1/ads/config
class AdsConfig {
  AdsConfig({required this.currency, required this.prices});

  factory AdsConfig.fromJson(Map<String, dynamic> j) {
    final raw = (j['prices'] as Map<String, dynamic>?) ?? const {};
    final prices = <int, int>{};
    for (final e in raw.entries) {
      final days = int.tryParse(e.key);
      final sek = (e.value as num?)?.toInt();
      if (days != null && sek != null) prices[days] = sek;
    }
    return AdsConfig(
      currency: (j['currency'] ?? 'SEK') as String,
      prices: prices,
    );
  }

  final String currency;
  final Map<int, int> prices; // days -> price SEK

  List<int> get dayOptions {
    final ds = prices.keys.toList()..sort();
    return ds;
  }
}

/// POST /v1/ads/promotions (+ /pay)
class Promotion {
  Promotion({
    required this.promotionId,
    required this.state,
    required this.amountSek,
    this.expiresAt,
  });

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        promotionId: (j['promotion_id'] ?? '') as String,
        state: (j['state'] ?? '') as String,
        amountSek: (j['amount_sek'] as num?)?.toInt() ?? 0,
        expiresAt: j['expires_at'] as String?,
      );

  final String promotionId;
  final String state; // pending_payment | pending_review | active | rejected | expired
  final int amountSek;
  final String? expiresAt;

  bool get pendingPayment => state == 'pending_payment';
  bool get pendingReview => state == 'pending_review';
}

/// GET /v1/ads/slot?placement=feed
class AdSlot {
  AdSlot({required this.type, this.listingId, this.headline});

  factory AdSlot.fromJson(Map<String, dynamic> j) => AdSlot(
        type: (j['type'] ?? 'none') as String,
        listingId: j['listing_id'] as String?,
        headline: j['headline'] as String?,
      );

  factory AdSlot.empty() => AdSlot(type: 'none');

  final String type; // none | promotion
  final String? listingId;
  final String? headline;

  bool get hasContent => type != 'none';
}
