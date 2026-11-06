import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../repositories/account_repository.dart';
import '../repositories/asset_repository.dart';
import 'color_settings_page.dart';
import '../utils/number_formatter.dart' as numbers;

class AssetManagementPage extends StatefulWidget {
  const AssetManagementPage({
    super.key,
  });

  @override
  State<AssetManagementPage> createState() => _AssetManagementPageState();
}

class _AssetManagementPageState extends State<AssetManagementPage> {
  final AssetRepository _repository = AssetRepository();
  final AccountRepository _accountRepository = AccountRepository();

  Map<String, dynamic> _accountSummary = {
    'initial_balance': 0.0,
    'daily_target_amount': 0.0,
    'weekly_target_amount': 0.0,
    'monthly_target_amount': 0.0,
  };
  List<Asset> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loading = true;
    });

    try {
      final assets = await _repository.getAllAssets();
      final accountSummary = await _accountRepository.getAccountSummary();

      if (!mounted) return;

      setState(() {
        _accountSummary = accountSummary;
        _assets = assets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage(
        'خطا در بارگذاری دارایی‌ها: $e',
        isError: true,
      );
    }
  }

  Future<void> _editAccountSettings() async {
    final initial = TextEditingController(
        text: (_accountSummary['initial_balance'] ?? 0).toString());
    final daily = TextEditingController(
        text: (_accountSummary['daily_target_amount'] ?? 0).toString());
    final weekly = TextEditingController(
        text: (_accountSummary['weekly_target_amount'] ?? 0).toString());
    final monthly = TextEditingController(
        text: (_accountSummary['monthly_target_amount'] ?? 0).toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('سرمایه و اهداف حساب'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: initial,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'سرمایه اولیه', prefixText: '\$ ')),
          TextField(
              controller: daily,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'هدف روزانه', prefixText: '\$ ')),
          TextField(
              controller: weekly,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'هدف هفتگی', prefixText: '\$ ')),
          TextField(
              controller: monthly,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'هدف ماهانه', prefixText: '\$ ')),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ذخیره')),
        ],
      ),
    );
    if (saved == true) {
      double parse(TextEditingController c) =>
          double.tryParse(numbers
              .normalizeNumberInput(c.text)
              .trim()
              .replaceAll(',', '')) ??
          0;
      await _accountRepository.saveAccountSettings(
        initialBalance: parse(initial),
        dailyTargetAmount: parse(daily),
        weeklyTargetAmount: parse(weekly),
        monthlyTargetAmount: parse(monthly),
      );
      await _loadAssets();
      _showMessage('سرمایه و اهداف حساب ذخیره شد.');
    }
    initial.dispose();
    daily.dispose();
    weekly.dispose();
    monthly.dispose();
  }

  Widget _accountSettingsCard() {
    String money(String key) =>
        '\$${numbers.formatNumber(((_accountSummary[key] as num?) ?? 0).toDouble(), decimals: 2, trimTrailingZeros: false)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('سرمایه و اهداف حساب',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            IconButton(
                tooltip: 'ویرایش سرمایه و اهداف',
                onPressed: _editAccountSettings,
                icon: const Icon(Icons.edit_outlined)),
          ]),
          _accountValueRow('سرمایه اولیه', money('initial_balance')),
          _accountValueRow('هدف روزانه', money('daily_target_amount')),
          _accountValueRow('هدف هفتگی', money('weekly_target_amount')),
          _accountValueRow('هدف ماهانه', money('monthly_target_amount')),
        ]),
      ),
    );
  }

  Widget _accountValueRow(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(title)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
        ]),
      );

  Future<void> _showAssetDialog({
    Asset? asset,
  }) async {
    final symbolController = TextEditingController(
      text: asset?.assetSymbol ?? '',
    );

    final nameController = TextEditingController(
      text: asset?.assetName ?? '',
    );

    bool enabled = asset?.assetEnabled ?? true;

    final isEditing = asset != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                isEditing ? 'ویرایش دارایی' : 'افزودن دارایی',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: symbolController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Symbol',
                        hintText: 'مثلاً BTCUSDT',
                      ),
                      enabled: !isEditing,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'نام دارایی',
                        hintText: 'مثلاً Bitcoin',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'فعال',
                      ),
                      value: enabled,
                      onChanged: (value) {
                        setDialogState(() {
                          enabled = value;
                        });
                      },
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
                  child: const Text('انصراف'),
                ),
                FilledButton(
                  onPressed: () async {
                    final symbol = symbolController.text.trim().toUpperCase();

                    if (symbol.isEmpty) {
                      _showMessage(
                        'Symbol را وارد کنید.',
                        isError: true,
                      );
                      return;
                    }

                    try {
                      if (isEditing) {
                        await _repository.updateAsset(
                          asset.copyWith(
                            assetSymbol: symbol,
                            assetName: nameController.text.trim(),
                            assetEnabled: enabled,
                          ),
                        );
                      } else {
                        await _repository.createAsset(
                          Asset(
                            assetSymbol: symbol,
                            assetName: nameController.text.trim(),
                            assetEnabled: enabled,
                            createdAt: DateTime.now(),
                          ),
                        );
                      }

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.pop(
                        dialogContext,
                        true,
                      );
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        SnackBar(
                          content: Text('$e'),
                        ),
                      );
                    }
                  },
                  child: const Text('ذخیره'),
                ),
              ],
            );
          },
        );
      },
    );

    symbolController.dispose();
    nameController.dispose();

    if (result == true) {
      await _loadAssets();
    }
  }

  Future<void> _toggleAsset(
    Asset asset,
  ) async {
    try {
      await _repository.setAssetEnabled(
        assetId: asset.assetId!,
        enabled: !asset.assetEnabled,
      );

      await _loadAssets();
    } catch (e) {
      _showMessage(
        '$e',
        isError: true,
      );
    }
  }

  Future<void> _deleteAsset(
    Asset asset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف دارایی'),
          content: Text(
            'آیا از حذف ${asset.assetSymbol} مطمئن هستید؟',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _repository.deleteAsset(
        asset.assetId!,
      );

      await _loadAssets();

      _showMessage(
        '${asset.assetSymbol} حذف شد.',
      );
    } catch (e) {
      _showMessage(
        '$e',
        isError: true,
      );
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت دارایی‌ها'),
        actions: [
          IconButton(
            onPressed: _loadAssets,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.button,
        foregroundColor: AppColors.buttonText,
        onPressed: () {
          _showAssetDialog();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.button))
          : RefreshIndicator(
              color: AppColors.button,
              backgroundColor: AppColors.cardBackground,
              onRefresh: _loadAssets,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _accountSettingsCard(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('دارایی‌ها',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (_assets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child:
                          Center(child: Text('هنوز دارایی‌ای ثبت نشده است.')),
                    )
                  else
                    ..._assets.map((asset) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.assetIconBackground,
                              foregroundColor: AppColors.assetIcon,
                              child: Text(asset.assetSymbol.isNotEmpty
                                  ? asset.assetSymbol[0]
                                  : '?'),
                            ),
                            title: Text(asset.assetSymbol,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(asset.assetName.isEmpty
                                ? 'بدون نام'
                                : asset.assetName),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'ویرایش دارایی',
                                  onPressed: () =>
                                      _showAssetDialog(asset: asset),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'حذف دارایی',
                                  onPressed: () => _deleteAsset(asset),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            onTap: () => _showAssetDialog(asset: asset),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
