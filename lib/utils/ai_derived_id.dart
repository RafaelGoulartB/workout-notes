import 'package:uuid/uuid.dart';

/// Deterministic id for a row created by an AI proposal: the same proposal
/// always derives the same ids, so applying it twice can never insert a
/// duplicate (the second insert hits the primary key instead).
String aiDerivedId(String proposalId, String name) =>
    const Uuid().v5(Namespace.url.value, 'workout-notes:ai:$proposalId/$name');
