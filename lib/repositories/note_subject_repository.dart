// lib/repositories/note_subject_repository.dart

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class NoteSubjectRepository {
  NoteSubjectRepository._internal();

  static final NoteSubjectRepository instance =
      NoteSubjectRepository._internal();

  final AppDatabase _database = AppDatabase.instance;

  Future<int> createSubject({
    required String name,
    int? parentId,
  }) async {
    final value = name.trim();

    if (value.isEmpty) {
      throw Exception('نام موضوع نمی‌تواند خالی باشد.');
    }

    final db = await _database.database;

    final duplicate = await db.query(
      'note_subjects',
      where: '''
        LOWER(subject_name) = LOWER(?)
        AND (
          parent_id = ?
          OR (parent_id IS NULL AND ? IS NULL)
        )
      ''',
      whereArgs: [
        value,
        parentId,
        parentId,
      ],
      limit: 1,
    );

    if (duplicate.isNotEmpty) {
      throw Exception('این موضوع در این سطح قبلاً وجود دارد.');
    }

    final now = DateTime.now().toIso8601String();

    return db.insert(
      'note_subjects',
      {
        'subject_name': value,
        'parent_id': parentId,
        'created_at': now,
        'updated_at': now,
      },
    );
  }

  Future<void> updateSubject({
    required int subjectId,
    required String name,
  }) async {
    final value = name.trim();

    if (value.isEmpty) {
      throw Exception('نام موضوع نمی‌تواند خالی باشد.');
    }

    final db = await _database.database;

    final current = await getSubject(subjectId);

    if (current == null) {
      throw Exception('موضوع پیدا نشد.');
    }

    final parentId = current['parent_id'] as int?;

    final duplicate = await db.query(
      'note_subjects',
      where: '''
        LOWER(subject_name) = LOWER(?)
        AND subject_id != ?
        AND (
          parent_id = ?
          OR (parent_id IS NULL AND ? IS NULL)
        )
      ''',
      whereArgs: [
        value,
        subjectId,
        parentId,
        parentId,
      ],
      limit: 1,
    );

    if (duplicate.isNotEmpty) {
      throw Exception('موضوع مشابهی در این سطح وجود دارد.');
    }

    await db.update(
      'note_subjects',
      {
        'subject_name': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'subject_id = ?',
      whereArgs: [subjectId],
    );
  }

  Future<void> moveSubject({
    required int subjectId,
    int? parentId,
  }) async {
    if (parentId == subjectId) {
      throw Exception('یک موضوع نمی‌تواند والد خودش باشد.');
    }

    if (parentId != null &&
        await _isDescendant(
          parentId,
          subjectId,
        )) {
      throw Exception('انتقال به زیرموضوع خودش امکان‌پذیر نیست.');
    }

    final db = await _database.database;

    final current = await getSubject(subjectId);

    if (current == null) {
      throw Exception('موضوع پیدا نشد.');
    }

    final duplicate = await db.query(
      'note_subjects',
      where: '''
        LOWER(subject_name) = LOWER(?)
        AND subject_id != ?
        AND (
          parent_id = ?
          OR (parent_id IS NULL AND ? IS NULL)
        )
      ''',
      whereArgs: [
        current['subject_name'],
        subjectId,
        parentId,
        parentId,
      ],
      limit: 1,
    );

    if (duplicate.isNotEmpty) {
      throw Exception('موضوع مشابهی در مقصد وجود دارد.');
    }

    await db.update(
      'note_subjects',
      {
        'parent_id': parentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'subject_id = ?',
      whereArgs: [subjectId],
    );
  }

  Future<void> makeRootSubject(
    int subjectId,
  ) async {
    await moveSubject(
      subjectId: subjectId,
      parentId: null,
    );
  }

  Future<void> makeChildSubject({
    required int subjectId,
    required int parentId,
  }) async {
    await moveSubject(
      subjectId: subjectId,
      parentId: parentId,
    );
  }

  Future<void> deleteSubject(
    int subjectId,
  ) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.delete(
          'trade_note_subjects',
          where: 'subject_id = ?',
          whereArgs: [subjectId],
        );

        await transaction.update(
          'note_subjects',
          {
            'parent_id': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'parent_id = ?',
          whereArgs: [subjectId],
        );

        await transaction.delete(
          'note_subjects',
          where: 'subject_id = ?',
          whereArgs: [subjectId],
        );
      },
    );
  }

  Future<List<Map<String, Object?>>> getAllSubjects() async {
    final db = await _database.database;

    return db.query(
      'note_subjects',
      orderBy: 'subject_name COLLATE NOCASE ASC',
    );
  }

  Future<List<Map<String, Object?>>> getRootSubjects() async {
    final db = await _database.database;

    return db.query(
      'note_subjects',
      where: 'parent_id IS NULL',
      orderBy: 'subject_name COLLATE NOCASE ASC',
    );
  }

  Future<List<Map<String, Object?>>> getChildren(
    int parentId,
  ) async {
    final db = await _database.database;

    return db.query(
      'note_subjects',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'subject_name COLLATE NOCASE ASC',
    );
  }

  Future<Map<String, Object?>?> getSubject(
    int subjectId,
  ) async {
    final db = await _database.database;

    final result = await db.query(
      'note_subjects',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<List<Map<String, Object?>>> searchSubjects(
    String query,
  ) async {
    final db = await _database.database;

    return db.query(
      'note_subjects',
      where: 'subject_name LIKE ?',
      whereArgs: ['%${query.trim()}%'],
      orderBy: 'subject_name COLLATE NOCASE ASC',
    );
  }

  Future<int> getChildrenCount(
    int subjectId,
  ) async {
    final db = await _database.database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM note_subjects
      WHERE parent_id = ?
      ''',
      [subjectId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getNotesCount(
    int subjectId,
  ) async {
    final db = await _database.database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM trade_note_subjects
      WHERE subject_id = ?
      ''',
      [subjectId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<String> getSubjectPath(
    int subjectId,
  ) async {
    final names = <String>[];

    int? currentId = subjectId;

    while (currentId != null) {
      final subject = await getSubject(currentId);

      if (subject == null) {
        break;
      }

      names.insert(
        0,
        subject['subject_name']?.toString() ?? '',
      );

      currentId = subject['parent_id'] as int?;
    }

    return names.join(' / ');
  }

  Future<bool> _isDescendant(
    int candidateParentId,
    int subjectId,
  ) async {
    int? currentId = candidateParentId;

    while (currentId != null) {
      if (currentId == subjectId) {
        return true;
      }

      final row = await getSubject(currentId);

      if (row == null) {
        return false;
      }

      currentId = row['parent_id'] as int?;
    }

    return false;
  }
}
