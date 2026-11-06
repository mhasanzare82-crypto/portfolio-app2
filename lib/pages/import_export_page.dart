import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:docx_dart/docx_dart.dart' as docx;
import 'package:docx_dart/src/shared.dart' show Inches;
import 'package:docx_to_text/docx_to_text.dart';

import '../database/app_database.dart';
import '../repositories/pre_trade_repository.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool _busy = false;
  final PreTradeRepository _preTradeRepository = PreTradeRepository();

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<Database> _getDatabase() async {
    return await AppDatabase.instance.database;
  }

  Future<List<String>> _getTableNames(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
      "ORDER BY name",
    );

    return result.map((r) => r['name'] as String).toList();
  }

  Future<Map<String, Set<String>>> _getColumns(
    Database db,
    List<String> tables,
  ) async {
    final result = <String, Set<String>>{};

    for (final table in tables) {
      final info = await db.rawQuery(
        'PRAGMA table_info("$table")',
      );
      result[table] = info.map((r) => r['name'] as String).toSet();
    }

    return result;
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirmText = 'ادامه',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<Uint8List?> _pickBytes({
    required String title,
    required List<String> extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.single.bytes;
  }

  Future<void> _saveBytes({
    required String title,
    required String fileName,
    required String extension,
    required Uint8List bytes,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );

    if (path != null) {
      _showMessage('فایل ذخیره شد: ${p.basename(path)}');
    } else {
      _showMessage('ذخیره فایل لغو شد.');
    }
  }

  String _categoryTitle(String category) {
    switch (category) {
      case 'questions':
        return 'سوالات قبل از معامله';
      case 'psychology':
        return 'چک‌لیست روانشناسی';
      default:
        return 'چک‌لیست فنی';
    }
  }

  Future<void> _exportPreTradeTxt(String category) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final items = await _preTradeRepository.getAllItems(category: category);
      final content = items
          .map((item) => item['item_title']?.toString().trim() ?? '')
          .where((line) => line.isNotEmpty)
          .join('\n');
      await _saveBytes(
        title: 'خروجی ${_categoryTitle(category)}',
        fileName: '${category}_items.txt',
        extension: 'txt',
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
    } catch (e) {
      _showMessage('خروجی گرفتن ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPreTradeTxt(String category) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _pickBytes(
        title: 'ورود ${_categoryTitle(category)} از TXT',
        extensions: ['txt'],
      );
      if (bytes == null) return;
      final lines = utf8
          .decode(bytes)
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      var count = 0;
      for (final line in lines) {
        await _preTradeRepository.createItem(
          title: line,
          category: category,
          itemType: category == 'questions' ? 'question' : 'checklist',
          isRequired: false,
          isEnabled: true,
        );
        count++;
      }
      _showMessage('$count مورد به ${_categoryTitle(category)} اضافه شد.');
    } catch (e) {
      _showMessage('ورود اطلاعات ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preTradeExportCard(String category) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_categoryTitle(category),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('هر خط فایل TXT یک سؤال یا یک مورد چک‌لیست محسوب می‌شود.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _exportPreTradeTxt(category),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('خروجی TXT')),
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _importPreTradeTxt(category),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('ورود TXT')),
          ]),
        ]),
      ),
    );
  }

  Future<void> _exportJson() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final db = await _getDatabase();
      final tableNames = await _getTableNames(db);

      final tables = <String, dynamic>{};
      for (final table in tableNames) {
        tables[table] = await db.query(table);
      }

      final backup = <String, dynamic>{
        'format': 'trading_journal_backup',
        'format_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'tables': tables,
      };

      await _saveBytes(
        title: 'ذخیره پشتیبان JSON',
        fileName: 'trading_journal_backup.json',
        extension: 'json',
        bytes: Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ').convert(backup),
          ),
        ),
      );
    } catch (e) {
      _showMessage('خطا در خروجی JSON: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJson() async {
    if (_busy) return;

    if (!await _confirm(
      'ورود پشتیبان JSON',
      'اطلاعات به دیتابیس فعلی اضافه می‌شوند. '
          'اطلاعات موجود حذف یا بازنویسی نمی‌شوند. '
          'اگر تعارض شناسه یا رابطه‌ای وجود داشته باشد، '
          'کل ورود لغو می‌شود.',
      confirmText: 'انتخاب فایل',
    )) {
      return;
    }

    setState(() => _busy = true);

    try {
      final bytes = await _pickBytes(
        title: 'انتخاب پشتیبان JSON',
        extensions: ['json'],
      );

      if (bytes == null) {
        _showMessage('فایلی انتخاب نشد.');
        return;
      }

      final decoded = jsonDecode(utf8.decode(bytes));

      if (decoded is! Map ||
          decoded['format'] != 'trading_journal_backup' ||
          decoded['format_version'] != 1 ||
          decoded['tables'] is! Map) {
        throw const FormatException('ساختار پشتیبان JSON معتبر نیست.');
      }

      await _insertTables(decoded['tables'] as Map);

      _showMessage('ورود JSON با موفقیت انجام شد.');
    } catch (e) {
      _showMessage('ورود JSON انجام نشد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _insertTables(
    Map rawTables, {
    Map<String, String> restoredPaths = const {},
  }) async {
    final db = await _getDatabase();
    final tableNames = await _getTableNames(db);
    final columns = await _getColumns(db, tableNames);

    for (final entry in rawTables.entries) {
      if (entry.key is! String || !tableNames.contains(entry.key)) {
        throw FormatException(
          'جدول ${entry.key} در دیتابیس فعلی وجود ندارد.',
        );
      }

      if (entry.value is! List) {
        throw FormatException(
          'ساختار جدول ${entry.key} معتبر نیست.',
        );
      }

      for (final row in entry.value as List) {
        if (row is! Map) {
          throw FormatException(
            'یک ردیف در جدول ${entry.key} معتبر نیست.',
          );
        }
      }
    }

    const preferredOrder = [
      'settings',
      'assets',
      'trades',
      'trade_experiences',
      'custom_fields',
      'pre_trade_items',
      'price_alerts',
      'trade_notes',
      'note_tags',
      'note_subjects',
      'trade_images',
      'experience_images',
      'trade_custom_values',
      'trade_pre_trade_values',
      'trade_note_tags',
      'trade_note_subjects',
      'trade_note_media',
    ];

    final ordered = <String>[
      ...preferredOrder.where(rawTables.containsKey),
      ...rawTables.keys
          .where((k) => !preferredOrder.contains(k))
          .cast<String>(),
    ];

    var imported = 0;

    await db.transaction((txn) async {
      for (final table in ordered) {
        final rows = rawTables[table] as List;

        for (final rawRow in rows) {
          final row = <String, Object?>{};

          for (final entry in (rawRow as Map).entries) {
            if (entry.key is String && columns[table]!.contains(entry.key)) {
              row[entry.key as String] = entry.value;
            }
          }

          const mediaColumns = {
            'trade_images': 'image_path',
            'experience_images': 'image_path',
            'trade_note_media': 'file_path',
            'price_alerts': 'sound_path',
          };

          final mediaColumn = mediaColumns[table];
          if (mediaColumn != null) {
            final oldPath = row[mediaColumn];
            if (oldPath is String && restoredPaths.containsKey(oldPath)) {
              row[mediaColumn] = restoredPaths[oldPath];
            }
          }
          if (table == 'analyses' || table == 'trade_experiences') {
            for (final column in (table == 'analyses'
                ? ['image_paths', 'audio_paths']
                : ['audio_paths'])) {
              try {
                final paths =
                    (jsonDecode(row[column]?.toString() ?? '[]') as List)
                        .map((value) {
                  final oldPath = value.toString();
                  return restoredPaths[oldPath] ?? oldPath;
                }).toList();
                row[column] = jsonEncode(paths);
              } catch (_) {}
            }
          }

          if (row.isEmpty) continue;

          // تنظیمات موجود را پیش از INSERT بررسی می‌کنیم.
          // در نتیجه نیازی به گرفتن خطای SQL و ادامه تراکنش نیست.
          if (table == 'settings' && row.containsKey('setting_key')) {
            final existing = await txn.query(
              'settings',
              columns: ['setting_key'],
              where: 'setting_key = ?',
              whereArgs: [row['setting_key']],
              limit: 1,
            );

            if (existing.isNotEmpty) continue;
          }

          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          imported++;
        }
      }
    });

    return imported;
  }

  Future<void> _exportZip() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final db = await _getDatabase();
      final tableNames = await _getTableNames(db);
      final tables = <String, dynamic>{};

      for (final table in tableNames) {
        tables[table] = await db.query(table);
      }

      final manifest = <String, String>{};
      final archive = Archive();

      const mediaColumns = {
        'trade_images': 'image_path',
        'experience_images': 'image_path',
        'trade_note_media': 'file_path',
        'price_alerts': 'sound_path',
      };

      var mediaIndex = 0;

      for (final entry in mediaColumns.entries) {
        if (!tableNames.contains(entry.key)) continue;

        final rows = tables[entry.key] as List;

        for (final row in rows) {
          final originalPath = row[entry.value];

          if (originalPath is! String || originalPath.trim().isEmpty) {
            continue;
          }

          try {
            final file = File(originalPath);
            if (!await file.exists()) continue;

            final data = await file.readAsBytes();
            final ext = p.extension(originalPath);
            final archivePath = 'media/file_${mediaIndex++}$ext';

            archive.addFile(
              ArchiveFile(archivePath, data.length, data),
            );

            manifest[originalPath] = archivePath;
          } catch (_) {
            // فایل غیرقابل دسترس به آرشیو اضافه نمی‌شود.
          }
        }
      }

      for (final mediaTable in ['analyses', 'trade_experiences']) {
        if (!tableNames.contains(mediaTable)) continue;
        final analysisRows = tables[mediaTable] as List;
        for (final rawRow in analysisRows) {
          if (rawRow is! Map) continue;
          final mediaPathColumns = mediaTable == 'analyses'
              ? ['image_paths', 'audio_paths']
              : ['audio_paths'];
          for (final column in mediaPathColumns) {
            try {
              final paths =
                  jsonDecode(rawRow[column]?.toString() ?? '[]') as List;
              for (final rawPath in paths) {
                final originalPath = rawPath.toString();
                if (originalPath.trim().isEmpty ||
                    manifest.containsKey(originalPath)) continue;
                final file = File(originalPath);
                if (!await file.exists()) continue;
                final data = await file.readAsBytes();
                final ext = p.extension(originalPath);
                final archivePath = 'media/file_${mediaIndex++}$ext';
                archive.addFile(ArchiveFile(archivePath, data.length, data));
                manifest[originalPath] = archivePath;
              }
            } catch (_) {}
          }
        }
      }

      final backup = <String, dynamic>{
        'format': 'trading_journal_full_backup',
        'format_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'tables': tables,
        'media_manifest': manifest,
      };

      final jsonBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(backup),
      );

      archive.addFile(
        ArchiveFile('backup.json', jsonBytes.length, jsonBytes),
      );

      final zipped = ZipEncoder().encode(archive);

      if (zipped == null || zipped.isEmpty) {
        throw Exception('ساخت ZIP ناموفق بود.');
      }

      await _saveBytes(
        title: 'ذخیره پشتیبان کامل ZIP',
        fileName: 'trading_journal_backup.zip',
        extension: 'zip',
        bytes: Uint8List.fromList(zipped),
      );

      _showMessage(
        'تعداد جدول‌ها: ${tableNames.length}؛ '
        'رسانه‌های اضافه‌شده: ${manifest.length}',
      );
    } catch (e) {
      _showMessage('خطا در خروجی ZIP: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _importTradeBundle(
      Map decoded, Map<String, ArchiveFile> archiveFiles) async {
    final rawTrade = decoded['trade'];
    if (rawTrade is! Map)
      throw const FormatException('اطلاعات معامله در بسته وجود ندارد.');
    final db = await _getDatabase();
    final trade = Map<String, dynamic>.from(rawTrade);
    final oldTradeId = trade['trade_id']?.toString() ?? 'trade';
    final newTradeId =
        '${oldTradeId}_import_${DateTime.now().microsecondsSinceEpoch}';
    trade['trade_id'] = newTradeId;
    await db.insert('trades', trade);
    final now = DateTime.now().toIso8601String();
    final rawCustomValues = decoded['custom_values'];
    if (rawCustomValues is Map) {
      for (final entry in rawCustomValues.entries) {
        final fieldId = int.tryParse(entry.key.toString());
        if (fieldId == null) continue;
        final exists = await db.query('custom_fields',
            columns: ['field_id'],
            where: 'field_id = ?',
            whereArgs: [fieldId],
            limit: 1);
        if (exists.isEmpty) continue;
        await db.insert(
            'trade_custom_values',
            {
              'trade_id': newTradeId,
              'field_id': fieldId,
              'value_text': entry.value?.toString() ?? '',
              'created_at': now
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    final rawPreTradeValues = decoded['pre_trade_values'];
    if (rawPreTradeValues is Map) {
      for (final entry in rawPreTradeValues.entries) {
        final itemId = int.tryParse(entry.key.toString());
        if (itemId == null) continue;
        final exists = await db.query('pre_trade_items',
            columns: ['item_id'],
            where: 'item_id = ?',
            whereArgs: [itemId],
            limit: 1);
        if (exists.isEmpty) continue;
        await db.insert(
            'trade_pre_trade_values',
            {
              'trade_id': newTradeId,
              'item_id': itemId,
              'value_text': entry.value?.toString() ?? '',
              'created_at': now
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    final documents = await getApplicationDocumentsDirectory();
    final mediaPaths = <Map<String, dynamic>>[];
    final rawMedia = decoded['media'];
    if (rawMedia is List) {
      var imageOrder = 0;
      for (final item in rawMedia) {
        if (item is! Map) continue;
        final archivePath = item['archive_path']?.toString() ?? '';
        if (!archivePath.startsWith('media/') ||
            archivePath.split('/').contains('..')) continue;
        final file = archiveFiles[archivePath];
        if (file == null) continue;
        final type = item['type']?.toString() ?? '';
        final name = item['name']?.toString() ?? p.basename(archivePath);
        final ext = p.extension(name).isNotEmpty
            ? p.extension(name)
            : p.extension(archivePath);
        final folderName = type == 'trade_image'
            ? 'trade_images'
            : type == 'experience_image'
                ? 'experience_images'
                : 'experience_audio';
        final folder = Directory(p.join(documents.path, folderName));
        await folder.create(recursive: true);
        final target = p.join(folder.path,
            '${DateTime.now().microsecondsSinceEpoch}_${mediaPaths.length}$ext');
        await File(target).writeAsBytes(
            List<int>.from(file.content as List<int>),
            flush: true);
        final record = <String, dynamic>{
          'type': type,
          'path': target,
          'name': name,
          'experience_id': item['experience_id']?.toString()
        };
        mediaPaths.add(record);
        if (type == 'trade_image') {
          await db.insert('trade_images', {
            'trade_id': newTradeId,
            'image_path': target,
            'image_order': imageOrder++,
            'created_at': DateTime.now().toIso8601String()
          });
        }
      }
    }

    final rawExperiences = decoded['experiences'];
    final experienceIdMap = <String, String>{};
    if (rawExperiences is List) {
      var expIndex = 0;
      for (final rawExperience in rawExperiences) {
        if (rawExperience is! Map) continue;
        final oldId = rawExperience['experience_id']?.toString() ??
            'experience_$expIndex';
        final newId = '${newTradeId}_experience_$expIndex';
        experienceIdMap[oldId] = newId;
        final audioPaths = mediaPaths
            .where((m) =>
                m['type'] == 'experience_audio' && m['experience_id'] == oldId)
            .map((m) => m['path'].toString())
            .toList();
        await db.insert('trade_experiences', {
          'experience_id': newId,
          'trade_id': newTradeId,
          'experience_title': rawExperience['title']?.toString() ?? '',
          'experience_description':
              rawExperience['description']?.toString() ?? '',
          'audio_paths': jsonEncode(audioPaths),
          'experience_created_at': rawExperience['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
        });
        expIndex++;
      }
    }
    final experienceImageOrder = <String, int>{};
    for (final media
        in mediaPaths.where((m) => m['type'] == 'experience_image')) {
      final oldId = media['experience_id']?.toString() ?? '';
      final newId = experienceIdMap[oldId];
      if (newId == null) continue;
      final order =
          experienceImageOrder.update(newId, (v) => v + 1, ifAbsent: () => 0);
      await db.insert('experience_images', {
        'experience_id': newId,
        'image_path': media['path'],
        'image_order': order,
        'created_at': DateTime.now().toIso8601String()
      });
    }
    return 1 + experienceIdMap.length + mediaPaths.length;
  }

  Future<void> _importZip() async {
    if (_busy) return;

    if (!await _confirm(
      'بازیابی پشتیبان ZIP',
      'پشتیبان کامل یا بستهٔ یک معامله به دیتابیس اضافه می‌شود. '
          'داده‌های موجود حذف یا بازنویسی نمی‌شوند. '
          'در صورت تعارض شناسه، ورود متوقف می‌شود.',
      confirmText: 'انتخاب ZIP',
    )) {
      return;
    }

    setState(() => _busy = true);

    String? restorePath;

    try {
      final bytes = await _pickBytes(
        title: 'انتخاب پشتیبان ZIP',
        extensions: ['zip'],
      );

      if (bytes == null) {
        _showMessage('فایلی انتخاب نشد.');
        return;
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      final archiveFiles = <String, ArchiveFile>{};

      for (final file in archive.files) {
        if (file.isFile) archiveFiles[file.name] = file;
      }

      final jsonFile =
          archiveFiles['backup.json'] ?? archiveFiles['trade.json'];
      if (jsonFile == null) {
        throw const FormatException('فایل backup.json یا trade.json پیدا نشد.');
      }

      final decoded = jsonDecode(
        utf8.decode(List<int>.from(jsonFile.content as List<int>)),
      );

      if (decoded is Map &&
          decoded['format'] == 'lbank_trade_bundle' &&
          decoded['version'] == 1) {
        final count = await _importTradeBundle(decoded, archiveFiles);
        _showMessage(
            'معاملهٔ جداگانه همراه رسانه‌ها وارد شد. رکوردهای ایجادشده: $count');
        return;
      }

      if (decoded is! Map ||
          decoded['format'] != 'trading_journal_full_backup' ||
          decoded['format_version'] != 1 ||
          decoded['tables'] is! Map ||
          decoded['media_manifest'] is! Map) {
        throw const FormatException('ساختار ZIP معتبر نیست.');
      }

      final tables = decoded['tables'] as Map;
      final rawManifest = decoded['media_manifest'] as Map;

      // ابتدا ساختار جدول‌ها بررسی می‌شود.
      final db = await _getDatabase();
      final tableNames = await _getTableNames(db);

      for (final entry in tables.entries) {
        if (entry.key is! String || !tableNames.contains(entry.key)) {
          throw FormatException(
            'جدول ${entry.key} در دیتابیس وجود ندارد.',
          );
        }
        if (entry.value is! List) {
          throw FormatException('اطلاعات جدول ${entry.key} معتبر نیست.');
        }
      }

      final documents = await getApplicationDocumentsDirectory();
      final folder = Directory(
        p.join(
          documents.path,
          'restored_backup_media',
          DateTime.now().microsecondsSinceEpoch.toString(),
        ),
      );
      await folder.create(recursive: true);
      restorePath = folder.path;

      final restoredPaths = <String, String>{};
      var mediaIndex = 0;

      for (final entry in rawManifest.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('فهرست رسانه‌ها معتبر نیست.');
        }

        final originalPath = entry.key as String;
        final archivePath = entry.value as String;

        if (!archivePath.startsWith('media/') ||
            archivePath.split('/').contains('..') ||
            archivePath.contains(r'\')) {
          throw const FormatException('مسیر رسانه نامعتبر است.');
        }

        final mediaFile = archiveFiles[archivePath];
        if (mediaFile == null) {
          throw FormatException('فایل $archivePath در ZIP نیست.');
        }

        final ext = p.extension(archivePath);
        final target = p.join(
          folder.path,
          'restored_${mediaIndex++}$ext',
        );

        await File(target).writeAsBytes(
          List<int>.from(mediaFile.content as List<int>),
          flush: true,
        );

        restoredPaths[originalPath] = target;
      }

      final count = await _insertTables(
        tables,
        restoredPaths: restoredPaths,
      );

      _showMessage(
        'بازیابی انجام شد. ردیف‌های اضافه‌شده: $count؛ '
        'رسانه‌های بازیابی‌شده: ${restoredPaths.length}',
      );
    } catch (e) {
      // اگر تراکنش شکست بخورد، فایل‌های رسانه‌ای یتیم پاک می‌شوند.
      if (restorePath != null) {
        try {
          final directory = Directory(restorePath);
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {}
      }

      _showMessage('بازیابی ZIP انجام نشد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportTxt() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final db = await _getDatabase();
      final notes = await db.query('trade_notes', orderBy: 'id ASC');
      final trades = await db.query('trades', orderBy: 'trade_id ASC');

      final buffer = StringBuffer()
        ..writeln('TRADING_JOURNAL_TEXT_BACKUP_V1')
        ..writeln('تاریخ: ${DateTime.now().toIso8601String()}')
        ..writeln()
        ..writeln('========== یادداشت‌ها ==========');

      for (final note in notes) {
        buffer
          ..writeln('--- NOTE ---')
          ..writeln('ID: ${note['id'] ?? ''}')
          ..writeln('عنوان: ${note['title'] ?? ''}')
          ..writeln('موضوع: ${note['subject'] ?? ''}')
          ..writeln('نوع: ${note['note_type'] ?? ''}')
          ..writeln('نماد: ${note['asset_symbol'] ?? ''}')
          ..writeln('شناسه معامله: ${note['trade_id'] ?? ''}')
          ..writeln('تاریخ ایجاد: ${note['created_at'] ?? ''}')
          ..writeln('متن:')
          ..writeln(note['content'] ?? '')
          ..writeln();
      }

      buffer.writeln('========== معاملات ==========');

      for (final trade in trades) {
        buffer.writeln('--- TRADE ---');
        for (final entry in trade.entries) {
          buffer.writeln('${entry.key}: ${entry.value ?? ''}');
        }
        buffer.writeln();
      }

      await _saveBytes(
        title: 'ذخیره خروجی TXT',
        fileName: 'trading_journal_backup.txt',
        extension: 'txt',
        bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
      );
    } catch (e) {
      _showMessage('خطا در خروجی TXT: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importTxt() async {
    if (_busy) return;

    if (!await _confirm(
      'ورود فایل TXT',
      'محتوای فایل به‌عنوان یک یادداشت جدید ذخیره می‌شود. '
          'معاملات داخل متن به‌صورت خودکار بازسازی نمی‌شوند.',
      confirmText: 'انتخاب فایل',
    )) {
      return;
    }

    setState(() => _busy = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'انتخاب فایل TXT',
        type: FileType.custom,
        allowedExtensions: ['txt'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        _showMessage('فایلی انتخاب نشد.');
        return;
      }

      final file = result.files.single;
      final content = utf8.decode(file.bytes!, allowMalformed: true);

      if (content.trim().isEmpty) {
        _showMessage('فایل خالی است.');
        return;
      }

      final db = await _getDatabase();
      final now = DateTime.now().toIso8601String();

      await db.insert('trade_notes', {
        'title': p.basenameWithoutExtension(file.name),
        'content': content,
        'subject': '',
        'note_type': 'text',
        'asset_symbol': '',
        'trade_id': null,
        'source': 'txt_import',
        'source_file_name': file.name,
        'created_at': now,
        'updated_at': now,
      });

      _showMessage('متن به‌عنوان یادداشت جدید وارد شد.');
    } catch (e) {
      _showMessage('خطا در ورود TXT: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _docxTradeLabel(String key) {
    const labels = <String, String>{
      'trade_id': 'شناسه معامله',
      'asset_symbol': 'دارایی',
      'trade_direction': 'جهت معامله',
      'trade_type': 'نوع معامله',
      'trade_status': 'وضعیت',
      'trade_timeframe': 'تایم‌فریم',
      'margin_mode': 'حالت مارجین',
      'margin_amount': 'مارجین (دلار)',
      'leverage_value': 'اهرم',
      'volume_amount': 'حجم (دلار)',
      'fee_per_hundred': 'کارمزد به ازای ۱۰۰',
      'trade_fee': 'کارمزد',
      'entry_price': 'قیمت ورود',
      'exit_price': 'قیمت خروج',
      'stop_price': 'حد ضرر',
      'target_price': 'حد سود',
      'risk_distance': 'فاصله ریسک',
      'reward_distance': 'فاصله ریوارد',
      'risk_value': 'ریسک (دلار)',
      'reward_value': 'ریوارد (دلار)',
      'trade_risk_reward': 'نسبت ریسک به ریوارد',
      'final_pnl': 'سود و زیان نهایی',
      'final_roi_percent': 'بازده نهایی (درصد)',
      'final_roi_dollar': 'بازده نهایی (دلار)',
      'final_risk_reward': 'نسبت نهایی ریسک به ریوارد',
      'max_drawdown_price_percent': 'بیشترین افت قیمت (درصد)',
      'max_drawdown_dollar': 'بیشترین افت (دلار)',
      'max_drawdown_margin_percent': 'افت مارجین (درصد)',
      'duration_seconds': 'مدت معامله (ثانیه)',
      'entry_setup': 'ستاپ ورود',
      'entry_reason': 'دلیل ورود',
      'entry_motivation': 'انگیزه ورود',
      'expected_scenario': 'سناریوی مورد انتظار',
      'entry_time': 'زمان ورود',
      'exit_time': 'زمان خروج',
    };
    return labels[key] ?? key;
  }

  String _docxTradeValue(String key, Object? value) {
    if (value == null || value.toString().isEmpty) return '—';
    final raw = value.toString();
    if (key == 'trade_direction')
      return raw == 'long'
          ? 'لانگ'
          : raw == 'short'
              ? 'شورت'
              : raw;
    if (key == 'trade_type')
      return raw == 'scalp'
          ? 'اسکالپ'
          : raw == 'day'
              ? 'روزانه'
              : raw;
    if (key == 'trade_status')
      return raw == 'open'
          ? 'باز'
          : raw == 'closed'
              ? 'بسته'
              : raw;
    if (key == 'margin_mode') return raw == 'cross' ? 'کراس' : 'ایزوله';
    if (key == 'entry_time' || key == 'exit_time')
      return DateTime.tryParse(raw)?.toLocal().toString() ?? raw;
    if (value is num) {
      if (key.contains('price')) return value.toDouble().toStringAsFixed(4);
      if (key.contains('percent'))
        return '${value.toDouble().toStringAsFixed(2)}٪';
      if (key.contains('amount') ||
          key.contains('pnl') ||
          key.contains('roi') ||
          key.contains('fee') ||
          key.contains('value')) return value.toDouble().toStringAsFixed(2);
    }
    return raw;
  }

  Future<void> _exportDocx() async {
    if (_busy) return;
    setState(() => _busy = true);

    String? tempPath;

    try {
      final db = await _getDatabase();
      final notes = await db.query('trade_notes', orderBy: 'id ASC');
      final trades = await db.query('trades', orderBy: 'trade_id ASC');

      final document = docx.loadDocxDocument();

      document.addHeading(
        text: 'گزارش یادداشت‌ها و معاملات',
        level: 1,
      );
      document.addParagraph(
        text: 'تاریخ تهیه: ${DateTime.now().toIso8601String()}',
      );

      document.addHeading(text: 'یادداشت‌ها', level: 1);

      for (final note in notes) {
        document.addHeading(
          text: (note['title'] ?? 'بدون عنوان').toString(),
          level: 2,
        );
        document.addParagraph(
          text: 'موضوع: ${(note['subject'] ?? '').toString()}',
        );
        document.addParagraph(
          text: (note['content'] ?? '').toString(),
        );
        final noteId = note['id'] as int?;
        if (noteId != null) {
          final mediaRows = await db.query('trade_note_media',
              where: 'note_id = ?',
              whereArgs: [noteId],
              orderBy: 'media_order ASC');
          for (final media in mediaRows) {
            final type = media['media_type']?.toString() ?? 'image';
            final path = media['file_path']?.toString() ?? '';
            final name = media['file_name']?.toString() ?? p.basename(path);
            if (type == 'image' &&
                path.isNotEmpty &&
                await File(path).exists()) {
              document.addParagraph(text: 'تصویر پیوست: $name');
              try {
                document.addPicture(path, width: Inches(4));
              } catch (_) {
                document.addParagraph(
                    text: 'تصویر اصلی در پشتیبان ZIP موجود است.');
              }
            } else {
              document.addParagraph(
                  text: 'فایل صوتی پیوست: $name (فایل اصلی همراه ZIP است)');
            }
          }
        }
      }

      document.addHeading(text: 'معاملات', level: 1);

      for (final trade in trades) {
        document.addHeading(
          text: 'معامله ${(trade['trade_id'] ?? '').toString()}',
          level: 2,
        );

        for (final entry in trade.entries) {
          document.addParagraph(
            text:
                '${_docxTradeLabel(entry.key)}: ${_docxTradeValue(entry.key, entry.value)}',
          );
        }
        final tradeId = trade['trade_id']?.toString();
        if (tradeId != null) {
          final images = await db.query('trade_images',
              where: 'trade_id = ?',
              whereArgs: [tradeId],
              orderBy: 'image_order ASC');
          if (images.isNotEmpty) {
            document.addHeading(
                text: 'تصاویر معامله (فایل‌های اصلی در پشتیبان ZIP)', level: 3);
            for (final image in images) {
              final imagePath = image['image_path']?.toString() ?? '';
              document.addParagraph(text: p.basename(imagePath));
              if (imagePath.isNotEmpty && await File(imagePath).exists()) {
                try {
                  document.addPicture(imagePath, width: Inches(4));
                } catch (_) {
                  document.addParagraph(
                      text: 'تصویر اصلی در پشتیبان ZIP موجود است.');
                }
              }
            }
          }
          final experiences = await db.query('trade_experiences',
              where: 'trade_id = ?', whereArgs: [tradeId]);
          if (experiences.isNotEmpty) {
            document.addHeading(text: 'تجربه‌های معامله', level: 3);
            for (final exp in experiences) {
              document.addParagraph(
                  text:
                      '${exp['experience_title'] ?? 'تجربه'}: ${exp['experience_description'] ?? ''}');
              final expId = exp['experience_id']?.toString();
              if (expId != null) {
                final expImages = await db.query('experience_images',
                    where: 'experience_id = ?',
                    whereArgs: [expId],
                    orderBy: 'image_order ASC');
                for (final expImage in expImages) {
                  final path = expImage['image_path']?.toString() ?? '';
                  if (path.isEmpty) continue;
                  document.addParagraph(
                      text: 'تصویر تجربه: ${p.basename(path)}');
                  if (await File(path).exists()) {
                    try {
                      document.addPicture(path, width: Inches(4));
                    } catch (_) {
                      document.addParagraph(
                          text: 'تصویر اصلی در پشتیبان ZIP موجود است.');
                    }
                  }
                }
              }
              final audio = exp['audio_paths']?.toString() ?? '[]';
              try {
                for (final path in (jsonDecode(audio) as List))
                  document.addParagraph(
                      text:
                          'ویس پیوست: ${p.basename(path.toString())} (فایل اصلی همراه ZIP است)');
              } catch (_) {}
            }
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      tempPath = p.join(
        tempDir.path,
        'trading_journal_${DateTime.now().microsecondsSinceEpoch}.docx',
      );

      document.save(tempPath);

      final outputBytes = await File(tempPath).readAsBytes();

      await _saveBytes(
        title: 'ذخیره سند Word',
        fileName: 'trading_journal_report.docx',
        extension: 'docx',
        bytes: Uint8List.fromList(outputBytes),
      );
    } catch (e) {
      _showMessage('خطا در تولید Word: $e');
    } finally {
      if (tempPath != null) {
        try {
          final file = File(tempPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }

      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importDocx() async {
    if (_busy) return;

    if (!await _confirm(
      'ورود سند Word',
      'متن سند به‌عنوان یک یادداشت جدید وارد می‌شود. '
          'این روش اطلاعات معاملات را از متن Word بازسازی نمی‌کند.',
      confirmText: 'انتخاب سند',
    )) {
      return;
    }

    setState(() => _busy = true);

    try {
      final bytes = await _pickBytes(
        title: 'انتخاب سند Word',
        extensions: ['docx'],
      );

      if (bytes == null) {
        _showMessage('فایلی انتخاب نشد.');
        return;
      }

      final content = docxToText(bytes);

      if (content.trim().isEmpty) {
        _showMessage('متن قابل‌خواندن در سند پیدا نشد.');
        return;
      }

      final db = await _getDatabase();
      final now = DateTime.now().toIso8601String();

      await db.insert('trade_notes', {
        'title': 'متن واردشده از Word',
        'content': content,
        'subject': '',
        'note_type': 'text',
        'asset_symbol': '',
        'trade_id': null,
        'source': 'docx_import',
        'source_file_name': 'imported.docx',
        'created_at': now,
        'updated_at': now,
      });

      _showMessage('متن Word به‌عنوان یادداشت جدید ذخیره شد.');
    } catch (e) {
      _showMessage('خطا در ورود Word: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildFormatCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onExport,
    required VoidCallback onImport,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : onExport,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('خروجی'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : onImport,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('ورود'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ورود و خروجی اطلاعات'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'انتقال و پشتیبان اطلاعات برنامه',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'JSON برای داده‌های ساختاریافته، TXT برای متن، '
                'Word برای گزارش قابل‌خواندن و ZIP برای پشتیبان '
                'کامل دیتابیس و فایل‌های رسانه‌ای طراحی شده‌اند. '
                'قبل از بازیابی، یک پشتیبان جداگانه نگه دار.',
              ),
              const SizedBox(height: 12),
              const Text('ورود و خروج سؤال‌ها و چک‌لیست‌ها (فایل متنی TXT)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _preTradeExportCard('questions'),
              _preTradeExportCard('psychology'),
              _preTradeExportCard('technical'),
              const SizedBox(height: 12),
              _buildFormatCard(
                icon: Icons.data_object,
                title: 'JSON',
                description: 'خروجی جدول‌های دیتابیس و افزودن اطلاعات '
                    'با حفظ شناسه‌ها. فایل‌های رسانه‌ای در JSON نیستند.',
                onExport: _exportJson,
                onImport: _importJson,
              ),
              _buildFormatCard(
                icon: Icons.description_outlined,
                title: 'TXT',
                description: 'خروجی متن یادداشت‌ها و معاملات. ورود TXT '
                    'فعلاً محتوای فایل را به‌عنوان یک یادداشت ذخیره می‌کند.',
                onExport: _exportTxt,
                onImport: _importTxt,
              ),
              _buildFormatCard(
                icon: Icons.article_outlined,
                title: 'Word (DOCX)',
                description: 'ساخت گزارش Word از یادداشت‌ها و معاملات. '
                    'ورود Word متن را به‌عنوان یادداشت ذخیره می‌کند.',
                onExport: _exportDocx,
                onImport: _importDocx,
              ),
              _buildFormatCard(
                icon: Icons.archive_outlined,
                title: 'ZIP — پشتیبان کامل',
                description: 'دیتابیس و فایل‌های رسانه‌ای موجود در مسیرهای '
                    'ثبت‌شده، همراه با امکان بازیابی.',
                onExport: _exportZip,
                onImport: _importZip,
              ),
              const SizedBox(height: 16),
              const Text(
                'توجه: پیش از بازیابی یک فایل بزرگ، '
                'از اطلاعات فعلی پشتیبان جداگانه بگیر.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
