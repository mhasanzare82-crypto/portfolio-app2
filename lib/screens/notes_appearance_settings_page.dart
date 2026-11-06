import 'package:flutter/material.dart';
import '../notes_appearance_settings.dart';

class NotesAppearanceSettingsPage extends StatefulWidget {
  const NotesAppearanceSettingsPage({super.key});

  @override
  State<NotesAppearanceSettingsPage> createState() =>
      _NotesAppearanceSettingsPageState();
}

class _NotesAppearanceSettingsPageState
    extends State<NotesAppearanceSettingsPage> {
  final List<Color> _palette = [
    const Color(0xFF0D1117),
    const Color(0xFF161B22),
    const Color(0xFF21262D),
    Colors.white,
    Colors.black,
    Colors.grey,
    Colors.blue,
    Colors.lightBlue,
    Colors.green,
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.purple,
    Colors.teal,
    Colors.pink,
  ];

  final Map<String, String> _labels = {
    'pageBackground': 'پس‌زمینه صفحه',
    'appBarBackground': 'پس‌زمینه نوار بالا',
    'appBarText': 'متن نوار بالا',
    'appBarIcon': 'آیکون نوار بالا',
    'cardBackground': 'پس‌زمینه باکس‌ها',
    'primaryText': 'متن اصلی',
    'secondaryText': 'متن فرعی',
    'icon': 'رنگ آیکون‌ها',
    'divider': 'خطوط جداکننده',
    'inputBackground': 'پس‌زمینه ورودی',
    'inputBorder': 'حاشیه ورودی',
    'inputText': 'متن ورودی',
    'hintText': 'متن راهنما',
    'buttonBackground': 'پس‌زمینه دکمه',
    'buttonText': 'متن دکمه',
    'floatingButtonBackground': 'پس‌زمینه دکمه شناور',
    'floatingButtonText': 'متن دکمه شناور',
    'dialogBackground': 'پس‌زمینه پنجره',
    'menuBackground': 'پس‌زمینه منو',
    'snackbarBackground': 'پس‌زمینه پیام',
    'snackbarText': 'متن پیام',
    'toolbarBackground': 'پس‌زمینه ابزارها',
    'recording': 'رنگ ضبط',
    'delete': 'رنگ حذف',
  };

  Future<void> _saveCurrentAsTheme() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ساخت قالب از تنظیمات فعلی'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'نام قالب'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text('ذخیره قالب'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final fonts = NotesAppearanceSettings.fonts.value;
    await NotesAppearanceSettings.saveCustomTheme(NoteTextTheme(
      id: 'custom_$now',
      name: name,
      backgroundColor: NotesAppearanceSettings.color('inputBackground').value,
      textColor: NotesAppearanceSettings.color('inputText').value,
      fontFamily: fonts.inputFontFamily,
      fontSize: fonts.inputTextSize,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _selectColor(String key) async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_labels[key] ?? key),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _palette.map((color) {
            return InkWell(
              onTap: () => Navigator.pop(context, color),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );

    if (selected != null) {
      await NotesAppearanceSettings.setColor(key, selected);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotesAppearanceSettings.color('pageBackground'),
      appBar: AppBar(
        title: const Text('تنظیمات ظاهر یادداشت‌ها'),
        backgroundColor: NotesAppearanceSettings.color('appBarBackground'),
        foregroundColor: NotesAppearanceSettings.color('appBarText'),
        actions: [
          IconButton(
            tooltip: 'بازنشانی تنظیمات',
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              await NotesAppearanceSettings.reset();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<Map<String, Color>>(
        valueListenable: NotesAppearanceSettings.colors,
        builder: (context, colors, child) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('قالب‌های آماده نوشته', textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                      'برای نوشته جدید یک قالب به‌صورت تصادفی انتخاب می‌شود. می‌توانی قالب‌های سفارشی بسازی و آن‌ها را مدیریت کنی.',
                      textAlign: TextAlign.right),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saveCurrentAsTheme,
                      icon: const Icon(Icons.add),
                      label: const Text('ساخت قالب از رنگ و فونت فعلی')),
                    ...NotesAppearanceSettings.allThemes.map((theme) => Card(
                      color: theme.background,
                      child: ListTile(
                        title: Text(theme.name, textAlign: TextAlign.right,
                          style: TextStyle(color: theme.foreground, fontFamily: theme.fontFamily,
                            fontSize: theme.fontSize, fontWeight: FontWeight.bold)),
                        subtitle: Text('پیش‌نمایش نوشته با این قالب', textAlign: TextAlign.right,
                          style: TextStyle(color: theme.foreground, fontFamily: theme.fontFamily,
                            fontSize: theme.fontSize)),
                        trailing: NotesAppearanceSettings.customThemes.value.any((item) => item.id == theme.id)
                          ? IconButton(
                              tooltip: 'حذف قالب',
                              icon: Icon(Icons.delete_outline, color: theme.foreground),
                              onPressed: () async {
                                await NotesAppearanceSettings.deleteCustomTheme(theme.id);
                                if (mounted) setState(() {});
                              })
                          : Icon(Icons.check_circle_outline, color: theme.foreground),
                      ),
                    )),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'تنظیم رنگ بخش‌های مختلف یادداشت‌ها',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ..._labels.entries.map((entry) {
                final color = colors[entry.key] ?? Colors.white;

                return Card(
                  color: NotesAppearanceSettings.color('cardBackground'),
                  child: ListTile(
                    title: Text(
                      entry.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: NotesAppearanceSettings.color('primaryText'),
                      ),
                    ),
                    leading: GestureDetector(
                      onTap: () => _selectColor(entry.key),
                      child: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                    ),
                    trailing: Icon(
                      Icons.palette_outlined,
                      color: NotesAppearanceSettings.color('icon'),
                    ),
                    onTap: () => _selectColor(entry.key),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
