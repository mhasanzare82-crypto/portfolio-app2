import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/custom_field.dart';

class CustomFieldRepository {
  final AppDatabase _database = AppDatabase.instance;

  // =========================================================
  // GET ALL FIELDS
  // =========================================================

  Future<List<CustomField>> getAllFields() async {
    final db = await _database.database;

    final result = await db.query(
      'custom_fields',
      orderBy: 'field_order ASC, field_id ASC',
    );

    return result
        .map(
          (map) => CustomField.fromMap(map),
        )
        .toList();
  }

  // =========================================================
  // GET ENABLED FIELDS
  // =========================================================

  Future<List<CustomField>> getEnabledFields() async {
    final db = await _database.database;

    final result = await db.query(
      'custom_fields',
      where: 'is_enabled = ?',
      whereArgs: [1],
      orderBy: 'field_order ASC, field_id ASC',
    );

    return result
        .map(
          (map) => CustomField.fromMap(map),
        )
        .toList();
  }

  // =========================================================
  // GET FIELDS BY CATEGORY
  // =========================================================

  Future<List<CustomField>> getFieldsByCategory(
    String category,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'custom_fields',
      where: 'category = ? AND is_enabled = ?',
      whereArgs: [
        category,
        1,
      ],
      orderBy: 'field_order ASC, field_id ASC',
    );

    return result
        .map(
          (map) => CustomField.fromMap(map),
        )
        .toList();
  }

  // =========================================================
  // GET CATEGORIES
  // =========================================================

  Future<List<String>> getCategories() async {
    final db = await _database.database;

    final result = await db.rawQuery(
      '''
      SELECT DISTINCT category
      FROM custom_fields
      WHERE category IS NOT NULL
        AND TRIM(category) != ''
      ORDER BY category ASC
      ''',
    );

    return result
        .map(
          (row) => row['category']?.toString() ?? 'عمومی',
        )
        .where(
          (category) => category.trim().isNotEmpty,
        )
        .toList();
  }

  // =========================================================
  // CREATE FIELD
  // =========================================================

  Future<int> createField(
    CustomField field,
  ) async {
    final db = await _database.database;

    final highestOrder = await db.rawQuery(
      '''
      SELECT MAX(field_order) AS max_order
      FROM custom_fields
      ''',
    );

    final maxOrder = highestOrder.first['max_order'];

    final nextOrder = (maxOrder is num ? maxOrder.toInt() : -1) + 1;

    return db.insert(
      'custom_fields',
      {
        'field_name': field.fieldName,
        'field_type': field.fieldType.name,

        // دسته‌بندی فیلد
        'category':
            field.category.trim().isEmpty ? 'عمومی' : field.category.trim(),

        'is_required': field.isRequired ? 1 : 0,
        'is_enabled': field.isEnabled ? 1 : 0,
        'field_order': field.fieldOrder == 0 ? nextOrder : field.fieldOrder,
        'options_text': field.options.join('\n'),
        'created_at': field.createdAt.toIso8601String(),
      },
    );
  }

  // =========================================================
  // UPDATE FIELD
  // =========================================================

  Future<void> updateField(
    CustomField field,
  ) async {
    if (field.fieldId == null) {
      return;
    }

    final db = await _database.database;

    await db.update(
      'custom_fields',
      {
        'field_name': field.fieldName,
        'field_type': field.fieldType.name,

        // دسته‌بندی فیلد
        'category':
            field.category.trim().isEmpty ? 'عمومی' : field.category.trim(),

        'is_required': field.isRequired ? 1 : 0,
        'is_enabled': field.isEnabled ? 1 : 0,
        'field_order': field.fieldOrder,
        'options_text': field.options.join('\n'),
      },
      where: 'field_id = ?',
      whereArgs: [field.fieldId],
    );
  }

  // =========================================================
  // SET FIELD ENABLED
  // =========================================================

  Future<void> setFieldEnabled(
    int fieldId,
    bool enabled,
  ) async {
    final db = await _database.database;

    await db.update(
      'custom_fields',
      {
        'is_enabled': enabled ? 1 : 0,
      },
      where: 'field_id = ?',
      whereArgs: [fieldId],
    );
  }

  // =========================================================
  // ARCHIVE FIELD
  // =========================================================

  /// فیلد را حذف واقعی نمی‌کند.
  ///
  /// دلیل:
  /// ممکن است این فیلد قبلاً در معاملات ثبت شده باشد.
  /// بنابراین برای حفظ اطلاعات تاریخی، فقط غیرفعال می‌شود.
  Future<void> archiveField(
    int fieldId,
  ) async {
    await setFieldEnabled(
      fieldId,
      false,
    );
  }

  // =========================================================
  // DELETE FIELD
  // =========================================================

  /// این متد فقط برای سازگاری با کدهای قبلی نگه داشته شده است.
  ///
  /// عمداً هیچ رکوردی از custom_fields یا
  /// trade_custom_values حذف نمی‌کند.
  Future<void> deleteField(
    int fieldId,
  ) async {
    await archiveField(
      fieldId,
    );
  }

  // =========================================================
  // SAVE TRADE VALUES
  // =========================================================

  Future<void> saveTradeValues(
    String tradeId,
    Map<int, String> values,
  ) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        for (final entry in values.entries) {
          if (entry.value.trim().isEmpty) {
            await transaction.delete(
              'trade_custom_values',
              where: 'trade_id = ? AND field_id = ?',
              whereArgs: [tradeId, entry.key],
            );
            continue;
          }
          await transaction.insert(
            'trade_custom_values',
            {
              'trade_id': tradeId,
              'field_id': entry.key,
              'value_text': entry.value,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      },
    );
  }

  // =========================================================
  // GET TRADE VALUES
  // =========================================================

  Future<Map<int, String>> getTradeValues(
    String tradeId,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'trade_custom_values',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
    );

    final values = <int, String>{};

    for (final row in result) {
      final fieldId = row['field_id'];

      if (fieldId is int) {
        values[fieldId] = row['value_text']?.toString() ?? '';
      }
    }

    return values;
  }

  // =========================================================
  // DELETE TRADE VALUES
  // =========================================================

  Future<void> deleteTradeValues(
    String tradeId,
  ) async {
    final db = await _database.database;

    await db.delete(
      'trade_custom_values',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
    );
  }
}
