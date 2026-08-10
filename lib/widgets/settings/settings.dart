/// Barrel for the shared settings surface primitives used across every
/// preferences / configuration screen in the app.
///
/// The components here define the canonical settings visual language:
/// uppercase tracked section headers, rounded outlined card groups, and
/// a family of tappable tiles (link, switch, radio, value, option,
/// color swatch). New settings screens should compose these rather than
/// re-implementing private copies.
library;

export 'settings_primitives.dart';
export 'settings_tiles.dart';
export 'settings_value_picker.dart';
export 'settings_app_bar.dart';
export 'settings_sheet_helpers.dart';