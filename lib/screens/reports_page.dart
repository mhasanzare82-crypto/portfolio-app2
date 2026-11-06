import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../calculators/pnl_calculator.dart';
import '../database/app_database.dart';
import '../models/trade.dart';
import '../repositories/trade_repository.dart';
import 'color_settings_page.dart';
import 'trade_history_page.dart';
import '../utils/number_formatter.dart' as numbers;

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    this.embedded = false,
  });

  /// When true, the page renders only its content (no AppBar/Scaffold),
  /// so it can be hosted inside another Scaffold, such as a tab.
  final bool embedded;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final TradeRepository _tradeRepository = TradeRepository();

  final AppDatabase _database = AppDatabase.instance;

  List<Trade> _openTrades = [];
  List<Trade> _closedTrades = [];

  double _initialBalance = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
    });

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

  Future<void> _exportReport(String format) async {
    try {
      final trades = [..._closedTrades, ..._openTrades];
      final payload = <String, dynamic>{
        'created_at': DateTime.now().toIso8601String(),
        'initial_balance': _initialBalance,
        'summary': {
          'closed_trades': _closedTrades.length,
          'open_trades': _openTrades.length,
          'total_pnl': _totalPnl,
          'total_profit': _totalProfit,
          'total_loss': _totalLoss,
          'total_fees': _totalFees,
          'win_rate_percent': _winRate,
          'winning_trades': _winningTrades,
          'losing_trades': _losingTrades,
        },
        'trades': trades.map((trade) => trade.toMap()).toList(),
      };
      String content;
      if (format == 'json') {
        content = const JsonEncoder.withIndent('  ').convert(payload);
      } else if (format == 'csv') {
        final rows = trades.map((trade) => [
              trade.tradeId,
              trade.assetSymbol,
              trade.tradeDirection.name,
              trade.tradeType.name,
              trade.tradeStatus.name,
              trade.entryPrice?.toString() ?? '',
              trade.exitPrice?.toString() ?? '',
              trade.stopPrice?.toString() ?? '',
              trade.targetPrice?.toString() ?? '',
              trade.marginAmount.toString(),
              trade.leverageValue.toString(),
              trade.volumeAmount.toString(),
              trade.tradeFee.toString(),
              trade.finalPnl.toString(),
              trade.entryTime.toIso8601String(),
              trade.exitTime?.toIso8601String() ?? '',
            ]);
        content = [
          [
            'trade_id',
            'asset_symbol',
            'direction',
            'type',
            'status',
            'entry_price',
            'exit_price',
            'stop_price',
            'target_price',
            'margin',
            'leverage',
            'volume',
            'fee',
            'final_pnl',
            'entry_time',
            'exit_time'
          ],
          ...rows,
        ]
            .map((row) => row.map((value) {
                  final escaped = value.toString().replaceAll('"', '""');
                  return '"$escaped"';
                }).join(','))
            .join('\n');
      } else {
        final b = StringBuffer()
          ..writeln('گزارش معاملات')
          ..writeln('تاریخ خروجی: ${DateTime.now().toIso8601String()}')
          ..writeln('سرمایه اولیه: $_initialBalance')
          ..writeln('تعداد معاملات بسته: ${_closedTrades.length}')
          ..writeln('تعداد معاملات باز: ${_openTrades.length}')
          ..writeln('سود/زیان کل: $_totalPnl')
          ..writeln('مجموع سودها: $_totalProfit')
          ..writeln('مجموع ضررها: $_totalLoss')
          ..writeln('کارمزد کل: $_totalFees')
          ..writeln('نرخ برد: $_winRate%')
          ..writeln('')
          ..writeln('جزئیات معاملات:');
        for (final trade in trades) {
          b.writeln('---');
          for (final entry in trade.toMap().entries) {
            b.writeln('${entry.key}: ${entry.value}');
          }
        }
        content = b.toString();
      }
      final extension = format;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'خروجی گزارش‌ها',
        fileName: 'trading_report.${extension}',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('گزارش ذخیره شد.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خروجی گزارش ناموفق بود: $e')));
    }
  }

  double _pnl(Trade trade) {
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
      (sum, trade) => sum + _pnl(trade),
    );
  }

  double get _totalProfit {
    return _closedTrades.fold(
      0,
      (sum, trade) {
        final value = _pnl(trade);

        return sum + (value > 0 ? value : 0);
      },
    );
  }

  double get _totalLoss {
    return _closedTrades.fold(
      0,
      (sum, trade) {
        final value = _pnl(trade);

        return sum + (value < 0 ? value.abs() : 0);
      },
    );
  }

  double get _totalFees {
    return _closedTrades.fold(
      0,
      (sum, trade) => sum + trade.tradeFee,
    );
  }

  int get _winningTrades {
    return _closedTrades.where((trade) => _pnl(trade) > 0).length;
  }

  int get _losingTrades {
    return _closedTrades.where((trade) => _pnl(trade) < 0).length;
  }

  double get _winRate {
    if (_closedTrades.isEmpty) {
      return 0;
    }

    return _winningTrades / _closedTrades.length * 100;
  }

  double get _averagePnl {
    if (_closedTrades.isEmpty) {
      return 0;
    }

    return _totalPnl / _closedTrades.length;
  }

  Trade? get _bestTrade {
    if (_closedTrades.isEmpty) {
      return null;
    }

    return _closedTrades.reduce(
      (a, b) => _pnl(a) >= _pnl(b) ? a : b,
    );
  }

  Trade? get _worstTrade {
    if (_closedTrades.isEmpty) {
      return null;
    }

    return _closedTrades.reduce(
      (a, b) => _pnl(a) <= _pnl(b) ? a : b,
    );
  }

  Map<String, double> get _assetPnl {
    final result = <String, double>{};

    for (final trade in _closedTrades) {
      final symbol = trade.assetSymbol;

      result[symbol] = (result[symbol] ?? 0) + _pnl(trade);
    }

    return result;
  }

  Map<String, double> get _directionPnl {
    final result = <String, double>{
      'Long': 0,
      'Short': 0,
    };

    for (final trade in _closedTrades) {
      final key =
          trade.tradeDirection == TradeDirection.long ? 'Long' : 'Short';

      result[key] = (result[key] ?? 0) + _pnl(trade);
    }

    return result;
  }

  Map<String, double> get _typePnl {
    final result = <String, double>{
      'Scalp': 0,
      'Day Trade': 0,
    };

    for (final trade in _closedTrades) {
      final key = trade.tradeType == TradeType.scalp ? 'Scalp' : 'Day Trade';

      result[key] = (result[key] ?? 0) + _pnl(trade);
    }

    return result;
  }

  Map<String, double> get _timeframePnl {
    final result = <String, double>{};

    for (final trade in _closedTrades) {
      final timeframe = trade.tradeTimeframe.trim().isEmpty
          ? 'Unknown'
          : trade.tradeTimeframe;

      result[timeframe] = (result[timeframe] ?? 0) + _pnl(trade);
    }

    return result;
  }

  double get _currentBalance {
    return _initialBalance + _totalPnl;
  }

  String _formatNumber(double value) {
    return numbers.formatNumber(value, decimals: 2, trimTrailingZeros: false);
  }

  // =========================================================
  // رنگ سود و زیان
  // =========================================================

  Color _pnlColor(double value) {
    if (value > 0) {
      return AppColors.profit;
    }

    if (value < 0) {
      return AppColors.loss;
    }

    return AppColors.neutral;
  }

  // =========================================================
  // ردیف معیارها
  // =========================================================

  Widget _metricRow(
    String title,
    String value, {
    Color? valueColor,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.text,
        ),
      ),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: valueColor ?? AppColors.text,
        ),
      ),
    );
  }

  // =========================================================
  // لیست معیارها
  // =========================================================

  Widget _metricListSection() {
    return Card(
      child: Column(
        children: [
          _metricRow(
            'کل معاملات',
            numbers.formatInteger(_openTrades.length + _closedTrades.length),
          ),
          const Divider(height: 1),
          _metricRow(
            'معاملات باز',
            numbers.formatInteger(_openTrades.length),
          ),
          const Divider(height: 1),
          _metricRow(
            'معاملات بسته',
            numbers.formatInteger(_closedTrades.length),
          ),
          const Divider(height: 1),
          _metricRow(
            'Win Rate',
            '${_formatNumber(_winRate)}%',
          ),
          const Divider(height: 1),
          _metricRow(
            'Net P&L',
            _formatNumber(
              _totalPnl,
            ),
            valueColor: _pnlColor(
              _totalPnl,
            ),
          ),
          const Divider(height: 1),
          _metricRow(
            'کل سود',
            _formatNumber(
              _totalProfit,
            ),
            valueColor: AppColors.profit,
          ),
          const Divider(height: 1),
          _metricRow(
            'کل ضرر',
            _formatNumber(
              _totalLoss,
            ),
            valueColor: AppColors.loss,
          ),
          const Divider(height: 1),
          _metricRow(
            'کل کارمزد',
            _formatNumber(
              _totalFees,
            ),
          ),
          const Divider(height: 1),
          _metricRow(
            'میانگین P&L',
            _formatNumber(
              _averagePnl,
            ),
            valueColor: _pnlColor(
              _averagePnl,
            ),
          ),
          const Divider(height: 1),
          _metricRow(
            'بالانس فعلی',
            _formatNumber(
              _currentBalance,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // عنوان بخش
  // =========================================================

  Widget _sectionTitle(
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 22,
        bottom: 10,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.text,
        ),
      ),
    );
  }

  // =========================================================
  // مقدار P&L
  // =========================================================

  Widget _pnlValue(double value) {
    final prefix = value > 0 ? '+' : '';

    return Text(
      '$prefix${_formatNumber(value)}',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: _pnlColor(value),
      ),
    );
  }

  // =========================================================
  // گروه‌ها
  // =========================================================

  Widget _groupList(
    Map<String, double> data,
  ) {
    if (data.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'اطلاعاتی برای نمایش وجود ندارد.',
            style: TextStyle(
              color: AppColors.secondaryText,
            ),
          ),
        ),
      );
    }

    final entries = data.entries.toList();

    entries.sort(
      (a, b) => b.value.compareTo(a.value),
    );

    return Card(
      child: Column(
        children: entries.map(
          (entry) {
            return ListTile(
              title: Text(
                entry.key,
                style: TextStyle(
                  color: AppColors.text,
                ),
              ),
              trailing: _pnlValue(entry.value),
            );
          },
        ).toList(),
      ),
    );
  }

  // =========================================================
  // نمودار Equity
  // =========================================================

  Widget _equityChart() {
    final trades = List<Trade>.from(
      _closedTrades,
    );

    trades.sort(
      (a, b) => a.entryTime.compareTo(b.entryTime),
    );

    if (trades.isEmpty) {
      return Card(
        child: SizedBox(
          height: 160,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'برای نمایش نمودار، حداقل یک معامله بسته‌شده لازم است.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final values = <double>[_initialBalance];

    var equity = _initialBalance;

    for (final trade in trades) {
      equity += _pnl(trade);
      values.add(equity);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 220,
          child: CustomPaint(
            painter: _EquityChartPainter(
              values: values,
              gridColor: AppColors.chartGrid,
              lineColor: AppColors.chartLine,
              pointColor: AppColors.chartPoint,
              textColor: AppColors.chartText,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // بهترین و بدترین معامله
  // =========================================================

  Widget _bestWorstSection() {
    final best = _bestTrade;
    final worst = _worstTrade;

    if (best == null || worst == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'هنوز معامله بسته‌شده‌ای برای مقایسه وجود ندارد.',
            style: TextStyle(
              color: AppColors.secondaryText,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              Icons.trending_up,
              color: AppColors.profit,
            ),
            title: Text(
              'بهترین معامله',
              style: TextStyle(
                color: AppColors.text,
              ),
            ),
            subtitle: Text(
              '${best.assetSymbol} • ${best.tradeDirection == TradeDirection.long ? 'Long' : 'Short'}',
              style: TextStyle(
                color: AppColors.secondaryText,
              ),
            ),
            trailing: _pnlValue(
              _pnl(best),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.trending_down,
              color: AppColors.loss,
            ),
            title: Text(
              'بدترین معامله',
              style: TextStyle(
                color: AppColors.text,
              ),
            ),
            subtitle: Text(
              '${worst.assetSymbol} • ${worst.tradeDirection == TradeDirection.long ? 'Long' : 'Short'}',
              style: TextStyle(
                color: AppColors.secondaryText,
              ),
            ),
            trailing: _pnlValue(
              _pnl(worst),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // بدنه
  // =========================================================

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.button,
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.button,
      backgroundColor: AppColors.cardBackground,
      onRefresh: _loadReport,
      child: ListView(
        padding: const EdgeInsets.all(
          16,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('خروجی گزارش:'),
                  OutlinedButton.icon(
                      onPressed: () => _exportReport('txt'),
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('TXT')),
                  OutlinedButton.icon(
                      onPressed: () => _exportReport('csv'),
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('CSV')),
                  OutlinedButton.icon(
                      onPressed: () => _exportReport('json'),
                      icon: const Icon(Icons.data_object),
                      label: const Text('JSON')),
                ],
              ),
            ),
          ),
          _metricListSection(),
          _sectionTitle(
            'رشد حساب',
          ),
          _equityChart(),
          _sectionTitle(
            'P&L بر اساس دارایی',
          ),
          _groupList(
            _assetPnl,
          ),
          _sectionTitle(
            'P&L بر اساس جهت معامله',
          ),
          _groupList(
            _directionPnl,
          ),
          _sectionTitle(
            'P&L بر اساس نوع معامله',
          ),
          _groupList(
            _typePnl,
          ),
          _sectionTitle(
            'عملکرد بر اساس تایم‌فریم',
          ),
          _groupList(
            _timeframePnl,
          ),
          _sectionTitle(
            'بهترین و بدترین معامله',
          ),
          _bestWorstSection(),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('تاریخچه معاملات'),
              subtitle: const Text('مشاهده کامل معاملات بسته‌شده'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TradeHistoryPage()),
                );
              },
            ),
          ),
          const SizedBox(
            height: 40,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (widget.embedded) {
      return _buildBody();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'گزارش‌ها و آمار',
        ),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _loading ? null : _loadReport,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

// =============================================================
// نمودار Equity
// =============================================================

class _EquityChartPainter extends CustomPainter {
  final List<double> values;

  final Color gridColor;
  final Color lineColor;
  final Color pointColor;
  final Color textColor;

  const _EquityChartPainter({
    required this.values,
    required this.gridColor,
    required this.lineColor,
    required this.pointColor,
    required this.textColor,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (values.isEmpty) {
      return;
    }

    const left = 45.0;
    const right = 10.0;
    const top = 15.0;
    const bottom = 25.0;

    final chartWidth = size.width - left - right;

    final chartHeight = size.height - top - bottom;

    final minValue = values.reduce(
      (a, b) => a < b ? a : b,
    );

    final maxValue = values.reduce(
      (a, b) => a > b ? a : b,
    );

    var range = maxValue - minValue;

    if (range == 0) {
      range = 1;
    }

    // =========================================================
    // خطوط شبکه
    // =========================================================

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;

    for (int i = 0; i <= 4; i++) {
      final y = top + chartHeight * i / 4;

      canvas.drawLine(
        Offset(left, y),
        Offset(
          left + chartWidth,
          y,
        ),
        gridPaint,
      );
    }

    // =========================================================
    // خط نمودار
    // =========================================================

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = lineColor;

    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? left + chartWidth / 2
          : left + chartWidth * i / (values.length - 1);

      final normalized = (values[i] - minValue) / range;

      final y = top + chartHeight * (1 - normalized);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      linePaint,
    );

    // =========================================================
    // نقاط نمودار
    // =========================================================

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = pointColor;

    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? left + chartWidth / 2
          : left + chartWidth * i / (values.length - 1);

      final normalized = (values[i] - minValue) / range;

      final y = top + chartHeight * (1 - normalized);

      canvas.drawCircle(
        Offset(x, y),
        4,
        pointPaint,
      );
    }

    // =========================================================
    // متن محور
    // =========================================================

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 10,
    );

    final maxPainter = TextPainter(
      text: TextSpan(
        text: numbers.formatNumber(maxValue,
            decimals: 0, trimTrailingZeros: false),
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );

    maxPainter.layout();

    maxPainter.paint(
      canvas,
      Offset(
        0,
        top - 5,
      ),
    );

    final minPainter = TextPainter(
      text: TextSpan(
        text: numbers.formatNumber(minValue,
            decimals: 0, trimTrailingZeros: false),
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );

    minPainter.layout();

    minPainter.paint(
      canvas,
      Offset(
        0,
        size.height - bottom - minPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(
    covariant _EquityChartPainter oldDelegate,
  ) {
    if (oldDelegate.values.length != values.length) {
      return true;
    }

    if (oldDelegate.gridColor != gridColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.textColor != textColor) {
      return true;
    }

    for (int i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) {
        return true;
      }
    }

    return false;
  }
}
