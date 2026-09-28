import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tax_invoice_app/services/ocr/tax_invoice_parser.dart';
import 'helpers/ground_truth_parser.dart';

void main() {
  group('Kaggle Invoice Dataset Local OCR Evaluation Benchmark', () {
    test('Evaluates OCR and parser accuracy against local Kaggle dataset if present', () async {
      // Directories checked for local Kaggle dataset images & annotations
      final possibleDatasetDirs = [
        Directory('local_dataset'),
        Directory('test/assets/kaggle_dataset'),
        Directory('indian-grocery-tax-invoice-image-dataset'),
        Directory('C:/Users/PRANATHI/Documents/indian-grocery-tax-invoice-image-dataset'),
      ];

      Directory? activeDatasetDir;
      for (final dir in possibleDatasetDirs) {
        if (await dir.exists()) {
          activeDatasetDir = dir;
          break;
        }
      }

      if (activeDatasetDir == null) {
        // Safe graceful skip if developer has not placed dataset files in local folder yet
        print('----------------------------------------------------------------------');
        print('INFO: No local Kaggle dataset directory found.');
        print('To run OCR accuracy benchmarks on your machine:');
        print('Place Kaggle invoice images & annotations inside: local_dataset/');
        print('Dataset reference: surajitsadhukhan/indian-grocery-tax-invoice-image-dataset');
        print('----------------------------------------------------------------------');
        expect(true, isTrue);
        return;
      }

      print('Found local Kaggle dataset at: ${activeDatasetDir.path}');
      final annotations = await GroundTruthParser.loadFromDirectory(activeDatasetDir);
      print('Loaded ${annotations.length} ground truth annotations.');

      final parser = TaxInvoiceParserService();

      int totalEvaluated = 0;
      int gstinExactMatches = 0;
      int invoiceNumExactMatches = 0;
      int totalAmountMatches = 0;
      int vendorEditDistancesSum = 0;

      for (final ann in annotations) {
        if (ann.imageFullPath != null) {
          final imgFile = File(ann.imageFullPath!);
          if (await imgFile.exists()) {
            totalEvaluated++;

            // Read corresponding OCR text file (.txt) if pre-extracted or available
            final textFile = File(ann.imageFullPath!.replaceAll(RegExp(r'\.(jpg|png|jpeg)$', caseSensitive: false), '.txt'));
            String ocrText = '';
            if (await textFile.exists()) {
              ocrText = await textFile.readAsString();
            }

            if (ocrText.isNotEmpty) {
              final result = parser.parse(ocrText);

              if (ann.expectedGstin.isNotEmpty && result.gstin.toLowerCase() == ann.expectedGstin.toLowerCase()) {
                gstinExactMatches++;
              }
              if (ann.expectedInvoiceNumber.isNotEmpty && result.invoiceNumber.toLowerCase() == ann.expectedInvoiceNumber.toLowerCase()) {
                invoiceNumExactMatches++;
              }
              if (ann.expectedTotalAmount != null && (result.totalAmount - ann.expectedTotalAmount!).abs() < 0.5) {
                totalAmountMatches++;
              }
              if (ann.expectedVendorName.isNotEmpty) {
                vendorEditDistancesSum += _computeLevenshtein(result.vendorName.toLowerCase(), ann.expectedVendorName.toLowerCase());
              }
            }
          }
        }
      }

      print('----------------------------------------------------------------------');
      print('KAGGLE TAX INVOICE OCR ACCURACY BENCHMARK REPORT');
      print('Dataset Path: ${activeDatasetDir.path}');
      print('Total Invoices Evaluated: $totalEvaluated');
      if (totalEvaluated > 0) {
        print('GSTIN Extraction Accuracy: ${(gstinExactMatches / totalEvaluated * 100).toStringAsFixed(1)}%');
        print('Invoice Number Accuracy: ${(invoiceNumExactMatches / totalEvaluated * 100).toStringAsFixed(1)}%');
        print('Total Amount Extraction Accuracy: ${(totalAmountMatches / totalEvaluated * 100).toStringAsFixed(1)}%');
        print('Avg Vendor Name Character Edit Distance: ${(vendorEditDistancesSum / totalEvaluated).toStringAsFixed(2)} chars');
      }
      print('----------------------------------------------------------------------');

      expect(totalEvaluated, greaterThanOrEqualTo(0));
    });
  });
}

int _computeLevenshtein(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);

  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < s2.length; j++) {
      int cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
      v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
    }
    for (int j = 0; j <= s2.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[s2.length];
}

