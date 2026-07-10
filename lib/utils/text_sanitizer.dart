/// Minimal text sanitiser for LLM outputs.
///
/// Most output cleanup is the model's job — the system prompt tells it to
/// avoid `$1`/`[1]`/`【1】` placeholders, and the model should have freedom
/// over its own wording.
///
/// The one pattern we have to strip is the citation placeholder several
/// models emit as a learned behavior from pre-training: `$1`, `$2`, `${1}`.
///
/// The model uses these as a token meaning "the proper noun I should write
/// here" (an exercise name, a routine, etc). It knows the data — it just
/// defaults to the placeholder instead of expanding it. The chat service can
/// then rebuild a factual response from the associated tool result; this
/// class remains the final safety net for every other response.
///
/// This sanitiser is intentionally tiny: it strips exactly `\$\d+` and
/// `\$\{\d+\}`. It does NOT touch:
///   - `[1]`, `【1]`, `〈1〉`, `⟨1⟩` (these don't appear in practice).
///   - Zero-width characters (over-engineering).
///   - Whitespace (the model's prerogative).
///   - Legitimate `$` usage (`R$ 100`, `\$variable` in code snippets, etc.)
///     because the regex requires a digit immediately after the `$`.
class TextSanitizer {
  // Matches $1, $2, $99, ${1}, ${42}. Requires a digit right after the $ or
  // the opening brace, so it won't touch R$, $identifier, or $.
  static final RegExp _dollarDigit = RegExp(
    r'\$[\u200B-\u200D\uFEFF]*\{?[\u200B-\u200D\uFEFF]*\d+[\u200B-\u200D\uFEFF]*\}?',
  );

  // Matches an opening <think> tag and anything up to the matching closing
  // tag. Handles multiple blocks and newlines.
  static final RegExp _thinkBlock = RegExp(
    r'<think>[\s\S]*?</think>',
    multiLine: true,
  );

  /// Strips citation placeholders and reasoning blocks from [input].
  /// Each step has an early-out (cheap `contains` check) so clean text
  /// doesn't pay the regex cost.
  static String sanitize(String input) {
    var result = stripReasoning(input);
    if (result.contains(r'$')) {
      result = result.replaceAll(_dollarDigit, '');
    }
    return result;
  }

  /// Removes private reasoning while preserving the response verbatim enough
  /// for the chat orchestrator to validate and, when necessary, regenerate it.
  static String stripReasoning(String input) =>
      input.contains('<think>') ? input.replaceAll(_thinkBlock, '') : input;

  /// Whether [input] contains a reference marker emitted instead of data.
  /// The optional invisible characters account for provider-specific output
  /// that looks like a normal marker in the chat UI.
  static bool containsReferencePlaceholder(String input) =>
      _dollarDigit.hasMatch(input);
}
