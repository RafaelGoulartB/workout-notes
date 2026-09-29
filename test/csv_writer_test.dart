import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/csv_writer.dart';

void main() {
  test('joins fields with commas and rows with CRLF, no trailing break', () {
    expect(
      encodeCsv([
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]),
      'a,b,c\r\n1,2,3',
    );
  });

  test('quotes fields with commas, quotes, CR or LF and doubles quotes', () {
    expect(
      encodeCsv([
        ['x,y', 'say "hi"', 'line\nbreak', 'cr\rhere', 'plain'],
      ]),
      '"x,y","say ""hi""","line\nbreak","cr\rhere",plain',
    );
  });

  test('quotes fields with leading or trailing spaces', () {
    expect(
      encodeCsv([
        [' lead', 'trail ', 'in ner'],
      ]),
      '" lead","trail ",in ner',
    );
  });

  test('keeps empty fields and handles no rows', () {
    expect(
      encodeCsv([
        ['', 'a', ''],
      ]),
      ',a,',
    );
    expect(encodeCsv([]), '');
  });
}
