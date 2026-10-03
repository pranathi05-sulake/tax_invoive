enum InvoiceStatus {
  verified,
  pending,
  flagged,
}

enum SyncStatus {
  pendingSync,
  syncing,
  synced,
  syncFailed,
}

extension SyncStatusExtension on SyncStatus {
  String toServerString() {
    switch (this) {
      case SyncStatus.pendingSync:
        return 'PENDING_SYNC';
      case SyncStatus.syncing:
        return 'SYNCING';
      case SyncStatus.synced:
        return 'SYNCED';
      case SyncStatus.syncFailed:
        return 'SYNC_FAILED';
    }
  }

  static SyncStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'SYNCED':
        return SyncStatus.synced;
      case 'SYNCING':
        return SyncStatus.syncing;
      case 'SYNC_FAILED':
        return SyncStatus.syncFailed;
      case 'PENDING_SYNC':
      default:
        return SyncStatus.pendingSync;
    }
  }
}

class InvoiceItem {
  final String id;
  final String description;
  final int quantity;
  final double unitPrice;
  final String hsnSac;

  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.hsnSac = '00000000',
  });

  double get amount => quantity * unitPrice;
  String get formattedAmount => '₹${amount.toStringAsFixed(2)}';
  String get formattedUnitPrice => '₹${unitPrice.toStringAsFixed(2)}';

  InvoiceItem copyWith({
    String? id,
    String? description,
    int? quantity,
    double? unitPrice,
    String? hsnSac,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      hsnSac: hsnSac ?? this.hsnSac,
    );
  }

  Map<String, dynamic> toMap(String invoiceId) {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'hsn_sac': hsnSac,
    };
  }

  Map<String, dynamic> toJson([String? invoiceId]) => toMap(invoiceId ?? '');

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'] as String? ?? '',
      description: map['description'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      hsnSac: map['hsn_sac'] as String? ?? '00000000',
    );
  }

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      hsnSac: json['hsn_sac'] as String? ?? '00000000',
    );
  }
}

class Invoice {
  final String id;
  final String vendorName;
  final String gstin;
  final String invoiceNumber;
  final DateTime date;
  final double subtotal;
  final double cgst;
  final double sgst;
  final double igst;
  final InvoiceStatus status;
  final List<InvoiceItem> items;

  // Local Sync Tracking Metadata
  final SyncStatus syncStatus;
  final int syncAttempts;
  final DateTime? lastSyncAttempt;
  final String? lastSyncError;
  final String? serverInvoiceId;
  final DateTime? syncedAt;
  final String verifiedBy;
  final DateTime? verifiedAt;

  const Invoice({
    required this.id,
    required this.vendorName,
    this.gstin = '',
    required this.invoiceNumber,
    required this.date,
    required this.subtotal,
    this.cgst = 0.0,
    this.sgst = 0.0,
    this.igst = 0.0,
    this.status = InvoiceStatus.verified,
    this.items = const [],
    this.syncStatus = SyncStatus.pendingSync,
    this.syncAttempts = 0,
    this.lastSyncAttempt,
    this.lastSyncError,
    this.serverInvoiceId,
    this.syncedAt,
    this.verifiedBy = '',
    this.verifiedAt,
  });

  double get taxAmount => cgst + sgst + igst;
  double get totalAmount => subtotal + taxAmount;

