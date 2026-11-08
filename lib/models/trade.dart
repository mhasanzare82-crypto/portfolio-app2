enum TradeDirection {
  long,
  short,
}

enum TradeType {
  scalp,
  day,
}

enum TradeStatus {
  open,
  closed,
}

class Trade {
  final String tradeId;

  final String assetSymbol;
  final TradeDirection tradeDirection;
  final TradeType tradeType;
  final TradeStatus tradeStatus;
  final String tradeTimeframe;
  final String marginMode;

  final double marginAmount;
  final double leverageValue;
  final double volumeAmount;
  /// USD-to-Toman exchange rate captured when the trade is created.
  final double dollarRate;

  final double feePerHundred;
  final double tradeFee;

  final double? entryPrice;
  final double? exitPrice;
  final double? stopPrice;
  final double? targetPrice;

  final double riskDistance;
  final double rewardDistance;

  final double riskValue;
  final double rewardValue;

  final double tradeRiskReward;

  // =========================================================
  // FINAL / LIVE TRADE RESULTS
  // =========================================================

  /// سود یا ضرر نهایی معامله بر اساس قیمت ورود و خروج.
  final double finalPnl;

  /// بازده معامله نسبت به Margin.
  /// مثال: Margin = 100 و PNL = 20 => 20%
  final double finalRoiPercent;

  /// مقدار دلاری سود/ضرر نسبت به Margin.
  final double finalRoiDollar;

  /// R:R نهایی در لحظه بسته شدن معامله.
  final double finalRiskReward;

  /// بیشترین افت قیمت از نقطه ورود.
  final double maxDrawdownPricePercent;

  /// بیشترین Drawdown به دلار.
  final double maxDrawdownDollar;

  /// بیشترین Drawdown نسبت به Margin.
  final double maxDrawdownMarginPercent;

  /// مدت زمان معامله بر حسب ثانیه.
  final int durationSeconds;

  final String entrySetup;
  final String entryReason;
  final String entryMotivation;
  final String expectedScenario;

  final List<String> imagePaths;

  final DateTime entryTime;
  final DateTime? exitTime;

  const Trade({
    required this.tradeId,
    required this.assetSymbol,
    required this.tradeDirection,
    required this.tradeType,
    required this.tradeStatus,
    required this.tradeTimeframe,
    this.marginMode = 'isolated',
    this.marginAmount = 0.0,
    this.leverageValue = 0.0,
    this.volumeAmount = 0.0,
    this.dollarRate = 0.0,
    this.feePerHundred = 0.0,
    this.tradeFee = 0.0,
    this.entryPrice,
    this.exitPrice,
    this.stopPrice,
    this.targetPrice,
    this.riskDistance = 0.0,
    this.rewardDistance = 0.0,
    this.riskValue = 0.0,
    this.rewardValue = 0.0,
    this.tradeRiskReward = 0.0,
    this.finalPnl = 0.0,
    this.finalRoiPercent = 0.0,
    this.finalRoiDollar = 0.0,
    this.finalRiskReward = 0.0,
    this.maxDrawdownPricePercent = 0.0,
    this.maxDrawdownDollar = 0.0,
    this.maxDrawdownMarginPercent = 0.0,
    this.durationSeconds = 0,
    this.entrySetup = '',
    this.entryReason = '',
    this.entryMotivation = '',
    this.expectedScenario = '',
    this.imagePaths = const [],
    required this.entryTime,
    this.exitTime,
  });

  String get id => tradeId;

  String get symbol => assetSymbol;

  TradeDirection get direction => tradeDirection;

  TradeType get type => tradeType;

  TradeStatus get status => tradeStatus;

  String get timeframe => tradeTimeframe;

  double get margin => marginAmount;

  double get leverage => leverageValue;

  double get volume => volumeAmount;

  // =========================================================
  // COPY WITH
  // =========================================================

