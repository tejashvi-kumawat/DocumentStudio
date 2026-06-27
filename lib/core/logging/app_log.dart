import 'package:logging/logging.dart';

final appLog = Logger('DocumentStudio');

void configureAppLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    // Privacy: never log document paths or content in production builds.
    // ignore: avoid_print
    print('[${record.level.name}] ${record.loggerName}: ${record.message}');
  });
}
