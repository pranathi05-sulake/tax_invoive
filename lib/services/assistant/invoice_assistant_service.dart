import '../../models/invoice.dart';
import '../validation/invoice_validator.dart';

/// Offline, deterministic local query handler for invoice details.
/// Operates strictly read-only on real local [Invoice] data.
class InvoiceAssistantService {
  /// Processes a user query deterministically against the provided [invoice].
  /// Returns standard responses if [invoice] is null or query cannot be answered from invoice data.
  static String processQuery(String rawQuery, {Invoice? invoice}) {
    if (invoice == null) {
      return "Please select an invoice first so I can answer questions about it.";
    }

    final query = _normalizeQuery(rawQuery);
    if (query.isEmpty) {
      return "Please enter a question about the current invoice.";
    }

    // Intent 1: Invoice Details / Summary
    if (_matches(query, [
      'show the invoice details',
      'invoice details',
      'show details',
      'invoice summary',
      'summary',
      'overview'
    ])) {
      return _getInvoiceDetails(invoice);
    }

    // Intent 2: Invoice Number
    if (_matches(query, [
      'what is the invoice number',
      'invoice number',
      'invoice no',
      'invoice id',
      'invoice number?'
    ])) {
      if (invoice.invoiceNumber.trim().isNotEmpty) {
        return "Invoice number: ${invoice.invoiceNumber.trim()}";
      }
      return "Invoice number is not available in the current invoice data.";
    }

    // Intent 3: GSTIN Validity
    if (_matches(query, [
      'is the gstin valid',
      'is gstin valid',
      'gstin validity'
    ])) {
      if (invoice.gstin.trim().isEmpty) {
        return "GSTIN is not available in the current invoice data.";
      }
      final isValidFormat = InvoiceValidator.gstinRegex.hasMatch(invoice.gstin.trim());
      if (isValidFormat) {
        return "GSTIN (${invoice.gstin.trim()}) is valid.";
      } else {
        return "GSTIN (${invoice.gstin.trim()}) is invalid in format.";
      }
    }

    // Intent 4: GSTIN
    if (_matches(query, [
      'what is the gstin',
      'gstin',
      'gst number',
      'vendor gstin',
      'gstin?'
    ])) {
      if (invoice.gstin.trim().isNotEmpty) {
        return "GSTIN: ${invoice.gstin.trim()}";
      }
      return "GSTIN is not available in the current invoice data.";
    }

    // Intent 5: Vendor Name
    if (_matches(query, [
      'what is the vendor name',
      'vendor name',
      'vendor',
      'supplier name',
      'supplier',
      'vendor?'
    ])) {
      if (invoice.vendorName.trim().isNotEmpty) {
        return "Vendor name: ${invoice.vendorName.trim()}";
      }
      return "Vendor name is not available in the current invoice data.";
    }

    // Intent 6: Invoice Date
    if (_matches(query, [
      'what is the invoice date',
      'invoice date',
      'date',
      'date of invoice',
      'invoice date?'
    ])) {
      return "Invoice date: ${invoice.formattedDate}";
    }

    // Intent 7: Total Amount
    if (_matches(query, [
      'what is the total amount',
      'total amount',
      'total',
      'grand total',
      'total price',
      'total amount?'
    ])) {
      return "Total amount: ${invoice.formattedTotal}";
    }

    // Intent 8: Taxable Value
    if (_matches(query, [
      'what is the taxable value',
      'taxable value',
      'taxable amount',
      'taxable value?'
    ])) {
      return "Taxable value: ${invoice.formattedSubtotal}";
    }

    // Intent 9: Subtotal
    if (_matches(query, [
      'what is the subtotal',
      'subtotal',
      'sub total',
      'subtotal?'
    ])) {
      return "Subtotal: ${invoice.formattedSubtotal}";
    }

    // Intent 10: CGST
    if (_matches(query, [
      'what is the cgst',
      'cgst',
      'cgst amount',
      'cgst?'
    ])) {
      return "CGST: ${invoice.formattedCgst}";
    }

    // Intent 11: SGST
    if (_matches(query, [
      'what is the sgst',
      'sgst',
      'sgst amount',
      'sgst?'
    ])) {
      return "SGST: ${invoice.formattedSgst}";
    }

    // Intent 12: IGST
    if (_matches(query, [
      'what is the igst',
      'igst',
      'igst amount',
      'igst?'
    ])) {
      return "IGST: ${invoice.formattedIgst}";
    }

    // Intent 13: Taxes Correct / Tax Summary
    if (_matches(query, [
      'are the taxes correct',
      'tax summary',
      'tax breakdown',
      'taxes correct'
    ])) {
      return _getTaxSummary(invoice);
    }

    // Intent 14: How many items
    if (_matches(query, [
      'how many items are in this invoice',
      'how many items',
      'item count',
      'number of items',
      'items count'
    ])) {
      if (invoice.items.isEmpty) {
        return "No items are listed in this invoice data.";
      }
      return "This invoice contains ${invoice.items.length} item(s).";
    }

    // Intent 15: Show items
    if (_matches(query, [
      'show the items',
      'show items',
      'items',
      'list items',
      'item list'
    ])) {
      return _getItemsSummary(invoice);
    }

    // Intent 16: HSN / SAC
    if (_matches(query, [
      'what is the hsn/sac',
      'what is the hsn sac',
      'hsn/sac',
      'hsn sac',
      'hsn',
      'sac'
    ])) {
      return _getHsnSacSummary(invoice);
    }

    // Intent 17: Quantity
    if (_matches(query, [
      'what is the quantity',
      'quantity',
      'qty',
      'item quantity'
    ])) {
      return _getQuantitySummary(invoice);
    }

    // Intent 18: Item description
    if (_matches(query, [
      'what is the item description',
      'item description',
      'item descriptions',
      'descriptions'
    ])) {
      return _getItemDescriptionsSummary(invoice);
    }

    // Intent 19: Item value / unit price
    if (_matches(query, [
      'what is the item value',
      'item value',
      'unit price',
      'item amount',
      'item price'
    ])) {
      return _getItemValuesSummary(invoice);
    }

    // Intent 20: Is this invoice valid?
    if (_matches(query, [
      'is this invoice valid',
      'is valid',
      'validation',
      'validation status',
      'is invoice valid'
    ])) {
      final validation = InvoiceValidator.validate(invoice);
      if (validation.isValid) {
        return "Yes, this invoice is valid and passes all structural tax compliance rules.";
      } else {
        final warningsList = validation.warnings.map((w) => "• $w").join('\n');
        return "No, this invoice has validation issues:\n$warningsList";
      }
    }

    // Intent 21: Missing fields
    if (_matches(query, [
      'are there any missing fields',
      'missing fields',
      'missing field',
      'check missing fields'
    ])) {
      return _getMissingFieldsSummary(invoice);
    }

    // Intent 22: Validation errors / What needs to be corrected
    if (_matches(query, [
      'what validation errors are present',
      'validation errors',
      'what needs to be corrected',
      'what needs to be corrected?'
    ])) {
      final validation = InvoiceValidator.validate(invoice);
      if (validation.isValid) {
        return "No validation errors are present.";
      } else {
        final warningsList = validation.warnings.map((w) => "• $w").join('\n');
        return "Validation errors present:\n$warningsList";
      }
    }

    // Intent 23: Verification status (Is this invoice verified?)
    if (_matches(query, [
      'is this invoice verified',
      'is verified',
      'verification status',
      'verified status'
    ])) {
      final statusName = invoice.status.name.toUpperCase();
      if (invoice.status == InvoiceStatus.verified) {
        return "Yes, this invoice is marked as VERIFIED.";
      } else {
        return "No, this invoice verification status is: $statusName.";
      }
    }

    // Intent 24: Who verified this invoice?
    if (_matches(query, [
      'who verified this invoice',
      'who verified',
      'verified by'
    ])) {
      if (invoice.verifiedBy.trim().isNotEmpty) {
        return "Verified by: ${invoice.verifiedBy.trim()}";
      }
      return "Verified by information is not available in the current invoice data.";
    }

    // Intent 25: When was it verified?
    if (_matches(query, [
      'when was it verified',
      'when verified',
      'verification date',
      'verified at'
    ])) {
      if (invoice.verifiedAt != null) {
        return "Verified at: ${_formatDateTime(invoice.verifiedAt!)}";
      }
      return "Verification date is not available in the current invoice data.";
    }

    // Intent 26: Is this invoice synced?
    if (_matches(query, [
      'is this invoice synced',
      'is synced',
      'synced'
    ])) {
      if (invoice.syncStatus == SyncStatus.synced) {
        return "Yes, this invoice has been synced to the server.";
      } else {
        return "No, current sync status is: ${invoice.syncStatus.toServerString()}.";
      }
    }

    // Intent 27: What is the sync status?
    if (_matches(query, [
      'what is the sync status',
      'sync status',
      'current sync status'
    ])) {
      var msg = "Sync status: ${invoice.syncStatus.toServerString()} (Attempts: ${invoice.syncAttempts})";
      if (invoice.syncedAt != null) {
        msg += "\nSynced at: ${_formatDateTime(invoice.syncedAt!)}";
      }
      return msg;
    }

    // Intent 28: Why did sync fail?
    if (_matches(query, [
      'why did sync fail',
      'sync error',
      'sync failure reason',
      'why sync failed'
    ])) {
      if (invoice.lastSyncError != null && invoice.lastSyncError!.trim().isNotEmpty) {
        return "Sync error: ${invoice.lastSyncError!.trim()}";
      } else if (invoice.syncStatus == SyncStatus.syncFailed) {
        return "Sync status is SYNC_FAILED, but no detailed error message was recorded.";
      } else {
        return "Sync has not failed. Current status is ${invoice.syncStatus.toServerString()}.";
      }
    }

    // Intent 29: When was it synced?
    if (_matches(query, [
      'when was it synced',
      'synced at',
      'sync date',
      'when synced'
    ])) {
      if (invoice.syncedAt != null) {
        return "Synced at: ${_formatDateTime(invoice.syncedAt!)}";
      }
      return "Synced date is not available in the current invoice data.";
    }

    // Intent 30: Can this invoice be synced?
    if (_matches(query, [
      'can this invoice be synced',
      'can sync',
      'ready to sync'
    ])) {
      final validation = InvoiceValidator.validate(invoice);
      if (!validation.isValid) {
        final warningsList = validation.warnings.map((w) => "• $w").join('\n');
        return "No, this invoice has validation errors that should be resolved before syncing:\n$warningsList";
      }
      return "Yes, this invoice is valid and ready to sync (Status: ${invoice.syncStatus.toServerString()}).";
    }

    // Default response for unmatched or out-of-bounds queries
    return "This information is not available in the current invoice data.";
  }

