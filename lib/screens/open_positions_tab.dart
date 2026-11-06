import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ticker.dart';
import '../models/trade.dart';
import '../calculators/pnl_calculator.dart';
import '../utils/number_formatter.dart';
import 'color_settings_page.dart';
import '../services/lbank_service.dart';
import 'asset_open_trades_page.dart';

/// First tab: shows every asset that currently has open trades, along with
/// its live price. Tapping an asset opens that asset's open trades.
class OpenPositionsTab extends StatefulWidget {
  const OpenPositionsTab({
    super.key,
    required this.openTrades,
    required this.loading,
    required this.onRefresh,
    required this.onChanged,
  });

  final List<Trade> openTrades;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onChanged;

  @override
  State<OpenPositionsTab> createState() => _OpenPositionsTabState();
}

class _OpenPositionsTabState extends State<OpenPositionsTab> {
  final Map<String, LBankService> _services = {};
  final Map<String, StreamSubscription<Ticker>> _subscriptions = {};
  final Map<String, double> _prices = {};
  static const String _decimalPreferenceKey = 'open_positions_decimal_digits';
  int _decimalDigits = 4;

  String _fmt(double value) => formatNumber(value, decimals: _decimalDigits);

  Future<void> _loadDecimalPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _decimalDigits =
          (prefs.getInt(_decimalPreferenceKey) ?? 4).clamp(0, 8).toInt();
    });
  }

  Future<void> _setDecimalDigits(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_decimalPreferenceKey, value);
    if (!mounted) return;
    setState(() => _decimalDigits = value);
  }

  @override
  void initState() {
    super.initState();

    _loadDecimalPreference();
    _syncServices();
  }

  @override
  void didUpdateWidget(
    OpenPositionsTab oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    _syncServices();
  }

  List<String> get _symbols {
    final symbols = widget.openTrades
        .map(
          (trade) => trade.assetSymbol,
        )
        .toSet()
        .toList();

    symbols.sort();

    return symbols;
  }

  void _syncServices() {
    final symbols = _symbols;

    for (final symbol in symbols) {
      if (_services.containsKey(symbol)) {
        continue;
      }

      final service = LBankService();

      _services[symbol] = service;

      _subscriptions[symbol] = service.tickerStream.listen(
        (ticker) {
          if (!mounted) return;

          setState(() {
            _prices[symbol] = ticker.price;
          });
        },
      );

      service.connect(symbol);
    }

    final removedSymbols =
        _services.keys.where((symbol) => !symbols.contains(symbol)).toList();

    for (final symbol in removedSymbols) {
      _subscriptions.remove(symbol)?.cancel();
      _services.remove(symbol)?.dispose();
      _prices.remove(symbol);
    }
  }

  List<Trade> _tradesForSymbol(
    String symbol,
  ) {
    return widget.openTrades
        .where(
          (trade) => trade.assetSymbol == symbol,
        )
        .toList();
  }

  Future<void> _openAsset(
    String symbol,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return AssetOpenTradesPage(
            assetSymbol: symbol,
            initialTrades: _tradesForSymbol(
              symbol,
            ),
            onChanged: widget.onChanged,
          );
        },
      ),
    );

    await widget.onRefresh();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }

    for (final service in _services.values) {
      service.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (widget.loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final symbols = _symbols;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: symbols.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 60,
                  ),
                  child: Center(
                    child: Text(
                      'در حال حاضر معامله بازی وجود ندارد.',
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: symbols.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'تعداد ارقام اعشار کارت‌ها',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: AppColors.secondaryText, fontSize: 12),
                          ),
                        ),
                        PopupMenuButton<int>(
                          tooltip: 'تنظیم تعداد ارقام اعشار',
                          initialValue: _decimalDigits,
                          onSelected: _setDecimalDigits,
                          itemBuilder: (context) => List.generate(
                              9,
                              (i) => PopupMenuItem<int>(
                                    value: i,
                                    child:
                                        Text('${formatInteger(i)} رقم اعشار'),
                                  )),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.boxBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text('${formatInteger(_decimalDigits)} رقم',
                                style: TextStyle(color: AppColors.text)),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final symbol = symbols[index - 1];

                final price = _prices[symbol];

                final symbolTrades = _tradesForSymbol(symbol);
                final longs = symbolTrades
                    .where((t) => t.tradeDirection == TradeDirection.long)
                    .toList();
                final shorts = symbolTrades
                    .where((t) => t.tradeDirection == TradeDirection.short)
                    .toList();

                Map<String, double> summary(List<Trade> trades) {
                  if (trades.isEmpty)
                    return {
                      'count': 0,
                      'entry': 0,
                      'volume': 0,
                      'avgVolume': 0,
                      'liquidation': 0,
                      'pnl': 0
                    };
                  final totalVolume =
                      trades.fold<double>(0, (sum, t) => sum + t.volumeAmount);
                  final weightedEntry = trades.fold<double>(0,
                      (sum, t) => sum + (t.entryPrice ?? 0) * t.volumeAmount);
                  final weightedLiquidation = trades.fold<double>(0, (sum, t) {
                    final entry = t.entryPrice ?? 0;
                    final leverage = t.leverageValue > 0 ? t.leverageValue : 1;
                    final estimated = t.tradeDirection == TradeDirection.long
                        ? entry * (1 - 1 / leverage)
                        : entry * (1 + 1 / leverage);
                    return sum + estimated * t.volumeAmount;
                  });
                  final pnl = price == null
                      ? 0.0
                      : trades.fold<double>(
                          0, (sum, t) => sum + PnlCalculator.netPnl(t, price));
                  return {
                    'count': trades.length.toDouble(),
                    'entry': totalVolume > 0 ? weightedEntry / totalVolume : 0,
                    'volume': totalVolume,
                    'avgVolume': totalVolume / trades.length,
                    'liquidation':
                        totalVolume > 0 ? weightedLiquidation / totalVolume : 0,
                    'pnl': pnl,
                  };
                }

                Widget metric(String label, String value, {Color? valueColor}) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          label,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.secondaryText),
                        ),
                        const SizedBox(height: 2),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            value,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: valueColor ?? AppColors.text),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                Widget sideSummary(
                    String label, List<Trade> trades, Color color) {
                  final values = summary(trades);
                  if (trades.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('—', textAlign: TextAlign.center));
                  }
                  final pnl = values['pnl']!;
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.20)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            '$label (${formatNumber(values['count']!, decimals: 0)})',
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: color)),
                        const SizedBox(height: 5),
                        metric('میانگین قیمت ورود', _fmt(values['entry']!),
                            valueColor: AppColors.entry),
                        metric('حجم کل', '${_fmt(values['volume']!)} USD',
                            valueColor: AppColors.neutral),
                        metric('میانگین حجم', _fmt(values['avgVolume']!),
                            valueColor: AppColors.neutral),
                        metric(
                            'قیمت لیکویید تخمینی', _fmt(values['liquidation']!),
                            valueColor: AppColors.target),
                        metric('سود و زیان کل (PnL)',
                            '${pnl >= 0 ? '+' : ''}${_fmt(pnl)} USD',
                            valueColor: pnl > 0
                                ? AppColors.profit
                                : (pnl < 0
                                    ? AppColors.loss
                                    : AppColors.neutral)),
                      ],
                    ),
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => _openAsset(symbol),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                              child: Text(symbol,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16))),
                          Text(
                              '${formatInteger(symbolTrades.length)} معامله باز',
                              style: const TextStyle(fontSize: 12)),
                        ]),
                        const SizedBox(height: 8),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: sideSummary(
                                      'شورت', shorts, AppColors.short)),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 4),
                                child: Column(children: [
                                  Text('قیمت لحظه‌ای',
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.secondaryText)),
                                  const SizedBox(height: 4),
                                  Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(
                                          price != null && price > 0
                                              ? _fmt(price)
                                              : '...',
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: AppColors.livePrice))),
                                  const SizedBox(height: 8),
                                  const Icon(Icons.chevron_left),
                                  const Text('جزئیات',
                                      style: TextStyle(fontSize: 10)),
                                ]),
                              )),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: sideSummary(
                                      'لانگ', longs, AppColors.long)),
                            ]),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
