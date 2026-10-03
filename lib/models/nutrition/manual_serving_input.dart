/// Optional input for a manual serving.
class ManualServingInput {
  final String label;
  final double quantity;
  final String unit;
  final double? gramsEquivalent;
  final double? mlEquivalent;

  const ManualServingInput({
    required this.label,
    required this.quantity,
    required this.unit,
    this.gramsEquivalent,
    this.mlEquivalent,
  });
}
