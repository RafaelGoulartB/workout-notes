import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/barcode_scanner_service.dart';

/// Launches the native Android barcode scanner and pops with the raw
/// code. On unsupported platforms it shows an explanatory message.
class BarcodeScanScreen extends StatefulWidget {
  final BarcodeScannerService scanner;

  const BarcodeScanScreen({
    super.key,
    this.scanner = const BarcodeScannerService(),
  });

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!widget.scanner.isSupported) return;
    try {
      final result = await widget.scanner.scan();
      if (!mounted) return;
      Navigator.of(context).pop(result?.value);
    } on BarcodeScanException {
      // A real failure (bridge missing, camera error): stay on the
      // screen and explain instead of silently closing.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final supported = widget.scanner.isSupported;
    final icon = _failed
        ? Icons.error_outline
        : (supported ? Icons.qr_code_scanner : Icons.qr_code_scanner_rounded);
    final message = _failed
        ? loc.nutritionScanError
        : (supported ? loc.nutritionScanning : loc.nutritionScanUnsupported);
    return Scaffold(
      appBar: AppBar(title: Text(loc.nutritionScanTitle), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              if (_failed || !supported)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(loc.nutritionCancel),
                )
              else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