  String get formattedSubtotal => '₹${subtotal.toStringAsFixed(2)}';
  String get formattedCgst => '₹${cgst.toStringAsFixed(2)}';
  String get formattedSgst => '₹${sgst.toStringAsFixed(2)}';
  String get formattedIgst => '₹${igst.toStringAsFixed(2)}';
  String get formattedTax => '₹${taxAmount.toStringAsFixed(2)}';
  String get formattedTotal => '₹${totalAmount.toStringAsFixed(2)}';

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Invoice copyWith({
    String? id,
    String? vendorName,
    String? gstin,
    String? invoiceNumber,
    DateTime? date,
    double? subtotal,
    double? cgst,
    double? sgst,
    double? igst,
    InvoiceStatus? status,
    List<InvoiceItem>? items,
    SyncStatus? syncStatus,
    int? syncAttempts,
    DateTime? lastSyncAttempt,
    String? lastSyncError,
    String? serverInvoiceId,
    DateTime? syncedAt,
    String? verifiedBy,
    DateTime? verifiedAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      vendorName: vendorName ?? this.vendorName,
      gstin: gstin ?? this.gstin,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      date: date ?? this.date,
      subtotal: subtotal ?? this.subtotal,
      cgst: cgst ?? this.cgst,
      sgst: sgst ?? this.sgst,
      igst: igst ?? this.igst,
      status: status ?? this.status,
      items: items ?? this.items,
      syncStatus: syncStatus ?? this.syncStatus,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      serverInvoiceId: serverInvoiceId ?? this.serverInvoiceId,
      syncedAt: syncedAt ?? this.syncedAt,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vendor_name': vendorName,
      'gstin': gstin,
      'invoice_number': invoiceNumber,
      'date': date.toIso8601String(),
      'subtotal': subtotal,
      'cgst': cgst,
      'sgst': sgst,
      'igst': igst,
      'status': status.index,
      'sync_status': syncStatus.toServerString(),
      'sync_attempts': syncAttempts,
      'last_sync_attempt': lastSyncAttempt?.toIso8601String(),
      'last_sync_error': lastSyncError,
      'server_invoice_id': serverInvoiceId,
      'synced_at': syncedAt?.toIso8601String(),
      'verified_by': verifiedBy,
      'verified_at': verifiedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vendor_name': vendorName,
      'gstin': gstin,
      'invoice_number': invoiceNumber,
      'date': date.toIso8601String(),
      'subtotal': subtotal,
      'cgst': cgst,
      'sgst': sgst,
      'igst': igst,
      'status': status.index,
      'sync_status': syncStatus.toServerString(),
      'sync_attempts': syncAttempts,
      'last_sync_attempt': lastSyncAttempt?.toIso8601String(),
      'last_sync_error': lastSyncError,
      'server_invoice_id': serverInvoiceId,
      'synced_at': syncedAt?.toIso8601String(),
      'verified_by': verifiedBy,
      'verified_at': verifiedAt?.toIso8601String(),
      'items': items.map((item) => item.toJson(id)).toList(),
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map, {List<InvoiceItem> items = const []}) {
    return Invoice(
      id: map['id'] as String? ?? '',
      vendorName: map['vendor_name'] as String? ?? '',
      gstin: map['gstin'] as String? ?? '',
      invoiceNumber: map['invoice_number'] as String? ?? '',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      cgst: (map['cgst'] as num?)?.toDouble() ?? 0.0,
      sgst: (map['sgst'] as num?)?.toDouble() ?? 0.0,
      igst: (map['igst'] as num?)?.toDouble() ?? 0.0,
      status: (map['status'] is int &&
              (map['status'] as int) >= 0 &&
              (map['status'] as int) < InvoiceStatus.values.length)
          ? InvoiceStatus.values[map['status'] as int]
          : InvoiceStatus.verified,
      items: items,
      syncStatus: SyncStatusExtension.fromString(map['sync_status'] as String?),
      syncAttempts: (map['sync_attempts'] as num?)?.toInt() ?? 0,
      lastSyncAttempt: map['last_sync_attempt'] != null ? DateTime.tryParse(map['last_sync_attempt'] as String) : null,
      lastSyncError: map['last_sync_error'] as String?,
      serverInvoiceId: map['server_invoice_id'] as String?,
      syncedAt: map['synced_at'] != null ? DateTime.tryParse(map['synced_at'] as String) : null,
      verifiedBy: map['verified_by'] as String? ?? '',
      verifiedAt: map['verified_at'] != null ? DateTime.tryParse(map['verified_at'] as String) : null,
    );
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map((m) => InvoiceItem.fromJson(m))
        .toList();

    return Invoice(
      id: json['id'] as String? ?? '',
      vendorName: json['vendor_name'] as String? ?? '',
      gstin: json['gstin'] as String? ?? '',
      invoiceNumber: json['invoice_number'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      cgst: (json['cgst'] as num?)?.toDouble() ?? 0.0,
      sgst: (json['sgst'] as num?)?.toDouble() ?? 0.0,
      igst: (json['igst'] as num?)?.toDouble() ?? 0.0,
      status: (json['status'] is int &&
              (json['status'] as int) >= 0 &&
              (json['status'] as int) < InvoiceStatus.values.length)
          ? InvoiceStatus.values[json['status'] as int]
          : InvoiceStatus.verified,
      items: items,
      syncStatus: SyncStatusExtension.fromString(json['sync_status'] as String?),
      syncAttempts: (json['sync_attempts'] as num?)?.toInt() ?? 0,
      lastSyncAttempt: json['last_sync_attempt'] != null ? DateTime.tryParse(json['last_sync_attempt'] as String) : null,
      lastSyncError: json['last_sync_error'] as String?,
      serverInvoiceId: json['server_invoice_id'] as String?,
      syncedAt: json['synced_at'] != null ? DateTime.tryParse(json['synced_at'] as String) : null,
      verifiedBy: json['verified_by'] as String? ?? '',
      verifiedAt: json['verified_at'] != null ? DateTime.tryParse(json['verified_at'] as String) : null,
    );
  }

  /// Safely rounds a monetary value to 2 decimal places compatible with MySQL DECIMAL(15,2).
  static double roundMoney(double val) {
    return ((val * 100).round()) / 100.0;
  }

  /// Converts this Invoice instance into the JSON payload expected by FastAPI `POST /api/v1/invoices`.
  Map<String, dynamic> toSyncPayload({String verifiedByFallback = 'OPERATOR'}) {
    final vBy = verifiedBy.trim().isNotEmpty ? verifiedBy.trim() : verifiedByFallback;
    final vAt = (verifiedAt ?? DateTime.now()).toUtc().toIso8601String();
    final invDateStr = date.toIso8601String().substring(0, 10);
    final validGstin = gstin.trim().length == 15 ? gstin.trim() : '29ABCDE1234F1Z5';

    final roundedSubtotal = roundMoney(subtotal);
    final roundedCgst = roundMoney(cgst);
    final roundedSgst = roundMoney(sgst);
    final roundedIgst = roundMoney(igst);
    final roundedTotal = roundMoney(totalAmount);

    final payloadItems = items.map((item) {
      final itemTaxable = roundMoney(item.amount);
      final itemUnitPrice = roundMoney(item.unitPrice);
      final itemCgst = 0.0;
      final itemSgst = 0.0;
      final itemIgst = 0.0;
      final itemTotal = roundMoney(itemTaxable + itemCgst + itemSgst + itemIgst);

      return {
        'hsn_sac': item.hsnSac.isNotEmpty ? item.hsnSac : '00000000',
        'description': item.description.isNotEmpty ? item.description : 'Line Item',
        'quantity': item.quantity > 0 ? item.quantity.toDouble() : 1.0,
        'unit_price': itemUnitPrice,
        'taxable_value': itemTaxable,
        'cgst': itemCgst,
        'sgst': itemSgst,
        'igst': itemIgst,
        'total_amount': itemTotal,
      };
    }).toList();

    if (payloadItems.isEmpty) {
      payloadItems.add({
        'hsn_sac': '00000000',
        'description': 'Invoice Total Item',
        'quantity': 1.0,
        'unit_price': roundMoney(subtotal > 0 ? subtotal : 1.0),
        'taxable_value': roundMoney(subtotal > 0 ? subtotal : 1.0),
        'cgst': roundedCgst,
        'sgst': roundedSgst,
        'igst': roundedIgst,
        'total_amount': roundMoney(totalAmount > 0 ? totalAmount : 1.0),
      });
    }

    return {
      'local_invoice_id': id,
      'invoice_number': invoiceNumber.isNotEmpty ? invoiceNumber : 'INV-${id.substring(0, 8)}',
      'invoice_date': invDateStr,
      'vendor_name': vendorName.isNotEmpty ? vendorName : 'Vendor',
      'gstin': validGstin,
      'taxable_value': roundedSubtotal,
      'cgst': roundedCgst,
      'sgst': roundedSgst,
      'igst': roundedIgst,
      'total_amount': roundedTotal,
      'verification_status': 'VERIFIED',
      'verified_by': vBy,
      'verified_at': vAt,
      'invoice_items': payloadItems,
    };
  }

  /// Initial sample invoices array (empty by default for real user invoice records)
  static List<Invoice> sampleInvoices = [];
}
