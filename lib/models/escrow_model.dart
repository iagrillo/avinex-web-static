


import '../core/utils/formatters.dart';

enum EscrowStatus { pending, released, cancelled, disputed }

extension EscrowStatusX on EscrowStatus {
  String get value {
    switch (this) {
      case EscrowStatus.pending:
        return 'pending';
      case EscrowStatus.released:
        return 'released';
      case EscrowStatus.cancelled:
        return 'cancelled';
      case EscrowStatus.disputed:
        return 'disputed';
    }
  }

  String get label => value[0].toUpperCase() + value.substring(1);

  static EscrowStatus fromValue(String? value) {
    switch (value) {
      case 'released':
        return EscrowStatus.released;
      case 'cancelled':
        return EscrowStatus.cancelled;
      case 'disputed':
        return EscrowStatus.disputed;
      case 'pending':
      default:
        return EscrowStatus.pending;
    }
  }
}


class EscrowModel {


    bool get hasEscrowComponent {
      final escrowPortion = escrowAmount;
      if (escrowPortion != null) {
        return escrowPortion > 0;
      }
      return !isDirectPayment;
    }
  const EscrowModel({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.sellerName,
    required this.sellerEmail,
    required this.sellerPhone,
    required this.buyerPhone,
    required this.description,
    required this.platform,
    required this.amount,
    required this.otp,
    this.directPay = false,
    required this.reference,
    required this.status,
    required this.createdAt,
    this.directPayAmount,
    this.escrowAmount,
  });

  final String id;
  final String buyerId;
  final String buyerName;
  final String sellerId;
  final String sellerName;
  final String sellerEmail;
  final String sellerPhone;
  final String buyerPhone;
  final String description;
  final String platform;
  final double amount;
  final String otp;
  final bool directPay;
  final String reference;
  final EscrowStatus status;
  final DateTime createdAt;
  final double? directPayAmount;
  final double? escrowAmount;

  /// True if this escrow is a mixed payment (both direct and escrow > 0)
  bool get isMixedPayment =>
      (directPayAmount != null && escrowAmount != null &&
       directPayAmount! > 0 && escrowAmount! > 0);

  /// True if this escrow is a pure direct payment (direct > 0, escrow null or 0)
  bool get isDirectOnly =>
      (directPayAmount != null && directPayAmount! > 0 &&
       (escrowAmount == null || escrowAmount == 0));

  /// True if this escrow is a pure escrow payment (escrow > 0, direct null or 0)
  bool get isEscrowOnly =>
      (escrowAmount != null && escrowAmount! > 0 &&
       (directPayAmount == null || directPayAmount == 0));

  /// Legacy: True if this is a pure direct payment (for compatibility)
  bool get isDirectPayment => isDirectOnly;

  double get resolvedEscrowAmount {
    final escrowPortion = escrowAmount;
    if (escrowPortion != null) {
      return escrowPortion;
    }
    return isDirectPayment ? 0 : amount;
  }

  double get resolvedDirectPayAmount {
    final directPortion = directPayAmount;
    if (directPortion != null) {
      return directPortion;
    }
    return isDirectPayment ? amount : 0;
  }

  bool get hasDirectPayComponent => resolvedDirectPayAmount > 0;

  factory EscrowModel.fromMap(Map<String, dynamic> map) {
    return EscrowModel(
      id: map['id'] as String? ?? '',
      buyerId: map['buyer_id'] as String? ?? '',
      buyerName: map['buyer_name'] as String? ?? 'Buyer',
      sellerId: map['seller_id'] as String? ?? '',
      sellerName: map['seller_name'] as String? ?? 'Seller',
      sellerEmail: map['seller_email'] as String? ?? '',
      sellerPhone: map['seller_phone'] as String? ?? '',
      buyerPhone: map['buyer_phone'] as String? ?? '',
      description: map['description'] as String? ?? '',
      platform: map['platform'] as String? ?? 'Other',
      amount: asDouble(map['amount']),
      otp: map['otp'] as String? ?? '',
      directPay: map['direct_pay'] == true,
      reference: map['reference'] as String? ?? '',
      status: EscrowStatusX.fromValue(map['status'] as String?),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      directPayAmount: map['direct_pay_amount'] != null ? asDouble(map['direct_pay_amount']) : null,
      escrowAmount: map['escrow_amount'] != null ? asDouble(map['escrow_amount']) : null,
    );
  }

  EscrowModel copyWith({EscrowStatus? status}) {
    return EscrowModel(
      id: id,
      buyerId: buyerId,
      buyerName: buyerName,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerEmail: sellerEmail,
      sellerPhone: sellerPhone,
      buyerPhone: buyerPhone,
      description: description,
      platform: platform,
      amount: amount,
      otp: otp,
      directPay: directPay,
      reference: reference,
      status: status ?? this.status,
      createdAt: createdAt,
      directPayAmount: directPayAmount,
      escrowAmount: escrowAmount,
    );
  }
}