  static String _normalizeQuery(String q) {
    return q
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\w\s\/\#\?]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _matches(String normalizedQuery, List<String> targets) {
    for (final target in targets) {
      final normTarget = _normalizeQuery(target);
      if (normalizedQuery == normTarget || normalizedQuery.contains(normTarget)) {
        return true;
      }
    }
    return false;
  }

  static String _getInvoiceDetails(Invoice invoice) {
    final sb = StringBuffer();
    sb.writeln("Invoice Details:");
    sb.writeln("• Number: ${invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : 'N/A'}");
    sb.writeln("• Vendor: ${invoice.vendorName.isNotEmpty ? invoice.vendorName : 'N/A'}");
    sb.writeln("• GSTIN: ${invoice.gstin.isNotEmpty ? invoice.gstin : 'N/A'}");
    sb.writeln("• Date: ${invoice.formattedDate}");
    sb.writeln("• Subtotal: ${invoice.formattedSubtotal}");
    sb.writeln("• Taxes (CGST/SGST/IGST): ${invoice.formattedCgst} / ${invoice.formattedSgst} / ${invoice.formattedIgst}");
    sb.writeln("• Total Amount: ${invoice.formattedTotal}");
    sb.writeln("• Line Items: ${invoice.items.length}");
    sb.writeln("• Status: ${invoice.status.name.toUpperCase()}");
    sb.writeln("• Sync Status: ${invoice.syncStatus.toServerString()}");
    return sb.toString().trim();
  }

