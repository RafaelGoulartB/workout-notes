import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/ai_service.dart';

/// The stable error code inside [error] (an `ai_error:<code>` string, an
/// [AiServiceException] or a bare code), or null when there is none.
String? aiErrorCode(Object? error) {
  if (error is AiServiceException) return error.code;
  if (error is String) {
    final raw = error.startsWith('ai_error:')
        ? error.substring('ai_error:'.length)
        : error;
    final code = raw.split(':').first;
    return code.isEmpty ? null : code;
  }
  return null;
}

/// Converts stable AI error codes into short, actionable localized text.
///
/// Accepts `ai_error:<code>` strings, [AiServiceException]s and bare codes
/// (for example `AiProviderCheck.errorCode`). `proposal_<code>` falls back to
/// the generic proposal failure; anything unknown becomes the generic error.
String localizeAiError(Object? error, AppLocalizations l10n) {
  final code = aiErrorCode(error);
  if (code == null) return l10n.aiChatErrorGeneric;
  if (code.startsWith('routine_apply_failed')) {
    return l10n.aiChatErrorProposalFailed;
  }
  if (code.startsWith('proposal_')) {
    return code == 'proposal_stale'
        ? l10n.aiChatErrorProposalStale
        : l10n.aiChatErrorProposalFailed;
  }
  switch (code) {
    case 'missing_provider':
      return l10n.aiChatErrorNoProvider;
    case 'consent_required':
      return l10n.aiChatErrorConsent;
    case 'missing_model':
      return l10n.aiChatErrorMissingModel;
    case 'missing_token':
      return l10n.aiChatErrorMissingToken;
    case 'invalid_token':
      return l10n.aiChatErrorInvalidToken;
    case 'too_many_images':
      return l10n.aiChatTooManyImages;
    case 'image_missing':
      return l10n.aiChatErrorImageMissing;
    case 'image_too_large':
      return l10n.aiChatImageTooLarge;
    case 'unsupported_image':
      return l10n.aiChatUnsupportedImage;
    case 'timeout':
      return l10n.aiChatErrorTimeout;
    case 'connection_error':
      return l10n.aiChatErrorConnection;
    case 'cancelled':
      return l10n.aiChatErrorCancelled;
    case 'payment_required':
      return l10n.aiChatErrorPaymentRequired;
    case 'forbidden':
      return l10n.aiChatErrorForbidden;
    case 'not_found':
      return l10n.aiChatErrorNotFound;
    case 'payload_too_large':
      return l10n.aiChatErrorPayloadTooLarge;
    case 'context_length_exceeded':
      return l10n.aiChatErrorContextLength;
    case 'bad_request':
      return l10n.aiChatErrorBadRequest;
    case 'rate_limited':
      return l10n.aiChatErrorRateLimited;
    case 'provider_unavailable':
      return l10n.aiChatErrorProviderUnavailable;
    case 'invalid_response':
    case 'empty_choices':
      return l10n.aiChatErrorInvalidResponse;
    case 'empty_answer':
      return l10n.aiChatErrorEmptyAnswer;
    case 'vision_not_supported':
      return l10n.aiChatErrorVisionUnsupported;
    case 'http_error':
    case 'list_models_failed':
      return l10n.aiChatErrorRequest;
    case 'user_message_missing':
      return l10n.aiChatErrorUserMessage;
    case 'generic':
    default:
      return l10n.aiChatErrorGeneric;
  }
}
