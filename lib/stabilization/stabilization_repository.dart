import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'stabilization_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION REPOSITORY
// All SQLite I/O for parameter_readings and stabilization summary columns.
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationRepository {
  StabilizationRepository._();
  static final instance = StabilizationRepository._();

  static const tReadings = 'parameter_readings';

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ── READINGS: INSERT ────────────────────────────────────────────────────────

  Future<ParameterReading> insertReading(ParameterReading reading) async {
    final db = await _db;
    final id = await db.insert(
      tReadings,
      reading.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return reading.copyWith(id: id);
  }

  // ── READINGS: LOAD ──────────────────────────────────────────────────────────

  Future<List<ParameterReading>> getReadingsForPoint(int fieldPointId) async {
    final db = await _db;
    final rows = await db.query(
      tReadings,
      where: 'field_point_id = ?',
      whereArgs: [fieldPointId],
      orderBy: 'parameter_name ASC, reading_order ASC',
    );
    return rows.map(ParameterReading.fromMap).toList();
  }

  Future<List<ParameterReading>> getReadingsForParam(
    int fieldPointId,
    String parameterName,
  ) async {
    final db = await _db;
    final rows = await db.query(
      tReadings,
      where: 'field_point_id = ? AND parameter_name = ?',
      whereArgs: [fieldPointId, parameterName],
      orderBy: 'reading_order ASC',
    );
    return rows.map(ParameterReading.fromMap).toList();
  }

  // ── READINGS: DELETE ────────────────────────────────────────────────────────

  Future<void> deleteReading(int id) async {
    final db = await _db;
    await db.delete(tReadings, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteReadingsForPoint(int fieldPointId) async {
    final db = await _db;
    await db.delete(
      tReadings,
      where: 'field_point_id = ?',
      whereArgs: [fieldPointId],
    );
  }

  // ── STABILIZATION SUMMARY: SAVE ─────────────────────────────────────────────

  /// Persists the stabilization outcome to the field_points row after save.
  Future<void> saveStabilizationSummary({
    required int fieldPointId,
    required String overallStatus,
    required Map<String, dynamic> summaryByParam,
    required Map<String, double?> finalParamValues,
    String? exceptionReason,
    String? exceptionNotes,
  }) async {
    final db = await _db;
    await db.update(
      DatabaseHelper.tFieldPoints,
      {
        'stabilization_status':           overallStatus,
        'stabilization_summary_json':     jsonEncode(summaryByParam),
        'stabilization_completed_at':     DateTime.now().toIso8601String(),
        'stabilization_exception_reason': exceptionReason,
        'stabilization_exception_notes':  exceptionNotes,
        'final_parameter_values_json':    jsonEncode(finalParamValues),
      },
      where: 'id = ?',
      whereArgs: [fieldPointId],
    );
  }

  // ── QAQC: CAMPAIGN AGGREGATE ────────────────────────────────────────────────

  /// Returns campaign-level stabilization metrics for the FinishScreen QAQC.
  Future<StabilizationQaqc> getQaqcForCampaign(String campaignId) async {
    final db = await _db;

    final rows = await db.query(
      DatabaseHelper.tFieldPoints,
      columns: ['stabilization_status'],
      where: 'campaignId = ? AND status = ?',
      whereArgs: [campaignId, 'done'],
    );

    int total = 0, stabilized = 0, withException = 0, outOfRange = 0;

    for (final row in rows) {
      final status = row['stabilization_status'] as String?;
      if (status == null || status.isEmpty) continue;
      total++;
      switch (status) {
        case 'stabilized':         stabilized++;    break;
        case 'justifiedException': withException++; break;
        case 'outOfRange':         outOfRange++;    break;
      }
    }

    final conformanceRate = total > 0
        ? (stabilized / total * 100.0).clamp(0.0, 100.0)
        : 100.0;

    return StabilizationQaqc(
      totalWithStabilization: total,
      stabilized:             stabilized,
      withException:          withException,
      outOfRange:             outOfRange,
      conformanceRate:        conformanceRate,
    );
  }
}
