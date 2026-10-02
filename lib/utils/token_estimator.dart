/// Cheap token estimator (~3.5 chars/token, same heuristic as gastos).
class TokenEstimator {
  static const double charsPerToken = 3.5;

  static int estimateText(String? text) {
    if (text == null || text.isEmpty) return 0;
    return estimateChars(text.length);
  }

  /// Same estimate from a length already known, so large payloads that were
  /// encoded once are not encoded again just to be measured.
  static int estimateChars(int length) =>
      length <= 0 ? 0 : (length / charsPerToken).ceil();

}
