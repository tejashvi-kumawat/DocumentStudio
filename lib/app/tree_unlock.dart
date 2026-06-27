import 'package:flutter/scheduler.dart';

/// Runs [fn] now, or right after the current frame when the widget tree is
/// locked (build, layout, or elements unmounting). Use for listener
/// notifications fired from `State.dispose` / `deactivate`, which otherwise
/// throw "setState() or markNeedsBuild() called when widget tree was locked".
void runWhenTreeUnlocked(VoidCallback fn) {
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    binding.addPostFrameCallback((_) => fn());
  } else {
    fn();
  }
}
