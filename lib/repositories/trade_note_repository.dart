import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class TradeNoteRepository {
  TradeNoteRepository._();

  static final TradeNoteRepository instance = TradeNoteRepository._();

  final AppDatabase _database = AppDatabase.instance;

  Future<Database> get _db async => _database.database;

  // CREATE NOTE

  Future<int> createNote({
    required String title,
    required String content,
    String? subject,
    String? noteType,
    String? assetSymbol,
    int? tradeId,
    String? source,
    String? sourceFileName,
    List<int>? subjectIds,
    List<int>? tagIds,
    List<int>? tags,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final id = await db.insert('trade_notes', {
      'title': title.trim(),
      'content': content,
      'subject': subject?.trim().isEmpty == true ? null : subject?.trim(),
      'note_type':
          noteType?.trim().isEmpty == true ? 'عمومی' : (noteType ?? 'عمومی'),
      'asset_symbol':
          assetSymbol?.trim().isEmpty == true ? null : assetSymbol?.trim(),
      'trade_id': tradeId,
      'source': source,
      'source_file_name': sourceFileName,
      'created_at': now,
      'updated_at': now,
    });

    if (subjectIds != null && subjectIds.isNotEmpty) {
      await setNoteSubjects(id, subjectIds);
    }

    final finalTagIds = <int>{...?tagIds, ...?tags}.toList();

    if (finalTagIds.isNotEmpty) {
      await setNoteTags(id, finalTagIds);
    }

    if ((subject == null || subject.trim().isEmpty) &&
        subjectIds != null &&
        subjectIds.isNotEmpty) {
      await _syncLegacySubjectColumn(id, subjectIds.first);
    }

    return id;
  }

  // UPDATE NOTE

  Future<int> updateNote({
    required int noteId,
    String? title,
    String? content,
    String? subject,
    String? noteType,
    String? assetSymbol,
    int? tradeId,
    String? source,
    String? sourceFileName,
    List<int>? subjectIds,
    List<int>? tagIds,
  }) async {
    final db = await _db;

    final values = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (title != null) values['title'] = title.trim();
    if (content != null) values['content'] = content;
    if (subject != null) {
      values['subject'] = subject.trim().isEmpty ? null : subject.trim();
    }
    if (noteType != null) {
      values['note_type'] = noteType.trim().isEmpty ? 'عمومی' : noteType.trim();
    }
    if (assetSymbol != null) {
      values['asset_symbol'] =
          assetSymbol.trim().isEmpty ? null : assetSymbol.trim();
    }
    if (tradeId != null) values['trade_id'] = tradeId;
    if (source != null) values['source'] = source;
    if (sourceFileName != null) values['source_file_name'] = sourceFileName;

    final result = await db.update(
      'trade_notes',
      values,
      where: 'id = ?',
      whereArgs: [noteId],
    );

    if (subjectIds != null) {
      await setNoteSubjects(noteId, subjectIds);
    }

    if (tagIds != null) {
      await setNoteTags(noteId, tagIds);
    }

    if (subjectIds != null && subjectIds.isEmpty) {
      await db.update(
        'trade_notes',
        {
          'subject': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [noteId],
      );
    }

    return result;
  }

  // GET ALL NOTES

  Future<List<Map<String, dynamic>>> getAllNotes() async {
    final db = await _db;

    return db.query(
      'trade_notes',
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
  }

  // GET NOTE

  Future<Map<String, dynamic>?> getNote(int noteId) async {
    final db = await _db;

    final result = await db.query(
      'trade_notes',
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  // SEARCH NOTES: هر واژه می‌تواند در یکی از فیلدها پیدا شود.

  Future<List<Map<String, dynamic>>> searchNotes(String query) async {
    final db = await _db;
    final words = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) return getAllNotes();

    final conditions = <String>[];
    final args = <Object?>[];

    for (final word in words) {
      final like = '%$word%';
      conditions.add('''
        (
          n.title LIKE ? COLLATE NOCASE OR
          n.content LIKE ? COLLATE NOCASE OR
          n.subject LIKE ? COLLATE NOCASE OR
          n.asset_symbol LIKE ? COLLATE NOCASE OR
          s.subject_name LIKE ? COLLATE NOCASE OR
          t.tag_name LIKE ? COLLATE NOCASE
        )
      ''');
      args.addAll(List<Object?>.filled(6, like));
    }

    return db.rawQuery(
      '''
      SELECT DISTINCT n.*
      FROM trade_notes n
      LEFT JOIN trade_note_subjects ns ON ns.note_id = n.id
      LEFT JOIN note_subjects s ON s.subject_id = ns.subject_id
      LEFT JOIN trade_note_tags nt ON nt.note_id = n.id
      LEFT JOIN note_tags t ON t.tag_id = nt.tag_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY n.title COLLATE NOCASE ASC, n.id ASC
      ''',
      args,
    );
  }

  // NOTES BY SUBJECT

  Future<List<Map<String, dynamic>>> getNotesBySubjectId(int subjectId) async {
    final db = await _db;

    return db.rawQuery(
      '''
      SELECT n.*
      FROM trade_notes n
      INNER JOIN trade_note_subjects ns ON ns.note_id = n.id
      WHERE ns.subject_id = ?
      ORDER BY n.title COLLATE NOCASE ASC, n.id ASC
      ''',
      [subjectId],
    );
  }

  Future<List<Map<String, dynamic>>> getNotesBySubject(String subject) async {
    final db = await _db;

    return db.rawQuery(
      '''
      SELECT DISTINCT n.*
      FROM trade_notes n
      LEFT JOIN trade_note_subjects ns ON ns.note_id = n.id
      LEFT JOIN note_subjects s ON s.subject_id = ns.subject_id
      WHERE n.subject = ? OR s.subject_name = ?
      ORDER BY n.title COLLATE NOCASE ASC, n.id ASC
      ''',
      [subject, subject],
    );
  }

  // NOTES BY TAG

  Future<List<Map<String, dynamic>>> getNotesByTagId(int tagId) async {
    final db = await _db;

    return db.rawQuery(
      '''
      SELECT n.*
      FROM trade_notes n
      INNER JOIN trade_note_tags nt ON nt.note_id = n.id
      WHERE nt.tag_id = ?
      ORDER BY n.title COLLATE NOCASE ASC, n.id ASC
      ''',
      [tagId],
    );
  }

  Future<List<Map<String, dynamic>>> getNotesByTag(String tagName) async {
    final db = await _db;

    return db.rawQuery(
      '''
      SELECT n.*
      FROM trade_notes n
      INNER JOIN trade_note_tags nt ON nt.note_id = n.id
      INNER JOIN note_tags t ON t.tag_id = nt.tag_id
      WHERE t.tag_name = ?
      ORDER BY n.title COLLATE NOCASE ASC, n.id ASC
      ''',
      [tagName],
    );
  }

  // NOTES BY ASSET

  Future<List<Map<String, dynamic>>> getNotesByAsset(String assetSymbol) async {
    final db = await _db;

    return db.query(
      'trade_notes',
      where: 'asset_symbol = ?',
      whereArgs: [assetSymbol],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
  }

  // NOTES BY TRADE

  Future<List<Map<String, dynamic>>> getNotesByTrade(int tradeId) async {
    final db = await _db;

    return db.query(
      'trade_notes',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
  }

  // DELETE NOTE

  Future<int> deleteNote(int noteId) async {
    final media = await getMediaForNote(noteId);

    for (final item in media) {
      final path = item['file_path']?.toString();
      if (path == null || path.isEmpty) continue;

      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    final directory = await getNoteStorageDirectory(noteId);

    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}

    final db = await _db;

    return db.delete(
      'trade_notes',
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  // NOTES BY TYPE

  Future<List<Map<String, dynamic>>> getNotesByType(String noteType) async {
    final db = await _db;

    return db.query(
      'trade_notes',
      where: 'note_type = ?',
      whereArgs: [noteType],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
  }

  // SUBJECTS FOR NOTE

  Future<List<Map<String, dynamic>>> getSubjectsForNote(int noteId) async {
    final db = await _db;

    return db.rawQuery(
      '''
      SELECT s.*
      FROM note_subjects s
      INNER JOIN trade_note_subjects ns ON ns.subject_id = s.subject_id
      WHERE ns.note_id = ?
      ORDER BY s.subject_name COLLATE NOCASE ASC
      ''',
      [noteId],
    );
  }

  Future<List<int>> getSubjectIdsForNote(int noteId) async {
    final db = await _db;

    final rows = await db.query(
      'trade_note_subjects',
      columns: ['subject_id'],
      where: 'note_id = ?',
      whereArgs: [noteId],
    );

    return rows.map((row) => row['subject_id'] as int).toList();
  }

  Future<List<String>> getSubjectNamesForNote(int noteId) async {
    final rows = await getSubjectsForNote(noteId);

    final names = rows
        .map((row) => row['subject_name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();

    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  // ADD SUBJECT TO NOTE

  Future<void> addSubjectToNote(int noteId, int subjectId) async {
    final db = await _db;

    await db.insert(
      'trade_note_subjects',
      {'note_id': noteId, 'subject_id': subjectId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await _syncLegacySubjectColumn(noteId, subjectId);
  }

  // REMOVE SUBJECT FROM NOTE

  Future<void> removeSubjectFromNote(int noteId, int subjectId) async {
    final db = await _db;

    await db.delete(
      'trade_note_subjects',
      where: 'note_id = ? AND subject_id = ?',
      whereArgs: [noteId, subjectId],
    );

    final ids = await getSubjectIdsForNote(noteId);

    if (ids.isEmpty) {
      await db.update(
        'trade_notes',
        {
          'subject': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [noteId],
      );
    } else {
      await _syncLegacySubjectColumn(noteId, ids.first);
    }
  }

  // SET SUBJECTS

  Future<void> setNoteSubjects(int noteId, List<int> subjectIds) async {
    final db = await _db;

    await db.transaction((txn) async {
      await txn.delete(
        'trade_note_subjects',
        where: 'note_id = ?',
        whereArgs: [noteId],
      );

      for (final subjectId in subjectIds.toSet()) {
        await txn.insert(
          'trade_note_subjects',
          {
            'note_id': noteId,
            'subject_id': subjectId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    if (subjectIds.isEmpty) {
      await db.update(
        'trade_notes',
        {
          'subject': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [noteId],
      );
    } else {
      await _syncLegacySubjectColumn(noteId, subjectIds.first);
    }
  }

  // GET SUBJECT IDS FOR NOTE

  Future<List<int>> getNoteSubjectIds(int noteId) async {
    final db = await _db;

    final rows = await db.query(
      'trade_note_subjects',
      columns: ['subject_id'],
      where: 'note_id = ?',
      whereArgs: [noteId],
    );

    return rows.map((row) => (row['subject_id'] as num).toInt()).toList();
  }

  // TAGS FOR NOTE

  Future<List<Map<String, dynamic>>> getTagsForNote(int noteId) async {
    final db = await _db;

    return db.rawQuery(
      '''
      SELECT t.*
      FROM note_tags t
      INNER JOIN trade_note_tags nt ON nt.tag_id = t.tag_id
      WHERE nt.note_id = ?
      ORDER BY t.tag_name COLLATE NOCASE ASC
      ''',
      [noteId],
    );
  }

  Future<List<String>> getTagNamesForNote(int noteId) async {
    final rows = await getTagsForNote(noteId);

    final names = rows
        .map((row) => row['tag_name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();

    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<List<int>> getTagIdsForNote(int noteId) async {
    final db = await _db;

    final rows = await db.query(
      'trade_note_tags',
      columns: ['tag_id'],
      where: 'note_id = ?',
      whereArgs: [noteId],
    );

    return rows.map((row) => row['tag_id'] as int).toList();
  }

  // ADD TAG

  Future<void> addTagToNote(int noteId, int tagId) async {
    final db = await _db;

    await db.insert(
      'trade_note_tags',
      {'note_id': noteId, 'tag_id': tagId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // REMOVE TAG

  Future<void> removeTagFromNote(int noteId, int tagId) async {
    final db = await _db;

    await db.delete(
      'trade_note_tags',
      where: 'note_id = ? AND tag_id = ?',
      whereArgs: [noteId, tagId],
    );
  }

  // SET TAGS

  Future<void> setNoteTags(int noteId, List<int> tagIds) async {
    final db = await _db;

    await db.transaction((txn) async {
      await txn.delete(
        'trade_note_tags',
        where: 'note_id = ?',
        whereArgs: [noteId],
      );

      for (final tagId in tagIds.toSet()) {
        await txn.insert(
          'trade_note_tags',
          {'note_id': noteId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  // ALL TAGS

  Future<List<Map<String, dynamic>>> getAllTags() async {
    final db = await _db;

    return db.query(
      'note_tags',
      orderBy: 'tag_name COLLATE NOCASE ASC, tag_id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getTagObjects() => getAllTags();

  // ALL SUBJECTS

  Future<List<Map<String, dynamic>>> getAllNoteSubjects() async {
    final db = await _db;

    return db.query(
      'note_subjects',
      orderBy: 'subject_name COLLATE NOCASE ASC, subject_id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getRootNoteSubjects() async {
    final db = await _db;

    return db.query(
      'note_subjects',
      where: 'parent_id IS NULL',
      orderBy: 'subject_name COLLATE NOCASE ASC, subject_id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getChildNoteSubjects(int parentId) async {
    final db = await _db;

    return db.query(
      'note_subjects',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'subject_name COLLATE NOCASE ASC, subject_id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> searchNoteSubjects(String query) async {
    final db = await _db;
    final text = query.trim();

    if (text.isEmpty) return getAllNoteSubjects();

    return db.query(
      'note_subjects',
      where: 'subject_name LIKE ?',
      whereArgs: ['%$text%'],
      orderBy: 'subject_name COLLATE NOCASE ASC',
    );
  }

  Future<List<Map<String, dynamic>>> searchNoteMatches(
    String query,
  ) async {
    final text = query.trim();
    if (text.isEmpty) return [];

    final notes = await getAllNotes();
    final results = <Map<String, dynamic>>[];

    final normalizedQuery = text.toLowerCase();

    for (final note in notes) {
      final rawId = note['id'];
      if (rawId is! num) continue;

      final noteId = rawId.toInt();

      final subjects = await getSubjectNamesForNote(noteId);
      final tags = await getTagNamesForNote(noteId);

      final fields = <Map<String, String>>[
        {
          'field': 'title',
          'label': 'عنوان',
          'text': note['title']?.toString() ?? '',
        },
        {
          'field': 'content',
          'label': 'متن یادداشت',
          'text': note['content']?.toString() ?? '',
        },
        {
          'field': 'subject',
          'label': 'موضوع',
          'text': note['subject']?.toString() ?? '',
        },
        {
          'field': 'asset_symbol',
          'label': 'دارایی',
          'text': note['asset_symbol']?.toString() ?? '',
        },
        ...subjects.map(
          (subject) => {
            'field': 'subject',
            'label': 'موضوع: $subject',
            'text': subject,
          },
        ),
        ...tags.map(
          (tag) => {
            'field': 'tag',
            'label': 'برچسب: $tag',
            'text': tag,
          },
        ),
      ];

      for (final field in fields) {
        final fieldText = field['text'] ?? '';
        final lowerText = fieldText.toLowerCase();

        var start = 0;

        while (start < lowerText.length) {
          final index = lowerText.indexOf(normalizedQuery, start);
          if (index < 0) break;

          results.add({
            'note': Map<String, dynamic>.from(note),
            'note_id': noteId,
            'field': field['field'],
            'field_label': field['label'],
            'matched_text': fieldText,
            'match_start': index,
            'match_end': index + text.length,
            'query': text,
          });

          start = index + normalizedQuery.length;
        }
      }
    }

    results.sort((a, b) {
      final aTitle = a['note']['title']?.toString().toLowerCase() ?? '';
      final bTitle = b['note']['title']?.toString().toLowerCase() ?? '';

      final titleCompare = aTitle.compareTo(bTitle);
      if (titleCompare != 0) return titleCompare;

      final idCompare = (a['note_id'] as int).compareTo(b['note_id'] as int);
      if (idCompare != 0) return idCompare;

      final fieldCompare = (a['field_label'] as String).compareTo(
        b['field_label'] as String,
      );

      if (fieldCompare != 0) return fieldCompare;

      return (a['match_start'] as int).compareTo(
        b['match_start'] as int,
      );
    });

    return results;
  }
  // MEDIA

  Future<List<Map<String, dynamic>>> getMediaForNote(int noteId) async {
    final db = await _db;

    return db.query(
      'trade_note_media',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'media_order ASC, media_id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getImagesForNote(int noteId) async {
    final db = await _db;

    return db.query(
      'trade_note_media',
      where: 'note_id = ? AND media_type = ?',
      whereArgs: [noteId, 'image'],
      orderBy: 'media_order ASC, media_id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAudioForNote(int noteId) async {
    final db = await _db;

    return db.query(
      'trade_note_media',
      where: 'note_id = ? AND media_type = ?',
      whereArgs: [noteId, 'audio'],
      orderBy: 'media_order ASC, media_id ASC',
    );
  }

  // ADD MEDIA

  Future<int> addMedia({
    required int noteId,
    required String mediaType,
    required String filePath,
    String? fileName,
    int? mediaOrder,
  }) async {
    final db = await _db;
    final type = mediaType.trim().toLowerCase();

    if (type != 'image' && type != 'audio') {
      throw Exception('نوع رسانه باید image یا audio باشد.');
    }

    final existing = await db.query(
      'trade_note_media',
      columns: ['media_order'],
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'media_order DESC',
      limit: 1,
    );

    final order = mediaOrder ??
        (existing.isEmpty
            ? 0
            : ((existing.first['media_order'] as int?) ?? 0) + 1);

    return db.insert('trade_note_media', {
      'note_id': noteId,
      'media_type': type,
      'file_path': filePath,
      'file_name': fileName ?? p.basename(filePath),
      'media_order': order,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateMediaPath({
    required int mediaId,
    required String filePath,
    String? fileName,
  }) async {
    final db = await _db;
    await db.update(
      'trade_note_media',
      {'file_path': filePath, if (fileName != null) 'file_name': fileName},
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
  }

  // DELETE MEDIA

  Future<int> deleteMedia(int mediaId) async {
    final db = await _db;

    final rows = await db.query(
      'trade_note_media',
      where: 'media_id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final path = rows.first['file_path']?.toString();

      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }

    final result = await db.delete(
      'trade_note_media',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );

    if (rows.isNotEmpty) {
      await _reorderMedia(rows.first['note_id'] as int);
    }

    return result;
  }

  // REORDER MEDIA

  Future<void> reorderMedia(int noteId, List<int> mediaIds) async {
    final db = await _db;

    await db.transaction((txn) async {
      for (var i = 0; i < mediaIds.length; i++) {
        await txn.update(
          'trade_note_media',
          {'media_order': i},
          where: 'media_id = ? AND note_id = ?',
          whereArgs: [mediaIds[i], noteId],
        );
      }
    });
  }

  // COPY MEDIA TO NOTE STORAGE

  Future<String> copyMediaToNoteStorage({
    required int noteId,
    required String sourcePath,
    String? mediaType,
    String? fileName,
    String? extension,
  }) async {
    if (noteId <= 0) throw Exception('شناسه یادداشت نامعتبر است.');
    if (sourcePath.trim().isEmpty)
      throw Exception('مسیر فایل رسانه مشخص نیست.');

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('فایل رسانه پیدا نشد:\n$sourcePath');
    }

    var type = (mediaType ?? '').trim().toLowerCase();

    if (type != 'image' && type != 'audio') {
      const imageExtensions = [
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.gif',
        '.bmp',
        '.heic',
      ];
      type =
          imageExtensions.contains(p.extension(sourceFile.path).toLowerCase())
              ? 'image'
              : 'audio';
    }

    var finalExtension = extension?.trim() ?? '';
    if (finalExtension.isEmpty) finalExtension = p.extension(sourceFile.path);
    if (finalExtension.isEmpty)
      finalExtension = type == 'image' ? '.jpg' : '.m4a';
    if (!finalExtension.startsWith('.')) finalExtension = '.$finalExtension';

    final targetPath = await createMediaFilePath(
      noteId: noteId,
      mediaType: type,
      extension: finalExtension,
    );

    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    await sourceFile.copy(targetPath);

    return targetPath;
  }

  // MEDIA DIRECTORIES

  Future<Directory> getNoteStorageDirectory(int noteId) async {
    final appDirectory = await getApplicationDocumentsDirectory();

    return Directory(p.join(
      appDirectory.path,
      'trade_notes',
      noteId.toString(),
    ));
  }

  Future<Directory> getNoteMediaDirectory(int noteId, String mediaType) async {
    final noteDirectory = await getNoteStorageDirectory(noteId);
    final type = mediaType.trim().toLowerCase();

    return Directory(p.join(
      noteDirectory.path,
      type == 'image' ? 'images' : 'audio',
    ));
  }

  Future<String> createMediaFilePath({
    required int noteId,
    required String mediaType,
    required String extension,
  }) async {
    final directory = await getNoteMediaDirectory(noteId, mediaType);
    await directory.create(recursive: true);

    final cleanExtension =
        extension.startsWith('.') ? extension : '.$extension';
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final type = mediaType.trim().toLowerCase();

    final fileName = type == 'image'
        ? 'image_$timestamp$cleanExtension'
        : 'audio_$timestamp$cleanExtension';

    return p.join(directory.path, fileName);
  }

  // MEDIA COUNTS

  Future<int> getMediaCount(int noteId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM trade_note_media WHERE note_id = ?',
      [noteId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getImageCount(int noteId) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM trade_note_media
      WHERE note_id = ? AND media_type = 'image'
      ''',
      [noteId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getAudioCount(int noteId) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM trade_note_media
      WHERE note_id = ? AND media_type = 'audio'
      ''',
      [noteId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // EXPORT ALL NOTES AS TEXT

  Future<String> exportAllNotesAsText() async {
    final notes = await getAllNotes();
    final buffer = StringBuffer();

    for (final note in notes) {
      final id = note['id'] as int;
      final title = note['title']?.toString() ?? '';
      final content = note['content']?.toString() ?? '';
      final asset = note['asset_symbol']?.toString() ?? '';
      final subjects = await getSubjectNamesForNote(id);
      final tags = await getTagNamesForNote(id);

      buffer.writeln(
          '============================================================');
      buffer.writeln('عنوان: $title');

      if (asset.trim().isNotEmpty) buffer.writeln('دارایی: $asset');
      if (subjects.isNotEmpty)
        buffer.writeln('موضوعات: ${subjects.join('، ')}');
      if (tags.isNotEmpty) buffer.writeln('برچسب‌ها: ${tags.join('، ')}');

      buffer.writeln();
      buffer.writeln(content);
      buffer.writeln();

      final media = await getMediaForNote(id);
      if (media.isNotEmpty) {
        buffer.writeln('رسانه‌ها:');
        for (final item in media) {
          buffer.writeln('- ${item['media_type']}: ${item['file_path']}');
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  // EXPORT ONE NOTE AS TEXT

  Future<String> exportNoteAsText(int noteId) async {
    final note = await getNote(noteId);
    if (note == null) throw Exception('یادداشت پیدا نشد.');

    final title = note['title']?.toString() ?? '';
    final content = note['content']?.toString() ?? '';
    final asset = note['asset_symbol']?.toString() ?? '';
    final subjects = await getSubjectNamesForNote(noteId);
    final tags = await getTagNamesForNote(noteId);
    final media = await getMediaForNote(noteId);

    final buffer = StringBuffer();
    buffer.writeln('عنوان: $title');

    if (asset.trim().isNotEmpty) buffer.writeln('دارایی: $asset');
    if (subjects.isNotEmpty) buffer.writeln('موضوعات: ${subjects.join('، ')}');
    if (tags.isNotEmpty) buffer.writeln('برچسب‌ها: ${tags.join('، ')}');

    buffer.writeln();
    buffer.writeln(content);

    if (media.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('رسانه‌ها:');
      for (final item in media) {
        buffer.writeln('- ${item['media_type']}: ${item['file_path']}');
      }
    }

    return buffer.toString();
  }

  // PRIVATE HELPERS

  Future<void> _syncLegacySubjectColumn(int noteId, int subjectId) async {
    final db = await _db;

    final rows = await db.query(
      'note_subjects',
      columns: ['subject_name'],
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      limit: 1,
    );

    if (rows.isEmpty) return;

    await db.update(
      'trade_notes',
      {
        'subject': rows.first['subject_name']?.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  Future<void> _reorderMedia(int noteId) async {
    final db = await _db;

    final rows = await db.query(
      'trade_note_media',
      columns: ['media_id'],
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'media_order ASC, media_id ASC',
    );

    await db.transaction((txn) async {
      for (var i = 0; i < rows.length; i++) {
        await txn.update(
          'trade_note_media',
          {'media_order': i},
          where: 'media_id = ?',
          whereArgs: [rows[i]['media_id']],
        );
      }
    });
  }
}
