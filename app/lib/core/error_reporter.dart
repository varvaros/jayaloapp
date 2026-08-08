import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'config.dart';

const _dedupWindow = Duration(seconds: 60);
final Map<String, DateTime> _recent = {};

@visibleForTesting
bool shouldSend(String key, DateTime now) {
  final last = _recent[key];
  if (last != null && now.difference(last) < _dedupWindow) return false;
  _recent[key] = now;
  return true;
}

/// Solo para tests: observa cada llamada a [reportError] sin tocar la red.
/// Se invoca ANTES del dedup, así los tests ven todos los reportes.
@visibleForTesting
void Function(Object error)? debugOnReport;

String? _release;

Future<void> _loadRelease() async {
  try {
    final info = await PackageInfo.fromPlatform();
    _release = '${info.version}+${info.buildNumber}';
  } catch (_) {/* opcional */}
}

Future<void> reportError(Object error, StackTrace? stack) async {
  try {
    debugOnReport?.call(error);
    final type = error.runtimeType.toString();
    final message = error.toString();
    if (!shouldSend('$type|$message', DateTime.now())) return;
    final body = jsonEncode({
      'source': 'flutter',
      'error_type': type,
      'message': message,
      if (stack != null) 'stack': stack.toString(),
      if (_release != null) 'release': _release,
      'environment': kReleaseMode ? 'production' : 'dev',
      'context': {'platform': Platform.operatingSystem},
    });
    await http.post(
      Uri.parse(AppConfig.reportErrorEndpoint),
      headers: {'Content-Type': 'application/json', 'Origin': AppConfig.siteUrl},
      body: body,
    );
  } catch (_) {
    // el reporter jamás rompe la app
  }
}

void initErrorReporting(FutureOr<void> Function() body) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _loadRelease();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(reportError(details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(reportError(error, stack));
      return true;
    };
    await body();
  }, (error, stack) => unawaited(reportError(error, stack)));
}
