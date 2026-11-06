import 'dart:convert';

class Experience {
  final String experienceId;
  final String tradeId;
  final String experienceTitle;
  final String experienceDescription;
  final List<String> imagePaths;
  final List<String> audioPaths;
  final DateTime experienceCreatedAt;

  const Experience({
    required this.experienceId,
    required this.tradeId,
    this.experienceTitle = '',
    this.experienceDescription = '',
    this.imagePaths = const [],
    this.audioPaths = const [],
    required this.experienceCreatedAt,
  });

  static List<String> _decodeAudioPaths(Object? raw) {
    try {
      return (jsonDecode(raw?.toString() ?? '[]') as List)
          .map((e) => e.toString())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'experience_id': experienceId,
      'trade_id': tradeId,
      'experience_title': experienceTitle,
      'experience_description': experienceDescription,
      'audio_paths': jsonEncode(audioPaths),
      'experience_created_at': experienceCreatedAt.toIso8601String(),
    };
  }

  factory Experience.fromMap(
    Map<String, dynamic> map, {
    List<String> imagePaths = const [],
    List<String>? audioPaths,
  }) {
    return Experience(
      experienceId: map['experience_id']?.toString() ?? '',
      tradeId: map['trade_id']?.toString() ?? '',
      experienceTitle: map['experience_title']?.toString() ?? '',
      experienceDescription: map['experience_description']?.toString() ?? '',
      imagePaths: imagePaths,
      audioPaths: audioPaths ?? _decodeAudioPaths(map['audio_paths']),
      experienceCreatedAt: DateTime.tryParse(
            map['experience_created_at']?.toString() ?? '',
          ) ??
          DateTime.now(),
    );
  }
}
