import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:docx_dart/docx_dart.dart' as docx;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';

import '../calculators/pnl_calculator.dart';
import '../database/app_database.dart';
import '../models/ticker.dart';
import '../models/trade.dart';
import '../repositories/account_repository.dart';
import '../repositories/price_alert_repository.dart';
import '../repositories/trade_repository.dart';
import '../services/lbank_service.dart';
import '../services/notification_service.dart';
import '../widgets/trade_card.dart';
import 'asset_management_page.dart';
import 'analysis_page.dart';
import 'custom_fields_page.dart';
import 'new_trade_page.dart' as new_trade;
import 'open_positions_tab.dart';
import 'pre_trade_management_page.dart';
import 'price_alerts_page.dart';
import 'reports_page.dart';
import 'trade_card_settings_page.dart';
import 'trade_details_page.dart';
import 'trade_notes_page.dart' as trade_notes;
import 'number_display_settings_page.dart';
import 'package:lbank_gold/pages/import_export_page.dart';
import '../utils/number_formatter.dart' as numbers;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TradeRepository _tradeRepository = TradeRepository();

  final AppDatabase _database = AppDatabase.instance;

  final AccountRepository _accountRepository = AccountRepository();

  final Map<String, double> _livePrices = {};
  final Map<String, LBankService> _lbankServices = {};
  final Map<String, StreamSubscription<Ticker>> _tickerSubscriptions = {};
  final Map<String, double> _pendingLivePrices = {};
  final Set<String> _simulatedLiquidationsInProgress = {};

  Timer? _uiUpdateTimer;

  static const Duration _uiUpdateInterval = Duration(milliseconds: 300);

  List<Trade> _openTrades = [];
  List<Trade> _closedTrades = [];
  List<Trade> _rangeOpenTrades = [];
  List<Trade> _rangeClosedTrades = [];
  DateTimeRange? _pnlDateRange;
  bool _loadingPnlRange = false;

  double _initialBalance = 0;

  // =========================================================
  // ACCOUNT TARGETS
  // =========================================================

  double _dailyTarget = 0;
  double _weeklyTarget = 0;
  double _monthlyTarget = 0;

  double _todayPnl = 0;
  double _weekPnl = 0;
  double _monthPnl = 0;

  double _dailyProgress = 0;
  double _weeklyProgress = 0;
  double _monthlyProgress = 0;

  bool _loading = true;
  bool _isAppActive = true;

  int _tabIndex = 0;

  static const List<String> _tabTitles = [
    'داشبورد',
    'معاملات باز',
    'تحلیل‌ها',
    'گزارش‌ها و آمار',
    'موارد سفارشی',
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initialize();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resumeLivePrices();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _pauseLivePrices();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _pauseLivePrices() async {
    if (!_isAppActive) {
      return;
    }

    _isAppActive = false;

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    _pendingLivePrices.clear();

    final services = _lbankServices.values.toList();

    for (final service in services) {
      try {
        await service.pause();
      } catch (_) {}
    }
  }

  Future<void> _resumeLivePrices() async {
    if (!mounted) {
      return;
    }

    if (_isAppActive) {
      return;
    }

    _isAppActive = true;

    final services = _lbankServices.values.toList();

    for (final service in services) {
      if (!_isAppActive) {
        return;
      }

      try {
        await service.resume();
      } catch (_) {}
    }
  }

  Future<void> _initialize() async {
    await _loadTrades();
  }

  String _normalizeSymbol(
    String symbol,
  ) {
    return symbol.trim().toUpperCase();
  }

  double _livePriceForTrade(
    Trade trade,
  ) {
    final symbol = _normalizeSymbol(
      trade.assetSymbol,
    );

    return _livePrices[symbol] ?? 0;
  }

  void _scheduleUiUpdate() {
    if (!mounted || !_isAppActive) {
      return;
    }

    if (_uiUpdateTimer != null) {
      return;
    }

    _uiUpdateTimer = Timer(
      _uiUpdateInterval,
      () {
        _uiUpdateTimer = null;

        if (!mounted || !_isAppActive) {
          _pendingLivePrices.clear();
          return;
        }

        if (_pendingLivePrices.isEmpty) {
          return;
        }

        final updates = Map<String, double>.from(_pendingLivePrices);
        setState(() {
          _livePrices.addAll(updates);
          _pendingLivePrices.clear();
        });
        for (final entry in updates.entries) {
          _checkSimulatedLiquidation(entry.key, entry.value);
        }
      },
    );
  }

  Future<void> _checkSimulatedLiquidation(String symbol, double price) async {
    final affected = _openTrades
        .where((trade) =>
            _normalizeSymbol(trade.assetSymbol) == symbol &&
            !_simulatedLiquidationsInProgress.contains(trade.tradeId))
        .toList();
    if (affected.isEmpty || price <= 0) return;

    final toClose = <Trade>[];
    for (final trade in affected) {
      if (trade.marginMode != 'cross' && trade.marginAmount > 0) {
        final pnl = PnlCalculator.netPnl(trade, price);
        if (pnl <= -trade.marginAmount) toClose.add(trade);
      }
    }

    final crossTrades =
        _openTrades.where((trade) => trade.marginMode == 'cross').toList();
    if (crossTrades.isNotEmpty) {
      var unrealized = 0.0;
      for (final trade in crossTrades) {
        final current = _normalizeSymbol(trade.assetSymbol) == symbol
            ? price
            : _livePrices[_normalizeSymbol(trade.assetSymbol)] ?? 0;
        if (current > 0) unrealized += PnlCalculator.netPnl(trade, current);
      }
      if (_currentBalance > 0 && _currentBalance + unrealized <= 0) {
        for (final trade in crossTrades) {
          if (!_simulatedLiquidationsInProgress.contains(trade.tradeId))
            toClose.add(trade);
        }
      }
    }

    if (toClose.isEmpty) return;
    for (final trade in toClose) {
      _simulatedLiquidationsInProgress.add(trade.tradeId);
      try {
        final currentPrice = _normalizeSymbol(trade.assetSymbol) == symbol
            ? price
            : _livePrices[_normalizeSymbol(trade.assetSymbol)] ?? price;
        final pnl = PnlCalculator.netPnl(trade, currentPrice);
        final adversePercent = trade.entryPrice == null ||
                trade.entryPrice! <= 0
            ? 0.0
            : (trade.tradeDirection == TradeDirection.long
                    ? ((trade.entryPrice! - currentPrice) / trade.entryPrice!) *
                        100
                    : ((currentPrice - trade.entryPrice!) / trade.entryPrice!) *
                        100)
                .clamp(0.0, double.infinity)
                .toDouble();
        final now = DateTime.now();
        final closed = trade.copyWith(
          tradeStatus: TradeStatus.closed,
          exitPrice: currentPrice,
          exitTime: now,
          finalPnl: pnl,
          finalRoiPercent:
              trade.marginAmount > 0 ? pnl / trade.marginAmount * 100 : 0,
          finalRoiDollar: pnl,
          finalRiskReward: 0,
          maxDrawdownPricePercent:
              adversePercent > trade.maxDrawdownPricePercent
                  ? adversePercent
                  : trade.maxDrawdownPricePercent,
          maxDrawdownDollar: trade.volumeAmount * adversePercent / 100,
          maxDrawdownMarginPercent: trade.marginAmount > 0
              ? trade.volumeAmount *
                  adversePercent /
                  100 /
                  trade.marginAmount *
                  100
              : 0,
          durationSeconds: now.difference(trade.entryTime).inSeconds,
        );
        await _tradeRepository.updateTrade(closed);
        try {
          await NotificationService.instance.showCustomNotification(
            title: 'لیکوییدیشن شبیه‌سازی‌شده',
            body:
                '${trade.assetSymbol} · ${trade.tradeDirection == TradeDirection.long ? 'لانگ' : 'شورت'} با P&L ${numbers.formatNumber(pnl, decimals: 2, trimTrailingZeros: false)} USD در ژورنال بسته شد. سفارش واقعی ارسال نشد.',
          );
        } catch (_) {}
      } catch (_) {
        _simulatedLiquidationsInProgress.remove(trade.tradeId);
      }
    }
    await _loadTrades();
    _simulatedLiquidationsInProgress.clear();
  }

  Future<void> _syncTickerServices() async {
    if (!mounted) {
      return;
    }

    final openTradeSymbols = _openTrades
        .map(
          (trade) => _normalizeSymbol(
            trade.assetSymbol,
          ),
        )
        .where(
          (symbol) => symbol.isNotEmpty,
        )
        .toSet();

    final activeAlerts = await PriceAlertRepository.instance.getActiveAlerts();

    final alertSymbols = activeAlerts
        .map(
          (alert) => _normalizeSymbol(
            alert.symbol,
          ),
        )
        .where(
          (symbol) => symbol.isNotEmpty,
        )
        .toSet();

    final requiredSymbols = <String>{
      ...openTradeSymbols,
      ...alertSymbols,
    };

    final existingSymbols = _lbankServices.keys.toList();

    for (final symbol in existingSymbols) {
      if (requiredSymbols.contains(symbol)) {
        continue;
      }

      await _tickerSubscriptions[symbol]?.cancel();

      _tickerSubscriptions.remove(symbol);

      await _lbankServices[symbol]?.dispose();

      _lbankServices.remove(symbol);

      _livePrices.remove(symbol);

      _pendingLivePrices.remove(symbol);
    }

    for (final symbol in requiredSymbols) {
      if (_lbankServices.containsKey(symbol)) {
        continue;
      }

      final service = LBankService();

      _lbankServices[symbol] = service;

      final subscription = service.tickerStream.listen(
        (ticker) {
          if (!mounted) {
            return;
          }

          if (!_isAppActive) {
            return;
          }

          if (ticker.price <= 0) {
            return;
          }

          _pendingLivePrices[symbol] = ticker.price;

          _scheduleUiUpdate();
        },
      );

      _tickerSubscriptions[symbol] = subscription;

      if (!_isAppActive) {
        continue;
      }

      try {
        await service.connect(symbol);
      } catch (_) {}
    }
  }

  // =========================================================
  // LOAD DATA
  // =========================================================

  Future<void> _loadTrades() async {
    final openTrades = await _tradeRepository.getOpenTrades();

    final closedTrades = await _tradeRepository.getClosedTrades();

    final accountSummary = await _accountRepository.getAccountSummary();

    if (!mounted) {
      return;
    }

    setState(() {
      _openTrades = openTrades;
      _closedTrades = closedTrades;

      _initialBalance =
          (accountSummary['initial_balance'] as num?)?.toDouble() ?? 0;

      _dailyTarget =
          (accountSummary['daily_target_amount'] as num?)?.toDouble() ?? 0;

      _weeklyTarget =
          (accountSummary['weekly_target_amount'] as num?)?.toDouble() ?? 0;

      _monthlyTarget =
          (accountSummary['monthly_target_amount'] as num?)?.toDouble() ?? 0;

      _todayPnl = (accountSummary['today_pnl'] as num?)?.toDouble() ?? 0;

      _weekPnl = (accountSummary['week_pnl'] as num?)?.toDouble() ?? 0;

      _monthPnl = (accountSummary['month_pnl'] as num?)?.toDouble() ?? 0;

      _dailyProgress =
          (accountSummary['daily_progress'] as num?)?.toDouble() ?? 0;

      _weeklyProgress =
          (accountSummary['weekly_progress'] as num?)?.toDouble() ?? 0;

      _monthlyProgress =
          (accountSummary['monthly_progress'] as num?)?.toDouble() ?? 0;

      _loading = false;
    });

    await _syncTickerServices();
    if (_pnlDateRange != null) {
      await _loadPnlDateRange(_pnlDateRange!);
    }
  }

  Future<void> _selectPnlDateRange() async {
    final now = DateTime.now();
    final initial = _pnlDateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day),
        );
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: initial,
      helpText: 'انتخاب بازه محاسبه سود و زیان',
      saveText: 'اعمال بازه',
      cancelText: 'انصراف',
      confirmText: 'تأیید',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _pnlDateRange = selected;
      _loadingPnlRange = true;
    });
    await _loadPnlDateRange(selected);
  }

  Future<void> _loadPnlDateRange(DateTimeRange range) async {
    if (!mounted) return;
    setState(() => _loadingPnlRange = true);
    try {
      final results = await Future.wait([
        _tradeRepository.getOpenTradesInRange(
            start: range.start, end: range.end),
        _tradeRepository.getClosedTradesInRange(
            start: range.start, end: range.end),
      ]);
      if (!mounted) return;
      setState(() {
        _rangeOpenTrades = results[0];
        _rangeClosedTrades = results[1];
        _loadingPnlRange = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPnlRange = false);
    }
  }

  void _clearPnlDateRange() {
    setState(() {
      _pnlDateRange = null;
      _rangeOpenTrades = [];
      _rangeClosedTrades = [];
    });
  }

  String _formatPnlDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

  double get _openPnl => PnlCalculator.openTradesPnl(_openTrades, _livePrices);

  double get _closedPnl => PnlCalculator.closedTradesPnl(_closedTrades);

  double get _combinedPnl =>
      PnlCalculator.totalTradesPnl(_openTrades, _closedTrades, _livePrices);

  double get _rangeOpenPnl =>
      PnlCalculator.openTradesPnl(_rangeOpenTrades, _livePrices);

  double get _rangeClosedPnl =>
      PnlCalculator.closedTradesPnl(_rangeClosedTrades);

  double get _rangeCombinedPnl => PnlCalculator.totalTradesPnl(
      _rangeOpenTrades, _rangeClosedTrades, _livePrices);

  // =========================================================
  // P&L
  // =========================================================

  double _tradeFinalPnl(
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
      (sum, trade) => sum + _tradeFinalPnl(trade),
    );
  }

  double get _totalProfit {
    return _closedTrades.fold(
      0,
      (sum, trade) {
        final pnl = _tradeFinalPnl(trade);

        return sum + (pnl > 0 ? pnl : 0);
      },
    );
  }

  double get _totalLoss {
    return _closedTrades.fold(
      0,
      (sum, trade) {
        final pnl = _tradeFinalPnl(trade);

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

  double get _averageEntryPrice {
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

    double totalPriceVolume = 0;
    double totalVolume = 0;

    for (final trade in trades) {
      totalPriceVolume += trade.entryPrice! * trade.volumeAmount;

      totalVolume += trade.volumeAmount;
    }

    if (totalVolume <= 0) {
      return 0;
    }

    return totalPriceVolume / totalVolume;
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
    if (_currentBalance <= 0) {
      return 0;
    }

    return _totalPnl / _currentBalance * 100;
  }

  int get _winningTradeCount {
    return _closedTrades
        .where(
          (trade) => _tradeFinalPnl(trade) > 0,
        )
        .length;
  }

  int get _losingTradeCount {
    return _closedTrades
        .where(
          (trade) => _tradeFinalPnl(trade) < 0,
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

  // =========================================================
  // EDIT ACCOUNT
  // =========================================================

  Future<void> _editAccountSettings() async {
    final initialController = TextEditingController(
      text: _initialBalance == 0 ? '' : _initialBalance.toString(),
    );

    final dailyController = TextEditingController(
      text: _dailyTarget == 0 ? '' : _dailyTarget.toString(),
    );

    final weeklyController = TextEditingController(
      text: _weeklyTarget == 0 ? '' : _weeklyTarget.toString(),
    );

    final monthlyController = TextEditingController(
      text: _monthlyTarget == 0 ? '' : _monthlyTarget.toString(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'سرمایه و اهداف حساب',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: initialController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'سرمایه اولیه (Initial Capital)',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                TextField(
                  controller: dailyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'تارگت روزانه (Daily Target)',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                TextField(
                  controller: weeklyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'تارگت هفتگی (Weekly Target)',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                TextField(
                  controller: monthlyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'تارگت ماهانه (Monthly Target)',
                    prefixText: '\$ ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'لغو',
              ),
            ),
            FilledButton(
              onPressed: () {
                final initial = double.tryParse(
                      numbers
                          .normalizeNumberInput(initialController.text)
                          .trim()
                          .replaceAll(',', ''),
                    ) ??
                    0;

                final daily = double.tryParse(
                      numbers
                          .normalizeNumberInput(dailyController.text)
                          .trim()
                          .replaceAll(',', ''),
                    ) ??
                    0;

                final weekly = double.tryParse(
                      numbers
                          .normalizeNumberInput(weeklyController.text)
                          .trim()
                          .replaceAll(',', ''),
                    ) ??
                    0;

                final monthly = double.tryParse(
                      numbers
                          .normalizeNumberInput(monthlyController.text)
                          .trim()
                          .replaceAll(',', ''),
                    ) ??
                    0;

                if (initial < 0 || daily < 0 || weekly < 0 || monthly < 0) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'مقادیر نمی‌توانند منفی باشند.',
                      ),
                    ),
                  );

                  return;
                }

                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'ذخیره',
              ),
            ),
          ],
        );
      },
    );

    if (result != true) {
      initialController.dispose();
      dailyController.dispose();
      weeklyController.dispose();
      monthlyController.dispose();

      return;
    }

    final initial = double.tryParse(
          numbers
              .normalizeNumberInput(initialController.text)
              .trim()
              .replaceAll(',', ''),
        ) ??
        0;

    final daily = double.tryParse(
          numbers
              .normalizeNumberInput(dailyController.text)
              .trim()
              .replaceAll(',', ''),
        ) ??
        0;

    final weekly = double.tryParse(
          numbers
              .normalizeNumberInput(weeklyController.text)
              .trim()
              .replaceAll(',', ''),
        ) ??
        0;

    final monthly = double.tryParse(
          numbers
              .normalizeNumberInput(monthlyController.text)
              .trim()
              .replaceAll(',', ''),
        ) ??
        0;

    initialController.dispose();
    dailyController.dispose();
    weeklyController.dispose();
    monthlyController.dispose();

    await _accountRepository.saveAccountSettings(
      initialBalance: initial,
      dailyTargetAmount: daily,
      weeklyTargetAmount: weekly,
      monthlyTargetAmount: monthly,
    );

    await _loadTrades();
  }

  // =========================================================
  // NAVIGATION
  // =========================================================

  String _tradeExportLabel(String key) {
    const labels = <String, String>{
      'trade_id': 'شناسه معامله',
      'asset_symbol': 'دارایی',
      'trade_direction': 'جهت معامله',
      'trade_type': 'نوع معامله',
      'trade_status': 'وضعیت معامله',
      'trade_timeframe': 'تایم‌فریم',
      'margin_mode': 'حالت مارجین',
      'margin_amount': 'مقدار مارجین (دلار)',
      'leverage_value': 'اهرم',
      'volume_amount': 'حجم معامله (دلار)',
      'fee_per_hundred': 'کارمزد به ازای هر ۱۰۰',
      'trade_fee': 'کارمزد معامله',
      'entry_price': 'قیمت ورود',
      'exit_price': 'قیمت خروج',
      'stop_price': 'حد ضرر',
      'target_price': 'حد سود',
      'risk_distance': 'فاصله ریسک',
      'reward_distance': 'فاصله ریوارد',
      'risk_value': 'مقدار ریسک (دلار)',
      'reward_value': 'مقدار ریوارد (دلار)',
      'trade_risk_reward': 'نسبت ریسک به ریوارد',
      'final_pnl': 'سود و زیان نهایی (دلار)',
      'final_roi_percent': 'بازده نهایی (درصد)',
      'final_roi_dollar': 'بازده نهایی (دلار)',
      'final_risk_reward': 'نسبت ریسک به ریوارد نهایی',
      'max_drawdown_price_percent': 'بیشترین افت قیمت (درصد)',
      'max_drawdown_dollar': 'بیشترین افت (دلار)',
      'max_drawdown_margin_percent': 'افت نسبت به مارجین (درصد)',
      'duration_seconds': 'مدت معامله (ثانیه)',
      'entry_setup': 'ستاپ ورود',
      'entry_reason': 'دلیل ورود',
      'entry_motivation': 'انگیزه ورود',
      'expected_scenario': 'سناریوی مورد انتظار',
      'entry_time': 'زمان ورود',
      'exit_time': 'زمان خروج',
    };
    return labels[key] ?? key;
  }

  String _tradeExportValue(String key, Object? value) {
    if (value == null || value.toString().trim().isEmpty) return '—';
    final raw = value.toString();
    if (key == 'trade_direction')
      return raw == 'long'
          ? 'لانگ'
          : raw == 'short'
              ? 'شورت'
              : raw;
    if (key == 'trade_type')
      return raw == 'scalp'
          ? 'اسکالپ'
          : raw == 'day'
              ? 'روزانه'
              : raw;
    if (key == 'trade_status')
      return raw == 'open'
          ? 'باز'
          : raw == 'closed'
              ? 'بسته'
              : raw;
    if (key == 'margin_mode') return raw == 'cross' ? 'کراس' : 'ایزوله';
    if (key == 'entry_time' || key == 'exit_time') {
      final date = DateTime.tryParse(raw);
      if (date != null) return date.toLocal().toString();
    }
    if (value is num) {
      if (key.contains('price'))
        return numbers.formatNumber(value.toDouble(),
            decimals: 4, trimTrailingZeros: false);
      if (key.contains('percent'))
        return '${numbers.formatNumber(value.toDouble(), decimals: 2, trimTrailingZeros: false)}٪';
      if (key.contains('amount') ||
          key.contains('pnl') ||
          key.contains('roi') ||
          key.contains('fee') ||
          key.contains('value'))
        return numbers.formatNumber(value.toDouble(),
            decimals: 2, trimTrailingZeros: false);
    }
    return raw;
  }

  Future<void> _exportTradeHistory(String format) async {
    try {
      final db = await _database.database;
      final rows = <Map<String, dynamic>>[];
      for (final trade in _closedTrades) {
        final map = trade.toMap();
        map['custom_values'] = await db.query('trade_custom_values',
            where: 'trade_id = ?', whereArgs: [trade.tradeId]);
        map['pre_trade_values'] = await db.query('trade_pre_trade_values',
            where: 'trade_id = ?', whereArgs: [trade.tradeId]);
        map['experiences'] = await db.query('trade_experiences',
            where: 'trade_id = ?', whereArgs: [trade.tradeId]);
        rows.add(map);
      }
      if (format == 'docx') {
        final document = docx.loadDocxDocument();
        document.addHeading(text: 'تاریخچه معاملات', level: 1);
        document.addParagraph(
            text: 'تاریخ خروجی: ${DateTime.now().toIso8601String()}');
        for (final row in rows) {
          document.addHeading(
              text: 'معامله ${(row['trade_id'] ?? '').toString()}', level: 2);
          for (final entry in row.entries) {
            if (entry.key == 'custom_values' ||
                entry.key == 'pre_trade_values' ||
                entry.key == 'experiences') continue;
            document.addParagraph(
              text:
                  '${_tradeExportLabel(entry.key)}: ${_tradeExportValue(entry.key, entry.value)}',
            );
          }
          final customValues = row['custom_values'];
          if (customValues is List && customValues.isNotEmpty) {
            document.addHeading(text: 'مقادیر فیلدهای سفارشی', level: 3);
            for (final item in customValues) {
              if (item is Map)
                document.addParagraph(
                    text:
                        'فیلد ${item['field_id'] ?? ''}: ${item['value_text'] ?? item['value'] ?? ''}');
            }
          }
          final preTradeValues = row['pre_trade_values'];
          if (preTradeValues is List && preTradeValues.isNotEmpty) {
            document.addHeading(text: 'پاسخ سؤال‌ها و چک‌لیست‌ها', level: 3);
            for (final item in preTradeValues) {
              if (item is Map)
                document.addParagraph(
                    text:
                        'مورد ${item['item_id'] ?? ''}: ${item['value_text'] ?? ''}');
            }
          }
          final experiences = row['experiences'];
          if (experiences is List && experiences.isNotEmpty) {
            document.addHeading(text: 'تجربه‌ها', level: 3);
            for (final item in experiences) {
              if (item is Map)
                document.addParagraph(
                    text:
                        '${item['experience_title'] ?? 'تجربه'}: ${item['experience_description'] ?? ''}');
            }
          }
        }
        final tempDir = await getTemporaryDirectory();
        final tempPath = p.join(tempDir.path,
            'trade_history_${DateTime.now().microsecondsSinceEpoch}.docx');
        try {
          document.save(tempPath);
          final bytes = Uint8List.fromList(await File(tempPath).readAsBytes());
          final path = await FilePicker.platform.saveFile(
            dialogTitle: 'خروجی Word تاریخچه معاملات',
            fileName: 'trade_history.docx',
            type: FileType.custom,
            allowedExtensions: ['docx'],
            bytes: bytes,
          );
          if (path != null && mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('خروجی Word تاریخچه ذخیره شد.')));
        } finally {
          final file = File(tempPath);
          if (await file.exists()) await file.delete();
        }
        return;
      }
      String content;
      if (format == 'json') {
        content = const JsonEncoder.withIndent('  ').convert({
          'created_at': DateTime.now().toIso8601String(),
          'record_count': rows.length,
          'trades': rows,
        });
      } else if (format == 'csv') {
        final headers = [
          'trade_id',
          'asset_symbol',
          'trade_direction',
          'trade_type',
          'trade_status',
          'trade_timeframe',
          'margin_amount',
          'leverage_value',
          'volume_amount',
          'fee_per_hundred',
          'trade_fee',
          'entry_price',
          'exit_price',
          'stop_price',
          'target_price',
          'risk_distance',
          'reward_distance',
          'risk_value',
          'reward_value',
          'trade_risk_reward',
          'final_pnl',
          'final_roi_percent',
          'final_roi_dollar',
          'final_risk_reward',
          'max_drawdown_price_percent',
          'max_drawdown_dollar',
          'max_drawdown_margin_percent',
          'duration_seconds',
          'entry_setup',
          'entry_reason',
          'entry_motivation',
          'expected_scenario',
          'entry_time',
          'exit_time',
          'custom_values',
          'pre_trade_values',
          'experiences'
        ];
        final csvRows = <List<String>>[headers];
        for (final row in rows) {
          csvRows.add(headers
              .map((key) => row[key] is List || row[key] is Map
                  ? jsonEncode(row[key])
                  : (row[key]?.toString() ?? ''))
              .toList());
        }
        content = csvRows
            .map((row) => row.map((value) {
                  final escaped = value.replaceAll('"', '""');
                  return '"$escaped"';
                }).join(','))
            .join('\n');
      } else {
        final buffer = StringBuffer(
            'تاریخچه معاملات بسته\nتاریخ خروجی: ${DateTime.now().toIso8601String()}\n');
        for (final row in rows) {
          buffer.writeln('\n==============================');
          for (final entry in row.entries) {
            final rawValue = entry.value;
            final valueText = rawValue is Map || rawValue is List
                ? const JsonEncoder.withIndent('  ').convert(rawValue)
                : rawValue.toString();
            buffer.writeln('${entry.key}: $valueText');
          }
        }
        content = buffer.toString();
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'خروجی تاریخچه معاملات',
        fileName: 'trade_history.$format',
        type: FileType.custom,
        allowedExtensions: [format],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خروجی تاریخچه ذخیره شد.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خروجی تاریخچه ناموفق بود: $e')));
    }
  }

  Future<void> _openNewTrade() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return new_trade.NewTradePage();
        },
      ),
    );

    await _loadTrades();
  }

  Future<void> _openAssetManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const AssetManagementPage();
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadTrades();
  }

  Future<void> _openCustomFields() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const CustomFieldsPage();
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadTrades();
  }

  Future<void> _openPreTradeManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const PreTradeManagementPage();
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadTrades();
  }

  Future<void> _openPriceAlerts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const PriceAlertsPage();
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _syncTickerServices();
  }

  Future<void> _openTrade(
    Trade trade,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return TradeDetailsPage(
            trade: trade,
            livePrice: _livePriceForTrade(
              trade,
            ),
            onChanged: _loadTrades,
          );
        },
      ),
    );

    await _loadTrades();
  }

  Future<void> _refresh() async {
    await _loadTrades();
  }

  void _openThemeSettings() {
    Navigator.pushNamed(
      context,
      '/theme-settings',
    );
  }

  void _openTradeCardSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const TradeCardSettingsPage();
        },
      ),
    );
  }

  Future<void> _openImportExport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ImportExportPage(),
      ),
    );

    if (!mounted) return;

    await _loadTrades();
  }

  // =========================================================
  // STAT ROW
  // =========================================================

  Widget _statRow(
    String title,
    String value, {
    Color? valueColor,
  }) {
    return ListTile(
      title: Text(title),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: valueColor,
        ),
      ),
    );
  }

  Color? _pnlColor(
    double value,
  ) {
    if (value > 0) {
      return Colors.green;
    }

    if (value < 0) {
      return Colors.red;
    }

    return null;
  }

  // =========================================================
  // INITIAL BALANCE + TARGETS
  // =========================================================

  Widget _initialBalanceSection() {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 20,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'سرمایه و اهداف حساب',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _editAccountSettings,
                  icon: const Icon(
                    Icons.edit,
                  ),
                  label: const Text(
                    'ویرایش',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16,
            ),
            _statRow(
              'سرمایه اولیه (Initial Capital)',
              '\$${numbers.formatNumber(_initialBalance, decimals: 2, trimTrailingZeros: false)}',
            ),
            const Divider(height: 1),
            _statRow(
              'تارگت روزانه (Daily Target)',
              '\$${numbers.formatNumber(_dailyTarget, decimals: 2, trimTrailingZeros: false)}',
            ),
            const Divider(height: 1),
            _statRow(
              'تارگت هفتگی (Weekly Target)',
              '\$${numbers.formatNumber(_weeklyTarget, decimals: 2, trimTrailingZeros: false)}',
            ),
            const Divider(height: 1),
            _statRow(
              'تارگت ماهانه (Monthly Target)',
              '\$${numbers.formatNumber(_monthlyTarget, decimals: 2, trimTrailingZeros: false)}',
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // TARGET PERFORMANCE
  // =========================================================

  double _targetRemaining(
    double actual,
    double target,
  ) {
    if (target <= 0) {
      return 0;
    }

    final remaining = target - actual;

    return remaining > 0 ? remaining : 0;
  }

  Widget _targetRow({
    required String title,
    required double actual,
    required double target,
    required double progress,
  }) {
    final remaining = _targetRemaining(actual, target);

    final achieved = target > 0 && actual >= target;

    final actualColor = _pnlColor(actual);

    final progressValue =
        target > 0 ? (progress / 100).clamp(0.0, 1.0).toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                achieved ? 'محقق شد' : 'محقق نشده',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: achieved ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'عملکرد: \$${numbers.formatNumber(actual, decimals: 2, trimTrailingZeros: false)}',
                  style: TextStyle(
                    color: actualColor,
                  ),
                ),
              ),
              Text(
                'هدف: \$${numbers.formatNumber(target, decimals: 2, trimTrailingZeros: false)}',
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          LinearProgressIndicator(
            value: progressValue,
          ),
          const SizedBox(
            height: 6,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'تحقق: ${numbers.formatNumber(progress, decimals: 1, trimTrailingZeros: false)}%',
                ),
              ),
              if (target > 0)
                Text(
                  achieved
                      ? 'مازاد: \$${numbers.formatNumber((actual - target), decimals: 2, trimTrailingZeros: false)}'
                      : 'باقی‌مانده: \$${numbers.formatNumber(remaining, decimals: 2, trimTrailingZeros: false)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetStatisticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اهداف عملکردی',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _targetRow(
                  title: 'هدف روزانه (Daily Target)',
                  actual: _todayPnl,
                  target: _dailyTarget,
                  progress: _dailyProgress,
                ),
                const Divider(),
                _targetRow(
                  title: 'هدف هفتگی (Weekly Target)',
                  actual: _weekPnl,
                  target: _weeklyTarget,
                  progress: _weeklyProgress,
                ),
                const Divider(),
                _targetRow(
                  title: 'هدف ماهانه (Monthly Target)',
                  actual: _monthPnl,
                  target: _monthlyTarget,
                  progress: _monthlyProgress,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // GENERAL STATISTICS
  // =========================================================

  Widget _pnlOverviewSection() {
    final range = _pnlDateRange;
    final openPnl = range == null ? _openPnl : _rangeOpenPnl;
    final closedPnl = range == null ? _closedPnl : _rangeClosedPnl;
    final totalPnl = range == null ? _combinedPnl : _rangeCombinedPnl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('سود و زیان حساب',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  TextButton.icon(
                    onPressed: _selectPnlDateRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(range == null ? 'انتخاب بازه' : 'تغییر بازه'),
                  ),
                  if (range != null)
                    IconButton(
                      tooltip: 'نمایش کل دوره',
                      onPressed: _clearPnlDateRange,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            if (range != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${_formatPnlDate(range.start)} تا ${_formatPnlDate(range.end)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            if (_loadingPnlRange)
              const LinearProgressIndicator(minHeight: 2)
            else ...[
              _statRow(
                  'سود و زیان معاملات باز',
                  numbers.formatNumber(openPnl,
                      decimals: 2, trimTrailingZeros: false),
                  valueColor: _pnlColor(openPnl)),
              const Divider(height: 1),
              _statRow(
                  'سود و زیان معاملات بسته',
                  numbers.formatNumber(closedPnl,
                      decimals: 2, trimTrailingZeros: false),
                  valueColor: _pnlColor(closedPnl)),
              const Divider(height: 1),
              _statRow(
                  'سود و زیان کل',
                  numbers.formatNumber(totalPnl,
                      decimals: 2, trimTrailingZeros: false),
                  valueColor: _pnlColor(totalPnl)),
            ],
            if (range != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'معاملات باز بر اساس تاریخ ورود و معاملات بسته بر اساس تاریخ خروج در بازه انتخابی محاسبه می‌شوند. سود معاملات باز با قیمت لحظه‌ای فعلی سنجیده می‌شود.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statisticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'آمار حساب',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        _pnlOverviewSection(),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              _statRow(
                'بالانس فعلی',
                numbers.formatNumber(_currentBalance,
                    decimals: 2, trimTrailingZeros: false),
                valueColor: _pnlColor(
                  _currentBalance - _initialBalance,
                ),
              ),
              const Divider(height: 1),
              _statRow(
                'P&L تحقق‌یافته',
                numbers.formatNumber(_totalPnl,
                    decimals: 2, trimTrailingZeros: false),
                valueColor: _pnlColor(_totalPnl),
              ),
              const Divider(height: 1),
              _statRow(
                'کل سود',
                numbers.formatNumber(_totalProfit,
                    decimals: 2, trimTrailingZeros: false),
                valueColor: _pnlColor(_totalProfit),
              ),
              const Divider(height: 1),
              _statRow(
                'کل ضرر',
                numbers.formatNumber(_totalLoss,
                    decimals: 2, trimTrailingZeros: false),
                valueColor: _totalLoss > 0 ? Colors.red : null,
              ),
              const Divider(height: 1),
              _statRow(
                'تعداد معاملات',
                numbers
                    .formatInteger(_closedTrades.length + _openTrades.length),
              ),
              const Divider(height: 1),
              _statRow(
                'معاملات سودده',
                numbers.formatInteger(_winningTradeCount),
                valueColor: _winningTradeCount > 0 ? Colors.green : null,
              ),
              const Divider(height: 1),
              _statRow(
                'معاملات ضررده',
                numbers.formatInteger(_losingTradeCount),
                valueColor: _losingTradeCount > 0 ? Colors.red : null,
              ),
              const Divider(height: 1),
              _statRow(
                'میانگین P&L',
                numbers.formatNumber(_averageTradePnl,
                    decimals: 2, trimTrailingZeros: false),
                valueColor: _pnlColor(
                  _averageTradePnl,
                ),
              ),
              const Divider(height: 1),
              _statRow(
                'میانگین Entry وزنی',
                numbers.formatNumber(_averageEntryPrice,
                    decimals: 2, trimTrailingZeros: false),
              ),
              const Divider(height: 1),
              _statRow(
                'P&L / Volume',
                '${numbers.formatNumber(_pnlVolumePercent, decimals: 2, trimTrailingZeros: false)}%',
                valueColor: _pnlColor(
                  _pnlVolumePercent,
                ),
              ),
              const Divider(height: 1),
              _statRow(
                'P&L / Margin',
                '${numbers.formatNumber(_pnlMarginPercent, decimals: 2, trimTrailingZeros: false)}%',
                valueColor: _pnlColor(
                  _pnlMarginPercent,
                ),
              ),
              const Divider(height: 1),
              _statRow(
                'P&L / سرمایه اولیه',
                '${numbers.formatNumber(_pnlInitialBalancePercent, decimals: 2, trimTrailingZeros: false)}%',
                valueColor: _pnlColor(
                  _pnlInitialBalancePercent,
                ),
              ),
              const Divider(height: 1),
              _statRow(
                'P&L / بالانس',
                '${numbers.formatNumber(_pnlCurrentBalancePercent, decimals: 2, trimTrailingZeros: false)}%',
                valueColor: _pnlColor(
                  _pnlCurrentBalancePercent,
                ),
              ),
              const Divider(height: 1),
              _statRow(
                'R/R کل',
                numbers.formatNumber(_totalRiskReward,
                    decimals: 2, trimTrailingZeros: false),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // DASHBOARD
  // =========================================================

  Widget _dashboardTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // سرمایه و اهداف حساب در صفحه مدیریت دارایی‌ها قرار گرفته‌اند.
          _targetStatisticsSection(),
          const SizedBox(
            height: 20,
          ),
          if (_openTrades.isNotEmpty) ...[
            const Text(
              'معاملات باز',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            ..._openTrades.map(
              (trade) {
                return TradeCard(
                  trade: trade,
                  livePrice: _livePriceForTrade(
                    trade,
                  ),
                  onTap: () => _openTrade(trade),
                );
              },
            ),
            const SizedBox(
              height: 10,
            ),
          ],
          _statisticsSection(),
          const SizedBox(
            height: 100,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HISTORY
  // =========================================================

  Widget _historyTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_closedTrades.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: 60,
              ),
              child: Center(
                child: Text(
                  'هنوز معامله بسته‌شده‌ای وجود ندارد.',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        children: _closedTrades.map(
          (trade) {
            return TradeCard(
              trade: trade,
              livePrice: 0,
              onTap: () => _openTrade(trade),
            );
          },
        ).toList(),
      ),
    );
  }

  // =========================================================
  // CUSTOM ITEMS
  // =========================================================

  Widget _customItemsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.tune,
            ),
            title: const Text(
              'فیلدهای سفارشی',
            ),
            subtitle: const Text(
              'افزودن و مدیریت فیلدهای دلخواه برای ثبت معامله',
            ),
            trailing: const Icon(
              Icons.chevron_left,
            ),
            onTap: _openCustomFields,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.checklist_outlined,
            ),
            title: const Text(
              'سؤالات و چک‌لیست‌ها',
            ),
            subtitle: const Text(
              'مدیریت سؤالات پیش از معامله و چک‌لیست‌ها',
            ),
            trailing: const Icon(
              Icons.chevron_left,
            ),
            onTap: _openPreTradeManagement,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.note_alt_outlined),
            title: const Text('یادداشت‌های معامله'),
            subtitle:
                const Text('مشاهده، جست‌وجو و مدیریت یادداشت‌های ذخیره‌شده'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const trade_notes.TradeNotesPage()),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('تنظیمات نمایش اعداد'),
            subtitle:
                const Text('انتخاب اعداد فارسی یا انگلیسی و جداسازی هزارگان'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NumberDisplaySettingsPage(),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.import_export,
            ),
            title: const Text(
              'ورود و خروجی اطلاعات',
            ),
            subtitle: const Text(
              'پشتیبان‌گیری، بازیابی و انتقال اطلاعات برنامه',
            ),
            trailing: const Icon(
              Icons.chevron_left,
            ),
            onTap: _openImportExport,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    for (final subscription in _tickerSubscriptions.values) {
      subscription.cancel();
    }

    for (final service in _lbankServices.values) {
      service.dispose();
    }

    _tickerSubscriptions.clear();
    _lbankServices.clear();

    _pendingLivePrices.clear();
    _livePrices.clear();

    super.dispose();
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final tabs = <Widget>[
      _dashboardTab(),
      OpenPositionsTab(
        openTrades: _openTrades,
        loading: _loading,
        onRefresh: _refresh,
        onChanged: _refresh,
      ),
      const AnalysisPage(),
      ReportsPage(
        embedded: true,
      ),
      _customItemsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tabTitles[_tabIndex],
        ),
        actions: [
          IconButton(
            tooltip: 'هشدارهای قیمت',
            onPressed: _openPriceAlerts,
            icon: const Icon(
              Icons.notifications_active_outlined,
            ),
          ),
          IconButton(
            tooltip: 'تنظیمات رنگ',
            onPressed: _openThemeSettings,
            icon: const Icon(
              Icons.palette_outlined,
            ),
          ),
          IconButton(
            tooltip: 'فیلدهای کارت معامله',
            onPressed: _openTradeCardSettings,
            icon: const Icon(
              Icons.view_list_outlined,
            ),
          ),
          IconButton(
            tooltip: 'مدیریت دارایی‌ها',
            onPressed: _openAssetManagement,
            icon: const Icon(
              Icons.account_balance_wallet,
            ),
          ),
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _tabIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _openNewTrade,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'معامله جدید',
              ),
            )
          : null,
      body: IndexedStack(
        index: _tabIndex,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _tabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.home_outlined,
            ),
            selectedIcon: Icon(
              Icons.home,
            ),
            label: 'داشبورد',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.trending_up,
            ),
            selectedIcon: Icon(
              Icons.trending_up,
            ),
            label: 'معاملات باز',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.analytics_outlined,
            ),
            selectedIcon: Icon(
              Icons.analytics,
            ),
            label: 'تحلیل‌ها',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.analytics_outlined,
            ),
            selectedIcon: Icon(
              Icons.analytics,
            ),
            label: 'گزارش‌ها',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.tune,
            ),
            selectedIcon: Icon(
              Icons.tune,
            ),
            label: 'سفارشی',
          ),
        ],
      ),
    );
  }
}
