/// Cheap token estimator (~3.5 chars/token, same heuristic as gastos).
class TokenEstimator {
  static const double charsPerToken = 3.5;

  static int estimateText(String? text) {
    if (text == null || text.isEmpty) return 0;
    return (text.length / charsPerToken).ceil();
  }

  static int estimateMessage({
    required String role,
    String? content,
    String? toolName,
    String? toolCallArguments,
  }) {
    var total = role.length + 8;
    total += estimateText(content);
    if (toolName != null) total += estimateText(toolName);
    if (toolCallArguments != null) total += estimateText(toolCallArguments);
    return total;
  }
}
