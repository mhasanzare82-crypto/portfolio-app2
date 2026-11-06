// lib/repositories/note_tag_repository.dart

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class NoteTagRepository {
  NoteTagRepository._internal();

  static final NoteTagRepository instance = NoteTagRepository._internal();

  final AppDatabase _database = AppDatabase.instance;

  Future<int> createTag(
    String name,
  ) async {
    final value = name.trim();

    if (value.isEmpty) {
      throw Exception('نام برچسب نمی‌تواند خالی باشد.');
    }

    final db = await _database.database;

    final existing = await db.query(
      'note_tags',
      where: 'LOWER(tag_name) = LOWER(?)',
      whereArgs: [value],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['tag_id'] as int;
    }

    return db.insert(
      'note_tags',
      {
        'tag_name': value,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> updateTag({
    required int tagId,
    required String name,
  }) async {
    final value = name.trim();

    if (value.isEmpty) {
      throw Exception('نام برچسب نمی‌تواند خالی باشد.');
    }

    final db = await _database.database;

    final duplicate = await db.query(
      'note_tags',
      where: 'LOWER(tag_name) = LOWER(?) AND tag_id != ?',
      whereArgs: [value, tagId],
      limit: 1,
    );

    if (duplicate.isNotEmpty) {
      throw Exception('این برچسب قبلاً وجود دارد.');
    }

    await db.update(
      'note_tags',
      {'tag_name': value},
      where: 'tag_id = ?',
      whereArgs: [tagId],
    );
  }

  Future<void> deleteTag(
    int tagId,
  ) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.delete(
          'trade_note_tags',
          where: 'tag_id = ?',
          whereArgs: [tagId],
        );

        await transaction.delete(
          'note_tags',
          where: 'tag_id = ?',
          whereArgs: [tagId],
        );
      },
    );
  }

  Future<List<Map<String, Object?>>> getAllTags() async {
    final db = await _database.database;

    return db.query(
      'note_tags',
      orderBy: 'tag_name COLLATE NOCASE ASC',
    );
  }

  Future<List<Map<String, Object?>>> searchTags(
    String query,
  ) async {
    final db = await _database.database;

    return db.query(
      'note_tags',
      where: 'tag_name LIKE ?',
      whereArgs: ['%${query.trim()}%'],
      orderBy: 'tag_name COLLATE NOCASE ASC',
    );
  }

  Future<Map<String, Object?>?> getTag(
    int tagId,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'note_tags',
      where: 'tag_id = ?',
      whereArgs: [tagId],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  Future<void> addTagToNote({
    required int noteId,
    required int tagId,
  }) async {
    final db = await _database.database;

    await db.insert(
      'trade_note_tags',
      {
        'note_id': noteId,
        'tag_id': tagId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTagFromNote({
    required int noteId,
    required int tagId,
  }) async {
    final db = await _database.database;

    await db.delete(
      'trade_note_tags',
      where: 'note_id = ? AND tag_id = ?',
      whereArgs: [noteId, tagId],
    );
  }

  Future<List<Map<String, Object?>>> getTagsForNote(
    int noteId,
  ) async {
    final db = await _database.database;

    return db.rawQuery(
      '''
      SELECT t.*
      FROM note_tags t
      INNER JOIN trade_note_tags nt
        ON nt.tag_id = t.tag_id
      WHERE nt.note_id = ?
      ORDER BY t.tag_name COLLATE NOCASE ASC
      ''',
      [noteId],
    );
  }

  Future<List<Map<String, Object?>>> getNotesByTag(
    int tagId,
  ) async {
    final db = await _database.database;

    return db.rawQuery(
      '''
      SELECT n.*
      FROM trade_notes n
      INNER JOIN trade_note_tags nt
        ON nt.note_id = n.note_id
      WHERE nt.tag_id = ?
      ORDER BY n.title COLLATE NOCASE ASC
      ''',
      [tagId],
    );
  }

  Future<int> getNotesCount(
    int tagId,
  ) async {
    final db = await _database.database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM trade_note_tags
      WHERE tag_id = ?
      ''',
      [tagId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }
}
