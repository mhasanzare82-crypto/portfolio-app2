class Asset {
  final int? assetId;
  final String assetSymbol;
  final String assetName;
  final bool assetEnabled;
  final DateTime createdAt;

  const Asset({
    this.assetId,
    required this.assetSymbol,
    this.assetName = '',
    this.assetEnabled = true,
    required this.createdAt,
  });

  String get symbol => assetSymbol;

  String get name => assetName;

  bool get enabled => assetEnabled;

  Map<String, dynamic> toMap() {
    return {
      if (assetId != null) 'asset_id': assetId,
      'asset_symbol': assetSymbol,
      'asset_name': assetName,
      'asset_enabled': assetEnabled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Asset.fromMap(
    Map<String, dynamic> map,
  ) {
    return Asset(
      assetId: _toInt(
        map['asset_id'],
      ),
      assetSymbol: map['asset_symbol']?.toString() ?? '',
      assetName: map['asset_name']?.toString() ?? '',
      assetEnabled: _toBool(
        map['asset_enabled'],
      ),
      createdAt: DateTime.tryParse(
            map['created_at']?.toString() ?? '',
          ) ??
          DateTime.now(),
    );
  }

  Asset copyWith({
    int? assetId,
    String? assetSymbol,
    String? assetName,
    bool? assetEnabled,
    DateTime? createdAt,
  }) {
    return Asset(
      assetId: assetId ?? this.assetId,
      assetSymbol: assetSymbol ?? this.assetSymbol,
      assetName: assetName ?? this.assetName,
      assetEnabled: assetEnabled ?? this.assetEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static int? _toInt(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(
      value.toString(),
    );
  }

  static bool _toBool(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is int) {
      return value == 1;
    }

    final text = value?.toString().toLowerCase();

    return text == '1' || text == 'true';
  }
}
