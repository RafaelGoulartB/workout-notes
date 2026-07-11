import '../l10n/app_localizations.dart';
import '../services/ai_service.dart';

/// Converts stable AI error codes into localized UI text.
String localizeAiError(Object? error, AppLocalizations l10n) {
  final code = error is AiServiceException
      ? error.code
      : error is String && error.startsWith('ai_error:')
      ? error.substring('ai_error:'.length)
      : null;
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
    case 'list_models_failed':
      return l10n.aiChatErrorRequest;
    case 'user_message_missing':
      return l10n.aiChatErrorUserMessage;
    case 'generic':
    case null:
      return l10n.aiChatErrorGeneric;
    default:
      return l10n.aiChatErrorGeneric;
  }
}
