import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RunAudioCapabilities {
  final bool headsetConnected;
  final bool inCall;

  const RunAudioCapabilities({
    required this.headsetConnected,
    required this.inCall,
  });

  const RunAudioCapabilities.unknown()
      : headsetConnected = false,
        inCall = false;
}

/// Android MethodChannel facade for headset / in-call gating.
class RunAudioGateService {
  RunAudioGateService._();
  static final RunAudioGateService instance = RunAudioGateService._();

  static const _methods = MethodChannel('workout_notes/run_audio/methods');

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<RunAudioCapabilities> getCapabilities() async {
    if (!_isAndroid) {
      // Desktop/tests: treat as headset present so announcements can be tested.
      return const RunAudioCapabilities(
        headsetConnected: true,
        inCall: false,
      );
    }
    try {
      final result =
          await _methods.invokeMapMethod<String, dynamic>('getCapabilities');
      if (result == null) return const RunAudioCapabilities.unknown();
      return RunAudioCapabilities(
        headsetConnected: result['headset_connected'] as bool? ?? false,
        inCall: result['in_call'] as bool? ?? false,
      );
    } on MissingPluginException {
      return const RunAudioCapabilities.unknown();
    } catch (_) {
      return const RunAudioCapabilities.unknown();
    }
  }
}