  static String _getTaxSummary(Invoice invoice) {
    final expectedTotal = invoice.subtotal + invoice.cgst + invoice.sgst + invoice.igst;
    final isTaxCorrect = (invoice.totalAmount - expectedTotal).abs() <= 0.1;
    final sb = StringBuffer();
    sb.writeln("Tax Summary:");
    sb.writeln("• CGST: ${invoice.formattedCgst}");
    sb.writeln("• SGST: ${invoice.formattedSgst}");
    sb.writeln("• IGST: ${invoice.formattedIgst}");
    sb.writeln("• Total Tax: ${invoice.formattedTax}");
    sb.writeln("• Subtotal: ${invoice.formattedSubtotal}");
    sb.writeln("• Calculated Total: ₹${expectedTotal.toStringAsFixed(2)}");
    sb.writeln(isTaxCorrect ? "• Tax Math: Correct" : "• Tax Math: Discrepancy detected between subtotal + taxes and total amount.");
    return sb.toString().trim();
  }

  static String _getItemsSummary(Invoice invoice) {
    if (invoice.items.isEmpty) {
      return "No items are listed in this invoice data.";
    }
    final sb = StringBuffer();
    sb.writeln("Invoice Items (${invoice.items.length}):");
    for (int i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      sb.writeln("${i + 1}. ${item.description.isNotEmpty ? item.description : 'Unnamed Item'}");
      sb.writeln("   Qty: ${item.quantity} | Unit Price: ${item.formattedUnitPrice} | HSN/SAC: ${item.hsnSac} | Total: ${item.formattedAmount}");
    }
    return sb.toString().trim();
  }

