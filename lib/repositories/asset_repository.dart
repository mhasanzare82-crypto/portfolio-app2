import '../database/app_database.dart';
import '../models/asset.dart';

class AssetRepository {
  AssetRepository({
    AppDatabase? database,
  }) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<List<Asset>> getAllAssets({
    bool includeDisabled = true,
  }) async {
    final db = await _database.database;

    final rows = await db.query(
      'assets',
      where: includeDisabled ? null : 'asset_enabled = ?',
      whereArgs: includeDisabled ? null : [1],
      orderBy: 'asset_symbol ASC',
    );

    return rows
        .map(
          (row) => Asset.fromMap(row),
        )
        .toList();
  }

  Future<List<Asset>> getEnabledAssets() {
    return getAllAssets(
      includeDisabled: false,
    );
  }

  Future<Asset?> getAsset(
    String symbol,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'assets',
      where: 'asset_symbol = ?',
      whereArgs: [
        symbol.toUpperCase(),
      ],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Asset.fromMap(
      rows.first,
    );
  }

  Future<int> createAsset(
    Asset asset,
  ) async {
    final db = await _database.database;

    final symbol = asset.assetSymbol.trim().toUpperCase();

    if (symbol.isEmpty) {
      throw Exception(
        'Asset symbol cannot be empty.',
      );
    }

    final existing = await getAsset(symbol);

    if (existing != null) {
      throw Exception(
        'Asset already exists.',
      );
    }

    return db.insert(
      'assets',
      {
        'asset_symbol': symbol,
        'asset_name': asset.assetName.trim(),
        'asset_enabled': asset.assetEnabled ? 1 : 0,
        'created_at': asset.createdAt.toIso8601String(),
      },
    );
  }

  /// ذخیره نماد معامله در فهرست دارایی‌ها؛ نمادهای تکراری نادیده گرفته می‌شوند.
  Future<void> saveSymbolIfAbsent(String value) async {
    final symbol = value.trim().toUpperCase();
    if (symbol.isEmpty) return;

    final db = await _database.database;
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO assets (
        asset_symbol,
        asset_name,
        asset_enabled,
        created_at
      ) VALUES (?, ?, 1, ?)
      ''',
      [symbol, symbol, DateTime.now().toIso8601String()],
    );
  }

  Future<void> updateAsset(
    Asset asset,
  ) async {
    if (asset.assetId == null) {
      throw Exception(
        'Asset ID is required.',
      );
    }

    final db = await _database.database;

    final symbol = asset.assetSymbol.trim().toUpperCase();

    if (symbol.isEmpty) {
      throw Exception(
        'Asset symbol cannot be empty.',
      );
    }

    await db.update(
      'assets',
      {
        'asset_symbol': symbol,
        'asset_name': asset.assetName.trim(),
        'asset_enabled': asset.assetEnabled ? 1 : 0,
      },
      where: 'asset_id = ?',
      whereArgs: [
        asset.assetId,
      ],
    );
  }

  Future<void> setAssetEnabled({
    required int assetId,
    required bool enabled,
  }) async {
    final db = await _database.database;

    await db.update(
      'assets',
      {
        'asset_enabled': enabled ? 1 : 0,
      },
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
  }

  Future<void> deleteAsset(
    int assetId,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'assets',
      columns: ['asset_symbol'],
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return;
    }

    final symbol = rows.first['asset_symbol']?.toString();

    if (symbol == 'GOLDUSDT') {
      throw Exception(
        'GOLDUSDT cannot be deleted.',
      );
    }

    final tradeRows = await db.query(
      'trades',
      columns: ['trade_id'],
      where: 'asset_symbol = ?',
      whereArgs: [symbol],
      limit: 1,
    );

    if (tradeRows.isNotEmpty) {
      throw Exception(
        'This asset has trades and cannot be deleted. Disable it instead.',
      );
    }

    await db.delete(
      'assets',
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
  }
}
