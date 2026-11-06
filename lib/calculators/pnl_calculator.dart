import '../models/trade.dart';

class PnlCalculator {
  static double grossPnl(
    Trade trade,
    double currentPrice,
  ) {
    if (trade.entryPrice == null ||
        trade.entryPrice! <= 0 ||
        currentPrice <= 0 ||
        trade.volumeAmount <= 0) {
      return 0.0;
    }

    final double entryPrice = trade.entryPrice!;

    final double priceChange = trade.tradeDirection == TradeDirection.long
        ? (currentPrice - entryPrice) / entryPrice
        : (entryPrice - currentPrice) / entryPrice;

    return trade.volumeAmount * priceChange;
  }

  static double fee(
    Trade trade,
  ) {
    if (trade.volumeAmount <= 0 || trade.feePerHundred <= 0) {
      return 0.0;
    }

    return (trade.volumeAmount / 100.0) * trade.feePerHundred;
  }

  static double netPnl(
    Trade trade,
    double currentPrice,
  ) {
    return grossPnl(
          trade,
          currentPrice,
        ) -
        fee(trade);
  }

  static double pnlPercentOfVolume(
    Trade trade,
    double currentPrice,
  ) {
    if (trade.volumeAmount <= 0) {
      return 0.0;
    }

    return netPnl(
          trade,
          currentPrice,
        ) /
        trade.volumeAmount *
        100.0;
  }

  static double pnlPercentOfMargin(
    Trade trade,
    double currentPrice,
  ) {
    if (trade.marginAmount <= 0) {
      return 0.0;
    }

    return netPnl(
          trade,
          currentPrice,
        ) /
        trade.marginAmount *
        100.0;
  }

  static double tradeProfit(
    Trade trade,
    double currentPrice,
  ) {
    final double pnl = netPnl(
      trade,
      currentPrice,
    );

    return pnl > 0 ? pnl : 0.0;
  }

  static double tradeLoss(
    Trade trade,
    double currentPrice,
  ) {
    final double pnl = netPnl(
      trade,
      currentPrice,
    );

    return pnl < 0 ? pnl.abs() : 0.0;
  }

  static double stopLossPnl(
    Trade trade,
  ) {
    if (trade.stopPrice == null || trade.stopPrice! <= 0) {
      return 0.0;
    }

    return grossPnl(
      trade,
      trade.stopPrice!,
    );
  }

  static double targetPnl(
    Trade trade,
  ) {
    if (trade.targetPrice == null || trade.targetPrice! <= 0) {
      return 0.0;
    }

    return grossPnl(
      trade,
      trade.targetPrice!,
    );
  }

  static double riskDistance(
    Trade trade,
  ) {
    if (trade.entryPrice == null || trade.stopPrice == null) {
      return 0.0;
    }

    return (trade.entryPrice! - trade.stopPrice!).abs();
  }

  static double rewardDistance(
    Trade trade,
  ) {
    if (trade.entryPrice == null || trade.targetPrice == null) {
      return 0.0;
    }

    return (trade.targetPrice! - trade.entryPrice!).abs();
  }

  static double riskReward(
    Trade trade,
  ) {
    final double risk = riskDistance(trade);

    final double reward = rewardDistance(trade);

    if (risk <= 0) {
      return 0.0;
    }

    return reward / risk;
  }

  static double riskValue(
    Trade trade,
  ) {
    if (trade.volumeAmount <= 0) {
      return 0.0;
    }

    final double risk = riskDistance(trade);

    if (trade.entryPrice == null || trade.entryPrice! <= 0 || risk <= 0) {
      return 0.0;
    }

    return trade.volumeAmount * (risk / trade.entryPrice!);
  }

  static double rewardValue(
    Trade trade,
  ) {
    if (trade.volumeAmount <= 0) {
      return 0.0;
    }

    final double reward = rewardDistance(trade);

    if (trade.entryPrice == null || trade.entryPrice! <= 0 || reward <= 0) {
      return 0.0;
    }

    return trade.volumeAmount * (reward / trade.entryPrice!);
  }

  static double riskPercentOfVolume(
    Trade trade,
  ) {
    if (trade.volumeAmount <= 0) {
      return 0.0;
    }

    return riskValue(trade) / trade.volumeAmount * 100.0;
  }

  static double rewardPercentOfVolume(
    Trade trade,
  ) {
    if (trade.volumeAmount <= 0) {
      return 0.0;
    }

    return rewardValue(trade) / trade.volumeAmount * 100.0;
  }

  static double calculatedRiskReward(
    Trade trade,
  ) {
    return riskReward(trade);
  }

  static double stopFromRisk(
    TradeDirection direction,
    double entryPrice,
    double riskDistance,
  ) {
    if (entryPrice <= 0 || riskDistance <= 0) {
      return 0.0;
    }

    if (direction == TradeDirection.long) {
      return entryPrice - riskDistance;
    }

    return entryPrice + riskDistance;
  }

  static double targetFromRiskReward(
    TradeDirection direction,
    double entryPrice,
    double riskDistance,
    double rewardMultiple,
  ) {
    if (entryPrice <= 0 || riskDistance <= 0 || rewardMultiple <= 0) {
      return 0.0;
    }

    final double rewardDistance = riskDistance * rewardMultiple;

    if (direction == TradeDirection.long) {
      return entryPrice + rewardDistance;
    }

    return entryPrice - rewardDistance;
  }

  /// مجموع سود و زیان شناور معاملات باز با استفاده از آخرین قیمت موجود.
  static double openTradesPnl(
    Iterable<Trade> trades,
    Map<String, double> livePrices,
  ) {
    return trades.fold<double>(0, (sum, trade) {
      final symbol = trade.assetSymbol.trim().toUpperCase();
      final price = livePrices[symbol] ?? 0;
      return sum + (price > 0 ? netPnl(trade, price) : 0);
    });
  }

  /// مجموع سود و زیان تحقق‌یافته معاملات بسته.
  static double closedTradesPnl(Iterable<Trade> trades) {
    return trades.fold<double>(0, (sum, trade) {
      if (trade.finalPnl != 0) return sum + trade.finalPnl;
      final exitPrice = trade.exitPrice;
      return sum +
          (exitPrice != null && exitPrice > 0 ? netPnl(trade, exitPrice) : 0);
    });
  }

  /// مجموع سود و زیان معاملات باز و بسته.
  static double totalTradesPnl(
    Iterable<Trade> openTrades,
    Iterable<Trade> closedTrades,
    Map<String, double> livePrices,
  ) {
    return openTradesPnl(openTrades, livePrices) +
        closedTradesPnl(closedTrades);
  }
}
