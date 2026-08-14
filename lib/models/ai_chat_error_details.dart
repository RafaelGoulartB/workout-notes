/// Safe diagnostic context for an AI Coach failure.
///
/// Tokens, request bodies and complete provider responses must never be stored
/// here. The object exists only in memory and is rendered in the error banner
/// so provider compatibility problems can be diagnosed without log access.
class AiChatErrorDetails {
  final String code;
  final String stage;
  final String? message;
  final int? httpStatus;
  final String? endpoint;
  final String? provider;
  final String? model;
  final int? round;
  final int? schemaToolCount;
  final int? requestCharacters;
  final List<String> tools;
  final int? providerAttempts;
  final List<String> compatibilityAdjustments;

  const AiChatErrorDetails({
    required this.code,
    required this.stage,
    this.message,
    this.httpStatus,
    this.endpoint,
    this.provider,
    this.model,
    this.round,
    this.schemaToolCount,
    this.requestCharacters,
    this.tools = const [],
    this.providerAttempts,
    this.compatibilityAdjustments = const [],
  });
}
