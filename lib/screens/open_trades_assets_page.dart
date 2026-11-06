import 'dart:async';
import 'package:flutter/material.dart';

import '../models/ticker.dart';
import '../models/trade.dart';
import '../repositories/trade_repository.dart';
import '../services/lbank_service.dart';
import 'color_settings_page.dart';
import 'trade_details_page.dart';
import '../utils/number_formatter.dart' as numbers;

class OpenTradesAssetsPage extends StatefulWidget {
  const OpenTradesAssetsPage({
    super.key,
  });

  @override
  State<OpenTradesAssetsPage> createState() => _OpenTradesAssetsPageState();
}

class _OpenTradesAssetsPageState extends State<OpenTradesAssetsPage> {
  final TradeRepository _tradeRepository = TradeRepository();

  List<Trade> _openTrades = [];

  final Map<String, double> _prices = {};
  final Map<String, LBankService> _services = {};
  final Map<String, StreamSubscription<Ticker>> _subscriptions = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOpenTrades();
  }

  Future<void> _loadOpenTrades() async {
    final trades = await _tradeRepository.getOpenTrades();

    if (!mounted) return;

    setState(() {
      _openTrades = trades;
      _loading = false;
    });

    await _startPriceStreams();
  }

  List<String> get _symbols {
    final symbols = <String>{};

    for (final trade in _openTrades) {
      symbols.add(trade.assetSymbol);
    }

    return symbols.toList();
  }

  Future<void> _startPriceStreams() async {
    for (final symbol in _symbols) {
      if (_services.containsKey(symbol)) {
        continue;
      }

      final service = LBankService();

      final subscription = service.tickerStream.listen(
        (Ticker ticker) {
          if (!mounted) return;

          setState(() {
            _prices[symbol] = ticker.price;
          });
        },
      );

      _services[symbol] = service;
      _subscriptions[symbol] = subscription;

      try {
        await service.connect(symbol);
      } catch (_) {
        // قیمت این دارایی در صورت خطا خالی می‌ماند.
      }
    }
  }

  List<Trade> _tradesForSymbol(
    String symbol,
  ) {
    return _openTrades
        .where(
          (trade) => trade.assetSymbol == symbol,
        )
        .toList();
  }

  Future<void> _openAssetTrades(
    String symbol,
  ) async {
    final trades = _tradesForSymbol(symbol);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return OpenAssetTradesPage(
            symbol: symbol,
            trades: trades,
            livePrice: _prices[symbol],
          );
        },
      ),
    );

    await _loadOpenTrades();
  }

  Widget _buildAssetCard(
    String symbol,
  ) {
    final trades = _tradesForSymbol(symbol);
    final price = _prices[symbol];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAssetTrades(symbol),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.assetIconBackground,
                  border: Border.all(
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.currency_exchange,
                  color: AppColors.assetIcon,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${numbers.formatInteger(trades.length)} معامله باز',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price == null
                        ? 'در حال دریافت...'
                        : numbers.formatNumber(price,
                            decimals: 4, trimTrailingZeros: false),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: price == null
                          ? AppColors.secondaryText
                          : AppColors.livePrice,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Icon(
                    Icons.chevron_left,
                    color: AppColors.chevron,
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'معاملات باز',
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: AppColors.button,
              ),
            )
          : _openTrades.isEmpty
              ? Center(
                  child: Text(
                    'هیچ معامله بازی وجود ندارد.',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.button,
                  backgroundColor: AppColors.cardBackground,
                  onRefresh: _loadOpenTrades,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'دارایی‌ها',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._symbols.map(
                        _buildAssetCard,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class OpenAssetTradesPage extends StatefulWidget {
  const OpenAssetTradesPage({
    super.key,
    required this.symbol,
    required this.trades,
    required this.livePrice,
  });

  final String symbol;
  final List<Trade> trades;
  final double? livePrice;

  @override
  State<OpenAssetTradesPage> createState() => _OpenAssetTradesPageState();
}

class _OpenAssetTradesPageState extends State<OpenAssetTradesPage> {
  late List<Trade> _trades;

  @override
  void initState() {
    super.initState();
    _trades = widget.trades;
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
            livePrice: widget.livePrice ?? 0,
            onChanged: () async {
              final repository = TradeRepository();
              final trades = await repository.getOpenTrades();

              if (!mounted) return;

              setState(() {
                _trades = trades
                    .where(
                      (item) => item.assetSymbol == widget.symbol,
                    )
                    .toList();
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildTradeCard(
    Trade trade,
  ) {
    final entry = trade.entryPrice ?? 0;
    final current = widget.livePrice ?? entry;

    double pnl = 0;

    if (entry > 0 && trade.volumeAmount > 0) {
      final priceDifference = trade.tradeDirection == TradeDirection.long
          ? current - entry
          : entry - current;

      pnl = priceDifference * (trade.volumeAmount / entry);
    }

    final isPositive = pnl >= 0;

    final directionColor = trade.tradeDirection == TradeDirection.long
        ? AppColors.long
        : AppColors.short;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openTrade(trade),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trade.tradeDirection == TradeDirection.long
                          ? 'LONG'
                          : 'SHORT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: directionColor,
                      ),
                    ),
                  ),
                  Text(
                    'Volume: ${numbers.formatNumber(trade.volumeAmount, decimals: 2, trimTrailingZeros: false)}',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Entry: ${numbers.formatNumber(entry, decimals: 4, trimTrailingZeros: false)}',
                      style: TextStyle(
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Stop: ${trade.stopPrice == null ? '-' : numbers.formatNumber(trade.stopPrice!, decimals: 4, trimTrailingZeros: false)}',
                      style: TextStyle(
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Target: ${trade.targetPrice == null ? '-' : numbers.formatNumber(trade.targetPrice!, decimals: 4, trimTrailingZeros: false)}',
                      style: TextStyle(
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Text(
                    'P&L: ${numbers.formatNumber(pnl, decimals: 2, trimTrailingZeros: false)} \$',
                    style: TextStyle(
                      color: isPositive ? AppColors.profit : AppColors.loss,
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
        title: Text(
          'معاملات باز ${{widget.symbol}}'.replaceAll(
            '${{widget.symbol}}',
            widget.symbol,
          ),
        ),
        centerTitle: true,
      ),
      body: _trades.isEmpty
          ? Center(
              child: Text(
                'معامله بازی برای این دارایی وجود ندارد.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          widget.symbol,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.livePrice == null
                              ? 'قیمت لحظه‌ای در دسترس نیست'
                              : numbers.formatNumber(widget.livePrice!,
                                  decimals: 4, trimTrailingZeros: false),
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                            color: widget.livePrice == null
                                ? AppColors.secondaryText
                                : AppColors.livePrice,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ..._trades.map(
                  _buildTradeCard,
                ),
              ],
            ),
    );
  }
}
