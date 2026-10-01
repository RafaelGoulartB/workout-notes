import 'package:workout_notes/services/ai_proposals/ai_proposal_handlers.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Guarded proposal tools, one per proposal kind. They never write data: the
/// app previews the proposal and only the user's approval applies it.
///
/// The specs come from the proposal handlers (schema, description and domain
/// live next to the validation they describe); calls are executed by
/// `AiProposalService.prepare`, so the specs carry no handler.
List<AiToolSpec> proposalToolSpecs() => [
  for (final handler in defaultAiProposalHandlers()) handler.catalogSpec,
];
