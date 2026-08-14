import '../l10n/app_localizations.dart';
import '../services/ai_service.dart';

/// Converts stable AI error codes into localized UI text.
String localizeAiError(Object? error, AppLocalizations l10n) {
  final code = error is AiServiceException
      ? error.code
      : error is String && error.startsWith('ai_error:')
      ? error.substring('ai_error:'.length)
      : null;
  if (code?.startsWith('routine_apply_failed') ?? false) {
    return l10n.aiChatErrorRoutineApply;
  }
  switch (code) {
    case 'missing_provider':
      return l10n.aiChatErrorNoProvider;
    case 'missing_token':
    case 'invalid_token':
      return l10n.aiChatErrorInvalidToken;
    case 'missing_model':
      return l10n.aiChatErrorMissingModel;
    case 'timeout':
      return l10n.aiChatErrorTimeout;
    case 'not_found':
      return l10n.aiChatErrorNotFound;
    case 'invalid_response':
    case 'empty_choices':
      return l10n.aiChatErrorInvalidResponse;
    case 'http_error':
    case 'connection_error':
    case 'list_models_failed':
      return l10n.aiChatErrorRequest;
    case 'provider_unavailable':
      return l10n.aiChatErrorProviderUnavailable;
    case 'vision_not_supported':
      return l10n.aiChatErrorVisionUnsupported;
    case 'image_missing':
      return l10n.aiChatErrorImageMissing;
    case 'too_many_images':
      return l10n.aiChatTooManyImages;
    case 'image_too_large':
      return l10n.aiChatImageTooLarge;
    case 'unsupported_image':
      return l10n.aiChatUnsupportedImage;
    case 'user_message_missing':
      return l10n.aiChatErrorUserMessage;
    case 'generic':
    case null:
      return l10n.aiChatErrorGeneric;
    default:
      return l10n.aiChatErrorGeneric;
  }
}
