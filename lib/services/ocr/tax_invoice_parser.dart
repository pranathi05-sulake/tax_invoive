import '../../models/invoice.dart';

/// Parsed metadata extracted from OCR text.
class ParsedInvoiceResult {
  final String vendorName;
  final String gstin;
  final String invoiceNumber;
  final DateTime date;
  final double subtotal;
  final double cgst;
  final double sgst;
  final double igst;
  final double totalAmount;
  final List<InvoiceItem> items;
  final String rawOcrText;

  const ParsedInvoiceResult({
    required this.vendorName,
    required this.gstin,
    required this.invoiceNumber,
    required this.date,
    required this.subtotal,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalAmount,
    required this.items,
    required this.rawOcrText,
  });

  /// Converts parsed result into domain [Invoice] object.
  Invoice toInvoice({String id = 'parsed-inv'}) {
    return Invoice(
      id: id,
      vendorName: vendorName,
      gstin: gstin,
      invoiceNumber: invoiceNumber,
      date: date,
      subtotal: subtotal > 0 ? subtotal : (totalAmount - (cgst + sgst + igst)),
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      status: gstin.isNotEmpty && totalAmount > 0
          ? InvoiceStatus.verified
          : InvoiceStatus.pending,
      items: items,
    );
  }
}

/// Rule-based parser for Indian Grocery & Retail Tax Invoices.
class TaxInvoiceParserService {
  // Indian GSTIN regex pattern (15 characters: 2 state digits + 10 PAN chars + 1 entity num + 'Z' + 1 checksum)
  static final RegExp gstinRegex =
      RegExp(r'\b[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}\b', caseSensitive: false);

  // Invoice number regex patterns
  static final RegExp invoiceNumRegex = RegExp(
    r'(?:inv(?:oice)?|bill|receipt|doc|tax\s*invoice)\s*(?:no|num|number|#)?[\s:\.\-]*([A-Z0-9/\-]{3,20})',
    caseSensitive: false,
  );

  // Date regex pattern (DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY, YYYY-MM-DD)
  static final RegExp dateRegex = RegExp(
    r'\b(\d{1,2})[\/\.\-](\d{1,2}|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[\/\.\-](\d{2,4})\b',
    caseSensitive: false,
  );

  // Currency/Amount regex pattern
  static final RegExp amountRegex = RegExp(r'(?:₹|Rs\.?|INR)?\s*([0-9]{1,7}(?:\.[0-9]{2})?)', caseSensitive: false);

  /// Main entry point to parse raw text or line array into structured [ParsedInvoiceResult].
  ParsedInvoiceResult parse(String rawText, {List<String>? lines}) {
    final lineList = lines ?? rawText.split(RegExp(r'\r?\n'));
    final cleanedLines = lineList.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final gstin = _extractGstin(rawText, cleanedLines);
    final invoiceNumber = _extractInvoiceNumber(rawText, cleanedLines);
    final date = _extractDate(rawText, cleanedLines);
    final vendorName = _extractVendorName(cleanedLines);
    final taxBreakdown = _extractTaxes(cleanedLines);
    final totalAmount = _extractTotalAmount(cleanedLines);
    final subtotal = _extractSubtotal(cleanedLines, totalAmount, taxBreakdown['totalTax'] ?? 0.0);
    final items = _extractLineItems(cleanedLines);

    return ParsedInvoiceResult(
      vendorName: vendorName,
      gstin: gstin,
      invoiceNumber: invoiceNumber,
      date: date ?? DateTime.now(),
      subtotal: subtotal,
      cgst: taxBreakdown['cgst'] ?? 0.0,
      sgst: taxBreakdown['sgst'] ?? 0.0,
      igst: taxBreakdown['igst'] ?? 0.0,
      totalAmount: totalAmount,
      items: items,
      rawOcrText: rawText,
    );
  }

  static String _extractGstin(String rawText, List<String> lines) {
    final match = gstinRegex.firstMatch(rawText.toUpperCase());
    if (match != null) {
      return match.group(0)!;
    }
    for (final line in lines) {
      if (line.toUpperCase().contains('GST')) {
        final lineMatch = gstinRegex.firstMatch(line.toUpperCase());
        if (lineMatch != null) return lineMatch.group(0)!;
      }
    }
    return '';
  }

  static String _extractInvoiceNumber(String rawText, List<String> lines) {
    const invalidNumbers = {'INVOICE', 'OICE', 'TAX', 'BILL', 'RECEIPT', 'NUMBER', 'ORIGINAL', 'DUPLICATE'};
    
    // First try lines containing explicit 'Invoice No:' or 'Bill No:' patterns
    final explicitRegex = RegExp(
      r'(?:inv(?:oice)?|bill|receipt|tax\s*invoice)\s*(?:no|num|number|#)[\s:\.\-]*([A-Z0-9/\-]{3,25})',
      caseSensitive: false,
    );

    for (final line in lines) {
      final match = explicitRegex.firstMatch(line);
      if (match != null && match.groupCount >= 1) {
        final captured = match.group(1)!.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '').toUpperCase();
        if (captured.length >= 3 && !invalidNumbers.contains(captured)) {
          return captured;
        }
      }
    }

