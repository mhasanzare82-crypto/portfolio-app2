import 'package:flutter/material.dart';
import '../utils/number_formatter.dart';

class NumberDisplaySettingsPage extends StatefulWidget {
  const NumberDisplaySettingsPage({super.key});

  @override
  State<NumberDisplaySettingsPage> createState() =>
      _NumberDisplaySettingsPageState();
}

class _NumberDisplaySettingsPageState extends State<NumberDisplaySettingsPage> {
  bool get _persian => NumberFormatSettings.usePersianDigits.value;

  Future<void> _setMode(bool value) async {
    await NumberFormatSettings.setPersianDigits(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نمایش اعداد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              value: _persian,
              onChanged: _setMode,
              secondary: const Icon(Icons.pin_outlined),
              title: const Text('نمایش اعداد فارسی'),
              subtitle: Text(_persian
                  ? 'نمونه: ${localizeDigits('123,456.78')}'
                  : 'نمونه: 123,456.78'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('جداکننده هزارگان'),
              subtitle: Text(
                  'اعداد از ${formatInteger(1000)} به بالا با ویرگول انگلیسی (,) گروه‌بندی می‌شوند.'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('پیش‌نمایش'),
              subtitle: Text(
                  'قیمت: ${formatNumber(1234567.89, decimals: 2, trimTrailingZeros: false)}'),
            ),
          ),
        ],
      ),
    );
  }
}
