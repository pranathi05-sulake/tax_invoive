import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/invoice.dart';
import '../database/database_helper.dart';
import '../ocr/ocr_engine.dart';
import '../ocr/tax_invoice_parser.dart';
import '../validation/invoice_validator.dart';
import 'rpa_workflow_models.dart';

class RpaWorkflowEngine {
  final OcrEngine ocrEngine;
  final TaxInvoiceParserService parserService;
  final InvoiceValidator validator;
  final DatabaseHelper databaseHelper;

  RpaWorkflowEngine({
    OcrEngine? ocrEngine,
    TaxInvoiceParserService? parserService,
    InvoiceValidator? validator,
    DatabaseHelper? databaseHelper,
  })  : ocrEngine = ocrEngine ?? MlKitOcrEngine(),
        parserService = parserService ?? TaxInvoiceParserService(),
        validator = validator ?? InvoiceValidator(),
        databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  /// Executes an automated RPA workflow on the provided image file up to the review gate or complete step.
  Future<RpaWorkflowExecution> executeWorkflow(
    File imageFile, {
    VoidCallback? onExecutionUpdated,
    bool Function()? isCancelled,
  }) async {
    final executionId = 'exec_${DateTime.now().millisecondsSinceEpoch}';
    final execution = RpaWorkflowExecution(
      id: executionId,
      sourcePath: imageFile.path,
      startTime: DateTime.now(),
      status: RpaWorkflowStatus.processing,
    );

    onExecutionUpdated?.call();

    // Helper to log and notify
    Future<void> recordLog(RpaWorkflowStep step, RpaWorkflowStatus status, String msg) async {
      execution.currentStep = step;
      execution.status = status;
      execution.addStepLog(step, status, msg);
      if (status == RpaWorkflowStatus.completed || status == RpaWorkflowStatus.failed) {
        execution.completedStepsCount = step.index + 1;
      } else {
        execution.completedStepsCount = step.index;
      }
      onExecutionUpdated?.call();

      await databaseHelper.insertWorkflowLog(
        WorkflowLogEntry(
          id: '${execution.id}_${step.name}',
          executionId: execution.id,
          invoiceId: execution.extractedInvoice?.id ?? '',
          sourcePath: execution.sourcePath,
          step: step.name,
          status: status.name,
          message: msg,
          timestamp: DateTime.now(),
        ),
      );
    }

    try {
      // Step 1: Capture Verification
      if (isCancelled?.call() == true) {
        return await cancelWorkflow(execution, onExecutionUpdated: onExecutionUpdated);
      }
      await recordLog(RpaWorkflowStep.capture, RpaWorkflowStatus.processing, 'Captured invoice document source: ${imageFile.path}');
      if (!kIsWeb && !await imageFile.exists()) {
        execution.errorMessage = 'Invoice source image file not found at path.';
        await recordLog(RpaWorkflowStep.failed, RpaWorkflowStatus.failed, execution.errorMessage!);
        return execution;
      }

      // Step 2: OCR Processing
      if (isCancelled?.call() == true) {
        return await cancelWorkflow(execution, onExecutionUpdated: onExecutionUpdated);
      }
      await recordLog(RpaWorkflowStep.ocr, RpaWorkflowStatus.processing, 'Running offline Google ML Kit OCR text recognition...');
      final ocrResult = await ocrEngine.processImageFile(imageFile);

      if (ocrResult.isEmpty) {
        execution.errorMessage = 'No readable OCR text extracted from invoice image.';
        await recordLog(RpaWorkflowStep.ocr, RpaWorkflowStatus.failed, execution.errorMessage!);
        return execution;
      }

      // Step 3: Rule-Based Extraction
      if (isCancelled?.call() == true) {
        return await cancelWorkflow(execution, onExecutionUpdated: onExecutionUpdated);
      }
      await recordLog(RpaWorkflowStep.extract, RpaWorkflowStatus.processing, 'Parsing structured invoice details and line items...');
      final parsedResult = parserService.parse(ocrResult.fullText);
      final invoice = parsedResult.toInvoice(id: execution.id);
      execution.extractedInvoice = invoice;

      // Step 4: Validation
      if (isCancelled?.call() == true) {
        return await cancelWorkflow(execution, onExecutionUpdated: onExecutionUpdated);
      }
      await recordLog(RpaWorkflowStep.validate, RpaWorkflowStatus.processing, 'Validating invoice fields and GSTIN checksum...');
      final validation = InvoiceValidator.validate(invoice);
      execution.validationWarnings = validation.warnings;

      // Step 5: Duplicate Check in SQLite
      if (isCancelled?.call() == true) {
        return await cancelWorkflow(execution, onExecutionUpdated: onExecutionUpdated);
      }
      await recordLog(RpaWorkflowStep.duplicateCheck, RpaWorkflowStatus.processing, 'Querying SQLite database for duplicate invoice...');
      final exists = await databaseHelper.checkInvoiceExists(
        gstin: invoice.gstin,
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.date,
        id: invoice.id,
      );

      if (exists) {
        execution.errorMessage = 'Duplicate invoice detected in database matching GSTIN/Invoice #/Date.';
        await recordLog(RpaWorkflowStep.duplicateCheck, RpaWorkflowStatus.duplicate, execution.errorMessage!);
        execution.endTime = DateTime.now();
        return execution;
      }

      // Step 6: Review Gate Decision
      final hasMissingFields = invoice.vendorName.isEmpty || invoice.invoiceNumber.isEmpty || invoice.gstin.isEmpty;
      final hasWarnings = validation.warnings.isNotEmpty;

      if (hasMissingFields || hasWarnings) {
        final reason = hasMissingFields ? 'missing required fields' : 'validation warnings';
        await recordLog(
          RpaWorkflowStep.reviewRequired,
          RpaWorkflowStatus.needsReview,
          'Invoice requires explicit user review due to $reason (${validation.warnings.length} warning(s)).',
        );
        return execution;
      }

      // If 100% clean, proceed to Auto-Save
      return await approveAndSaveInvoice(execution, onExecutionUpdated: onExecutionUpdated);
    } catch (e) {
      execution.errorMessage = 'RPA workflow processing exception: $e';
      await recordLog(RpaWorkflowStep.failed, RpaWorkflowStatus.failed, execution.errorMessage!);
      execution.endTime = DateTime.now();
      return execution;
    }
  }

