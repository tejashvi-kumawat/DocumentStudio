import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:equatable/equatable.dart';

enum BatchItemOutcome { success, failed, skipped }

class BatchOptions extends Equatable {
  const BatchOptions({this.continueOnError = true});

  final bool continueOnError;

  @override
  List<Object?> get props => [continueOnError];
}

class BatchItemResult extends Equatable {
  const BatchItemResult({
    required this.input,
    required this.outcome,
    this.outputPath,
    this.error,
  });

  final LocalFileRef input;
  final BatchItemOutcome outcome;
  final String? outputPath;
  final Object? error;

  @override
  List<Object?> get props => [input, outcome, outputPath, error];
}

class BatchResult extends Equatable {
  const BatchResult({required this.items});

  final List<BatchItemResult> items;

  int get successCount =>
      items.where((i) => i.outcome == BatchItemOutcome.success).length;

  int get failedCount =>
      items.where((i) => i.outcome == BatchItemOutcome.failed).length;

  bool get cancelled => items.any((i) => i.outcome == BatchItemOutcome.skipped);

  @override
  List<Object?> get props => [items];
}

class BatchProgress extends Equatable {
  const BatchProgress({
    required this.index,
    required this.total,
    required this.overallFraction,
    this.currentInput,
    this.message,
  });

  final int index;
  final int total;
  final double overallFraction;
  final LocalFileRef? currentInput;
  final String? message;

  @override
  List<Object?> get props => [
    index,
    total,
    overallFraction,
    currentInput,
    message,
  ];
}

typedef BatchFileProcessor = Future<String?> Function(
  LocalFileRef input,
  void Function(JobProgress) reportFileProgress,
  JobCancelToken cancelToken,
);

/// Runs one registered tool across many inputs via [JobRunner] (DS-BATCH-001).
class BatchRunner {
  BatchRunner({required this._jobs});

  final JobRunner _jobs;
  JobCancelToken? _activeCancel;

  void requestCancel() {
    _activeCancel?.isCancelled = true;
  }

  Future<BatchResult> run({
    required List<LocalFileRef> inputs,
    required BatchOptions options,
    required BatchFileProcessor processFile,
    void Function(BatchProgress progress)? onProgress,
  }) async {
    if (inputs.isEmpty) {
      return const BatchResult(items: []);
    }

    final handle = JobHandle<BatchResult>();
    return _jobs.run(
      handle: handle,
      work: (reportJob, jobCancel) async {
        final cancel = JobCancelToken();
        _activeCancel = cancel;
        final results = <BatchItemResult>[];

        try {
          for (var i = 0; i < inputs.length; i++) {
            if (cancel.isCancelled || jobCancel.isCancelled) {
              for (var j = i; j < inputs.length; j++) {
                results.add(
                  BatchItemResult(
                    input: inputs[j],
                    outcome: BatchItemOutcome.skipped,
                  ),
                );
              }
              break;
            }

            final input = inputs[i];
            final baseFraction = i / inputs.length;

            void reportOverall(String? message, double fileFraction) {
              final overall =
                  baseFraction + (fileFraction.clamp(0.0, 1.0) / inputs.length);
              final progress = BatchProgress(
                index: i,
                total: inputs.length,
                overallFraction: overall.clamp(0.0, 1.0),
                currentInput: input,
                message: message,
              );
              onProgress?.call(progress);
              reportJob(
                JobProgress(
                  fraction: progress.overallFraction,
                  message: message ?? input.displayName,
                ),
              );
            }

            reportOverall('Processing ${input.displayName}', 0);

            try {
              final outputPath = await processFile(
                input,
                (p) => reportOverall(p.message, p.fraction),
                cancel,
              );
              results.add(
                BatchItemResult(
                  input: input,
                  outcome: BatchItemOutcome.success,
                  outputPath: outputPath,
                ),
              );
              reportOverall('Done ${input.displayName}', 1);
            } catch (e) {
              results.add(
                BatchItemResult(
                  input: input,
                  outcome: BatchItemOutcome.failed,
                  error: e,
                ),
              );
              if (!options.continueOnError) {
                for (var j = i + 1; j < inputs.length; j++) {
                  results.add(
                    BatchItemResult(
                      input: inputs[j],
                      outcome: BatchItemOutcome.skipped,
                    ),
                  );
                }
                break;
              }
            }
          }
        } finally {
          _activeCancel = null;
        }

        return BatchResult(items: results);
      },
    );
  }
}
