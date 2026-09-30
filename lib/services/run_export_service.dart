import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';

typedef RunShareFileCallback = Future<void> Function(XFile file, String text);

/// Exports a finished run: a GPX 1.1 track for other apps and a rendered
/// share-card image. Files go to the temp directory and then the system
/// share sheet, mirroring `ExportService`.
class RunExportService {
  final RunShareFileCallback _shareFile;
  final Future<Directory> Function() _tempDirectory;

  RunExportService({
    RunShareFileCallback? shareFile,
    Future<Directory> Function()? tempDirectory,
  }) : _shareFile = shareFile ?? _shareWithSheet,
       _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  static const String creator = 'Workout Notes';

  static Future<void> _shareWithSheet(XFile file, String text) async {
    await SharePlus.instance.share(ShareParams(files: [file], text: text));
  }

  // ---------------------------------------------------------------- GPX

  /// GPX 1.1 document for [points] (lat, lon, ele, time), ordered by `seq`.
  static String buildGpx({
    required RunActivity activity,
    required List<RunTrackPoint> points,
    String? name,
  }) {
    final ordered = List<RunTrackPoint>.of(points)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final title = _xmlEscape(_displayName(activity, name));
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="$creator" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>$title</name>')
      ..writeln('    <time>${_time(activity.startedAt)}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>$title</name>');
    if (activity.notes?.trim().isNotEmpty == true) {
      buffer.writeln('    <desc>${_xmlEscape(activity.notes!.trim())}</desc>');
    }
    buffer
      ..writeln('    <type>running</type>')
      ..writeln('    <trkseg>');
    for (final point in ordered) {
      buffer.write(
        '      <trkpt lat="${point.lat.toStringAsFixed(7)}" '
        'lon="${point.lng.toStringAsFixed(7)}">',
      );
      final altitude = point.altitude;
      if (altitude != null && altitude.isFinite) {
        buffer.write('<ele>${altitude.toStringAsFixed(1)}</ele>');
      }
      buffer.writeln('<time>${_time(point.recordedAt)}</time></trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  static String _displayName(RunActivity activity, String? name) {
    final title = name?.trim().isNotEmpty == true
        ? name!.trim()
        : activity.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return 'Run ${_time(activity.startedAt)}';
  }

  /// UTC timestamp without fractional seconds, as GPX readers expect.
  static String _time(DateTime value) {
    final utc = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
        '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
        '${two(utc.second)}Z';
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// File name like `run_2026-08-25_0630.gpx`.
  static String fileStem(RunActivity activity) {
    final local = activity.startedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'run_${local.year}-${two(local.month)}-${two(local.day)}_'
        '${two(local.hour)}${two(local.minute)}';
  }

  /// Writes the GPX file and returns its path.
  Future<String> writeGpx({
    required RunActivity activity,
    required List<RunTrackPoint> points,
  }) async {
    final dir = await _tempDirectory();
    final file = File('${dir.path}/${fileStem(activity)}.gpx');
    await file.writeAsString(buildGpx(activity: activity, points: points));
    return file.path;
  }

  Future<String> shareGpx({
    required RunActivity activity,
    required List<RunTrackPoint> points,
    String text = 'Workout Notes',
  }) async {
    final path = await writeGpx(activity: activity, points: points);
    await _shareFile(XFile(path, mimeType: 'application/gpx+xml'), text);
    return path;
  }

  // -------------------------------------------------------------- image

  /// Renders the [RepaintBoundary] behind [boundaryKey] to PNG bytes.
  static Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3,
  }) async {
    final render = boundaryKey.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) return null;
    final ui.Image image = await render.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Saves [png] to the temp directory and opens the share sheet.
  Future<String> sharePng({
    required RunActivity activity,
    required Uint8List png,
    String text = 'Workout Notes',
  }) async {
    final dir = await _tempDirectory();
    final file = File('${dir.path}/${fileStem(activity)}.png');
    await file.writeAsBytes(png);
    await _shareFile(XFile(file.path, mimeType: 'image/png'), text);
    return file.path;
  }
}
