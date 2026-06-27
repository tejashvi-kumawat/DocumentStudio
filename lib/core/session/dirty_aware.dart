/// Sessions that expose an unsaved-edit indicator for the shell sidebar.
abstract interface class DirtyAware {
  bool get isDirty;
}
