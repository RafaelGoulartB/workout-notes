/// Shared color palette for periodization phases and plans. Kept in one
/// place so a design change to the phase swatches lands in a single file.
const int kPhaseColorBlue = 0xFF4F8EF7;
const int kPhaseColorAmber = 0xFFF5B942;
const int kPhaseColorPurple = 0xFF9B6BE8;
const int kPhaseColorGreen = 0xFF43B581;
const int kPhaseColorRed = 0xFFE85858;
const int kPhaseColorTeal = 0xFF26A6A1;

/// Palette order shown by the phase / plan editors.
const List<int> kPeriodizationColors = [
  kPhaseColorBlue,
  kPhaseColorAmber,
  kPhaseColorPurple,
  kPhaseColorGreen,
  kPhaseColorRed,
  kPhaseColorTeal,
];

/// Default phase color, also used as the fallback when none is chosen.
const int kDefaultPhaseColor = kPhaseColorBlue;
