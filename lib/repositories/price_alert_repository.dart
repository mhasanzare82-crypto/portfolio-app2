import '../database/app_database.dart';
import '../models/price_alert.dart';

class PriceAlertRepository {
  PriceAlertRepository._internal();

  static final PriceAlertRepository instance = PriceAlertRepository._internal();

  final AppDatabase _database = AppDatabase.instance;

  // =========================================================
  // INSERT
  // =========================================================

  Future<void> insertAlert(
    PriceAlert alert,
  ) async {
    final db = await _database.database;

    await db.insert(
      'price_alerts',
      _toMap(alert),
    );
  }

  // =========================================================
  // GET ALL
  // =========================================================

  Future<List<PriceAlert>> getAllAlerts() async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      orderBy: 'created_at DESC',
    );

    return rows.map(_fromMap).toList();
  }

  // =========================================================
  // GET ACTIVE
  // =========================================================

  Future<List<PriceAlert>> getActiveAlerts() async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );

    return rows.map(_fromMap).toList();
  }

  // =========================================================
  // GET ACTIVE UNTRIGGERED
  // =========================================================

  Future<List<PriceAlert>> getActiveUntriggeredAlerts(
    String symbol,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      where: '''
        symbol = ?
        AND is_active = ?
        AND is_triggered = ?
      ''',
      whereArgs: [
        symbol.trim().toUpperCase(),
        1,
        0,
      ],
      orderBy: 'created_at ASC',
    );

    return rows.map(_fromMap).toList();
  }

  // =========================================================
  // GET BY SYMBOL
  // =========================================================

  Future<List<PriceAlert>> getAlertsBySymbol(
    String symbol,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      where: 'symbol = ?',
      whereArgs: [
        symbol.trim().toUpperCase(),
      ],
      orderBy: 'created_at DESC',
    );

    return rows.map(_fromMap).toList();
  }

  // =========================================================
  // GET BY TRADE
  // =========================================================

  Future<List<PriceAlert>> getAlertsByTradeId(
    String tradeId,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
      orderBy: 'created_at ASC',
    );

    return rows.map(_fromMap).toList();
  }

  // =========================================================
  // GET BY MULTI STAGE GROUP
  // =========================================================

  Future<List<PriceAlert>> getAlertsByGroupId(
    String groupId,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      where: 'multi_stage_group_id = ?',
      whereArgs: [groupId],
      orderBy: 'stage_index ASC',
    );

    return rows.map(_fromMap).toList();
  }

  // =========================================================
  // GET BY ID
  // =========================================================

  Future<PriceAlert?> getAlertById(
    String id,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'price_alerts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _fromMap(rows.first);
  }

  // =========================================================
  // UPDATE
  // =========================================================

  Future<void> updateAlert(
    PriceAlert alert,
  ) async {
    final db = await _database.database;

    await db.update(
      'price_alerts',
      _toMap(alert),
      where: 'id = ?',
      whereArgs: [alert.id],
    );
  }

  // =========================================================
  // ENABLE / DISABLE
  // =========================================================

  Future<void> setActive(
    String id,
    bool isActive,
  ) async {
    final db = await _database.database;

    await db.update(
      'price_alerts',
      {
        'is_active': isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =========================================================
  // MARK AS TRIGGERED
  // =========================================================

  Future<void> markAsTriggered(
    String id,
  ) async {
    final db = await _database.database;

    final now = DateTime.now().toIso8601String();

    await db.update(
      'price_alerts',
      {
        'is_triggered': 1,
        'is_active': 0,
        'last_triggered_at': now,
        'triggered_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =========================================================
  // MARK AS REPEATED
  // =========================================================

  Future<void> markAsRepeated(
    String id,
  ) async {
    final db = await _database.database;

    final now = DateTime.now().toIso8601String();

    await db.update(
      'price_alerts',
      {
        'last_triggered_at': now,
        'triggered_at': now,
        'is_triggered': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =========================================================
  // RESET
  // =========================================================

  Future<void> resetAlert(
    String id,
  ) async {
    final db = await _database.database;

    await db.update(
      'price_alerts',
      {
        'is_triggered': 0,
        'is_active': 1,
        'triggered_at': null,
        'last_triggered_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =========================================================
  // RESET GROUP
  // =========================================================

  Future<void> resetGroup(
    String groupId,
  ) async {
    final db = await _database.database;

    await db.update(
      'price_alerts',
      {
        'is_triggered': 0,
        'is_active': 1,
        'triggered_at': null,
        'last_triggered_at': null,
      },
      where: 'multi_stage_group_id = ?',
      whereArgs: [groupId],
    );
  }

  // =========================================================
  // DELETE
  // =========================================================

  Future<void> deleteAlert(
    String id,
  ) async {
    final db = await _database.database;

    await db.delete(
      'price_alerts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =========================================================
  // DELETE GROUP
  // =========================================================

  Future<void> deleteGroup(
    String groupId,
  ) async {
    final db = await _database.database;

    await db.delete(
      'price_alerts',
      where: 'multi_stage_group_id = ?',
      whereArgs: [groupId],
    );
  }

  // =========================================================
  // DELETE ALL
  // =========================================================

  Future<void> deleteAllAlerts() async {
    final db = await _database.database;

    await db.delete(
      'price_alerts',
    );
  }

  // =========================================================
  // MAP -> DATABASE
  // =========================================================

  Map<String, dynamic> _toMap(
    PriceAlert alert,
  ) {
    return {
      'id': alert.id,
      'symbol': alert.symbol.trim().toUpperCase(),
      'title': alert.title,
      'note': alert.note,
      'type': alert.typeKey,
      'target_price': alert.targetPrice,
      'lower_price': alert.lowerPrice,
      'upper_price': alert.upperPrice,
      'trigger_on_rise': alert.triggerOnRise ? 1 : 0,
      'repeat_mode': alert.repeatModeKey,
      'repeat_interval_minutes': alert.repeatIntervalMinutes,
      'is_active': alert.isActive ? 1 : 0,
      'is_triggered': alert.isTriggered ? 1 : 0,
      'sound_path': alert.soundPath,
      'trade_id': alert.tradeId,
      'trade_price_type': alert.tradePriceType,
      'multi_stage_group_id': alert.multiStageGroupId,
      'stage_index': alert.stageIndex,
      'created_at': alert.createdAt.toIso8601String(),
      'last_triggered_at': alert.lastTriggeredAt?.toIso8601String(),
      'triggered_at': alert.triggeredAt?.toIso8601String(),
    };
  }

  // =========================================================
  // DATABASE -> MODEL
  // =========================================================

  PriceAlert _fromMap(
    Map<String, dynamic> map,
  ) {
    return PriceAlert(
      id: map['id'].toString(),
      symbol: map['symbol'].toString(),
      title: map['title']?.toString() ?? '',
      note: map['note']?.toString() ?? '',
      type: PriceAlert.typeFromKey(
        map['type']?.toString(),
      ),
      targetPrice: _toDouble(
        map['target_price'],
      ),
      lowerPrice: _toDouble(
        map['lower_price'],
      ),
      upperPrice: _toDouble(
        map['upper_price'],
      ),
      triggerOnRise: map['trigger_on_rise'] == 1,
      repeatMode: PriceAlert.repeatModeFromKey(
        map['repeat_mode']?.toString(),
      ),
      repeatIntervalMinutes: _toInt(
        map['repeat_interval_minutes'],
      ),
      isActive: map['is_active'] == 1,
      isTriggered: map['is_triggered'] == 1,
      soundPath: map['sound_path']?.toString(),
      tradeId: map['trade_id']?.toString(),
      tradePriceType: map['trade_price_type']?.toString(),
      multiStageGroupId: map['multi_stage_group_id']?.toString(),
      stageIndex: _toInt(
        map['stage_index'],
      ),
      createdAt: _toDateTime(
            map['created_at'],
          ) ??
          DateTime.now(),
      lastTriggeredAt: _toDateTime(
        map['last_triggered_at'],
      ),
      triggeredAt: _toDateTime(
        map['triggered_at'],
      ),
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================

  double? _toDouble(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }

  int? _toInt(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    );
  }

  DateTime? _toDateTime(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }
}
