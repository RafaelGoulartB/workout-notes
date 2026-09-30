/// Lets only the newest of several overlapping loads apply its result.
///
/// ```dart
/// final token = _generation.begin();
/// final data = await fetch();
/// if (!mounted || !_generation.isCurrent(token)) return; // a newer load won
/// ```
class LoadGeneration {
  int _current = 0;

  /// Starts a load; every earlier one becomes stale.
  int begin() => ++_current;

  bool isCurrent(int token) => token == _current;

  /// Makes every load in flight stale (e.g. when the screen is disposed).
  void invalidate() => _current++;
}
