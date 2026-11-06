import '../database/app_database.dart';

class AccountRepository {
  final AppDatabase _database = AppDatabase.instance;

  AccountRepository();

  // ============================================================
  // دریافت دیتابیس
  // ============================================================

  Future<dynamic> _getDb() async {
    return await _database.database;
  }

  // ============================================================
  // دریافت خلاصه حساب
  // ============================================================

  Future<Map<String, dynamic>> getAccountSummary() async {
    final db = await _getDb();

    try {
      final result = await db.query(
        'account_info',
        limit: 1,
      );

      if (result.isEmpty) {
        return {
          'initial_balance': 0.0,
          'daily_target_amount': 0.0,
          'weekly_target_amount': 0.0,
          'monthly_target_amount': 0.0,
        };
      }

      final row = result.first;

      return {
        'initial_balance': _toDouble(
          row['initial_balance'],
        ),
        'daily_target_amount': _toDouble(
          row['daily_target_amount'],
        ),
        'weekly_target_amount': _toDouble(
          row['weekly_target_amount'],
        ),
        'monthly_target_amount': _toDouble(
          row['monthly_target_amount'],
        ),
      };
    } catch (_) {
      return {
        'initial_balance': 0.0,
        'daily_target_amount': 0.0,
        'weekly_target_amount': 0.0,
        'monthly_target_amount': 0.0,
      };
    }
  }

  // ============================================================
  // ذخیره تنظیمات حساب
  // ============================================================

  Future<void> saveAccountSettings({
    required double initialBalance,
    required double dailyTargetAmount,
    required double weeklyTargetAmount,
    required double monthlyTargetAmount,
  }) async {
    final db = await _getDb();

    final existing = await db.query(
      'account_info',
      limit: 1,
    );

    final values = <String, dynamic>{
      'initial_balance': initialBalance,
      'daily_target_amount': dailyTargetAmount,
      'weekly_target_amount': weeklyTargetAmount,
      'monthly_target_amount': monthlyTargetAmount,
    };

    if (existing.isEmpty) {
      await db.insert(
        'account_info',
        values,
      );
    } else {
      await db.update(
        'account_info',
        values,
        where: 'id = ?',
        whereArgs: [
          existing.first['id'],
        ],
      );
    }
  }

  // ============================================================
  // سرمایه اولیه
  // ============================================================

  Future<double> getInitialCapital() async {
    final summary = await getAccountSummary();

    return _toDouble(
      summary['initial_balance'],
    );
  }

  // ============================================================
  // ذخیره سرمایه اولیه
  // ============================================================

  Future<void> saveInitialCapital(
    double value,
  ) async {
    final summary = await getAccountSummary();

    await saveAccountSettings(
      initialBalance: value,
      dailyTargetAmount: _toDouble(
        summary['daily_target_amount'],
      ),
      weeklyTargetAmount: _toDouble(
        summary['weekly_target_amount'],
      ),
      monthlyTargetAmount: _toDouble(
        summary['monthly_target_amount'],
      ),
    );
  }

  // ============================================================
  // اطلاعات کامل حساب
  // ============================================================

  Future<Map<String, dynamic>?> getAccountInfo() async {
    final db = await _getDb();

    try {
      final result = await db.query(
        'account_info',
        limit: 1,
      );

      if (result.isEmpty) {
        return null;
      }

      return Map<String, dynamic>.from(
        result.first,
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // تبدیل مقدار به double
  // ============================================================

  double _toDouble(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0.0;
  }
}
