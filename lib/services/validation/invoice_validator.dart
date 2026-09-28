import '../../models/invoice.dart';

class InvoiceValidationResult {
  final bool isValid;
  final List<String> warnings;

  InvoiceValidationResult({required this.isValid, this.warnings = const []});
}

class InvoiceValidator {
  static final RegExp gstinRegex =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$', caseSensitive: false);

  static InvoiceValidationResult validate(Invoice invoice) {
    List<String> warnings = [];

    if (invoice.vendorName.trim().isEmpty) {
      warnings.add('Vendor Name is missing.');
    }

    if (invoice.invoiceNumber.trim().isEmpty) {
      warnings.add('Invoice Number is missing.');
    }

    if (invoice.gstin.trim().isNotEmpty) {
      if (!gstinRegex.hasMatch(invoice.gstin.trim())) {
        warnings.add('GSTIN format appears invalid.');
      }
    } else {
      warnings.add('GSTIN is missing.');
    }

    final double expectedTotal = invoice.subtotal + invoice.cgst + invoice.sgst + invoice.igst;
    // Allow small floating point difference (e.g. 0.01)
    if ((invoice.totalAmount - expectedTotal).abs() > 0.1) {
      warnings.add('Total amount (₹${invoice.totalAmount.toStringAsFixed(2)}) does not match subtotal + taxes (₹${expectedTotal.toStringAsFixed(2)}).');
    }

    if (invoice.items.isEmpty) {
      warnings.add('No line items provided.');
    } else {
      double itemsTotal = 0;
      for (final item in invoice.items) {
        itemsTotal += (item.quantity * item.unitPrice);
      }
      if ((invoice.subtotal - itemsTotal).abs() > 0.1) {
        warnings.add('Subtotal (₹${invoice.subtotal.toStringAsFixed(2)}) does not match the sum of line items (₹${itemsTotal.toStringAsFixed(2)}).');
      }
    }

    return InvoiceValidationResult(
      isValid: warnings.isEmpty,
      warnings: warnings,
    );
  }
}
