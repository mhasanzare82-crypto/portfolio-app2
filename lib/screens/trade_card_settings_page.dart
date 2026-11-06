import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'color_settings_page.dart';

class TradeCardFieldKeys {
  static const String currentPrice = 'current_price';
  static const String margin = 'margin';
  static const String leverage = 'leverage';
  static const String volume = 'volume';
  static const String entry = 'entry';
  static const String stop = 'stop';
  static const String target = 'target';
  static const String pnl = 'pnl';
  static const String roi = 'roi';
  static const String marginEffect = 'margin_effect';
  static const String priceChange = 'price_change';
  static const String pnlMargin = 'pnl_margin';
  static const String fee = 'fee';
  static const String riskToStop = 'risk_to_stop';
  static const String riskMargin = 'risk_margin';
  static const String targetProfit = 'target_profit';
  static const String targetRR = 'target_rr';
  static const String finalRR = 'final_rr';
  static const String maxDrawdownPercent = 'max_drawdown_percent';
  static const String drawdownDollar = 'drawdown_dollar';
  static const String drawdownMargin = 'drawdown_margin';
  static const String duration = 'duration';
  static const String pricePosition = 'price_position';
  static const String positionPercent = 'position_percent';

  static const List<String> all = [
    currentPrice,
    margin,
    leverage,
    volume,
    entry,
    stop,
    target,
    pnl,
    roi,
    marginEffect,
    priceChange,
    pnlMargin,
    fee,
    riskToStop,
    riskMargin,
    targetProfit,
    targetRR,
    finalRR,
    maxDrawdownPercent,
    drawdownDollar,
    drawdownMargin,
    duration,
    pricePosition,
    positionPercent,
  ];

  static const List<String> defaultVisible = [
    currentPrice,
    margin,
    leverage,
    volume,
    entry,
    stop,
    target,
    pnl,
    roi,
    marginEffect,
    priceChange,
    pnlMargin,
    fee,
    riskToStop,
    riskMargin,
    targetProfit,
    targetRR,
    finalRR,
    maxDrawdownPercent,
    drawdownDollar,
    drawdownMargin,
    duration,
    pricePosition,
    positionPercent,
  ];
}

class TradeCardFieldSettings {
  static const String _storageKey = 'trade_card_visible_fields';

  static Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();

    final values = preferences.getStringList(
      _storageKey,
    );

    if (values == null) {
      return TradeCardFieldKeys.defaultVisible.toSet();
    }

    final validValues = values
        .where(
          (value) => TradeCardFieldKeys.all.contains(value),
        )
        .toSet();

    if (validValues.isEmpty) {
      return TradeCardFieldKeys.defaultVisible.toSet();
    }

    return validValues;
  }

  static Future<void> save(
    Set<String> fields,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setStringList(
      _storageKey,
      fields.toList(),
    );
  }

  static Future<void> reset() async {
    await save(
      TradeCardFieldKeys.defaultVisible.toSet(),
    );
  }
}

class TradeCardSettingsPage extends StatefulWidget {
  const TradeCardSettingsPage({
    super.key,
  });

  @override
  State<TradeCardSettingsPage> createState() => _TradeCardSettingsPageState();
}

class _TradeCardSettingsPageState extends State<TradeCardSettingsPage> {
  Set<String> _selectedFields = TradeCardFieldKeys.defaultVisible.toSet();

  bool _loading = true;

