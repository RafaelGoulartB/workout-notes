/// Minimal RFC 4180 CSV writer.
///
/// Fields are separated by commas and rows by CRLF, with no trailing line
/// break. A field is wrapped in double quotes when it contains a comma, a
/// double quote, a CR or an LF (or starts/ends with a space, which spreadsheet
/// importers would otherwise trim); embedded double quotes are doubled.
String encodeCsv(List<List<String>> rows) =>
    rows.map((row) => row.map(_encodeField).join(',')).join('\r\n');

String _encodeField(String field) {
  final needsQuotes =
      field.contains(',') ||
      field.contains('"') ||
      field.contains('\r') ||
      field.contains('\n') ||
      field.startsWith(' ') ||
      field.endsWith(' ');
  if (!needsQuotes) return field;
  return '"${field.replaceAll('"', '""')}"';
}
