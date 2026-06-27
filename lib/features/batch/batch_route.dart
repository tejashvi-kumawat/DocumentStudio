import 'package:document_studio/features/batch/batch_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Route path for the app router to register in [app_router.dart].
const batchRoutePath = '/batch';

GoRoute buildBatchRoute({GlobalKey<NavigatorState>? parentNavigatorKey}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: batchRoutePath,
    builder: (context, state) => const BatchScreen(),
  );
}
