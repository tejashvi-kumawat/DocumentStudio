import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum JobStatus {
  queued,
  running,
  cancelling,
  cancelled,
  completed,
  failed,
}

class JobProgress extends Equatable {
  const JobProgress({
    required this.fraction,
    this.message,
  });

  final double fraction;
  final String? message;

  @override
  List<Object?> get props => [fraction, message];
}

/// Live, mutable handle for one job; equal handles share an [id].
class JobHandle<T> {
  JobHandle({String? id}) : id = id ?? const Uuid().v4();

  final String id;
  JobStatus status = JobStatus.queued;
  JobProgress? progress;
  T? result;
  Object? error;

  @override
  bool operator ==(Object other) => other is JobHandle && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Mutable cancel flag shared with in-flight job work.
class JobCancelToken {
  bool isCancelled = false;
}

JobCancelToken newCancelToken() => JobCancelToken();
