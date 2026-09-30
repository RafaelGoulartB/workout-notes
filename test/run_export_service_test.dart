import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/services/run_export_service.dart';

RunActivity _activity({String? title, String? notes}) {
  final started = DateTime.utc(2026, 8, 25, 10, 5, 7);
  return RunActivity(
    id: 'run-1',
    startedAt: started,
    endedAt: started.add(const Duration(minutes: 30)),
    durationSeconds: 1800,
    movingTimeSeconds: 1750,
    distanceMeters: 5000,
    avgPaceSecPerKm: 350,
    maxPaceSecPerKm: 330,
    calories: 400,
    title: title,
    notes: notes,
    status: 'completed',
    polylineSummary: null,
    createdAt: started,
    updatedAt: started,
  );
}

RunTrackPoint _point(int seq, double lat, double lng, double? altitude) =>
    RunTrackPoint(
      id: 'p$seq',
      activityId: 'run-1',
      seq: seq,
      lat: lat,
      lng: lng,
      altitude: altitude,
      accuracy: 5,
      speed: 3,
      recordedAt: DateTime.utc(
        2026,
        8,
        25,
        10,
        5,
        7,
      ).add(Duration(seconds: seq * 5)),
    );

void main() {
  group('RunExportService.buildGpx', () {
    test('writes a GPX 1.1 track with lat, lon, ele and time', () {
      final gpx = RunExportService.buildGpx(
        activity: _activity(title: 'Long run'),
        points: [
          _point(0, -23.5505, -46.6333, 760.24),
          _point(1, -23.5506, -46.6335, 761.0),
        ],
      );

      expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1" creator="Workout Notes"'));
      expect(gpx, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
      expect(gpx, contains('<name>Long run</name>'));
      expect(gpx, contains('<type>running</type>'));
      expect(gpx, contains('<time>2026-08-25T10:05:07Z</time>'));
      expect(
        gpx,
        contains(
          '<trkpt lat="-23.5505000" lon="-46.6333000"><ele>760.2</ele>'
          '<time>2026-08-25T10:05:07Z</time></trkpt>',
        ),
      );
      expect(gpx, contains('<time>2026-08-25T10:05:12Z</time></trkpt>'));
      expect(RegExp('<trkpt ').allMatches(gpx), hasLength(2));
      expect(gpx.trimRight(), endsWith('</gpx>'));
    });

    test('skips <ele> when altitude is unknown and sorts by seq', () {
      final gpx = RunExportService.buildGpx(
        activity: _activity(),
        points: [_point(2, 1, 2, null), _point(1, 3, 4, 10)],
      );
      final first = gpx.indexOf('lat="3.0000000"');
      final second = gpx.indexOf('lat="1.0000000"');
      expect(first, isNonNegative);
      expect(second, greaterThan(first));
      expect(
        gpx,
        contains(
          '<trkpt lat="1.0000000" lon="2.0000000">'
          '<time>2026-08-25T10:05:17Z</time></trkpt>',
        ),
      );
    });

    test('escapes XML in title and notes', () {
      final gpx = RunExportService.buildGpx(
        activity: _activity(title: 'Tom & <Jerry>', notes: 'say "hi"'),
        points: [_point(0, 0, 0, 1)],
      );
      expect(gpx, contains('<name>Tom &amp; &lt;Jerry&gt;</name>'));
      expect(gpx, contains('<desc>say &quot;hi&quot;</desc>'));
      expect(gpx, isNot(contains('<Jerry>')));
    });

    test('falls back to a dated name when the run is untitled', () {
      final gpx = RunExportService.buildGpx(
        activity: _activity(),
        points: [_point(0, 0, 0, null)],
      );
      expect(gpx, contains('<name>Run 2026-08-25T10:05:07Z</name>'));
    });
  });

  group('RunExportService sharing', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('run_export_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test(
      'shareGpx writes the file and hands it to the share callback',
      () async {
        XFile? shared;
        final service = RunExportService(
          tempDirectory: () async => temp,
          shareFile: (file, text) async => shared = file,
        );
        final path = await service.shareGpx(
          activity: _activity(),
          points: [_point(0, 0, 0, 1), _point(1, 0.001, 0, 2)],
        );

        expect(path, endsWith('.gpx'));
        expect(File(path).existsSync(), isTrue);
        expect(await File(path).readAsString(), contains('<trkseg>'));
        expect(shared?.path, path);
        expect(shared?.mimeType, 'application/gpx+xml');
      },
    );

    test('sharePng writes the bytes as a png', () async {
      XFile? shared;
      final service = RunExportService(
        tempDirectory: () async => temp,
        shareFile: (file, text) async => shared = file,
      );
      final path = await service.sharePng(
        activity: _activity(),
        png: Uint8List.fromList([1, 2, 3]),
      );
      expect(path, endsWith('.png'));
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(shared?.mimeType, 'image/png');
    });
  });
}