  Trade copyWith({
    String? tradeId,
    String? assetSymbol,
    TradeDirection? tradeDirection,
    TradeType? tradeType,
    TradeStatus? tradeStatus,
    String? tradeTimeframe,
    String? marginMode,
    double? marginAmount,
    double? leverageValue,
    double? volumeAmount,
    double? dollarRate,
    double? feePerHundred,
    double? tradeFee,
    Object? entryPrice = _copyWithUnset,
    Object? exitPrice = _copyWithUnset,
    Object? stopPrice = _copyWithUnset,
    Object? targetPrice = _copyWithUnset,
    double? riskDistance,
    double? rewardDistance,
    double? riskValue,
    double? rewardValue,
    double? tradeRiskReward,
    double? finalPnl,
    double? finalRoiPercent,
    double? finalRoiDollar,
    double? finalRiskReward,
    double? maxDrawdownPricePercent,
    double? maxDrawdownDollar,
    double? maxDrawdownMarginPercent,
    int? durationSeconds,
    String? entrySetup,
    String? entryReason,
    String? entryMotivation,
    String? expectedScenario,
    List<String>? imagePaths,
    DateTime? entryTime,
    Object? exitTime = _copyWithUnset,
  }) {
    return Trade(
      tradeId: tradeId ?? this.tradeId,
      assetSymbol: assetSymbol ?? this.assetSymbol,
      tradeDirection: tradeDirection ?? this.tradeDirection,
      tradeType: tradeType ?? this.tradeType,
      tradeStatus: tradeStatus ?? this.tradeStatus,
      tradeTimeframe: tradeTimeframe ?? this.tradeTimeframe,
      marginMode: marginMode ?? this.marginMode,
      marginAmount: marginAmount ?? this.marginAmount,
      leverageValue: leverageValue ?? this.leverageValue,
      volumeAmount: volumeAmount ?? this.volumeAmount,
      dollarRate: dollarRate ?? this.dollarRate,
      feePerHundred: feePerHundred ?? this.feePerHundred,
      tradeFee: tradeFee ?? this.tradeFee,
      entryPrice: entryPrice == _copyWithUnset
          ? this.entryPrice
          : entryPrice as double?,
      exitPrice:
          exitPrice == _copyWithUnset ? this.exitPrice : exitPrice as double?,
      stopPrice:
          stopPrice == _copyWithUnset ? this.stopPrice : stopPrice as double?,
      targetPrice: targetPrice == _copyWithUnset
          ? this.targetPrice
          : targetPrice as double?,
      riskDistance: riskDistance ?? this.riskDistance,
      rewardDistance: rewardDistance ?? this.rewardDistance,
      riskValue: riskValue ?? this.riskValue,
      rewardValue: rewardValue ?? this.rewardValue,
      tradeRiskReward: tradeRiskReward ?? this.tradeRiskReward,
      finalPnl: finalPnl ?? this.finalPnl,
      finalRoiPercent: finalRoiPercent ?? this.finalRoiPercent,
      finalRoiDollar: finalRoiDollar ?? this.finalRoiDollar,
      finalRiskReward: finalRiskReward ?? this.finalRiskReward,
      maxDrawdownPricePercent:
          maxDrawdownPricePercent ?? this.maxDrawdownPricePercent,
      maxDrawdownDollar: maxDrawdownDollar ?? this.maxDrawdownDollar,
      maxDrawdownMarginPercent:
          maxDrawdownMarginPercent ?? this.maxDrawdownMarginPercent,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      entrySetup: entrySetup ?? this.entrySetup,
      entryReason: entryReason ?? this.entryReason,
      entryMotivation: entryMotivation ?? this.entryMotivation,
      expectedScenario: expectedScenario ?? this.expectedScenario,
      imagePaths: imagePaths ?? this.imagePaths,
      entryTime: entryTime ?? this.entryTime,
      exitTime:
          exitTime == _copyWithUnset ? this.exitTime : exitTime as DateTime?,
    );
  }

  // =========================================================
  // TO MAP
  // =========================================================