    // Fallback search for lines with INV/ or BILL/
    final fallbackRegex = RegExp(r'\b(INV[A-Z0-9/\-]{3,20}|BILL[A-Z0-9/\-]{3,20})\b', caseSensitive: false);
    for (final line in lines) {
      final match = fallbackRegex.firstMatch(line);
      if (match != null) {
        final captured = match.group(0)!.toUpperCase();
        if (!invalidNumbers.contains(captured)) {
          return captured;
        }
      }
    }

    return '';
  }

  static DateTime? _extractDate(String rawText, List<String> lines) {
    for (final line in lines) {
      final match = dateRegex.firstMatch(line);
      if (match != null) {
        try {
          final p1 = match.group(1)!;
          final p2 = match.group(2)!;
          final p3 = match.group(3)!;

          int day = int.tryParse(p1) ?? 1;
          int month = int.tryParse(p2) ?? _parseMonthName(p2);
          int year = int.tryParse(p3) ?? DateTime.now().year;
          if (year < 100) year += 2000;

          if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            return DateTime(year, month, day);
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static int _parseMonthName(String monthStr) {
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final index = months.indexOf(monthStr.toLowerCase());
    return index != -1 ? index + 1 : 1;
  }

  static String _extractVendorName(List<String> lines) {
    const skipKeywords = [
      'TAX INVOICE',
      'INVOICE',
      'CASH MEMO',
      'BILL',
      'GSTIN',
      'ORIGINAL',
      'RETAIL',
      'SUPERMARKET',
      'DATE',
      'TEL',
      'PHONE',
      'TOTAL',
    ];

    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.length >= 3 && !skipKeywords.any((keyword) => upper.startsWith(keyword) || upper.contains(keyword))) {
        // Clean line from non-alphanumeric trailing prefix/suffixes
        if (RegExp(r'[A-Za-z]').hasMatch(line)) {
          return line.replaceAll(RegExp(r'[^\w\s\&\.\-\,]'), '').trim();
        }
      }
    }
    return '';
  }

  static Map<String, double> _extractTaxes(List<String> lines) {
    double cgst = 0.0;
    double sgst = 0.0;
    double igst = 0.0;

    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('CGST')) {
        cgst += _parseLastAmount(line);
      } else if (upper.contains('SGST')) {
        sgst += _parseLastAmount(line);
      } else if (upper.contains('IGST')) {
        igst += _parseLastAmount(line);
      }
    }

    return {
      'cgst': cgst,
      'sgst': sgst,
      'igst': igst,
      'totalTax': cgst + sgst + igst,
    };
  }

  static double _extractTotalAmount(List<String> lines) {
    const totalKeywords = ['GRAND TOTAL', 'NET AMOUNT', 'TOTAL AMOUNT', 'TOTAL', 'AMOUNT DUE', 'NET PAYABLE'];

    for (final keyword in totalKeywords) {
      for (final line in lines.reversed) {
        if (line.toUpperCase().contains(keyword)) {
          final amt = _parseLastAmount(line);
          if (amt > 0) return amt;
        }
      }
    }

    // Fallback: search lines near the bottom for the largest numeric figure
    double maxAmt = 0.0;
    for (int i = lines.length - 1; i >= (lines.length - 8).clamp(0, lines.length); i--) {
      final val = _parseLastAmount(lines[i]);
      if (val > maxAmt && val < 1000000) {
        maxAmt = val;
      }
    }
    return maxAmt;
  }

  static double _extractSubtotal(List<String> lines, double totalAmount, double totalTax) {
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('SUBTOTAL') || upper.contains('SUB TOTAL') || upper.contains('TAXABLE VALUE')) {
        final amt = _parseLastAmount(line);
        if (amt > 0) return amt;
      }
    }

    if (totalAmount > totalTax && totalTax > 0) {
      return totalAmount - totalTax;
    }
    return totalAmount;
  }

  static List<InvoiceItem> _extractLineItems(List<String> lines) {
    final items = <InvoiceItem>[];
    int counter = 1;

    for (final line in lines) {
      // Look for lines containing numbers matching quantity * price pattern (e.g., "1  Milk 1L  60.00")
      final parts = line.trim().split(RegExp(r'\s{2,}|\t'));
      if (parts.length >= 2) {
        final lastPart = parts.last;
        final amount = double.tryParse(lastPart.replaceAll(RegExp(r'[^\d\.]'), ''));
        if (amount != null && amount > 0 && amount < 50000) {
          final desc = parts.sublist(0, parts.length - 1).join(' ').trim();
          if (desc.length > 2 && !desc.toUpperCase().contains('TOTAL') && !desc.toUpperCase().contains('GST')) {
            items.add(
              InvoiceItem(
                id: 'item-$counter',
                description: desc,
                quantity: 1,
                unitPrice: amount,
              ),
            );
            counter++;
          }
        }
      }
    }
    return items;
  }

  static double _parseLastAmount(String text) {
    final matches = amountRegex.allMatches(text);
    if (matches.isNotEmpty) {
      final lastMatch = matches.last.group(1);
      if (lastMatch != null) {
        return double.tryParse(lastMatch) ?? 0.0;
      }
    }
    return 0.0;
  }
}