  /// Explicitly approves and saves an invoice into SQLite after user review/confirmation.
  Future<RpaWorkflowExecution> approveAndSaveInvoice(
    RpaWorkflowExecution execution, {
    Invoice? editedInvoice,
    VoidCallback? onExecutionUpdated,
  }) async {
    if (editedInvoice != null) {
      execution.extractedInvoice = editedInvoice;
      execution.isReviewed = true;
    }

    final invoice = execution.extractedInvoice;
    if (invoice == null) {
      execution.errorMessage = 'Cannot save null invoice to database.';
      execution.status = RpaWorkflowStatus.failed;
      onExecutionUpdated?.call();
      return execution;
    }

    // Re-check duplicate before actual insert
    final isDup = await databaseHelper.checkInvoiceExists(
      gstin: invoice.gstin,
      invoiceNumber: invoice.invoiceNumber,
      date: invoice.date,
      id: invoice.id,
    );

    if (isDup) {
      execution.status = RpaWorkflowStatus.duplicate;
      execution.errorMessage = 'Duplicate invoice detected during save attempt.';
      execution.addStepLog(
        RpaWorkflowStep.save,
        RpaWorkflowStatus.duplicate,
        execution.errorMessage!,
      );
      execution.endTime = DateTime.now();
      onExecutionUpdated?.call();
      await databaseHelper.insertWorkflowLog(
        WorkflowLogEntry(
          id: '${execution.id}_save_duplicate',
          executionId: execution.id,
          invoiceId: invoice.id,
          sourcePath: execution.sourcePath,
          step: RpaWorkflowStep.save.name,
          status: RpaWorkflowStatus.duplicate.name,
          message: execution.errorMessage!,
          timestamp: DateTime.now(),
        ),
      );
      return execution;
    }

    final savedInvoice = await databaseHelper.insertInvoice(invoice);
    if (savedInvoice != null) {
      execution.status = RpaWorkflowStatus.completed;
      execution.currentStep = RpaWorkflowStep.completed;
      execution.completedStepsCount = RpaWorkflowStep.values.length;
      execution.endTime = DateTime.now();
      execution.addStepLog(
        RpaWorkflowStep.save,
        RpaWorkflowStatus.completed,
        'Successfully saved invoice ${invoice.invoiceNumber} to SQLite database.',
      );
      onExecutionUpdated?.call();

      await databaseHelper.insertWorkflowLog(
        WorkflowLogEntry(
          id: '${execution.id}_save_completed',
          executionId: execution.id,
          invoiceId: invoice.id,
          sourcePath: execution.sourcePath,
          step: RpaWorkflowStep.completed.name,
          status: RpaWorkflowStatus.completed.name,
          message: 'Saved invoice ${invoice.invoiceNumber} to SQLite.',
          timestamp: DateTime.now(),
        ),
      );
    } else {
      execution.status = RpaWorkflowStatus.duplicate;
      execution.errorMessage = 'Invoice insert skipped by database due to duplicate conflict.';
      onExecutionUpdated?.call();
    }

    return execution;
  }

  /// Cancels an active workflow safely without leaving background locks or creating partial SQLite records.
  Future<RpaWorkflowExecution> cancelWorkflow(
    RpaWorkflowExecution execution, {
    VoidCallback? onExecutionUpdated,
  }) async {
    execution.status = RpaWorkflowStatus.cancelled;
    execution.endTime = DateTime.now();
    execution.addStepLog(
      execution.currentStep,
      RpaWorkflowStatus.cancelled,
      'RPA workflow execution cancelled by user.',
    );
    onExecutionUpdated?.call();

    await databaseHelper.insertWorkflowLog(
      WorkflowLogEntry(
        id: '${execution.id}_cancelled',
        executionId: execution.id,
        invoiceId: execution.extractedInvoice?.id ?? '',
        sourcePath: execution.sourcePath,
        step: execution.currentStep.name,
        status: RpaWorkflowStatus.cancelled.name,
        message: 'Workflow execution cancelled safely.',
        timestamp: DateTime.now(),
      ),
    );

    return execution;
  }
}