  Map<String, dynamic> toMap() {
    return {
      'trade_id': tradeId,
      'asset_symbol': assetSymbol,
      'trade_direction': tradeDirection.name,
      'trade_type': tradeType.name,
      'trade_status': tradeStatus.name,
      'trade_timeframe': tradeTimeframe,
      'margin_mode': marginMode,
      'margin_amount': marginAmount,
      'leverage_value': leverageValue,
      'volume_amount': volumeAmount,
      'dollar_rate': dollarRate,
      'fee_per_hundred': feePerHundred,
      'trade_fee': tradeFee,
      'entry_price': entryPrice,
      'exit_price': exitPrice,
      'stop_price': stopPrice,
      'target_price': targetPrice,
      'risk_distance': riskDistance,
      'reward_distance': rewardDistance,
      'risk_value': riskValue,
      'reward_value': rewardValue,
      'trade_risk_reward': tradeRiskReward,
      'final_pnl': finalPnl,
      'final_roi_percent': finalRoiPercent,
      'final_roi_dollar': finalRoiDollar,
      'final_risk_reward': finalRiskReward,
      'max_drawdown_price_percent': maxDrawdownPricePercent,
      'max_drawdown_dollar': maxDrawdownDollar,
      'max_drawdown_margin_percent': maxDrawdownMarginPercent,
      'duration_seconds': durationSeconds,
      'entry_setup': entrySetup,
      'entry_reason': entryReason,
      'entry_motivation': entryMotivation,
      'expected_scenario': expectedScenario,
      'entry_time': entryTime.toIso8601String(),
      'exit_time': exitTime?.toIso8601String(),
    };
  }

  // =========================================================
  // FROM MAP
  // =========================================================

  factory Trade.fromMap(
    Map<String, dynamic> map, {
    List<String> imagePaths = const [],
  }) {
    return Trade(
      tradeId: map['trade_id']?.toString() ?? '',
      assetSymbol: map['asset_symbol']?.toString() ?? '',
      tradeDirection: _directionFromString(
        map['trade_direction']?.toString(),
      ),
      tradeType: _typeFromString(
        map['trade_type']?.toString(),
      ),
      tradeStatus: _statusFromString(
        map['trade_status']?.toString(),
      ),
      tradeTimeframe: map['trade_timeframe']?.toString() ?? '',
      marginMode:
          map['margin_mode']?.toString() == 'cross' ? 'cross' : 'isolated',
      marginAmount: _toDouble(map['margin_amount']),
      leverageValue: _toDouble(map['leverage_value']),
      volumeAmount: _toDouble(map['volume_amount']),
      dollarRate: _toDouble(map['dollar_rate']),
      feePerHundred: _toDouble(map['fee_per_hundred']),
      tradeFee: _toDouble(map['trade_fee']),
      entryPrice: _toNullableDouble(map['entry_price']),
      exitPrice: _toNullableDouble(map['exit_price']),
      stopPrice: _toNullableDouble(map['stop_price']),
      targetPrice: _toNullableDouble(map['target_price']),
      riskDistance: _toDouble(map['risk_distance']),
      rewardDistance: _toDouble(map['reward_distance']),
      riskValue: _toDouble(map['risk_value']),
      rewardValue: _toDouble(map['reward_value']),
      tradeRiskReward: _toDouble(map['trade_risk_reward']),
      finalPnl: _toDouble(map['final_pnl']),
      finalRoiPercent: _toDouble(map['final_roi_percent']),
      finalRoiDollar: _toDouble(map['final_roi_dollar']),
      finalRiskReward: _toDouble(map['final_risk_reward']),
      maxDrawdownPricePercent: _toDouble(map['max_drawdown_price_percent']),
      maxDrawdownDollar: _toDouble(map['max_drawdown_dollar']),
      maxDrawdownMarginPercent: _toDouble(map['max_drawdown_margin_percent']),
      durationSeconds: _toInt(map['duration_seconds']),
      entrySetup: map['entry_setup']?.toString() ?? '',
      entryReason: map['entry_reason']?.toString() ?? '',
      entryMotivation: map['entry_motivation']?.toString() ?? '',
      expectedScenario: map['expected_scenario']?.toString() ?? '',
      imagePaths: imagePaths,
      entryTime: DateTime.tryParse(
            map['entry_time']?.toString() ?? '',
          ) ??
          DateTime.now(),
      exitTime: _toDateTime(map['exit_time']),
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0.0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    return double.tryParse(
      value.toString(),
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    );
  }

  static TradeDirection _directionFromString(
    String? value,
  ) {
    if (value == 'short') {
      return TradeDirection.short;
    }

    return TradeDirection.long;
  }

  static TradeType _typeFromString(
    String? value,
  ) {
    if (value == 'day') {
      return TradeType.day;
    }

    return TradeType.scalp;
  }

  static TradeStatus _statusFromString(
    String? value,
  ) {
    if (value == 'closed') {
      return TradeStatus.closed;
    }

    return TradeStatus.open;
  }
}

const Object _copyWithUnset = Object();
