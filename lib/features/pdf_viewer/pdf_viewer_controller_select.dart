import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Rebuilds [builder] only when [selector] changes.
///
/// [PdfViewerController] notifies on every scroll / zoom frame; chrome that
/// shows only the page number or zoom percent should not rebuild 60× a second.
class PdfViewerControllerSelector<T> extends StatefulWidget {
  const PdfViewerControllerSelector({
    super.key,
    required this.controller,
    required this.selector,
    required this.builder,
  });

  final PdfViewerController controller;
  final T Function(PdfViewerController controller) selector;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<PdfViewerControllerSelector<T>> createState() =>
      _PdfViewerControllerSelectorState<T>();
}

class _PdfViewerControllerSelectorState<T>
    extends State<PdfViewerControllerSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.selector(widget.controller);
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant PdfViewerControllerSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    _value = widget.selector(widget.controller);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final next = widget.selector(widget.controller);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
