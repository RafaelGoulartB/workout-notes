/// Barrel for the shared settings surface primitives used across every
/// preferences / configuration screen in the app.
///
/// The components here define the canonical settings visual language:
/// uppercase tracked section headers, rounded outlined card groups, and
/// a family of tappable tiles (link, switch, radio, value, option,
/// color swatch). New settings screens should compose these rather than
/// re-implementing private copies.
library;

export 'package:workout_notes/widgets/settings/settings_app_bar.dart';
export 'package:workout_notes/widgets/settings/settings_primitives.dart';
export 'package:workout_notes/widgets/settings/settings_sheet_helpers.dart';
export 'package:workout_notes/widgets/settings/settings_tiles.dart';
export 'package:workout_notes/widgets/settings/settings_value_picker.dart';
