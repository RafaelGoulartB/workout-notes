import 'package:flutter/widgets.dart';
import 'package:workout_notes/utils/load_generation.dart';

/// Gives a screen a load that can never leave it spinning forever.
///
/// ```dart
/// class _MyScreenState extends State<MyScreen> with GuardedLoad {
///   Future<void> _load() => guardedLoad(() async {
///     final data = await repo.read();
///     if (!mounted) return;
///     setState(() => _data = data);
///   });
///
///   // build: isLoading ? spinner : loadFailed ? LoadErrorView(onRetry: _load) : content
/// }
/// ```
///
/// [isLoading] starts `true` and turns `false` once the newest load ends, with
/// or without an error; [loadFailed] tells the build to show a
/// `LoadErrorView` with a retry. Only the newest load decides these flags, and
/// a failure is logged with `debugPrint`.
mixin GuardedLoad<T extends StatefulWidget> on State<T> {
  final LoadGeneration _loadGeneration = LoadGeneration();
  int _loadToken = 0;

  /// True until the first (or a spinner-requested) load has ended.
  bool isLoading = true;

  /// True when the newest load threw.
  bool loadFailed = false;

  /// Token of the load that is currently running. Read it at the start of the
  /// body and compare with [isLoadCurrent] after an `await` to ignore a load
  /// that a newer one superseded.
  int get loadToken => _loadToken;

  bool isLoadCurrent(int token) => _loadGeneration.isCurrent(token);

  /// Runs [body] as the newest load. [showSpinner] puts the screen back into
  /// the loading state first (a retry after a failure always does).
  Future<void> guardedLoad(
    Future<void> Function() body, {
    bool showSpinner = false,
  }) async {
    final token = _loadGeneration.begin();
    _loadToken = token;
    if (mounted && (showSpinner || loadFailed) && !(isLoading && !loadFailed)) {
      setState(() {
        isLoading = true;
        loadFailed = false;
      });
    }
    try {
      await body();
      if (!mounted || !_loadGeneration.isCurrent(token)) return;
      if (isLoading || loadFailed) {
        setState(() {
          isLoading = false;
          loadFailed = false;
        });
      }
    } catch (error, stack) {
      debugPrint('$runtimeType: load failed: $error\n$stack');
      if (!mounted || !_loadGeneration.isCurrent(token)) return;
      setState(() {
        isLoading = false;
        loadFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration.invalidate();
    super.dispose();
  }
}
