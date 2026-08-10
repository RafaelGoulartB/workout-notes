import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Raw result of a native barcode scan.
class BarcodeScanResult {
  final String value;
  final String format;

  const BarcodeScanResult({required this.value, required this.format});
}

/// Thrown when the native scanner is unavailable or fails (e.g. the
/// platform bridge is missing or the camera could not be started).
class BarcodeScanException implements Exception {
  final String code;
  final String message;

  const BarcodeScanException(this.code, this.message);

  @override
  String toString() => 'BarcodeScanException($code): $message';
}

/// Thin Dart facade over the native Android barcode scanner
/// ([BarcodeScannerActivity] via `BarcodeScannerBridge`).
///
/// Returns null when the user cancels the scan. Throws
/// [BarcodeScanException] when the scan cannot run at all.
class BarcodeScannerService {
  static const MethodChannel _channel = MethodChannel(
    'workout_notes/barcode_scanner/methods',
  );

  const BarcodeScannerService();

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<BarcodeScanResult?> scan() async {
    if (!isSupported) {
      throw const BarcodeScanException(
        'unsupported',
        'Barcode scanning is only available on Android',
      );
    }
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('scan');
      // A null payload means the user cancelled the native scanner.
      if (map == null) return null;
      final value = (map['value'] as String?)?.trim() ?? '';
      if (value.isEmpty) return null;
      return BarcodeScanResult(
        value: value,
        format: (map['format'] as String?) ?? '',
      );
    } on MissingPluginException {
      throw const BarcodeScanException(
        'bridge_missing',
        'Native barcode scanner bridge is not available. Reinstall the app.',
      );
    } on PlatformException catch (e) {
      throw BarcodeScanException(
        e.code,
        e.message ?? 'Native barcode scanner failed',
      );
    }
  }
}
