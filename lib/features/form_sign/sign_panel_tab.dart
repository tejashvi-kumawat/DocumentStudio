import 'package:flutter/foundation.dart';

/// Which tab to open in the visual-sign / stamps panel.
enum SignPanelTab {
  signatures,
  stamps,
  digital,
}

/// Cross-route request to focus a sign panel tab when opening visual sign.
final ValueNotifier<SignPanelTab?> signPanelTabRequest =
    ValueNotifier<SignPanelTab?>(null);
