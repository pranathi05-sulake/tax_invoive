import '../../models/invoice.dart';

enum RpaWorkflowStep {
  capture,
  ocr,
  extract,
  validate,
  duplicateCheck,
  reviewRequired,
  save,
  completed,
  failed,
}

enum RpaWorkflowStatus {
  pending,
  processing,
  needsReview,
  completed,
  duplicate,
  failed,
  cancelled,
}

class RpaStepLog {
  final RpaWorkflowStep step;
  final RpaWorkflowStatus status;
  final String message;
  final DateTime timestamp;

  const RpaStepLog({
    required this.step,
    required this.status,
    required this.message,
    required this.timestamp,
  });

  String get formattedStep {
    switch (step) {
      case RpaWorkflowStep.capture:
        return 'Capture';
      case RpaWorkflowStep.ocr:
        return 'OCR';
      case RpaWorkflowStep.extract:
        return 'Extract';
      case RpaWorkflowStep.validate:
        return 'Validate';
      case RpaWorkflowStep.duplicateCheck:
        return 'Duplicate Check';
      case RpaWorkflowStep.reviewRequired:
        return 'Review Required';
      case RpaWorkflowStep.save:
        return 'Save to SQLite';
      case RpaWorkflowStep.completed:
        return 'Completed';
      case RpaWorkflowStep.failed:
        return 'Failed';
    }
  }
}

class RpaWorkflowExecution {
  final String id;
  final String sourcePath;
  final DateTime startTime;
  DateTime? endTime;
  RpaWorkflowStep currentStep;
  RpaWorkflowStatus status;
  String? errorMessage;
  int completedStepsCount;
  Invoice? extractedInvoice;
  List<String> validationWarnings;
  bool isReviewed;
  final List<RpaStepLog> stepLogs;

  RpaWorkflowExecution({
    required this.id,
    required this.sourcePath,
    required this.startTime,
    this.endTime,
    this.currentStep = RpaWorkflowStep.capture,
    this.status = RpaWorkflowStatus.pending,
    this.errorMessage,
    this.completedStepsCount = 0,
    this.extractedInvoice,
    List<String>? validationWarnings,
    this.isReviewed = false,
    List<RpaStepLog>? stepLogs,
  })  : validationWarnings = validationWarnings ?? [],
        stepLogs = stepLogs ?? [];

  void addStepLog(RpaWorkflowStep step, RpaWorkflowStatus stepStatus, String message) {
    stepLogs.add(
      RpaStepLog(
        step: step,
        status: stepStatus,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
  }
}
