import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/experience.dart';

class ExperienceRepository {
  ExperienceRepository({
    AppDatabase? database,
  }) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> createExperience(
    Experience experience,
  ) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.insert(
          'trade_experiences',
          experience.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (var index = 0; index < experience.imagePaths.length; index++) {
          await transaction.insert(
            'experience_images',
            {
              'experience_id': experience.experienceId,
              'image_path': experience.imagePaths[index],
              'image_order': index,
              'created_at': DateTime.now().toIso8601String(),
            },
          );
        }
      },
    );
  }

  Future<List<Experience>> getExperiencesForTrade(
    String tradeId,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'trade_experiences',
      where: 'trade_id = ?',
      whereArgs: [tradeId],
      orderBy: 'experience_created_at DESC',
    );

    final result = <Experience>[];

    for (final row in rows) {
      final experienceId = row['experience_id']?.toString() ?? '';

      final imageRows = await db.query(
        'experience_images',
        columns: ['image_path'],
        where: 'experience_id = ?',
        whereArgs: [experienceId],
        orderBy: 'image_order ASC',
      );

      final imagePaths = imageRows
          .map(
            (row) => row['image_path']?.toString() ?? '',
          )
          .where((path) => path.isNotEmpty)
          .toList();

      result.add(
        Experience.fromMap(
          row,
          imagePaths: imagePaths,
        ),
      );
    }

    return result;
  }

  Future<void> updateExperience(Experience experience) async {
    final db = await _database.database;
    await db.update(
      'trade_experiences',
      experience.toMap(),
      where: 'experience_id = ?',
      whereArgs: [experience.experienceId],
    );
    // تصویرها و ویس‌ها عمداً دست‌نخورده می‌مانند.
  }

  Future<void> deleteExperience(
    String experienceId,
  ) async {
    final db = await _database.database;

    await db.transaction(
      (transaction) async {
        await transaction.delete(
          'experience_images',
          where: 'experience_id = ?',
          whereArgs: [experienceId],
        );

        await transaction.delete(
          'trade_experiences',
          where: 'experience_id = ?',
          whereArgs: [experienceId],
        );
      },
    );
  }
}
