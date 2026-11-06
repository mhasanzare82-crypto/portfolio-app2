import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ticker.dart';
import '../models/trade.dart';
import '../repositories/trade_repository.dart';
import '../services/lbank_service.dart';
import '../widgets/trade_card.dart';
import 'color_settings_page.dart';
import 'trade_notes_page.dart' as new_trade;
import 'trade_details_page.dart';

/// Shows the open trades of a single asset, with the asset's live price,
/// and lets the user open a new trade directly from here.
class AssetOpenTradesPage extends StatefulWidget {
  const AssetOpenTradesPage({
    super.key,
    required this.assetSymbol,
    required this.initialTrades,
    required this.onChanged,
  });

  final String assetSymbol;
  final List<Trade> initialTrades;
  final VoidCallback onChanged;

  @override
  State<AssetOpenTradesPage> createState() => _AssetOpenTradesPageState();
}

class _AssetOpenTradesPageState extends State<AssetOpenTradesPage> {
  final LBankService _lbankService = LBankService();

  final TradeRepository _tradeRepository = TradeRepository();

  StreamSubscription<Ticker>? _tickerSubscription;

  late List<Trade> _trades;

  double _livePrice = 0;

  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _trades = widget.initialTrades;

    _tickerSubscription = _lbankService.tickerStream.listen(
      (ticker) {
        if (!mounted) return;

        setState(() {
          _livePrice = ticker.price;
        });
      },
    );

    _lbankService.connect(
      widget.assetSymbol,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });

    final trades = await _tradeRepository.getTradesByAsset(
      widget.assetSymbol,
    );

    if (!mounted) return;

    setState(() {
      _trades = trades
          .where(
            (trade) => trade.tradeStatus == TradeStatus.open,
          )
          .toList();
      _loading = false;
    });

    widget.onChanged();
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

    await _refresh();
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
            livePrice: _livePrice,
            onChanged: _refresh,
          );
        },
      ),
    );

    await _refresh();
  }

  @override
  void dispose() {
    _tickerSubscription?.cancel();
    _lbankService.dispose();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'معاملات باز ${widget.assetSymbol}',
        ),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTrade,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'معامله جدید',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      widget.assetSymbol,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      _livePrice > 0
                          ? _livePrice.toStringAsFixed(4)
                          : 'در حال دریافت قیمت...',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.livePrice,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      'قیمت لحظه‌ای LBank',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _trades.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 40,
                          ),
                          child: Center(
                            child: Text(
                              'معامله باز دیگری برای این دارایی وجود ندارد.',
                              style: TextStyle(
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        100,
                      ),
                      children: _trades.map(
                        (trade) {
                          return TradeCard(
                            trade: trade,
                            livePrice: _livePrice,
                            onTap: () => _openTrade(
                              trade,
                            ),
                          );
                        },
                      ).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
