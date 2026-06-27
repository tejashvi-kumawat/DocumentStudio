import 'package:document_studio/features/home/home_tool.dart';

/// Visual Sign is available for placement; certificate PKCS#7 is a separate path.
const HomeToolAvailability partialVisualSignAvailability =
    HomeToolAvailability.available;

/// Maps blocked/coming-soon reasons for home tool badges.
String? homeToolAvailabilityHint(HomeToolAvailability availability) {
  return switch (availability) {
    HomeToolAvailability.available => null,
    HomeToolAvailability.comingSoon => 'Coming soon',
    HomeToolAvailability.blocked => 'Unavailable on this system',
  };
}

bool homeToolIsEnabled(HomeToolAvailability availability) =>
    availability == HomeToolAvailability.available;
