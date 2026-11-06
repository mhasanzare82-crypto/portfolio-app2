import 'package:flutter/material.dart';

import '../calculators/pnl_calculator.dart';
import '../models/trade.dart';
import '../repositories/trade_repository.dart';
import 'color_settings_page.dart';
import 'trade_details_page.dart';
import '../utils/number_formatter.dart' as numbers;

class TradeHistoryPage extends StatefulWidget {
  const TradeHistoryPage({
    super.key,
  });

  @override
  State<TradeHistoryPage> createState() => _TradeHistoryPageState();
}

class _TradeHistoryPageState extends State<TradeHistoryPage> {
  final TradeRepository _tradeRepository = TradeRepository();

  List<Trade> _trades = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrades();
  }

  Future<void> _loadTrades() async {
    final trades = await _tradeRepository.getClosedTrades();

    if (!mounted) return;

    setState(() {
      _trades = trades;
      _loading = false;
    });
  }

  double _pnl(
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

  Widget _buildTradeCard(
    Trade trade,
  ) {
    final pnl = _pnl(trade);
    final positive = pnl >= 0;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                return TradeDetailsPage(
                  trade: trade,
                  livePrice: trade.exitPrice ?? 0,
                  onChanged: _loadTrades,
                );
              },
            ),
          );

          await _loadTrades();
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trade.assetSymbol,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    trade.tradeDirection == TradeDirection.long
                        ? 'LONG'
                        : 'SHORT',
                    style: TextStyle(
                      color: trade.tradeDirection == TradeDirection.long
                          ? AppColors.long
                          : AppColors.short,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Entry: ${trade.entryPrice == null ? '-' : numbers.formatNumber(trade.entryPrice!, decimals: 4, trimTrailingZeros: false)}',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Exit: ${trade.exitPrice == null ? '-' : numbers.formatNumber(trade.exitPrice!, decimals: 4, trimTrailingZeros: false)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Volume: ${numbers.formatNumber(trade.volumeAmount, decimals: 2, trimTrailingZeros: false)}',
                    ),
                  ),
                  Text(
                    'P&L: ${numbers.formatNumber(pnl, decimals: 2, trimTrailingZeros: false)} \$',
                    style: TextStyle(
                      color: positive ? AppColors.profit : AppColors.loss,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تاریخچه معاملات',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadTrades,
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
          : _trades.isEmpty
              ? const Center(
                  child: Text(
                    'هنوز معامله بسته‌شده‌ای وجود ندارد.',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTrades,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'تعداد معاملات: ${numbers.formatInteger(_trades.length)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._trades.map(
                        _buildTradeCard,
                      ),
                    ],
                  ),
                ),
    );
  }
}
