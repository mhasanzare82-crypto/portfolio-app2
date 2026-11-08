import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  Database? _database;

  // ============================================================
  // DATABASE
  // ============================================================

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();

    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();

    final path = p.join(
      databasesPath,
      'trading_journal.db',
    );

    return openDatabase(
      path,
      version: 18,
      onConfigure: (db) async {
        await db.execute(
          'PRAGMA foreign_keys = ON',
        );
      },
      onCreate: (db, version) async {
        await _createDatabase(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _upgradeDatabase(
          db,
          oldVersion,
          newVersion,
        );
      },
    );
  }

  // ============================================================
  // CREATE DATABASE
  // ============================================================

  Future<void> _createDatabase(Database db) async {
    // ==========================================================
    // SETTINGS
    // ==========================================================

    await db.execute('''
      CREATE TABLE settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT
      )
    ''');

    await db.insert(
      'settings',
      {
        'setting_key': 'initial_balance',
        'setting_value': '0',
      },
    );

    // ==========================================================
    // ASSETS
    // ==========================================================

    await db.execute('''
      CREATE TABLE assets (
        asset_id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_symbol TEXT NOT NULL UNIQUE,
        asset_name TEXT,
        asset_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.insert(
      'assets',
      {
        'asset_symbol': 'GOLDUSDT',
        'asset_name': 'Gold USDT',
        'asset_enabled': 1,
        'created_at': DateTime.now().toIso8601String(),
      },
    );

    // ==========================================================
    // TRADES
    // ==========================================================

    await db.execute('''
      CREATE TABLE trades (
        trade_id TEXT PRIMARY KEY,

        asset_symbol TEXT NOT NULL,

        trade_direction TEXT NOT NULL,
        trade_type TEXT NOT NULL,
        trade_status TEXT NOT NULL,
        trade_timeframe TEXT,
        margin_mode TEXT NOT NULL DEFAULT 'isolated',

        dollar_rate REAL NOT NULL DEFAULT 0,

        margin_amount REAL NOT NULL DEFAULT 0,
        leverage_value REAL NOT NULL DEFAULT 0,
        volume_amount REAL NOT NULL DEFAULT 0,

        fee_per_hundred REAL NOT NULL DEFAULT 0,
        trade_fee REAL NOT NULL DEFAULT 0,

        entry_price REAL,
        exit_price REAL,
        stop_price REAL,
        target_price REAL,

        risk_distance REAL NOT NULL DEFAULT 0,
        reward_distance REAL NOT NULL DEFAULT 0,

        risk_value REAL NOT NULL DEFAULT 0,
        reward_value REAL NOT NULL DEFAULT 0,

        trade_risk_reward REAL NOT NULL DEFAULT 0,

        final_pnl REAL NOT NULL DEFAULT 0,
        final_roi_percent REAL NOT NULL DEFAULT 0,
        final_roi_dollar REAL NOT NULL DEFAULT 0,
        final_risk_reward REAL NOT NULL DEFAULT 0,

        max_drawdown_price_percent REAL NOT NULL DEFAULT 0,
        max_drawdown_dollar REAL NOT NULL DEFAULT 0,
        max_drawdown_margin_percent REAL NOT NULL DEFAULT 0,

        duration_seconds INTEGER NOT NULL DEFAULT 0,

        entry_setup TEXT,
        entry_reason TEXT,
        entry_motivation TEXT,
        expected_scenario TEXT,

        entry_time TEXT NOT NULL,
        exit_time TEXT
      )
    ''');

    // ==========================================================
    // TRADE IMAGES
    // ==========================================================

    await db.execute('''
      CREATE TABLE trade_images (
        trade_image_id INTEGER PRIMARY KEY AUTOINCREMENT,

        trade_id TEXT NOT NULL,

        image_path TEXT NOT NULL,

        image_type TEXT NOT NULL DEFAULT 'entry',

        image_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        FOREIGN KEY (trade_id)
          REFERENCES trades (trade_id)
          ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // TRADE EXPERIENCES
    // ==========================================================

    await db.execute('''
      CREATE TABLE trade_experiences (
        experience_id TEXT PRIMARY KEY,

        trade_id TEXT NOT NULL,

        experience_title TEXT,
        experience_description TEXT,
        audio_paths TEXT NOT NULL DEFAULT '[]',

        experience_created_at TEXT NOT NULL,

        FOREIGN KEY (trade_id)
          REFERENCES trades (trade_id)
          ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // EXPERIENCE IMAGES
    // ==========================================================

    await db.execute('''
      CREATE TABLE experience_images (
        experience_image_id INTEGER PRIMARY KEY AUTOINCREMENT,

        experience_id TEXT NOT NULL,

        image_path TEXT NOT NULL,

        image_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        FOREIGN KEY (experience_id)
          REFERENCES trade_experiences (experience_id)
          ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // CUSTOM FIELDS
    // ==========================================================

    await _createCustomFieldTables(db);

    // ==========================================================
    // PRE TRADE
    // ==========================================================

    await _createPreTradeTables(db);

    // ==========================================================
    // PRICE ALERTS
    // ==========================================================

    await _createPriceAlertTable(db);

    // ==========================================================
    // NOTES
    // ==========================================================

    await _createTradeNotesIfNeeded(db);

    await _createAdvancedNoteTablesIfNeeded(db);

    // ==========================================================
    // ANALYSES
    // ==========================================================

    await _createAnalysisTable(db);

    // ==========================================================
    // INDEXES
    // ==========================================================

    await _createIndexes(db);

    // Ensure gallery tables exist on fresh installs.
    await _createCustomGalleryTables(db);
  }

  // ============================================================
  // CUSTOM FIELD TABLES
  // ============================================================

  Future<void> _createCustomFieldTables(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE custom_fields (
        field_id INTEGER PRIMARY KEY AUTOINCREMENT,

        field_name TEXT NOT NULL,

        field_type TEXT NOT NULL,

        category TEXT NOT NULL DEFAULT 'عمومی',

        is_required INTEGER NOT NULL DEFAULT 0,

        is_enabled INTEGER NOT NULL DEFAULT 1,

        field_order INTEGER NOT NULL DEFAULT 0,

        options_text TEXT,

        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE trade_custom_values (
        value_id INTEGER PRIMARY KEY AUTOINCREMENT,

        trade_id TEXT NOT NULL,

        field_id INTEGER NOT NULL,

        value_text TEXT,

        created_at TEXT NOT NULL,

        UNIQUE (
          trade_id,
          field_id
        ),

        FOREIGN KEY (trade_id)
          REFERENCES trades (trade_id)
          ON DELETE CASCADE,

        FOREIGN KEY (field_id)
          REFERENCES custom_fields (field_id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_custom_values_trade
      ON trade_custom_values (trade_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_custom_values_field
      ON trade_custom_values (field_id)
    ''');
  }

  // ============================================================
  // PRE TRADE TABLES
  // ============================================================

  Future<void> _createPreTradeTables(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE pre_trade_items (
        item_id INTEGER PRIMARY KEY AUTOINCREMENT,

        item_title TEXT NOT NULL,

        category TEXT NOT NULL,

        folder_name TEXT NOT NULL DEFAULT '',

        item_type TEXT NOT NULL,

        is_required INTEGER NOT NULL DEFAULT 0,

        is_enabled INTEGER NOT NULL DEFAULT 1,

        item_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE trade_pre_trade_values (
        value_id INTEGER PRIMARY KEY AUTOINCREMENT,

        trade_id TEXT NOT NULL,

        item_id INTEGER NOT NULL,

        value_text TEXT,

        created_at TEXT NOT NULL,

        UNIQUE (
          trade_id,
          item_id
        ),

        FOREIGN KEY (trade_id)
          REFERENCES trades (trade_id)
          ON DELETE CASCADE,

        FOREIGN KEY (item_id)
          REFERENCES pre_trade_items (item_id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_pre_trade_items_category
      ON pre_trade_items (category)
    ''');

    await db.execute('''
      CREATE INDEX idx_pre_trade_items_enabled
      ON pre_trade_items (is_enabled)
    ''');

    await db.execute('''
      CREATE INDEX idx_pre_trade_values_trade
      ON trade_pre_trade_values (trade_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_pre_trade_values_item
      ON trade_pre_trade_values (item_id)
    ''');
  }

  // ============================================================
  // PRICE ALERTS
  // ============================================================

  Future<void> _createPriceAlertTable(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE price_alerts (
        id TEXT PRIMARY KEY,

        symbol TEXT NOT NULL,

        title TEXT NOT NULL DEFAULT '',

        note TEXT NOT NULL DEFAULT '',

        type TEXT NOT NULL DEFAULT 'target',

        target_price REAL,

        lower_price REAL,

        upper_price REAL,

        trigger_on_rise INTEGER NOT NULL DEFAULT 1,

        repeat_mode TEXT NOT NULL DEFAULT 'once',

        repeat_interval_minutes INTEGER,

        is_active INTEGER NOT NULL DEFAULT 1,

        is_triggered INTEGER NOT NULL DEFAULT 0,

        sound_path TEXT,

        trade_id TEXT,

        trade_price_type TEXT,

        multi_stage_group_id TEXT,

        stage_index INTEGER,

        created_at TEXT NOT NULL,

        last_triggered_at TEXT,

        triggered_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_price_alerts_symbol
      ON price_alerts (symbol)
    ''');

    await db.execute('''
      CREATE INDEX idx_price_alerts_active
      ON price_alerts (is_active)
    ''');

    await db.execute('''
      CREATE INDEX idx_price_alerts_trade
      ON price_alerts (trade_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_price_alerts_group
      ON price_alerts (multi_stage_group_id)
    ''');
  }

  // ============================================================
  // TRADE NOTES
  // ============================================================

  Future<void> _createTradeNotesIfNeeded(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_notes'
    ''');

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE trade_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,

          title TEXT NOT NULL,

          content TEXT NOT NULL,

          subject TEXT,

          note_type TEXT NOT NULL DEFAULT 'عمومی',

          asset_symbol TEXT,

          trade_id TEXT,

          source TEXT,

          source_file_name TEXT,

          created_at TEXT NOT NULL,

          updated_at TEXT NOT NULL,

          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE SET NULL
        )
      ''');
    }

    final tagTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='note_tags'
    ''');

    if (tagTables.isEmpty) {
      await db.execute('''
        CREATE TABLE note_tags (
          tag_id INTEGER PRIMARY KEY AUTOINCREMENT,

          tag_name TEXT NOT NULL UNIQUE,

          created_at TEXT NOT NULL
        )
      ''');
    }

    final relationTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_note_tags'
    ''');

    if (relationTables.isEmpty) {
      await db.execute('''
        CREATE TABLE trade_note_tags (
          note_id INTEGER NOT NULL,

          tag_id INTEGER NOT NULL,

          PRIMARY KEY (note_id, tag_id),

          FOREIGN KEY (note_id)
            REFERENCES trade_notes(id)
            ON DELETE CASCADE,

          FOREIGN KEY (tag_id)
            REFERENCES note_tags(tag_id)
            ON DELETE CASCADE
        )
      ''');
    }
  }

  // ============================================================
  // ADVANCED NOTE TABLES
  // ============================================================

  Future<void> _createAdvancedNoteTablesIfNeeded(
    Database db,
  ) async {
    final subjectTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='note_subjects'
    ''');

    if (subjectTables.isEmpty) {
      await db.execute('''
        CREATE TABLE note_subjects (
          subject_id INTEGER PRIMARY KEY AUTOINCREMENT,

          subject_name TEXT NOT NULL,

          parent_id INTEGER,

          created_at TEXT NOT NULL,

          updated_at TEXT NOT NULL,

          FOREIGN KEY (parent_id)
            REFERENCES note_subjects(subject_id)
            ON DELETE SET NULL
        )
      ''');
    }

    final relationTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_note_subjects'
    ''');

    if (relationTables.isEmpty) {
      await db.execute('''
        CREATE TABLE trade_note_subjects (
          note_id INTEGER NOT NULL,

          subject_id INTEGER NOT NULL,

          PRIMARY KEY (note_id, subject_id),

          FOREIGN KEY (note_id)
            REFERENCES trade_notes(id)
            ON DELETE CASCADE,

          FOREIGN KEY (subject_id)
            REFERENCES note_subjects(subject_id)
            ON DELETE CASCADE
        )
      ''');
    }

    final mediaTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_note_media'
    ''');

    if (mediaTables.isEmpty) {
      await db.execute('''
        CREATE TABLE trade_note_media (
          media_id INTEGER PRIMARY KEY AUTOINCREMENT,

          note_id INTEGER NOT NULL,

          media_type TEXT NOT NULL,

          file_path TEXT NOT NULL,

          file_name TEXT,

          media_order INTEGER NOT NULL DEFAULT 0,

          created_at TEXT NOT NULL,

          FOREIGN KEY (note_id)
            REFERENCES trade_notes(id)
            ON DELETE CASCADE
        )
      ''');
    }
  }

  Future<void> _createAnalysisTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS analyses (
        analysis_id TEXT PRIMARY KEY,
        asset_symbol TEXT NOT NULL DEFAULT 'GOLDUSDT',
        timeframe TEXT NOT NULL DEFAULT '15m',
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        target_price REAL,
        target_title TEXT NOT NULL DEFAULT '',
        website_url TEXT NOT NULL DEFAULT 'https://www.tradingview.com/chart/',
        image_paths TEXT NOT NULL DEFAULT '[]',
        audio_paths TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'valid',
        created_at TEXT NOT NULL,
        triggered_at TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_analyses_status_symbol
      ON analyses(status, asset_symbol)
    ''');
  }

  // ============================================================
  // INDEXES
  // ============================================================

  Future<void> _createIndexes(
    Database db,
  ) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trades_asset
      ON trades (asset_symbol)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trades_status
      ON trades (trade_status)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trades_entry_time
      ON trades (entry_time)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_images_trade
      ON trade_images (trade_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_experiences_trade
      ON trade_experiences (trade_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_experience_images
      ON experience_images (experience_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_notes_title
      ON trade_notes(title COLLATE NOCASE)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_notes_created
      ON trade_notes(created_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_notes_asset
      ON trade_notes(asset_symbol)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_note_tags_note
      ON trade_note_tags(note_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_note_tags_tag
      ON trade_note_tags(tag_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_note_subjects_name
      ON note_subjects(subject_name COLLATE NOCASE)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_note_subjects_parent
      ON note_subjects(parent_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_note_subjects_note
      ON trade_note_subjects(note_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_note_subjects_subject
      ON trade_note_subjects(subject_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_note_media_note
      ON trade_note_media(note_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_trade_note_media_type
      ON trade_note_media(media_type)
    ''');
  }

  // ============================================================
  // DATABASE UPGRADE
  // ============================================================

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // ==========================================================
    // VERSION 2
    // ==========================================================

    if (oldVersion < 2) {
      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type='table'
        AND name='custom_fields'
      ''');

      if (tables.isEmpty) {
        await _createCustomFieldTables(db);
      }
    }

    // ==========================================================
    // VERSION 3
    // ==========================================================

    if (oldVersion < 3) {
      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type='table'
        AND name='pre_trade_items'
      ''');

      if (tables.isEmpty) {
        await _createPreTradeTables(db);
      }
    }

    // ==========================================================
    // VERSION 4
    // ==========================================================

    if (oldVersion < 4) {
      await _upgradeToVersion4(db);
    }

    // ==========================================================
    // VERSION 5
    // ==========================================================

    if (oldVersion < 5) {
      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type='table'
        AND name='price_alerts'
      ''');

      if (tables.isEmpty) {
        await _createPriceAlertTable(db);
      }
    }

    // ==========================================================
    // VERSION 6
    // ==========================================================

    if (oldVersion < 6) {
      await _upgradeToVersion6(db);
    }

    // ==========================================================
    // VERSION 7
    // ==========================================================

    if (oldVersion < 7) {
      await _upgradeToVersion7(db);
    }

    // ==========================================================
    // VERSION 8
    // NOTES
    // ==========================================================

    if (oldVersion < 8) {
      await _createTradeNotesIfNeeded(db);
    }

    // ==========================================================
    // VERSION 9
    // ==========================================================

    if (oldVersion < 9) {
      await _createAdvancedNoteTablesIfNeeded(db);
      await _migrateOldNoteSubjects(db);
    }

    // ==========================================================
    // VERSION 10
    // ==========================================================

    if (oldVersion < 10) {
      await _createAdvancedNoteTablesIfNeeded(db);
      await _migrateOldNoteSubjects(db);
    }

    // ==========================================================
    // VERSION 11
    // CUSTOM FIELDS
    // ==========================================================

    if (oldVersion < 11) {
      await _repairCustomFields(db);
    }

    // ==========================================================
    // VERSION 12
    // COMPLETE DATABASE REPAIR
    // ==========================================================

    if (oldVersion < 12) {
      await _repairDatabaseToVersion12(db);
    }

    if (oldVersion < 13) {
      final tradeColumns = await db.rawQuery('PRAGMA table_info(trades)');
      final tradeNames = tradeColumns
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();
      if (!tradeNames.contains('margin_mode')) {
        await db.execute(
          "ALTER TABLE trades ADD COLUMN margin_mode TEXT NOT NULL DEFAULT 'isolated'",
        );
      }
      await _createAnalysisTable(db);
    }

    if (oldVersion < 14) {
      final preTradeTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='pre_trade_items'");
      if (preTradeTables.isNotEmpty) {
        final info = await db.rawQuery('PRAGMA table_info(pre_trade_items)');
        final names = info
            .map((row) => row['name']?.toString())
            .whereType<String>()
            .toSet();
        if (!names.contains('folder_name')) {
          await db.execute(
              "ALTER TABLE pre_trade_items ADD COLUMN folder_name TEXT NOT NULL DEFAULT ''");
        }
      }
    }

    if (oldVersion < 16) {
      await _createCustomGalleryTables(db);
    }

    // Repair databases already marked as version 16.
    if (oldVersion < 17) {
      await _createCustomGalleryTables(db);
    }

    // ==========================================================
    // VERSION 18
    // DOLLAR RATE
    // ==========================================================

    if (oldVersion < 18) {
      final columns = await db.rawQuery('PRAGMA table_info(trades)');
      if (!columns.any((column) => column['name'] == 'dollar_rate')) {
        await db.execute(
          'ALTER TABLE trades ADD COLUMN dollar_rate REAL NOT NULL DEFAULT 0',
        );
      }
    }

    if (oldVersion < 15) {
      final experienceTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='trade_experiences'");
      if (experienceTables.isNotEmpty) {
        final info = await db.rawQuery('PRAGMA table_info(trade_experiences)');
        final names = info
            .map((row) => row['name']?.toString())
            .whereType<String>()
            .toSet();
        if (!names.contains('audio_paths')) {
          await db.execute(
              "ALTER TABLE trade_experiences ADD COLUMN audio_paths TEXT NOT NULL DEFAULT '[]'");
        }
      }
    }
  }

  // ============================================================
  // VERSION 4
  // ============================================================

  Future<void> _upgradeToVersion4(
    Database db,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(trades)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    final additions = <String, String>{
      'final_pnl':
          'ALTER TABLE trades ADD COLUMN final_pnl REAL NOT NULL DEFAULT 0',
      'final_roi_percent':
          'ALTER TABLE trades ADD COLUMN final_roi_percent REAL NOT NULL DEFAULT 0',
      'final_roi_dollar':
          'ALTER TABLE trades ADD COLUMN final_roi_dollar REAL NOT NULL DEFAULT 0',
      'final_risk_reward':
          'ALTER TABLE trades ADD COLUMN final_risk_reward REAL NOT NULL DEFAULT 0',
      'max_drawdown_price_percent':
          'ALTER TABLE trades ADD COLUMN max_drawdown_price_percent REAL NOT NULL DEFAULT 0',
      'max_drawdown_dollar':
          'ALTER TABLE trades ADD COLUMN max_drawdown_dollar REAL NOT NULL DEFAULT 0',
      'max_drawdown_margin_percent':
          'ALTER TABLE trades ADD COLUMN max_drawdown_margin_percent REAL NOT NULL DEFAULT 0',
      'duration_seconds':
          'ALTER TABLE trades ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0',
    };

    for (final entry in additions.entries) {
      if (!names.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  // ============================================================
  // VERSION 6
  // ============================================================

  Future<void> _upgradeToVersion6(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='price_alerts'
    ''');

    if (tables.isEmpty) {
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(price_alerts)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    final additions = <String, String>{
      'title':
          "ALTER TABLE price_alerts ADD COLUMN title TEXT NOT NULL DEFAULT ''",
      'note':
          "ALTER TABLE price_alerts ADD COLUMN note TEXT NOT NULL DEFAULT ''",
      'type':
          "ALTER TABLE price_alerts ADD COLUMN type TEXT NOT NULL DEFAULT 'target'",
      'lower_price': 'ALTER TABLE price_alerts ADD COLUMN lower_price REAL',
      'upper_price': 'ALTER TABLE price_alerts ADD COLUMN upper_price REAL',
      'repeat_mode':
          "ALTER TABLE price_alerts ADD COLUMN repeat_mode TEXT NOT NULL DEFAULT 'once'",
      'repeat_interval_minutes':
          'ALTER TABLE price_alerts ADD COLUMN repeat_interval_minutes INTEGER',
      'sound_path': 'ALTER TABLE price_alerts ADD COLUMN sound_path TEXT',
      'trade_id': 'ALTER TABLE price_alerts ADD COLUMN trade_id TEXT',
      'trade_price_type':
          'ALTER TABLE price_alerts ADD COLUMN trade_price_type TEXT',
      'multi_stage_group_id':
          'ALTER TABLE price_alerts ADD COLUMN multi_stage_group_id TEXT',
      'stage_index': 'ALTER TABLE price_alerts ADD COLUMN stage_index INTEGER',
      'last_triggered_at':
          'ALTER TABLE price_alerts ADD COLUMN last_triggered_at TEXT',
    };

    for (final entry in additions.entries) {
      if (!names.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_price_alerts_trade
      ON price_alerts (trade_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_price_alerts_group
      ON price_alerts (multi_stage_group_id)
    ''');
  }

  // ============================================================
  // VERSION 7
  // ============================================================

  Future<void> _upgradeToVersion7(
    Database db,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(custom_fields)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (!names.contains('category')) {
      await db.execute('''
        ALTER TABLE custom_fields
        ADD COLUMN category TEXT NOT NULL DEFAULT 'عمومی'
      ''');
    }
  }

  // ============================================================
  // VERSION 11
  // CUSTOM FIELD REPAIR
  // ============================================================

  Future<void> _repairCustomFields(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='custom_fields'
    ''');

    if (tables.isEmpty) {
      await _createCustomFieldTables(db);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(custom_fields)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('field_id') &&
        names.contains('field_name') &&
        names.contains('field_type') &&
        names.contains('is_enabled') &&
        names.contains('field_order') &&
        names.contains('options_text')) {
      return;
    }

    await db.execute('''
      CREATE TABLE custom_fields_v11 (
        field_id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_name TEXT NOT NULL,
        field_type TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'عمومی',
        is_required INTEGER NOT NULL DEFAULT 0,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        field_order INTEGER NOT NULL DEFAULT 0,
        options_text TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    final oldRows = await db.query(
      'custom_fields',
    );

    for (var i = 0; i < oldRows.length; i++) {
      final row = oldRows[i];

      await db.insert(
        'custom_fields_v11',
        {
          'field_id': row['field_id'] ?? row['id'],
          'field_name':
              row['field_name']?.toString() ?? row['name']?.toString() ?? '',
          'field_type': row['field_type']?.toString() ??
              row['type']?.toString() ??
              'text',
          'category': row['category']?.toString().trim().isNotEmpty == true
              ? row['category'].toString()
              : 'عمومی',
          'is_required': row['is_required'] ?? 0,
          'is_enabled': row['is_enabled'] ?? 1,
          'field_order': row['field_order'] ?? i,
          'options_text': row['options_text']?.toString() ??
              row['options']?.toString() ??
              '',
          'created_at':
              row['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        },
      );
    }

    await db.execute(
      'DROP TABLE custom_fields',
    );

    await db.execute(
      'ALTER TABLE custom_fields_v11 RENAME TO custom_fields',
    );
  }

  // ============================================================
  // VERSION 12
  // COMPLETE DATABASE REPAIR
  // ============================================================

  Future<void> _repairDatabaseToVersion12(
    Database db,
  ) async {
    // ----------------------------------------------------------
    // 1. Ensure basic tables exist
    // ----------------------------------------------------------

    await _ensureSettingsTable(db);

    await _ensureAssetsTable(db);

    // ----------------------------------------------------------
    // 2. Repair TRADES
    // ----------------------------------------------------------

    await _repairTradesTable(db);

    // ----------------------------------------------------------
    // 3. Repair trade-dependent tables
    // ----------------------------------------------------------

    await _repairTradeImagesTable(db);

    await _repairTradeExperiencesTable(db);

    await _repairExperienceImagesTable(db);

    // ----------------------------------------------------------
    // 4. Repair custom fields
    // ----------------------------------------------------------

    await _repairCustomFields(db);

    await _repairTradeCustomValues(db);

    // ----------------------------------------------------------
    // 5. Repair pre-trade
    // ----------------------------------------------------------

    await _repairPreTradeItems(db);

    await _repairTradePreTradeValues(db);

    // ----------------------------------------------------------
    // 6. Repair price alerts
    // ----------------------------------------------------------

    await _repairPriceAlerts(db);

    // ----------------------------------------------------------
    // 7. Notes
    // ----------------------------------------------------------

    await _createTradeNotesIfNeeded(db);

    await _createAdvancedNoteTablesIfNeeded(db);

    await _migrateOldNoteSubjects(db);

    // ----------------------------------------------------------
    // 8. Indexes
    // ----------------------------------------------------------

    await _createIndexes(db);
  }

  // ============================================================
  // SETTINGS REPAIR
  // ============================================================

  Future<void> _ensureSettingsTable(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='settings'
    ''');

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE settings (
          setting_key TEXT PRIMARY KEY,
          setting_value TEXT
        )
      ''');

      await db.insert(
        'settings',
        {
          'setting_key': 'initial_balance',
          'setting_value': '0',
        },
      );

      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(settings)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('setting_key') && names.contains('setting_value')) {
      return;
    }

    if (names.contains('key') && names.contains('value')) {
      await db.execute('''
        CREATE TABLE settings_v12 (
          setting_key TEXT PRIMARY KEY,
          setting_value TEXT
        )
      ''');

      final rows = await db.query(
        'settings',
      );

      for (final row in rows) {
        await db.insert(
          'settings_v12',
          {
            'setting_key': row['key']?.toString() ?? '',
            'setting_value': row['value']?.toString() ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE settings',
      );

      await db.execute(
        'ALTER TABLE settings_v12 RENAME TO settings',
      );
    }
  }

  // ============================================================
  // ASSETS REPAIR
  // ============================================================

  Future<void> _ensureAssetsTable(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='assets'
    ''');

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE assets (
          asset_id INTEGER PRIMARY KEY AUTOINCREMENT,
          asset_symbol TEXT NOT NULL UNIQUE,
          asset_name TEXT,
          asset_enabled INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');

      await db.insert(
        'assets',
        {
          'asset_symbol': 'GOLDUSDT',
          'asset_name': 'Gold USDT',
          'asset_enabled': 1,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(assets)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('asset_id') &&
        names.contains('asset_symbol') &&
        names.contains('asset_name') &&
        names.contains('asset_enabled')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('symbol') &&
        names.contains('name')) {
      await db.execute('''
        CREATE TABLE assets_v12 (
          asset_id INTEGER PRIMARY KEY AUTOINCREMENT,
          asset_symbol TEXT NOT NULL UNIQUE,
          asset_name TEXT,
          asset_enabled INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');

      final rows = await db.query(
        'assets',
      );

      for (final row in rows) {
        await db.insert(
          'assets_v12',
          {
            'asset_id': row['id'],
            'asset_symbol': row['symbol']?.toString() ?? 'GOLDUSDT',
            'asset_name': row['name']?.toString() ?? 'Gold USDT',
            'asset_enabled': 1,
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE assets',
      );

      await db.execute(
        'ALTER TABLE assets_v12 RENAME TO assets',
      );
    }
  }

  // ============================================================
  // TRADES REPAIR
  // ============================================================

  Future<void> _repairTradesTable(
    Database db,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(trades)',
    );

    if (columns.isEmpty) {
      await db.execute('''
        CREATE TABLE trades (
          trade_id TEXT PRIMARY KEY,
          asset_symbol TEXT NOT NULL,
          trade_direction TEXT NOT NULL,
          trade_type TEXT NOT NULL,
          trade_status TEXT NOT NULL,
          trade_timeframe TEXT,
          margin_amount REAL NOT NULL DEFAULT 0,
          leverage_value REAL NOT NULL DEFAULT 0,
          volume_amount REAL NOT NULL DEFAULT 0,
          fee_per_hundred REAL NOT NULL DEFAULT 0,
          trade_fee REAL NOT NULL DEFAULT 0,
          entry_price REAL,
          exit_price REAL,
          stop_price REAL,
          target_price REAL,
          risk_distance REAL NOT NULL DEFAULT 0,
          reward_distance REAL NOT NULL DEFAULT 0,
          risk_value REAL NOT NULL DEFAULT 0,
          reward_value REAL NOT NULL DEFAULT 0,
          trade_risk_reward REAL NOT NULL DEFAULT 0,
          final_pnl REAL NOT NULL DEFAULT 0,
          final_roi_percent REAL NOT NULL DEFAULT 0,
          final_roi_dollar REAL NOT NULL DEFAULT 0,
          final_risk_reward REAL NOT NULL DEFAULT 0,
          max_drawdown_price_percent REAL NOT NULL DEFAULT 0,
          max_drawdown_dollar REAL NOT NULL DEFAULT 0,
          max_drawdown_margin_percent REAL NOT NULL DEFAULT 0,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          entry_setup TEXT,
          entry_reason TEXT,
          entry_motivation TEXT,
          expected_scenario TEXT,
          entry_time TEXT NOT NULL,
          exit_time TEXT
        )
      ''');

      return;
    }

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    // Already correct.
    if (names.contains('trade_id') &&
        names.contains('asset_symbol') &&
        names.contains('trade_direction') &&
        names.contains('trade_type') &&
        names.contains('trade_status')) {
      return;
    }

    // ----------------------------------------------------------
    // Malformed current schema
    // ----------------------------------------------------------

    if (names.contains('id') &&
        names.contains('symbol') &&
        names.contains('side')) {
      await db.execute('''
        CREATE TABLE trades_v12 (
          trade_id TEXT PRIMARY KEY,

          asset_symbol TEXT NOT NULL,

          trade_direction TEXT NOT NULL,
          trade_type TEXT NOT NULL,
          trade_status TEXT NOT NULL,
          trade_timeframe TEXT,

          margin_amount REAL NOT NULL DEFAULT 0,
          leverage_value REAL NOT NULL DEFAULT 0,
          volume_amount REAL NOT NULL DEFAULT 0,

          fee_per_hundred REAL NOT NULL DEFAULT 0,
          trade_fee REAL NOT NULL DEFAULT 0,

          entry_price REAL,
          exit_price REAL,
          stop_price REAL,
          target_price REAL,

          risk_distance REAL NOT NULL DEFAULT 0,
          reward_distance REAL NOT NULL DEFAULT 0,

          risk_value REAL NOT NULL DEFAULT 0,
          reward_value REAL NOT NULL DEFAULT 0,

          trade_risk_reward REAL NOT NULL DEFAULT 0,

          final_pnl REAL NOT NULL DEFAULT 0,
          final_roi_percent REAL NOT NULL DEFAULT 0,
          final_roi_dollar REAL NOT NULL DEFAULT 0,
          final_risk_reward REAL NOT NULL DEFAULT 0,

          max_drawdown_price_percent REAL NOT NULL DEFAULT 0,
          max_drawdown_dollar REAL NOT NULL DEFAULT 0,
          max_drawdown_margin_percent REAL NOT NULL DEFAULT 0,

          duration_seconds INTEGER NOT NULL DEFAULT 0,

          entry_setup TEXT,
          entry_reason TEXT,
          entry_motivation TEXT,
          expected_scenario TEXT,

          entry_time TEXT NOT NULL,
          exit_time TEXT
        )
      ''');

      final rows = await db.query(
        'trades',
      );

      for (final row in rows) {
        final oldId = row['id']?.toString();

        if (oldId == null || oldId.isEmpty) {
          continue;
        }

        await db.insert(
          'trades_v12',
          {
            'trade_id': oldId,
            'asset_symbol': row['symbol']?.toString() ?? 'GOLDUSDT',
            'trade_direction': row['side']?.toString() ?? 'long',
            'trade_type': 'scalp',
            'trade_status': row['status']?.toString() ?? 'open',
            'trade_timeframe': null,
            'margin_amount': row['margin'] ?? 0,
            'leverage_value': row['leverage'] ?? 0,
            'volume_amount': row['volume'] ?? 0,
            'fee_per_hundred': 0,
            'trade_fee': 0,
            'entry_price': row['entry_price'],
            'exit_price': row['exit_price'],
            'stop_price': row['stop_loss'],
            'target_price': row['take_profit'],
            'risk_distance': 0,
            'reward_distance': 0,
            'risk_value': 0,
            'reward_value': 0,
            'trade_risk_reward': 0,
            'final_pnl': row['pnl'] ?? 0,
            'final_roi_percent': 0,
            'final_roi_dollar': 0,
            'final_risk_reward': 0,
            'max_drawdown_price_percent': 0,
            'max_drawdown_dollar': 0,
            'max_drawdown_margin_percent': 0,
            'duration_seconds': 0,
            'entry_setup': null,
            'entry_reason': null,
            'entry_motivation': null,
            'expected_scenario': null,
            'entry_time': row['opened_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'exit_time': row['closed_at']?.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE trades',
      );

      await db.execute(
        'ALTER TABLE trades_v12 RENAME TO trades',
      );
    }
  }

  // ============================================================
  // TRADE IMAGES REPAIR
  // ============================================================

  Future<void> _repairTradeImagesTable(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_images'
    ''');

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE trade_images (
          trade_image_id INTEGER PRIMARY KEY AUTOINCREMENT,
          trade_id TEXT NOT NULL,
          image_path TEXT NOT NULL,
          image_type TEXT NOT NULL DEFAULT 'entry',
          image_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE
        )
      ''');

      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(trade_images)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('trade_image_id') &&
        names.contains('image_path') &&
        names.contains('image_type')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('trade_id') &&
        names.contains('file_path')) {
      await db.execute('''
        CREATE TABLE trade_images_v12 (
          trade_image_id INTEGER PRIMARY KEY AUTOINCREMENT,
          trade_id TEXT NOT NULL,
          image_path TEXT NOT NULL,
          image_type TEXT NOT NULL DEFAULT 'entry',
          image_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE
        )
      ''');

      final rows = await db.query(
        'trade_images',
      );

      for (final row in rows) {
        await db.insert(
          'trade_images_v12',
          {
            'trade_image_id': row['id'],
            'trade_id': row['trade_id']?.toString() ?? '',
            'image_path': row['file_path']?.toString() ?? '',
            'image_type': 'entry',
            'image_order': 0,
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE trade_images',
      );

      await db.execute(
        'ALTER TABLE trade_images_v12 RENAME TO trade_images',
      );
    }
  }

  // ============================================================
  // TRADE EXPERIENCES REPAIR
  // ============================================================

  Future<void> _repairTradeExperiencesTable(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_experiences'
    ''');

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE trade_experiences (
          experience_id TEXT PRIMARY KEY,
          trade_id TEXT NOT NULL,
          experience_title TEXT,
          experience_description TEXT,
          experience_created_at TEXT NOT NULL,
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE
        )
      ''');

      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(trade_experiences)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('experience_id') && names.contains('experience_title')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('trade_id') &&
        names.contains('experience')) {
      await db.execute('''
        CREATE TABLE trade_experiences_v12 (
          experience_id TEXT PRIMARY KEY,
          trade_id TEXT NOT NULL,
          experience_title TEXT,
          experience_description TEXT,
          experience_created_at TEXT NOT NULL,
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE
        )
      ''');

      final rows = await db.query(
        'trade_experiences',
      );

      for (final row in rows) {
        final id = row['id']?.toString();

        if (id == null || id.isEmpty) {
          continue;
        }

        await db.insert(
          'trade_experiences_v12',
          {
            'experience_id': id,
            'trade_id': row['trade_id']?.toString() ?? '',
            'experience_title': null,
            'experience_description': row['experience']?.toString(),
            'experience_created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE trade_experiences',
      );

      await db.execute(
        'ALTER TABLE trade_experiences_v12 RENAME TO trade_experiences',
      );
    }
  }

  // ============================================================
  // EXPERIENCE IMAGES REPAIR
  // ============================================================

  Future<void> _repairExperienceImagesTable(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='experience_images'
    ''');

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE experience_images (
          experience_image_id INTEGER PRIMARY KEY AUTOINCREMENT,
          experience_id TEXT NOT NULL,
          image_path TEXT NOT NULL,
          image_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (experience_id)
            REFERENCES trade_experiences(experience_id)
            ON DELETE CASCADE
        )
      ''');

      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(experience_images)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('experience_image_id') && names.contains('image_path')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('experience_id') &&
        names.contains('file_path')) {
      await db.execute('''
        CREATE TABLE experience_images_v12 (
          experience_image_id INTEGER PRIMARY KEY AUTOINCREMENT,
          experience_id TEXT NOT NULL,
          image_path TEXT NOT NULL,
          image_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (experience_id)
            REFERENCES trade_experiences(experience_id)
            ON DELETE CASCADE
        )
      ''');

      final rows = await db.query(
        'experience_images',
      );

      for (final row in rows) {
        await db.insert(
          'experience_images_v12',
          {
            'experience_image_id': row['id'],
            'experience_id': row['experience_id']?.toString() ?? '',
            'image_path': row['file_path']?.toString() ?? '',
            'image_order': 0,
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE experience_images',
      );

      await db.execute(
        'ALTER TABLE experience_images_v12 RENAME TO experience_images',
      );
    }
  }

  // ============================================================
  // TRADE CUSTOM VALUES REPAIR
  // ============================================================

  Future<void> _repairTradeCustomValues(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_custom_values'
    ''');

    if (tables.isEmpty) {
      await _createTradeCustomValuesOnly(db);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(trade_custom_values)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('value_id') &&
        names.contains('trade_id') &&
        names.contains('field_id') &&
        names.contains('value_text')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('trade_id') &&
        names.contains('field_id') &&
        names.contains('value_text')) {
      await db.execute('''
        CREATE TABLE trade_custom_values_v12 (
          value_id INTEGER PRIMARY KEY AUTOINCREMENT,
          trade_id TEXT NOT NULL,
          field_id INTEGER NOT NULL,
          value_text TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(trade_id, field_id),
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE,
          FOREIGN KEY (field_id)
            REFERENCES custom_fields(field_id)
            ON DELETE CASCADE
        )
      ''');

      final rows = await db.query(
        'trade_custom_values',
      );

      for (final row in rows) {
        await db.insert(
          'trade_custom_values_v12',
          {
            'value_id': row['id'],
            'trade_id': row['trade_id']?.toString() ?? '',
            'field_id': row['field_id'],
            'value_text': row['value_text']?.toString() ?? '',
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE trade_custom_values',
      );

      await db.execute(
        'ALTER TABLE trade_custom_values_v12 RENAME TO trade_custom_values',
      );

      return;
    }

    if (names.contains('id') &&
        names.contains('trade_id') &&
        names.contains('field_id') &&
        names.contains('value')) {
      await db.execute('''
        CREATE TABLE trade_custom_values_v12 (
          value_id INTEGER PRIMARY KEY AUTOINCREMENT,
          trade_id TEXT NOT NULL,
          field_id INTEGER NOT NULL,
          value_text TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(trade_id, field_id),
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE,
          FOREIGN KEY (field_id)
            REFERENCES custom_fields(field_id)
            ON DELETE CASCADE
        )
      ''');

      final rows = await db.query(
        'trade_custom_values',
      );

      for (final row in rows) {
        await db.insert(
          'trade_custom_values_v12',
          {
            'value_id': row['id'],
            'trade_id': row['trade_id']?.toString() ?? '',
            'field_id': row['field_id'],
            'value_text': row['value']?.toString() ?? '',
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE trade_custom_values',
      );

      await db.execute(
        'ALTER TABLE trade_custom_values_v12 RENAME TO trade_custom_values',
      );
    }
  }

  // ============================================================
  // CREATE ONLY TRADE CUSTOM VALUES
  // ============================================================

  Future<void> _createTradeCustomValuesOnly(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE trade_custom_values (
        value_id INTEGER PRIMARY KEY AUTOINCREMENT,

        trade_id TEXT NOT NULL,

        field_id INTEGER NOT NULL,

        value_text TEXT,

        created_at TEXT NOT NULL,

        UNIQUE (
          trade_id,
          field_id
        ),

        FOREIGN KEY (trade_id)
          REFERENCES trades(trade_id)
          ON DELETE CASCADE,

        FOREIGN KEY (field_id)
          REFERENCES custom_fields(field_id)
          ON DELETE CASCADE
      )
    ''');
  }

  // ============================================================
  // PRE TRADE ITEMS REPAIR
  // ============================================================

  Future<void> _repairPreTradeItems(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='pre_trade_items'
    ''');

    if (tables.isEmpty) {
      await _createPreTradeTables(db);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(pre_trade_items)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('item_id') &&
        names.contains('item_title') &&
        names.contains('item_type') &&
        names.contains('item_order')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('title') &&
        names.contains('type') &&
        names.contains('sort_order')) {
      await db.execute('''
        CREATE TABLE pre_trade_items_v12 (
          item_id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_title TEXT NOT NULL,
          category TEXT NOT NULL,
          item_type TEXT NOT NULL,
          is_required INTEGER NOT NULL DEFAULT 0,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          item_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');

      final rows = await db.query(
        'pre_trade_items',
      );

      for (final row in rows) {
        await db.insert(
          'pre_trade_items_v12',
          {
            'item_id': row['id'],
            'item_title': row['title']?.toString() ?? '',
            'category': row['category']?.toString() ?? 'questions',
            'item_type': row['type']?.toString() ?? 'text',
            'is_required': row['is_required'] ?? 0,
            'is_enabled': row['is_enabled'] ?? 1,
            'item_order': row['sort_order'] ?? 0,
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE pre_trade_items',
      );

      await db.execute(
        'ALTER TABLE pre_trade_items_v12 RENAME TO pre_trade_items',
      );
    }
  }

  // ============================================================
  // TRADE PRE-TRADE VALUES REPAIR
  // ============================================================

  Future<void> _repairTradePreTradeValues(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_pre_trade_values'
    ''');

    if (tables.isEmpty) {
      await _createTradePreTradeValuesOnly(db);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(trade_pre_trade_values)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    if (names.contains('value_id') &&
        names.contains('trade_id') &&
        names.contains('item_id') &&
        names.contains('value_text')) {
      return;
    }

    if (names.contains('id') &&
        names.contains('trade_id') &&
        names.contains('item_id') &&
        names.contains('value')) {
      await db.execute('''
        CREATE TABLE trade_pre_trade_values_v12 (
          value_id INTEGER PRIMARY KEY AUTOINCREMENT,
          trade_id TEXT NOT NULL,
          item_id INTEGER NOT NULL,
          value_text TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(trade_id, item_id),
          FOREIGN KEY (trade_id)
            REFERENCES trades(trade_id)
            ON DELETE CASCADE,
          FOREIGN KEY (item_id)
            REFERENCES pre_trade_items(item_id)
            ON DELETE CASCADE
        )
      ''');

      final rows = await db.query(
        'trade_pre_trade_values',
      );

      for (final row in rows) {
        await db.insert(
          'trade_pre_trade_values_v12',
          {
            'value_id': row['id'],
            'trade_id': row['trade_id']?.toString() ?? '',
            'item_id': row['item_id'],
            'value_text': row['value']?.toString() ?? '',
            'created_at': row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await db.execute(
        'DROP TABLE trade_pre_trade_values',
      );

      await db.execute(
        'ALTER TABLE trade_pre_trade_values_v12 RENAME TO trade_pre_trade_values',
      );
    }
  }

  // ============================================================
  // CREATE ONLY TRADE PRE-TRADE VALUES
  // ============================================================

  Future<void> _createTradePreTradeValuesOnly(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE trade_pre_trade_values (
        value_id INTEGER PRIMARY KEY AUTOINCREMENT,

        trade_id TEXT NOT NULL,

        item_id INTEGER NOT NULL,

        value_text TEXT,

        created_at TEXT NOT NULL,

        UNIQUE(
          trade_id,
          item_id
        ),

        FOREIGN KEY (trade_id)
          REFERENCES trades(trade_id)
          ON DELETE CASCADE,

        FOREIGN KEY (item_id)
          REFERENCES pre_trade_items(item_id)
          ON DELETE CASCADE
      )
    ''');
  }

  // ============================================================
  // PRICE ALERT REPAIR
  // ============================================================

  Future<void> _repairPriceAlerts(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='price_alerts'
    ''');

    if (tables.isEmpty) {
      await _createPriceAlertTable(db);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(price_alerts)',
    );

    final names =
        columns.map((e) => e['name']?.toString()).whereType<String>().toSet();

    final requiredColumns = [
      'id',
      'symbol',
      'title',
      'note',
      'type',
      'target_price',
      'lower_price',
      'upper_price',
      'trigger_on_rise',
      'repeat_mode',
      'repeat_interval_minutes',
      'is_active',
      'is_triggered',
      'sound_path',
      'trade_id',
      'trade_price_type',
      'multi_stage_group_id',
      'stage_index',
      'created_at',
      'last_triggered_at',
      'triggered_at',
    ];

    var complete = true;

    for (final column in requiredColumns) {
      if (!names.contains(column)) {
        complete = false;
        break;
      }
    }

    if (complete) {
      return;
    }

    final additions = <String, String>{
      'title':
          "ALTER TABLE price_alerts ADD COLUMN title TEXT NOT NULL DEFAULT ''",
      'note':
          "ALTER TABLE price_alerts ADD COLUMN note TEXT NOT NULL DEFAULT ''",
      'type':
          "ALTER TABLE price_alerts ADD COLUMN type TEXT NOT NULL DEFAULT 'target'",
      'lower_price': 'ALTER TABLE price_alerts ADD COLUMN lower_price REAL',
      'upper_price': 'ALTER TABLE price_alerts ADD COLUMN upper_price REAL',
      'trigger_on_rise':
          'ALTER TABLE price_alerts ADD COLUMN trigger_on_rise INTEGER NOT NULL DEFAULT 1',
      'repeat_mode':
          "ALTER TABLE price_alerts ADD COLUMN repeat_mode TEXT NOT NULL DEFAULT 'once'",
      'repeat_interval_minutes':
          'ALTER TABLE price_alerts ADD COLUMN repeat_interval_minutes INTEGER',
      'is_active':
          'ALTER TABLE price_alerts ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
      'is_triggered':
          'ALTER TABLE price_alerts ADD COLUMN is_triggered INTEGER NOT NULL DEFAULT 0',
      'sound_path': 'ALTER TABLE price_alerts ADD COLUMN sound_path TEXT',
      'trade_id': 'ALTER TABLE price_alerts ADD COLUMN trade_id TEXT',
      'trade_price_type':
          'ALTER TABLE price_alerts ADD COLUMN trade_price_type TEXT',
      'multi_stage_group_id':
          'ALTER TABLE price_alerts ADD COLUMN multi_stage_group_id TEXT',
      'stage_index': 'ALTER TABLE price_alerts ADD COLUMN stage_index INTEGER',
      'last_triggered_at':
          'ALTER TABLE price_alerts ADD COLUMN last_triggered_at TEXT',
      'triggered_at': 'ALTER TABLE price_alerts ADD COLUMN triggered_at TEXT',
    };

    for (final entry in additions.entries) {
      if (!names.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  // ============================================================
  // MIGRATE OLD NOTE SUBJECTS
  // ============================================================

  Future<void> _migrateOldNoteSubjects(
    Database db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_notes'
    ''');

    if (tables.isEmpty) {
      return;
    }

    final subjectTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='note_subjects'
    ''');

    final relationTables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name='trade_note_subjects'
    ''');

    if (subjectTables.isEmpty || relationTables.isEmpty) {
      return;
    }

    final oldSubjects = await db.rawQuery('''
      SELECT DISTINCT subject
      FROM trade_notes
      WHERE subject IS NOT NULL
      AND TRIM(subject) != ''
      ORDER BY subject COLLATE NOCASE ASC
    ''');

    for (final row in oldSubjects) {
      final subjectName = row['subject']?.toString().trim();

      if (subjectName == null || subjectName.isEmpty) {
        continue;
      }

      int? subjectId;

      final existing = await db.query(
        'note_subjects',
        columns: ['subject_id'],
        where: 'subject_name = ? AND parent_id IS NULL',
        whereArgs: [subjectName],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        subjectId = existing.first['subject_id'] as int;
      } else {
        subjectId = await db.insert(
          'note_subjects',
          {
            'subject_name': subjectName,
            'parent_id': null,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
        );
      }

      final notes = await db.query(
        'trade_notes',
        columns: ['id'],
        where: 'subject = ?',
        whereArgs: [subjectName],
      );

      for (final note in notes) {
        final noteId = note['id'] as int;

        await db.insert(
          'trade_note_subjects',
          {
            'note_id': noteId,
            'subject_id': subjectId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  Future<String?> getSetting(
    String key,
  ) async {
    final db = await database;

    final result = await db.query(
      'settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first['setting_value']?.toString();
  }

  Future<void> setSetting(
    String key,
    String value,
  ) async {
    final db = await database;

    await db.insert(
      'settings',
      {
        'setting_key': key,
        'setting_value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // INITIAL BALANCE
  // ============================================================

  Future<double> getInitialBalance() async {
    final value = await getSetting('initial_balance');

    return double.tryParse(
          value ?? '',
        ) ??
        0;
  }

  Future<void> setInitialBalance(
    double value,
  ) async {
    await setSetting(
      'initial_balance',
      value.toString(),
    );
  }

  // ============================================================
  // CLEAR ALL DATA
  // ============================================================

  Future<void> clearAllData() async {
    final db = await database;

    await db.transaction(
      (transaction) async {
        await transaction.delete(
          'trade_note_media',
        );

        await transaction.delete(
          'trade_note_subjects',
        );

        await transaction.delete(
          'trade_note_tags',
        );

        await transaction.delete(
          'trade_notes',
        );

        await transaction.delete(
          'note_subjects',
        );

        await transaction.delete(
          'note_tags',
        );

        await transaction.delete(
          'trade_pre_trade_values',
        );

        await transaction.delete(
          'pre_trade_items',
        );

        await transaction.delete(
          'trade_custom_values',
        );

        await transaction.delete(
          'custom_fields',
        );

        await transaction.delete(
          'experience_images',
        );

        await transaction.delete(
          'trade_experiences',
        );

        await transaction.delete(
          'trade_images',
        );

        await transaction.delete(
          'trades',
        );

        await transaction.delete(
          'price_alerts',
        );

        await transaction.delete(
          'assets',
        );

        await transaction.delete(
          'settings',
        );

        await transaction.insert(
          'settings',
          {
            'setting_key': 'initial_balance',
            'setting_value': '0',
          },
        );

        await transaction.insert(
          'assets',
          {
            'asset_symbol': 'GOLDUSDT',
            'asset_name': 'Gold USDT',
            'asset_enabled': 1,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
      },
    );
  }

  // ============================================================
  // CLOSE DATABASE
  // ============================================================

  Future<void> closeDatabase() async {
    if (_database == null) {
      return;
    }

    await _database!.close();

    _database = null;
  }

  // ============================================================
  // CUSTOM IMAGE GALLERY
  // ============================================================

  Future<void> _createCustomGalleryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_gallery_topics (
        topic_id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_gallery_images (
        image_id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_id INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        image_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (topic_id)
          REFERENCES custom_gallery_topics(topic_id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_custom_gallery_images_topic
      ON custom_gallery_images(topic_id)
    ''');
  }
}
