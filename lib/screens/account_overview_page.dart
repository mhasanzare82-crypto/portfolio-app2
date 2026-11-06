import 'package:flutter/material.dart';

import '../calculators/pnl_calculator.dart';
import '../database/app_database.dart';
import '../models/trade.dart';
import '../repositories/trade_repository.dart';
import 'color_settings_page.dart';
import '../utils/number_formatter.dart' as numbers;

class AccountOverviewPage extends StatefulWidget {
  const AccountOverviewPage({
    super.key,
  });

  @override
  State<AccountOverviewPage> createState() => _AccountOverviewPageState();
}

class _AccountOverviewPageState extends State<AccountOverviewPage> {
  final TradeRepository _tradeRepository = TradeRepository();

  final AppDatabase _database = AppDatabase.instance;

  List<Trade> _openTrades = [];
  List<Trade> _closedTrades = [];

  double _initialBalance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final openTrades = await _tradeRepository.getOpenTrades();

    final closedTrades = await _tradeRepository.getClosedTrades();

    final initialBalance = await _database.getInitialBalance();

    if (!mounted) return;

    setState(() {
      _openTrades = openTrades;
      _closedTrades = closedTrades;
      _initialBalance = initialBalance;
      _loading = false;
    });
  }

  double _tradePnl(
    Trade trade,
  ) {
    if (trade.exitPrice == null) {
      return 0;
    }

    return PnlCalculator.netPnl(
      trade,
      trade.exitPrice!,
    );
  }

  double get _totalPnl {
    return _closedTrades.fold(
      0,
      (sum, trade) => sum + _tradePnl(trade),
    );
  }

  double get _totalProfit {
    return _closedTrades.fold(
      0,
      (sum, trade) {
        final pnl = _tradePnl(trade);
        return sum + (pnl > 0 ? pnl : 0);
      },
    );
  }

  double get _totalLoss {
    return _closedTrades.fold(
      0,
      (sum, trade) {
        final pnl = _tradePnl(trade);
        return sum + (pnl < 0 ? pnl.abs() : 0);
      },
    );
  }

  double get _currentBalance {
    return _initialBalance + _totalPnl;
  }

  double get _averageTradePnl {
    if (_closedTrades.isEmpty) {
      return 0;
    }

    return _totalPnl / _closedTrades.length;
  }

  double get _weightedAverageEntryPrice {
    final trades = [
      ..._openTrades,
      ..._closedTrades,
    ].where(
      (trade) =>
          trade.entryPrice != null &&
          trade.entryPrice! > 0 &&
          trade.volumeAmount > 0,
    );

    if (trades.isEmpty) {
      return 0;
    }

    double weightedTotal = 0;
    double totalVolume = 0;

    for (final trade in trades) {
      weightedTotal += trade.entryPrice! * trade.volumeAmount;
      totalVolume += trade.volumeAmount;
    }

    if (totalVolume <= 0) {
      return 0;
    }

    return weightedTotal / totalVolume;
  }

  double get _totalVolume {
    return _closedTrades.fold(
      0,
      (sum, trade) => sum + trade.volumeAmount,
    );
  }

  double get _totalMargin {
    return _closedTrades.fold(
      0,
      (sum, trade) => sum + trade.marginAmount,
    );
  }

  double get _pnlVolumePercent {
    if (_totalVolume <= 0) {
      return 0;
    }

    return _totalPnl / _totalVolume * 100;
  }

  double get _pnlMarginPercent {
    if (_totalMargin <= 0) {
      return 0;
    }

    return _totalPnl / _totalMargin * 100;
  }

  double get _pnlInitialBalancePercent {
    if (_initialBalance <= 0) {
      return 0;
    }

    return _totalPnl / _initialBalance * 100;
  }

  double get _pnlCurrentBalancePercent {
    if (_currentBalance == 0) {
      return 0;
    }

    return _totalPnl / _currentBalance * 100;
  }

  int get _winningTradeCount {
    return _closedTrades
        .where(
          (trade) => _tradePnl(trade) > 0,
        )
        .length;
  }

  int get _losingTradeCount {
    return _closedTrades
        .where(
          (trade) => _tradePnl(trade) < 0,
        )
        .length;
  }

  double get _totalRiskReward {
    double totalRisk = 0;
    double totalReward = 0;

    for (final trade in [
      ..._openTrades,
      ..._closedTrades,
    ]) {
      final risk = PnlCalculator.riskDistance(trade);

      final reward = PnlCalculator.rewardDistance(trade);

      if (risk > 0) {
        totalRisk += risk;
        totalReward += reward;
      }
    }

    if (totalRisk <= 0) {
      return 0;
    }

    return totalReward / totalRisk;
  }

  Future<void> _editInitialBalance() async {
    final controller = TextEditingController(
      text: _initialBalance == 0 ? '' : _initialBalance.toString(),
    );

    final value = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'سرمایه اولیه',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'مقدار سرمایه',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(
                  numbers
                      .normalizeNumberInput(controller.text)
                      .trim()
                      .replaceAll(',', ''),
                );

                Navigator.pop(
                  context,
                  value,
                );
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (value == null) {
      return;
    }

    await _database.setInitialBalance(value);
    await _loadData();
  }

  Color _valueColor(
    double value,
  ) {
    if (value > 0) {
      return AppColors.profit;
    }

    if (value < 0) {
      return AppColors.loss;
    }

    return AppColors.neutral;
  }

  Widget _statCard({
    required String title,
    required String value,
    double? numericValue,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: numericValue == null
                    ? AppColors.text
                    : _valueColor(
                        numericValue,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'حساب و آمار',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'سرمایه اولیه',
            onPressed: _editInitialBalance,
            icon: const Icon(
              Icons.account_balance,
            ),
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            size: 32,
                            color: AppColors.assetIcon,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'سرمایه اولیه',
                                  style: TextStyle(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${numbers.formatNumber(_initialBalance, decimals: 2, trimTrailingZeros: false)} \$',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _editInitialBalance,
                            icon: const Icon(
                              Icons.edit,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.75,
                    children: [
                      _statCard(
                        title: 'بالانس فعلی',
                        value:
                            '${numbers.formatNumber(_currentBalance, decimals: 2, trimTrailingZeros: false)} \$',
                        numericValue: _currentBalance - _initialBalance,
                      ),
                      _statCard(
                        title: 'کل P&L',
                        value:
                            '${numbers.formatNumber(_totalPnl, decimals: 2, trimTrailingZeros: false)} \$',
                        numericValue: _totalPnl,
                      ),
                      _statCard(
                        title: 'کل سود',
                        value:
                            '${numbers.formatNumber(_totalProfit, decimals: 2, trimTrailingZeros: false)} \$',
                        numericValue: _totalProfit,
                      ),
                      _statCard(
                        title: 'کل ضرر',
                        value:
                            '${numbers.formatNumber(_totalLoss, decimals: 2, trimTrailingZeros: false)} \$',
                        numericValue: -_totalLoss,
                      ),
                      _statCard(
                        title: 'تعداد معاملات',
                        value: numbers.formatInteger(
                            _closedTrades.length + _openTrades.length),
                      ),
                      _statCard(
                        title: 'معاملات سودده',
                        value: numbers.formatInteger(_winningTradeCount),
                        numericValue: _winningTradeCount.toDouble(),
                      ),
                      _statCard(
                        title: 'معاملات ضررده',
                        value: numbers.formatInteger(_losingTradeCount),
                        numericValue: -_losingTradeCount.toDouble(),
                      ),
                      _statCard(
                        title: 'میانگین P&L',
                        value:
                            '${numbers.formatNumber(_averageTradePnl, decimals: 2, trimTrailingZeros: false)} \$',
                        numericValue: _averageTradePnl,
                      ),
                      _statCard(
                        title: 'میانگین وزنی Entry',
                        value: numbers.formatNumber(_weightedAverageEntryPrice,
                            decimals: 4, trimTrailingZeros: false),
                      ),
                      _statCard(
                        title: 'P&L / Volume',
                        value:
                            '${numbers.formatNumber(_pnlVolumePercent, decimals: 2, trimTrailingZeros: false)}%',
                        numericValue: _pnlVolumePercent,
                      ),
                      _statCard(
                        title: 'P&L / Margin',
                        value:
                            '${numbers.formatNumber(_pnlMarginPercent, decimals: 2, trimTrailingZeros: false)}%',
                        numericValue: _pnlMarginPercent,
                      ),
                      _statCard(
                        title: 'P&L / سرمایه اولیه',
                        value:
                            '${numbers.formatNumber(_pnlInitialBalancePercent, decimals: 2, trimTrailingZeros: false)}%',
                        numericValue: _pnlInitialBalancePercent,
                      ),
                      _statCard(
                        title: 'P&L / بالانس',
                        value:
                            '${numbers.formatNumber(_pnlCurrentBalancePercent, decimals: 2, trimTrailingZeros: false)}%',
                        numericValue: _pnlCurrentBalancePercent,
                      ),
                      _statCard(
                        title: 'R/R کل',
                        value: numbers.formatNumber(_totalRiskReward,
                            decimals: 2, trimTrailingZeros: false),
                      ),
                      _statCard(
                        title: 'Volume کل',
                        value:
                            '${numbers.formatNumber(_totalVolume, decimals: 2, trimTrailingZeros: false)} \$',
                      ),
                      _statCard(
                        title: 'Margin کل',
                        value:
                            '${numbers.formatNumber(_totalMargin, decimals: 2, trimTrailingZeros: false)} \$',
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}