  static String _getHsnSacSummary(Invoice invoice) {
    if (invoice.items.isEmpty) {
      return "HSN/SAC is not available in the current invoice data.";
    }
    final itemsWithHsn = invoice.items.where((i) => i.hsnSac.isNotEmpty).toList();
    if (itemsWithHsn.isEmpty) {
      return "HSN/SAC is not available in the current invoice data.";
    }
    final sb = StringBuffer("HSN/SAC Codes:\n");
    for (final item in itemsWithHsn) {
      sb.writeln("• ${item.description}: ${item.hsnSac}");
    }
    return sb.toString().trim();
  }

  static String _getQuantitySummary(Invoice invoice) {
    if (invoice.items.isEmpty) {
      return "Quantity information is not available in the current invoice data.";
    }
    final sb = StringBuffer("Item Quantities:\n");
    for (final item in invoice.items) {
      sb.writeln("• ${item.description}: ${item.quantity}");
    }
    return sb.toString().trim();
  }

  static String _getItemDescriptionsSummary(Invoice invoice) {
    if (invoice.items.isEmpty) {
      return "Item descriptions are not available in the current invoice data.";
    }
    final sb = StringBuffer("Item Descriptions:\n");
    for (final item in invoice.items) {
      sb.writeln("• ${item.description}");
    }
    return sb.toString().trim();
  }

  static String _getItemValuesSummary(Invoice invoice) {
    if (invoice.items.isEmpty) {
      return "Item value is not available in the current invoice data.";
    }
    final sb = StringBuffer("Item Values:\n");
    for (final item in invoice.items) {
      sb.writeln("• ${item.description}: ${item.quantity} x ${item.formattedUnitPrice} = ${item.formattedAmount}");
    }
    return sb.toString().trim();
  }

  static String _getMissingFieldsSummary(Invoice invoice) {
    final missing = <String>[];
    if (invoice.vendorName.trim().isEmpty) missing.add("Vendor Name");
    if (invoice.invoiceNumber.trim().isEmpty) missing.add("Invoice Number");
    if (invoice.gstin.trim().isEmpty) missing.add("GSTIN");
    if (invoice.items.isEmpty) missing.add("Line Items");

    if (missing.isEmpty) {
      return "No critical fields are missing.";
    }
    final missingList = missing.map((f) => "• $f").join("\n");
    return "Missing fields in current invoice:\n$missingList";
  }

  static String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return "${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute";
  }
}