  static const List<_FieldItem> _items = [
    _FieldItem(
      keyName: TradeCardFieldKeys.currentPrice,
      title: 'قیمت لحظه‌ای',
      icon: Icons.price_change_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.margin,
      title: 'مارجین',
      icon: Icons.account_balance_wallet_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.leverage,
      title: 'اهرم',
      icon: Icons.speed_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.volume,
      title: 'حجم',
      icon: Icons.bar_chart_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.entry,
      title: 'قیمت ورود',
      icon: Icons.login_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.stop,
      title: 'حد ضرر',
      icon: Icons.stop_circle_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.target,
      title: 'هدف',
      icon: Icons.flag_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.pnl,
      title: 'سود و زیان',
      icon: Icons.trending_up,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.roi,
      title: 'بازدهی',
      icon: Icons.percent,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.marginEffect,
      title: 'اثر مارجین',
      icon: Icons.account_balance_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.priceChange,
      title: 'تغییر قیمت',
      icon: Icons.swap_vert,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.pnlMargin,
      title: 'سود و زیان نسبت به مارجین',
      icon: Icons.percent_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.fee,
      title: 'کارمزد',
      icon: Icons.payments_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.riskToStop,
      title: 'ریسک تا حد ضرر',
      icon: Icons.warning_amber_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.riskMargin,
      title: 'ریسک نسبت به مارجین',
      icon: Icons.warning_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.targetProfit,
      title: 'سود هدف',
      icon: Icons.flag_circle_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.targetRR,
      title: 'نسبت ریسک به بازده هدف',
      icon: Icons.compare_arrows,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.finalRR,
      title: 'نسبت ریسک به بازده نهایی',
      icon: Icons.analytics_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.maxDrawdownPercent,
      title: 'حداکثر افت سرمایه',
      icon: Icons.trending_down,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.drawdownDollar,
      title: 'مقدار افت سرمایه',
      icon: Icons.money_off_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.drawdownMargin,
      title: 'افت سرمایه نسبت به مارجین',
      icon: Icons.percent,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.duration,
      title: 'مدت معامله',
      icon: Icons.timer_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.pricePosition,
      title: 'موقعیت قیمت',
      icon: Icons.linear_scale_outlined,
    ),
    _FieldItem(
      keyName: TradeCardFieldKeys.positionPercent,
      title: 'درصد موقعیت',
      icon: Icons.pie_chart_outline,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final fields = await TradeCardFieldSettings.load();

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedFields = fields;
      _loading = false;
    });
  }

  Future<void> _toggleField(
    String keyName,
    bool value,
  ) async {
    setState(() {
      if (value) {
        _selectedFields.add(keyName);
      } else {
        _selectedFields.remove(keyName);
      }
    });

    await TradeCardFieldSettings.save(
      _selectedFields,
    );
  }

  Future<void> _selectAll() async {
    final fields = TradeCardFieldKeys.all.toSet();

    setState(() {
      _selectedFields = fields;
    });

    await TradeCardFieldSettings.save(
      fields,
    );
  }

  Future<void> _clearAll() async {
    setState(() {
      _selectedFields = {};
    });

    await TradeCardFieldSettings.save(
      {},
    );
  }

  Future<void> _reset() async {
    final fields = TradeCardFieldKeys.defaultVisible.toSet();

    setState(() {
      _selectedFields = fields;
    });

    await TradeCardFieldSettings.save(
      fields,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'فیلدهای کارت معامله',
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.button,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'فیلدهای کارت معامله',
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'all':
                  _selectAll();
                  break;

                case 'none':
                  _clearAll();
                  break;

                case 'reset':
                  _reset();
                  break;
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value: 'all',
                  child: Text(
                    'نمایش همه',
                  ),
                ),
                PopupMenuItem(
                  value: 'none',
                  child: Text(
                    'مخفی کردن همه',
                  ),
                ),
                PopupMenuItem(
                  value: 'reset',
                  child: Text(
                    'بازگشت به حالت پیش‌فرض',
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          12,
          12,
          12,
          30,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'انتخاب فیلدهای کارت معامله باز',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'فقط فیلدهایی که فعال هستند در کارت معامله نمایش داده می‌شوند.',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          ..._items.map(
            (item) {
              final selected = _selectedFields.contains(
                item.keyName,
              );

              return Card(
                margin: const EdgeInsets.only(
                  bottom: 6,
                ),
                child: SwitchListTile(
                  value: selected,
                  onChanged: (value) {
                    _toggleField(
                      item.keyName,
                      value,
                    );
                  },
                  secondary: Icon(
                    item.icon,
                    color: selected ? AppColors.button : AppColors.disabledText,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      color: AppColors.text,
                    ),
                  ),
                  activeColor: AppColors.button,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FieldItem {
  const _FieldItem({
    required this.keyName,
    required this.title,
    required this.icon,
  });

  final String keyName;
  final String title;
  final IconData icon;
}
