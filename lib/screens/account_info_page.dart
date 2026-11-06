import 'package:flutter/material.dart';

import '../repositories/account_repository.dart';
import '../utils/number_formatter.dart' as numbers;

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({
    super.key,
  });

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  final AccountRepository _accountRepository = AccountRepository();

  final TextEditingController _initialBalanceController =
      TextEditingController();

  final TextEditingController _dailyTargetController = TextEditingController();

  final TextEditingController _weeklyTargetController = TextEditingController();

  final TextEditingController _monthlyTargetController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  double _currentCapital = 0.0;
  double _totalPnl = 0.0;

  double _todayPnl = 0.0;
  double _weekPnl = 0.0;
  double _monthPnl = 0.0;

  double _dailyTargetAmount = 0.0;
  double _weeklyTargetAmount = 0.0;
  double _monthlyTargetAmount = 0.0;

  double _dailyProgress = 0.0;
  double _weeklyProgress = 0.0;
  double _monthlyProgress = 0.0;

  @override
  void initState() {
    super.initState();

    _loadAccountData();
  }

  @override
  void dispose() {
    _initialBalanceController.dispose();
    _dailyTargetController.dispose();
    _weeklyTargetController.dispose();
    _monthlyTargetController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _loadAccountData() async {
    try {
      final summary = await _accountRepository.getAccountSummary();

      if (!mounted) {
        return;
      }

      setState(() {
        _initialBalanceController.text = _formatNumber(
          summary['initial_balance'] ?? 0.0,
        );

        _dailyTargetController.text = _formatNumber(
          summary['daily_target_percent'] ?? 0.0,
        );

        _weeklyTargetController.text = _formatNumber(
          summary['weekly_target_percent'] ?? 0.0,
        );

        _monthlyTargetController.text = _formatNumber(
          summary['monthly_target_percent'] ?? 0.0,
        );

        _currentCapital = summary['current_capital'] ?? 0.0;

        _totalPnl = summary['total_pnl'] ?? 0.0;

        _todayPnl = summary['today_pnl'] ?? 0.0;

        _weekPnl = summary['week_pnl'] ?? 0.0;

        _monthPnl = summary['month_pnl'] ?? 0.0;

        _dailyTargetAmount = summary['daily_target_amount'] ?? 0.0;

        _weeklyTargetAmount = summary['weekly_target_amount'] ?? 0.0;

        _monthlyTargetAmount = summary['monthly_target_amount'] ?? 0.0;

        _dailyProgress = summary['daily_progress'] ?? 0.0;

        _weeklyProgress = summary['weekly_progress'] ?? 0.0;

        _monthlyProgress = summary['monthly_progress'] ?? 0.0;

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        'خطا در دریافت اطلاعات حساب',
        isError: true,
      );
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _saveAccountSettings() async {
    if (_isSaving) {
      return;
    }

    final initialBalance = _toDouble(
      _initialBalanceController.text,
    );

    final dailyTarget = _toDouble(
      _dailyTargetController.text,
    );

    final weeklyTarget = _toDouble(
      _weeklyTargetController.text,
    );

    final monthlyTarget = _toDouble(
      _monthlyTargetController.text,
    );

    if (initialBalance < 0) {
      _showMessage(
        'سرمایه اولیه نمی‌تواند منفی باشد.',
        isError: true,
      );
      return;
    }

    if (dailyTarget < 0 || weeklyTarget < 0 || monthlyTarget < 0) {
      _showMessage(
        'درصد تارگت‌ها نمی‌تواند منفی باشد.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _accountRepository.saveAccountSettings(
        initialBalance: initialBalance,
        dailyTargetAmount: 0,
        weeklyTargetAmount: 0,
        monthlyTargetAmount: 0,
      );

      await _loadAccountData();

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showMessage(
        'تنظیمات حساب با موفقیت ذخیره شد.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showMessage(
        'خطا در ذخیره تنظیمات حساب.',
        isError: true,
      );
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'اطلاعات حساب',
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadAccountData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCapitalSection(),
                  const SizedBox(height: 24),
                  _buildTargetSection(),
                  const SizedBox(height: 24),
                  _buildPerformanceSection(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // CAPITAL
  // ============================================================

  Widget _buildCapitalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'سرمایه حساب',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildNumberField(
          controller: _initialBalanceController,
          label: 'سرمایه اولیه',
          suffix: 'دلار',
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 20),
        _buildInfoRow(
          title: 'سرمایه فعلی',
          value: '${_formatMoney(_currentCapital)} دلار',
        ),
        const SizedBox(height: 12),
        _buildInfoRow(
          title: 'سود/ضرر کل',
          value: '${_formatSignedMoney(_totalPnl)} دلار',
          valueColor: _pnlColor(_totalPnl),
        ),
      ],
    );
  }

  // ============================================================
  // TARGETS
  // ============================================================

  Widget _buildTargetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تارگت‌های حساب',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'این مقادیر یک‌بار برای حساب تنظیم می‌شوند و برای معاملات جداگانه وارد نمی‌شوند.',
          style: TextStyle(
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 16),
        _buildNumberField(
          controller: _dailyTargetController,
          label: 'تارگت روزانه',
          suffix: '%',
          icon: Icons.today_outlined,
        ),
        const SizedBox(height: 16),
        _buildNumberField(
          controller: _weeklyTargetController,
          label: 'تارگت هفتگی',
          suffix: '%',
          icon: Icons.date_range_outlined,
        ),
        const SizedBox(height: 16),
        _buildNumberField(
          controller: _monthlyTargetController,
          label: 'تارگت ماهانه',
          suffix: '%',
          icon: Icons.calendar_month_outlined,
        ),
      ],
    );
  }

  // ============================================================
  // PERFORMANCE
  // ============================================================

  Widget _buildPerformanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'عملکرد حساب',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildPerformanceItem(
          title: 'امروز',
          pnl: _todayPnl,
          target: _dailyTargetAmount,
          progress: _dailyProgress,
        ),
        const SizedBox(height: 20),
        _buildPerformanceItem(
          title: 'این هفته',
          pnl: _weekPnl,
          target: _weeklyTargetAmount,
          progress: _weeklyProgress,
        ),
        const SizedBox(height: 20),
        _buildPerformanceItem(
          title: 'این ماه',
          pnl: _monthPnl,
          target: _monthlyTargetAmount,
          progress: _monthlyProgress,
        ),
      ],
    );
  }

  Widget _buildPerformanceItem({
    required String title,
    required double pnl,
    required double target,
    required double progress,
  }) {
    final progressForBar = (progress / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        _buildInfoRow(
          title: 'سود/ضرر',
          value: '${_formatSignedMoney(pnl)} دلار',
          valueColor: _pnlColor(pnl),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          title: 'مقدار تارگت',
          value: '${_formatMoney(target)} دلار',
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          title: 'تحقق تارگت',
          value: '${_formatNumber(progress)}%',
          valueColor: _progressColor(progress),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progressForBar,
            minHeight: 10,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SAVE BUTTON
  // ============================================================

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _saveAccountSettings,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.save_outlined,
              ),
        label: Text(
          _isSaving ? 'در حال ذخیره...' : 'ذخیره تنظیمات حساب',
        ),
      ),
    );
  }

  // ============================================================
  // NUMBER FIELD
  // ============================================================

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _buildInfoRow({
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
            ),
          ),
        ),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
        ),
      );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  double _toDouble(String value) {
    final normalized =
        numbers.normalizeNumberInput(value).trim().replaceAll(',', '');

    return double.tryParse(
          normalized,
        ) ??
        0.0;
  }

  String _formatNumber(double value) {
    return numbers.formatNumber(value, decimals: 2);
  }

  String _formatMoney(double value) {
    return numbers.formatNumber(value, decimals: 2, trimTrailingZeros: false);
  }

  String _formatSignedMoney(double value) {
    if (value > 0) {
      return '+${_formatMoney(value)}';
    }

    if (value < 0) {
      return _formatMoney(value);
    }

    return '0.00';
  }

  Color _pnlColor(double value) {
    if (value > 0) {
      return Colors.green;
    }

    if (value < 0) {
      return Colors.red;
    }

    return null ?? Theme.of(context).textTheme.bodyMedium!.color!;
  }

  Color _progressColor(double progress) {
    if (progress >= 100) {
      return Colors.green;
    }

    if (progress > 0) {
      return Colors.orange;
    }

    if (progress < 0) {
      return Colors.red;
    }

    return Theme.of(context).textTheme.bodyMedium!.color!;
  }
}
