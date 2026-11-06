import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/trade.dart';

class TradeRepository {
  TradeRepository({
    AppDatabase? database,
  }) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> createTrade(Trade trade) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.insert(
          'trades',
          trade.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await _saveTradeImages(
          transaction,
          trade,
        );
      },
    );
  }

  Future<void> updateTrade(Trade trade) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.update(
          'trades',
          trade.toMap(),
          where: 'trade_id = ?',
          whereArgs: [trade.tradeId],
        );

        await transaction.delete(
          'trade_images',
          where: 'trade_id = ?',
          whereArgs: [trade.tradeId],
        );

        await _saveTradeImages(
          transaction,
          trade,
        );
      },
    );
  }

  // ============================================================
  // CLOSE TRADE + SAVE FINAL METRICS
  // ============================================================

  Future<void> closeTrade({
    required String tradeId,
    required double exitPrice,
    required DateTime exitTime,
    required double finalPnl,
    required double finalRoiPercent,
    required double finalRoiDollar,
    required double finalRiskReward,
    required double maxDrawdownPricePercent,
    required double maxDrawdownDollar,
    required double maxDrawdownMarginPercent,
    required int durationSeconds,
  }) async {
    final db = await _database.database;

    final affectedRows = await db.update(
      'trades',
      {
        'trade_status': TradeStatus.closed.name,
        'exit_price': exitPrice,
        'exit_time': exitTime.toIso8601String(),

        // Final metrics
        'final_pnl': finalPnl,
        'final_roi_percent': finalRoiPercent,
        'final_roi_dollar': finalRoiDollar,
        'final_risk_reward': finalRiskReward,

        // Maximum drawdown
        'max_drawdown_price_percent': maxDrawdownPricePercent,
        'max_drawdown_dollar': maxDrawdownDollar,
        'max_drawdown_margin_percent': maxDrawdownMarginPercent,

        // Duration
        'duration_seconds': durationSeconds,
      },
      where: 'trade_id = ?',
      whereArgs: [tradeId],
    );

    if (affectedRows == 0) {
      throw Exception(
        'Trade not found: $tradeId',
      );
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> deleteTrade(String tradeId) async {
    final db = await _database.database;

    await db.delete(
      'trades',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
    );
  }

  // ============================================================
  // GET ONE
  // ============================================================

  Future<Trade?> getTrade(String tradeId) async {
    final db = await _database.database;

    final result = await db.query(
      'trades',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    final imagePaths = await _getTradeImages(
      tradeId,
    );

    return Trade.fromMap(
      result.first,
      imagePaths: imagePaths,
    );
  }

  // ============================================================
  // GET ALL
  // ============================================================

  Future<List<Trade>> getAllTrades() async {
    final db = await _database.database;

    final result = await db.query(
      'trades',
      orderBy: 'entry_time DESC',
    );

    return _rowsToTrades(
      result,
    );
  }

  // ============================================================
  // OPEN TRADES
  // ============================================================

  Future<List<Trade>> getOpenTrades() async {
    final db = await _database.database;

    final result = await db.query(
      'trades',
      where: 'trade_status = ?',
      whereArgs: [
        TradeStatus.open.name,
      ],
      orderBy: 'entry_time DESC',
    );

    return _rowsToTrades(
      result,
    );
  }

  // ============================================================
  // CLOSED TRADES
  // ============================================================

  Future<List<Trade>> getClosedTrades() async {
    final db = await _database.database;

    final result = await db.query(
      'trades',
      where: 'trade_status = ?',
      whereArgs: [
        TradeStatus.closed.name,
      ],
      orderBy: 'exit_time DESC',
    );

    return _rowsToTrades(
      result,
    );
  }

  // ============================================================
  // TRADES IN DATE RANGE
  // ============================================================

  Future<List<Trade>> getOpenTradesInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _database.database;
    final startIso =
        DateTime(start.year, start.month, start.day).toIso8601String();
    final endExclusive =
        DateTime(end.year, end.month, end.day + 1).toIso8601String();
    final rows = await db.query(
      'trades',
      where: 'trade_status = ? AND entry_time >= ? AND entry_time < ?',
      whereArgs: [TradeStatus.open.name, startIso, endExclusive],
      orderBy: 'entry_time DESC',
    );
    return _rowsToTrades(rows);
  }

  Future<List<Trade>> getClosedTradesInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _database.database;
    final startIso =
        DateTime(start.year, start.month, start.day).toIso8601String();
    final endExclusive =
        DateTime(end.year, end.month, end.day + 1).toIso8601String();
    final rows = await db.query(
      'trades',
      where:
          'trade_status = ? AND exit_time IS NOT NULL AND exit_time >= ? AND exit_time < ?',
      whereArgs: [TradeStatus.closed.name, startIso, endExclusive],
      orderBy: 'exit_time DESC',
    );
    return _rowsToTrades(rows);
  }

  // ============================================================
  // BY ASSET
  // ============================================================

  Future<List<Trade>> getTradesByAsset(
    String assetSymbol,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'trades',
      where: 'asset_symbol = ?',
      whereArgs: [assetSymbol],
      orderBy: 'entry_time DESC',
    );

    return _rowsToTrades(
      result,
    );
  }

  // ============================================================
  // IMAGES
  // ============================================================

  Future<void> addTradeImage({
    required String tradeId,
    required String imagePath,
    String imageType = 'entry',
  }) async {
    final db = await _database.database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS image_count
      FROM trade_images
      WHERE trade_id = ?
      ''',
      [tradeId],
    );

    final imageCount = (result.first['image_count'] as int?) ?? 0;

    await db.insert(
      'trade_images',
      {
        'trade_id': tradeId,
        'image_path': imagePath,
        'image_type': imageType,
        'image_order': imageCount,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> removeTradeImage(
    int tradeImageId,
  ) async {
    final db = await _database.database;

    await db.delete(
      'trade_images',
      where: 'trade_image_id = ?',
      whereArgs: [tradeImageId],
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Future<List<Trade>> _rowsToTrades(
    List<Map<String, dynamic>> rows,
  ) async {
    final trades = <Trade>[];

    for (final row in rows) {
      final tradeId = row['trade_id']?.toString() ?? '';

      final imagePaths = await _getTradeImages(
        tradeId,
      );

      trades.add(
        Trade.fromMap(
          row,
          imagePaths: imagePaths,
        ),
      );
    }

    return trades;
  }

  Future<List<String>> _getTradeImages(
    String tradeId,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'trade_images',
      columns: ['image_path'],
      where: 'trade_id = ?',
      whereArgs: [tradeId],
      orderBy: 'image_order ASC',
    );

    return result
        .map(
          (row) => row['image_path']?.toString() ?? '',
        )
        .where(
          (path) => path.isNotEmpty,
        )
        .toList();
  }

  Future<void> _saveTradeImages(
    Transaction transaction,
    Trade trade,
  ) async {
    for (var index = 0; index < trade.imagePaths.length; index++) {
      await transaction.insert(
        'trade_images',
        {
          'trade_id': trade.tradeId,
          'image_path': trade.imagePaths[index],
          'image_type': 'entry',
          'image_order': index,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
    }
  }
}
