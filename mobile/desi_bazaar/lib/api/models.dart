// Typed models for the Desi Bazaar slice backend (frozen SRS v1.5).
//
// Field names mirror the backend JSON (snake_case) via explicit fromJson
// mapping so the wire contract stays visible in one place.
library;

import 'media.dart';

/// User-readable API failure. Never thrown silently: every screen surfaces
/// [message] to the user.
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => 'ApiException($status): $message';
}

class Listing {
  Listing({
    required this.id,
    required this.category,
    required this.condition,
    required this.sizeText,
    required this.priceSek,
    this.defectDisclosure,
    this.sellerBadgeScope,
    this.sellerBadgeDate,
    this.sellerId,
    this.unitsAvailable = 0,
    this.promoted = false,
    this.media = const [],
  });

  factory Listing.fromJson(Map<String, dynamic> j) {
    final badge = j['seller_badge'] as Map<String, dynamic>?;
    final media = (j['media'] as List?) ?? const [];
    return Listing(
      id: j['id'] as String,
      category: (j['category'] ?? '') as String,
      condition: (j['condition'] ?? '') as String,
      sizeText: (j['size_text'] ?? '') as String,
      priceSek: (j['price_sek'] as num?)?.toInt() ?? 0,
      defectDisclosure: j['defect_disclosure'] as String?,
      sellerBadgeScope: badge?['scope'] as String?,
      sellerBadgeDate: badge?['date'] as String?,
      sellerId: j['seller_id'] as String?,
      unitsAvailable: (j['units_available'] as num?)?.toInt() ?? 0,
      // SC-1: only ever true when the backend says so (DB-TC-189).
      promoted: (j['promoted'] ?? false) as bool,
      media: media
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final String category;
  final String condition;
  final String sizeText;
  final int priceSek;
  final String? defectDisclosure;
  final String? sellerBadgeScope;
  final String? sellerBadgeDate;
  final String? sellerId;
  final int unitsAvailable;

  /// SC-1: true only when the backend marks the listing promoted.
  /// The UI shows the "Sponsored" label exactly when this is true —
  /// never otherwise (DB-TC-189).
  final bool promoted;

  /// SC-2: accepted media (images + videos) for the carousel.
  final List<MediaItem> media;
}

/// The five honest order dimensions (§11 engine).
class OrderDimensions {
  OrderDimensions({
    required this.payment,
    required this.fulfilment,
    required this.cancelRefund,
    required this.dispute,
    required this.ret,
  });

  factory OrderDimensions.fromJson(Map<String, dynamic> j) => OrderDimensions(
        payment: (j['payment'] ?? '') as String,
        fulfilment: (j['fulfilment'] ?? '') as String,
        cancelRefund: (j['cancel_refund'] ?? '') as String,
        dispute: (j['dispute'] ?? '') as String,
        ret: (j['return'] ?? '') as String,
      );

  final String payment;
  final String fulfilment;
  final String cancelRefund;
  final String dispute;
  final String ret;
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.dimensions,
    required this.orderVersion,
    required this.buyerId,
    required this.sellerId,
    required this.snapshot,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> j) => OrderDetail(
        id: j['id'] as String,
        dimensions: OrderDimensions.fromJson(
            (j['dimensions'] as Map<String, dynamic>?) ?? const {}),
        orderVersion: (j['order_version'] as num?)?.toInt() ?? 1,
        buyerId: (j['buyer_id'] ?? '') as String,
        sellerId: (j['seller_id'] ?? '') as String,
        snapshot: (j['snapshot'] as Map<String, dynamic>?) ?? const {},
      );

  final String id;
  final OrderDimensions dimensions;
  final int orderVersion;
  final String buyerId;
  final String sellerId;
  final Map<String, dynamic> snapshot;

  /// Immutable checkout snapshot bits the checkout sheet needs.
  String get snapshotRecipient =>
      (snapshot['recipient'] ?? '—').toString();
  int get snapshotAmountSek =>
      (snapshot['amount_sek'] as num?)?.toInt() ?? 0;
  String get snapshotCategory =>
      ((snapshot['listing'] as Map<String, dynamic>?)?['category'] ?? '')
          .toString();
}

class CommandResult {
  CommandResult({
    required this.orderId,
    required this.operationId,
    required this.replayed,
    required this.dimensions,
    required this.orderVersion,
  });

  factory CommandResult.fromJson(Map<String, dynamic> j) => CommandResult(
        orderId: (j['order_id'] ?? '') as String,
        operationId: (j['operation_id'] ?? '') as String,
        replayed: (j['replayed'] ?? false) as bool,
        dimensions: OrderDimensions.fromJson(
            (j['dimensions'] as Map<String, dynamic>?) ?? const {}),
        orderVersion: (j['order_version'] as num?)?.toInt() ?? 1,
      );

  final String orderId;
  final String operationId;
  final bool replayed;
  final OrderDimensions dimensions;
  final int orderVersion;
}

class QueueApplication {
  QueueApplication({
    required this.id,
    required this.sellerId,
    required this.phone,
    required this.trader,
    this.traderBasis,
    required this.categories,
    required this.submittedAt,
  });

  factory QueueApplication.fromJson(Map<String, dynamic> j) => QueueApplication(
        id: (j['id'] ?? '') as String,
        sellerId: (j['seller_id'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        trader: (j['trader'] ?? false) as bool,
        traderBasis: j['trader_basis'] as String?,
        categories:
            ((j['categories'] as List?) ?? const []).map((e) => '$e').toList(),
        submittedAt: (j['submitted_at'] ?? '') as String,
      );

  final String id;
  final String sellerId;
  final String phone;
  final bool trader;
  final String? traderBasis;
  final List<String> categories;
  final String submittedAt;
}

class SellerPublicProfile {
  SellerPublicProfile({
    required this.sellerId,
    required this.name,
    required this.status,
    this.badgeScope,
    this.badgeDate,
    this.evidenced = 0,
    this.unconfirmed = 0,
    this.inProgress = 0,
  });

  factory SellerPublicProfile.fromJson(Map<String, dynamic> j) {
    final badge = j['badge'] as Map<String, dynamic>?;
    final hist = j['fulfilment_history'] as Map<String, dynamic>?;
    return SellerPublicProfile(
      sellerId: (j['seller_id'] ?? '') as String,
      name: (j['name'] ?? '') as String,
      status: (j['status'] ?? '') as String,
      badgeScope: badge?['scope'] as String?,
      badgeDate: badge?['date'] as String?,
      evidenced: (hist?['evidenced'] as num?)?.toInt() ?? 0,
      unconfirmed: (hist?['unconfirmed'] as num?)?.toInt() ?? 0,
      inProgress: (hist?['in_progress'] as num?)?.toInt() ?? 0,
    );
  }

  final String sellerId;
  final String name;
  final String status;
  final String? badgeScope;
  final String? badgeDate;
  final int evidenced;
  final int unconfirmed;
  final int inProgress;
}
