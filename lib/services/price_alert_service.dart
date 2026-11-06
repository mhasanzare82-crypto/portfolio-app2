import 'dart:async';

import '../models/price_alert.dart';
import '../repositories/price_alert_repository.dart';
import 'notification_service.dart';

class PriceAlertService {
  PriceAlertService._();

  static final PriceAlertService instance = PriceAlertService._();

  final PriceAlertRepository _repository = PriceAlertRepository.instance;

  final Map<String, double> _previousPrices = {};

  final Set<String> _checkingSymbols = {};

  Future<void> checkPrice({
    required String symbol,
    required double currentPrice,
  }) async {
    if (currentPrice <= 0) {
      return;
    }

    final normalizedSymbol = symbol.toUpperCase().trim();

    if (normalizedSymbol.isEmpty) {
      return;
    }

    if (_checkingSymbols.contains(
      normalizedSymbol,
    )) {
      return;
    }

    _checkingSymbols.add(
      normalizedSymbol,
    );

    try {
      final previousPrice = _previousPrices[normalizedSymbol];

      _previousPrices[normalizedSymbol] = currentPrice;

      final alerts = await _repository.getActiveAlerts();

      final symbolAlerts = alerts.where(
        (alert) {
          return alert.symbol.toUpperCase().trim() == normalizedSymbol &&
              alert.isActive;
        },
      ).toList();

      for (final alert in symbolAlerts) {
        try {
          await _processAlert(
            alert: alert,
            currentPrice: currentPrice,
            previousPrice: previousPrice,
          );
        } catch (_) {
          // خطای یک هشدار نباید
          // باعث توقف سایر هشدارها شود.
        }
      }
    } finally {
      _checkingSymbols.remove(
        normalizedSymbol,
      );
    }
  }

  Future<void> _processAlert({
    required PriceAlert alert,
    required double currentPrice,
    required double? previousPrice,
  }) async {
    final shouldTrigger = _shouldTriggerAlert(
      alert: alert,
      currentPrice: currentPrice,
      previousPrice: previousPrice,
    );

    if (!shouldTrigger) {
      return;
    }

    switch (alert.repeatMode) {
      case PriceAlertRepeatMode.once:
        await _triggerOnce(
          alert: alert,
          currentPrice: currentPrice,
        );
        break;

      case PriceAlertRepeatMode.everyCrossing:
        await _triggerEveryCrossing(
          alert: alert,
          currentPrice: currentPrice,
          previousPrice: previousPrice,
        );
        break;

      case PriceAlertRepeatMode.periodic:
        await _triggerPeriodic(
          alert: alert,
          currentPrice: currentPrice,
        );
        break;
    }
  }

  bool _shouldTriggerAlert({
    required PriceAlert alert,
    required double currentPrice,
    required double? previousPrice,
  }) {
    switch (alert.type) {
      case PriceAlertType.target:
      case PriceAlertType.tradeTarget:
      case PriceAlertType.tradeStopLoss:
      case PriceAlertType.multiStage:
        switch (alert.repeatMode) {
          case PriceAlertRepeatMode.once:
          case PriceAlertRepeatMode.periodic:
            return _targetConditionReached(
              alert: alert,
              currentPrice: currentPrice,
            );

          case PriceAlertRepeatMode.everyCrossing:
            return _hasCrossedTarget(
              alert: alert,
              previousPrice: previousPrice,
              currentPrice: currentPrice,
            );
        }

      case PriceAlertType.crossing:
        return _hasCrossedTarget(
          alert: alert,
          previousPrice: previousPrice,
          currentPrice: currentPrice,
        );

      case PriceAlertType.rangeExit:
        return _hasExitedRange(
          alert: alert,
          previousPrice: previousPrice,
          currentPrice: currentPrice,
        );
    }
  }

  bool _targetConditionReached({
    required PriceAlert alert,
    required double currentPrice,
  }) {
    final target = alert.targetPrice;

    if (target == null) {
      return false;
    }

    if (alert.triggerOnRise) {
      return currentPrice >= target;
    }

    return currentPrice <= target;
  }

  bool _hasCrossedTarget({
    required PriceAlert alert,
    required double? previousPrice,
    required double currentPrice,
  }) {
    final target = alert.targetPrice;

    if (target == null || previousPrice == null) {
      return false;
    }

    if (alert.triggerOnRise) {
      return previousPrice < target && currentPrice >= target;
    }

    return previousPrice > target && currentPrice <= target;
  }

  bool _hasExitedRange({
    required PriceAlert alert,
    required double? previousPrice,
    required double currentPrice,
  }) {
    final lower = alert.lowerPrice;

    final upper = alert.upperPrice;

    if (lower == null || upper == null) {
      return false;
    }

    final minPrice = lower < upper ? lower : upper;

    final maxPrice = lower < upper ? upper : lower;

    if (previousPrice == null) {
      return currentPrice < minPrice || currentPrice > maxPrice;
    }

    final crossedBelow = previousPrice >= minPrice && currentPrice < minPrice;

    final crossedAbove = previousPrice <= maxPrice && currentPrice > maxPrice;

    return crossedBelow || crossedAbove;
  }

  Future<void> _triggerOnce({
    required PriceAlert alert,
    required double currentPrice,
  }) async {
    await _notify(
      alert: alert,
      currentPrice: currentPrice,
    );

    await _repository.markAsTriggered(
      alert.id,
    );

    if (alert.type == PriceAlertType.multiStage) {
      await _activateNextMultiStage(
        alert,
      );
    }
  }

