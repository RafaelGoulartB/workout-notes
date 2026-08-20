import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Keeps large image encoding away from the UI isolate on native platforms.
Future<String> encodeBase64OffMain(Uint8List bytes) =>
    compute<Uint8List, String>(_encodeBase64, bytes);

String _encodeBase64(Uint8List bytes) => base64Encode(bytes);
