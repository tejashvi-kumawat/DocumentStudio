import 'dart:async';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/logging/app_log.dart';

/// Runs heavy work off the UI thread (async scheduling; isolates for CPU-heavy
/// jobs will be added per feature).
class JobRunner {
  JobRunner();

  final _controllers = <String, StreamController<JobProgress>>{};
  final _cancelTokens = <String, JobCancelToken>{};

  Stream<JobProgress>? progressStream(String jobId) =>
      _controllers[jobId]?.stream;

  Future<T> run<T>({
    required JobHandle<T> handle,
    required Future<T> Function(
      void Function(JobProgress) reportProgress,
      JobCancelToken cancelToken,
    )
    work,
  }) async {
    final cancelToken = JobCancelToken();
    final controller = StreamController<JobProgress>.broadcast();
    _controllers[handle.id] = controller;
    _cancelTokens[handle.id] = cancelToken;

    handle.status = JobStatus.running;
    appLog.info('Job ${handle.id} started');

    void report(JobProgress progress) {
      handle.progress = progress;
      if (!controller.isClosed) {
        controller.add(progress);
      }
    }

    try {
      final result = await work(report, cancelToken);
      if (cancelToken.isCancelled) {
        handle.status = JobStatus.cancelled;
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.processCancelled,
          message: 'Cancelled',
        );
      }
      handle.result = result;
      handle.status = JobStatus.completed;
      report(const JobProgress(fraction: 1, message: 'Done'));
      return result;
    } catch (e, st) {
      appLog.warning('Job ${handle.id} failed', e, st);
      handle.error = e;
      handle.status = JobStatus.failed;
      rethrow;
    } finally {
      await controller.close();
      _controllers.remove(handle.id);
      _cancelTokens.remove(handle.id);
    }
  }

  void requestCancel(JobHandle<dynamic> handle) {
    handle.status = JobStatus.cancelling;
    _cancelTokens[handle.id]?.isCancelled = true;
  }
}
