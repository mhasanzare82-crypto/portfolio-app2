enum PriceAlertType {
  target,
  crossing,
  rangeExit,
  tradeTarget,
  tradeStopLoss,
  multiStage,
}

enum PriceAlertRepeatMode {
  once,
  everyCrossing,
  periodic,
}

class PriceAlert {
  final String id;

  /// نماد دارایی
  final String symbol;

  /// عنوان هشدار
  final String title;

  /// توضیح کوتاه
  final String note;

  /// نوع هشدار
  final PriceAlertType type;

  /// قیمت هدف
  final double? targetPrice;

  /// حد پایین محدوده
  final double? lowerPrice;

  /// حد بالای محدوده
  final double? upperPrice;

  /// جهت عبور
  ///
  /// true  = عبور به بالا
  /// false = عبور به پایین
  final bool triggerOnRise;

  /// نوع تکرار
  final PriceAlertRepeatMode repeatMode;

  /// فاصله تکرار بر حسب دقیقه
  ///
  /// فقط برای repeatMode.periodic استفاده می‌شود.
  final int? repeatIntervalMinutes;

  /// فعال یا غیرفعال بودن
  final bool isActive;

  /// آیا هشدار اجرا شده؟
  final bool isTriggered;

  /// مسیر فایل صدای انتخاب‌شده از گوشی
  final String? soundPath;

  /// شناسه معامله‌ای که هشدار به آن متصل است.
  ///
  /// برای هشدارهای معمولی null است.
  final String? tradeId;

  /// مشخص می‌کند هشدار مربوط به Target یا Stop Loss معامله است.
  ///
  /// مقادیر مورد انتظار:
  /// target
  /// stop_loss
  final String? tradePriceType;

  /// شناسه گروه هشدارهای چندمرحله‌ای
  final String? multiStageGroupId;

  /// شماره مرحله در هشدار چندمرحله‌ای
  final int? stageIndex;

  /// زمان ایجاد
  final DateTime createdAt;

  /// آخرین زمان اجرای هشدار
  final DateTime? lastTriggeredAt;

  /// زمان فعال شدن هشدار
  final DateTime? triggeredAt;

  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.title,
    this.note = '',
    required this.type,
    this.targetPrice,
    this.lowerPrice,
    this.upperPrice,
    required this.triggerOnRise,
    this.repeatMode = PriceAlertRepeatMode.once,
    this.repeatIntervalMinutes,
    this.isActive = true,
    this.isTriggered = false,
    this.soundPath,
    this.tradeId,
    this.tradePriceType,
    this.multiStageGroupId,
    this.stageIndex,
    required this.createdAt,
    this.lastTriggeredAt,
    this.triggeredAt,
  });

  PriceAlert copyWith({
    String? id,
    String? symbol,
    String? title,
    String? note,
    PriceAlertType? type,
    double? targetPrice,
    double? lowerPrice,
    double? upperPrice,
    bool? triggerOnRise,
    PriceAlertRepeatMode? repeatMode,
    int? repeatIntervalMinutes,
    bool? isActive,
    bool? isTriggered,
    String? soundPath,
    String? tradeId,
    String? tradePriceType,
    String? multiStageGroupId,
    int? stageIndex,
    DateTime? createdAt,
    DateTime? lastTriggeredAt,
    DateTime? triggeredAt,
  }) {
    return PriceAlert(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      title: title ?? this.title,
      note: note ?? this.note,
      type: type ?? this.type,
      targetPrice: targetPrice ?? this.targetPrice,
      lowerPrice: lowerPrice ?? this.lowerPrice,
      upperPrice: upperPrice ?? this.upperPrice,
      triggerOnRise: triggerOnRise ?? this.triggerOnRise,
      repeatMode: repeatMode ?? this.repeatMode,
      repeatIntervalMinutes:
          repeatIntervalMinutes ?? this.repeatIntervalMinutes,
      isActive: isActive ?? this.isActive,
      isTriggered: isTriggered ?? this.isTriggered,
      soundPath: soundPath ?? this.soundPath,
      tradeId: tradeId ?? this.tradeId,
      tradePriceType: tradePriceType ?? this.tradePriceType,
      multiStageGroupId: multiStageGroupId ?? this.multiStageGroupId,
      stageIndex: stageIndex ?? this.stageIndex,
      createdAt: createdAt ?? this.createdAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
    );
  }

  String get typeKey {
    switch (type) {
      case PriceAlertType.target:
        return 'target';

      case PriceAlertType.crossing:
        return 'crossing';

      case PriceAlertType.rangeExit:
        return 'range_exit';

      case PriceAlertType.tradeTarget:
        return 'trade_target';

      case PriceAlertType.tradeStopLoss:
        return 'trade_stop_loss';

      case PriceAlertType.multiStage:
        return 'multi_stage';
    }
  }

  String get repeatModeKey {
    switch (repeatMode) {
      case PriceAlertRepeatMode.once:
        return 'once';

      case PriceAlertRepeatMode.everyCrossing:
        return 'every_crossing';

      case PriceAlertRepeatMode.periodic:
        return 'periodic';
    }
  }

  static PriceAlertType typeFromKey(
    String? value,
  ) {
    switch (value) {
      case 'target':
        return PriceAlertType.target;

      case 'crossing':
        return PriceAlertType.crossing;

      case 'range_exit':
        return PriceAlertType.rangeExit;

      case 'trade_target':
        return PriceAlertType.tradeTarget;

      case 'trade_stop_loss':
        return PriceAlertType.tradeStopLoss;

      case 'multi_stage':
        return PriceAlertType.multiStage;

      default:
        return PriceAlertType.target;
    }
  }

  static PriceAlertRepeatMode repeatModeFromKey(
    String? value,
  ) {
    switch (value) {
      case 'every_crossing':
        return PriceAlertRepeatMode.everyCrossing;

      case 'periodic':
        return PriceAlertRepeatMode.periodic;

      case 'once':
      default:
        return PriceAlertRepeatMode.once;
    }
  }
}
