import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

class PreTradeRepository {
  final AppDatabase _database = AppDatabase.instance;

  // =========================================================
  // GET ITEMS
  // =========================================================

  Future<List<Map<String, dynamic>>> getAllItems({
    String? category,
    bool enabledOnly = false,
  }) async {
    final db = await _database.database;

    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (category != null) {
      whereParts.add('category = ?');
      whereArgs.add(category);
    }

    if (enabledOnly) {
      whereParts.add('is_enabled = 1');
    }

    final result = await db.query(
      'pre_trade_items',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'item_order ASC, item_id ASC',
    );

    return result;
  }

  Future<List<Map<String, dynamic>>> getEnabledItems(
    String category,
  ) async {
    return getAllItems(
      category: category,
      enabledOnly: true,
    );
  }

  // =========================================================
  // GET SINGLE ITEM
  // =========================================================

  Future<Map<String, dynamic>?> getItem(
    int itemId,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'pre_trade_items',
      where: 'item_id = ?',
      whereArgs: [itemId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  // =========================================================
  // CREATE
  // =========================================================

  Future<int> createItem({
    required String title,
    required String category,
    required String itemType,
    bool isRequired = false,
    bool isEnabled = true,
    String folderName = '',
  }) async {
    final db = await _database.database;

    final orderResult = await db.rawQuery(
      '''
      SELECT MAX(item_order) AS max_order
      FROM pre_trade_items
      WHERE category = ?
      ''',
      [category],
    );

    final maxOrder = orderResult.first['max_order'] as int? ?? -1;

    return db.insert(
      'pre_trade_items',
      {
        'item_title': title.trim(),
        'category': category,
        'folder_name': folderName.trim(),
        'item_type': itemType,
        'is_required': isRequired ? 1 : 0,
        'is_enabled': isEnabled ? 1 : 0,
        'item_order': maxOrder + 1,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  // =========================================================
  // UPDATE
  // =========================================================

  Future<void> updateItem({
    required int itemId,
    required String title,
    required String category,
    required String itemType,
    required bool isRequired,
    String folderName = '',
  }) async {
    final db = await _database.database;

    await db.update(
      'pre_trade_items',
      {
        'item_title': title.trim(),
        'category': category,
        'folder_name': folderName.trim(),
        'item_type': itemType,
        'is_required': isRequired ? 1 : 0,
      },
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
  }

  // =========================================================
  // ENABLE / DISABLE
  // =========================================================

  Future<void> setEnabled(
    int itemId,
    bool enabled,
  ) async {
    final db = await _database.database;

    await db.update(
      'pre_trade_items',
      {
        'is_enabled': enabled ? 1 : 0,
      },
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
  }

  // =========================================================
  // DELETE
  // =========================================================

  Future<void> deleteItem(
    int itemId,
  ) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.delete(
          'trade_pre_trade_values',
          where: 'item_id = ?',
          whereArgs: [itemId],
        );

        await transaction.delete(
          'pre_trade_items',
          where: 'item_id = ?',
          whereArgs: [itemId],
        );
      },
    );
  }

  // =========================================================
  // SAVE TRADE ANSWERS
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
              'trade_pre_trade_values',
              where: 'trade_id = ? AND item_id = ?',
              whereArgs: [tradeId, entry.key],
            );
            continue;
          }
          await transaction.insert(
            'trade_pre_trade_values',
            {
              'trade_id': tradeId,
              'item_id': entry.key,
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
  // GET TRADE ANSWERS
  // =========================================================

  Future<Map<int, String>> getTradeValues(
    String tradeId,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'trade_pre_trade_values',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
    );

    final values = <int, String>{};

    for (final row in result) {
      final itemId = row['item_id'];

      if (itemId is int) {
        values[itemId] = row['value_text']?.toString() ?? '';
      }
    }

    return values;
  }

  // =========================================================
  // DELETE ALL ANSWERS OF A TRADE
  // =========================================================

  Future<void> deleteTradeValues(
    String tradeId,
  ) async {
    final db = await _database.database;

    await db.delete(
      'trade_pre_trade_values',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
    );
  }

  // =========================================================
  // MOVE ITEM UP
  // =========================================================

  Future<void> moveItemUp(
    int itemId,
  ) async {
    final db = await _database.database;

    final current = await getItem(itemId);

    if (current == null) {
      return;
    }

    final category = current['category']?.toString() ?? '';

    final currentOrder = current['item_order'] as int? ?? 0;

    final previousResult = await db.query(
      'pre_trade_items',
      where: '''
        category = ?
        AND item_order < ?
      ''',
      whereArgs: [
        category,
        currentOrder,
      ],
      orderBy: 'item_order DESC',
      limit: 1,
    );

    if (previousResult.isEmpty) {
      return;
    }

    final previous = previousResult.first;

    final previousId = previous['item_id'] as int;

    final previousOrder = previous['item_order'] as int;

    await db.transaction(
      (transaction) async {
        await transaction.update(
          'pre_trade_items',
          {
            'item_order': previousOrder,
          },
          where: 'item_id = ?',
          whereArgs: [itemId],
        );

        await transaction.update(
          'pre_trade_items',
          {
            'item_order': currentOrder,
          },
          where: 'item_id = ?',
          whereArgs: [previousId],
        );
      },
    );
  }

  // =========================================================
  // MOVE ITEM DOWN
  // =========================================================

  Future<void> moveItemDown(
    int itemId,
  ) async {
    final db = await _database.database;

    final current = await getItem(itemId);

    if (current == null) {
      return;
    }

    final category = current['category']?.toString() ?? '';

    final currentOrder = current['item_order'] as int? ?? 0;

    final nextResult = await db.query(
      'pre_trade_items',
      where: '''
        category = ?
        AND item_order > ?
      ''',
      whereArgs: [
        category,
        currentOrder,
      ],
      orderBy: 'item_order ASC',
      limit: 1,
    );

    if (nextResult.isEmpty) {
      return;
    }

    final next = nextResult.first;

    final nextId = next['item_id'] as int;

    final nextOrder = next['item_order'] as int;

    await db.transaction(
      (transaction) async {
        await transaction.update(
          'pre_trade_items',
          {
            'item_order': nextOrder,
          },
          where: 'item_id = ?',
          whereArgs: [itemId],
        );

        await transaction.update(
          'pre_trade_items',
          {
            'item_order': currentOrder,
          },
          where: 'item_id = ?',
          whereArgs: [nextId],
        );
      },
    );
  }
}