  Future<void> _triggerEveryCrossing({
    required PriceAlert alert,
    required double currentPrice,
    required double? previousPrice,
  }) async {
    if (previousPrice == null) {
      return;
    }

    await _notify(
      alert: alert,
      currentPrice: currentPrice,
    );

    await _repository.markAsRepeated(
      alert.id,
    );
  }

  Future<void> _triggerPeriodic({
    required PriceAlert alert,
    required double currentPrice,
  }) async {
    final now = DateTime.now();

    final lastTriggered = alert.lastTriggeredAt;

    if (lastTriggered == null) {
      await _notify(
        alert: alert,
        currentPrice: currentPrice,
      );

      await _repository.markAsRepeated(
        alert.id,
      );

      return;
    }

    final intervalMinutes = alert.repeatIntervalMinutes;

    if (intervalMinutes == null || intervalMinutes <= 0) {
      return;
    }

    final elapsed = now.difference(
      lastTriggered,
    );

    if (elapsed.inMinutes < intervalMinutes) {
      return;
    }

    await _notify(
      alert: alert,
      currentPrice: currentPrice,
    );

    await _repository.markAsRepeated(
      alert.id,
    );
  }

  Future<void> _activateNextMultiStage(
    PriceAlert currentAlert,
  ) async {
    final groupId = currentAlert.multiStageGroupId;

    if (groupId == null || groupId.isEmpty) {
      return;
    }

    final currentStage = currentAlert.stageIndex;

    if (currentStage == null) {
      return;
    }

    final groupAlerts = await _repository.getAlertsByGroupId(
      groupId,
    );

    final nextStages = groupAlerts.where(
      (alert) {
        final stage = alert.stageIndex;

        return stage != null && stage > currentStage && !alert.isTriggered;
      },
    ).toList();

    if (nextStages.isEmpty) {
      return;
    }

    nextStages.sort(
      (a, b) {
        return a.stageIndex!.compareTo(
          b.stageIndex!,
        );
      },
    );

    final nextStage = nextStages.first;

    await _repository.setActive(
      nextStage.id,
      true,
    );
  }

  Future<void> _notify({
    required PriceAlert alert,
    required double currentPrice,
  }) async {
    /*
     * NotificationService فعلی پروژه
     * برای showPriceAlert به targetPrice نیاز دارد.
     *
     * در هشدارهای عادی targetPrice داریم.
     * در هشدار خروج از محدوده، برای نمایش اعلان
     * از مرزی که شکسته شده استفاده می‌کنیم.
     */

    double targetPrice;

    if (alert.targetPrice != null) {
      targetPrice = alert.targetPrice!;
    } else if (alert.type == PriceAlertType.rangeExit &&
        alert.lowerPrice != null &&
        alert.upperPrice != null) {
      /*
       * اگر قیمت فعلی خارج از محدوده باشد،
       * نزدیک‌ترین مرز خروج را برای نمایش
       * در NotificationService انتخاب می‌کنیم.
       */
      if (currentPrice < (alert.lowerPrice!)) {
        targetPrice = alert.lowerPrice!;
      } else {
        targetPrice = alert.upperPrice!;
      }
    } else if (alert.lowerPrice != null) {
      targetPrice = alert.lowerPrice!;
    } else if (alert.upperPrice != null) {
      targetPrice = alert.upperPrice!;
    } else {
      targetPrice = currentPrice;
    }

    await NotificationService.instance.showPriceAlert(
      symbol: alert.symbol,
      targetPrice: targetPrice,
      currentPrice: currentPrice,
      title: alert.title.trim().isEmpty ? 'هشدار قیمت' : alert.title.trim(),
      note: _buildNotificationBody(
        alert: alert,
        currentPrice: currentPrice,
      ),
      alert: alert,
    );
  }

  String _buildNotificationBody({
    required PriceAlert alert,
    required double currentPrice,
  }) {
    final buffer = StringBuffer();

    buffer.write(
      '${alert.symbol} — قیمت فعلی: '
      '${_formatPrice(currentPrice)}',
    );

    switch (alert.type) {
      case PriceAlertType.target:
      case PriceAlertType.tradeTarget:
      case PriceAlertType.tradeStopLoss:
      case PriceAlertType.crossing:
      case PriceAlertType.multiStage:
        if (alert.targetPrice != null) {
          buffer.write(
            ' | سطح: '
            '${_formatPrice(alert.targetPrice!)}',
          );
        }
        break;

      case PriceAlertType.rangeExit:
        if (alert.lowerPrice != null && alert.upperPrice != null) {
          buffer.write(
            ' | محدوده: '
            '${_formatPrice(alert.lowerPrice!)}'
            ' تا '
            '${_formatPrice(alert.upperPrice!)}',
          );

          if (currentPrice < alert.lowerPrice!) {
            buffer.write(
              '\nخروج از پایین محدوده',
            );
          } else if (currentPrice > alert.upperPrice!) {
            buffer.write(
              '\nخروج از بالای محدوده',
            );
          }
        }
        break;
    }

    if (alert.note.trim().isNotEmpty) {
      buffer.write(
        '\n${alert.note.trim()}',
      );
    }

    return buffer.toString();
  }

  String _formatPrice(
    double value,
  ) {
    if (value >= 1000) {
      return value.toStringAsFixed(2);
    }

    if (value >= 1) {
      return value.toStringAsFixed(4);
    }

    return value.toStringAsFixed(6);
  }

  void clearPreviousPrice(
    String symbol,
  ) {
    _previousPrices.remove(
      symbol.toUpperCase().trim(),
    );
  }

  void clearAllPreviousPrices() {
    _previousPrices.clear();
  }
}
