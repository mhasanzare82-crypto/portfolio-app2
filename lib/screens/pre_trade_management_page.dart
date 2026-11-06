import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/number_formatter.dart' as numbers;
import '../repositories/pre_trade_repository.dart';
import 'color_settings_page.dart';

class PreTradeManagementPage extends StatefulWidget {
  const PreTradeManagementPage({
    super.key,
  });

  @override
  State<PreTradeManagementPage> createState() => _PreTradeManagementPageState();
}

class _PreTradeManagementPageState extends State<PreTradeManagementPage> {
  final PreTradeRepository _repository = PreTradeRepository();

  static const String _questions = 'questions';

  static const String _psychology = 'psychology';

  static const String _technical = 'technical';

  int _selectedCategory = 0;

  bool _loading = true;

  List<Map<String, dynamic>> _items = [];
  final Set<int> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();

    _loadItems();
  }

  Future<void> _exportCurrentItems() async {
    try {
      final content = _items
          .map((item) => (item['item_title']?.toString() ?? '').trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
      final categoryName = _selectedCategory == 2
          ? 'pre_trade_questions'
          : _selectedCategory == 0
              ? 'non_trading_checklist'
              : 'trading_checklist';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'خروجی گرفتن از $_currentTitle',
        fileName: '$categoryName.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (path != null) _showMessage('خروجی متنی ذخیره شد.');
    } catch (e) {
      _showMessage('خروجی گرفتن ناموفق بود: $e');
    }
  }

  Future<void> _importCurrentItems() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'انتخاب فایل TXT برای $_currentTitle',
        type: FileType.custom,
        allowedExtensions: ['txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _showMessage('خواندن فایل انتخاب‌شده ممکن نشد.');
        return;
      }
      final lines = utf8
          .decode(bytes)
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      var imported = 0;
      for (final line in lines) {
        await _repository.createItem(
          title: line,
          category: _currentCategory,
          itemType: _currentItemType,
          isRequired: false,
          isEnabled: true,
        );
        imported++;
      }
      await _loadItems();
      _showMessage('$imported مورد از فایل متنی اضافه شد.');
    } catch (e) {
      _showMessage('ورود اطلاعات ناموفق بود: $e');
    }
  }

  // =========================================================
  // CATEGORY
  // =========================================================

  String get _currentCategory {
    switch (_selectedCategory) {
      case 0:
        return _psychology;
      case 1:
        return _technical;
      default:
        return _questions;
    }
  }

  String get _currentTitle {
    switch (_selectedCategory) {
      case 0:
        return 'چک لیست های غیر معاملاتی';
      case 1:
        return 'چک لیست های معاملاتی';
      default:
        return 'سوالات قبل از معامله';
    }
  }

  String get _currentItemType {
    return _selectedCategory == 2 ? 'question' : 'checklist';
  }

  // =========================================================
  // LOAD
  // =========================================================

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
    });

    try {
      final items = await _repository.getAllItems(
        category: _currentCategory,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      _showMessage(
        'خطا در دریافت اطلاعات: $error',
      );
    }
  }

  // =========================================================
  // ADD
  // =========================================================

  Future<void> _addItem({String folderName = ''}) async {
    final result = await _showItemDialog(existingFolderName: folderName);

    if (result == null) {
      return;
    }

    final lines = result.title
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      _showMessage('حداقل یک مورد وارد کن.');
      return;
    }

    try {
      for (final line in lines) {
        await _repository.createItem(
          title: line,
          category: _currentCategory,
          itemType: _currentItemType,
          isRequired: result.isRequired,
          isEnabled: true,
          folderName: result.folderName,
        );
      }

      await _loadItems();

      _showMessage(
        '${numbers.formatInteger(lines.length)} مورد جدید با موفقیت اضافه شد.',
      );
    } catch (error) {
      _showMessage(
        'خطا در اضافه کردن مورد: $error',
      );
    }
  }

  Future<void> _addManyItems() async {
    final controller = TextEditingController();
    final folderController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(_selectedCategory == 2
                  ? 'افزودن چند سؤال'
                  : 'افزودن چند مورد چک‌لیست'),
              content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: folderController,
                        decoration: const InputDecoration(
                            labelText: 'موضوع / پوشه (اختیاری)')),
                    const SizedBox(height: 8),
                    TextField(
                        controller: controller,
                        autofocus: true,
                        minLines: 6,
                        maxLines: 12,
                        decoration: const InputDecoration(
                            labelText: 'هر خط یک سؤال یا مورد',
                            hintText: 'مورد اول\nمورد دوم\nمورد سوم',
                            border: OutlineInputBorder())),
                  ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('لغو')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, {
                          'items': controller.text,
                          'folder': folderController.text
                        }),
                    child: const Text('افزودن همه'))
              ],
            ));
    controller.dispose();
    folderController.dispose();
    if (result == null) return;
    final lines = (result['items'] ?? '')
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      _showMessage('حداقل یک مورد وارد کن.');
      return;
    }
    try {
      for (final line in lines) {
        await _repository.createItem(
            title: line,
            category: _currentCategory,
            itemType: _currentItemType,
            isRequired: false,
            isEnabled: true,
            folderName: result['folder'] ?? '');
      }
      await _loadItems();
      _showMessage('${numbers.formatInteger(lines.length)} مورد اضافه شد.');
    } catch (e) {
      _showMessage('افزودن موارد ناموفق بود: $e');
    }
  }


  Future<void> _createCollection() async {
    final titleController = TextEditingController();
    final itemsController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ایجاد مجموعه جدید'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleController, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان مجموعه')),
            const SizedBox(height: 12),
            TextField(controller: itemsController, minLines: 5, maxLines: 10, keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(labelText: 'موارد مجموعه', hintText: 'هر خط یک مورد', border: OutlineInputBorder())),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, {'title': titleController.text.trim(), 'items': itemsController.text}), child: const Text('ایجاد مجموعه')),
        ],
      ),
    );
    titleController.dispose();
    itemsController.dispose();
    if (result == null) return;
    final title = (result['title'] ?? '').trim();
    final lines = (result['items'] ?? '').split(RegExp(r'\r?\n')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    if (title.isEmpty) { _showMessage('عنوان مجموعه را وارد کن.'); return; }
    if (lines.isEmpty) { _showMessage('حداقل یک مورد برای مجموعه وارد کن.'); return; }
    try {
      for (final line in lines) {
        await _repository.createItem(title: line, category: _currentCategory, itemType: _currentItemType, isRequired: false, isEnabled: true, folderName: title);
      }
      await _loadItems();
      _showMessage('مجموعه «$title» با ${numbers.formatInteger(lines.length)} مورد ایجاد شد.');
    } catch (e) { _showMessage('ایجاد مجموعه ناموفق بود: $e'); }
  }

  Future<void> _renameCollection(String oldTitle, List<Map<String, dynamic>> items) async {
    final controller = TextEditingController(text: oldTitle);
    final value = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('ویرایش نام مجموعه'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان مجموعه جدید')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('ذخیره')),
      ],
    ));
    controller.dispose();
    if (value == null || value.isEmpty || value == oldTitle) return;
    try {
      for (final item in items) {
        await _repository.updateItem(itemId: item['item_id'] as int, title: item['item_title']?.toString() ?? '',
          category: _currentCategory, itemType: _currentItemType, isRequired: item['is_required'] == 1, folderName: value);
      }
      await _loadItems();
      _showMessage('نام مجموعه تغییر کرد.');
    } catch (e) { _showMessage('ویرایش نام مجموعه ناموفق بود: $e'); }
  }

  Future<void> _toggleCollection(List<Map<String, dynamic>> items) async {
    final enable = items.any((item) => item['is_enabled'] != 1);
    for (final item in items) {
      final id = item['item_id'];
      if (id is int) await _repository.setEnabled(id, enable);
    }
    await _loadItems();
    _showMessage(enable ? 'همه موارد مجموعه فعال شدند.' : 'همه موارد مجموعه غیرفعال شدند.');
  }

  Future<void> _deleteCollection(String title, List<Map<String, dynamic>> items) async {
    final yes = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('حذف مجموعه؟'),
      content: Text('مجموعه «$title» و تمام موارد آن حذف شوند؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
      ],
    ));
    if (yes != true) return;
    for (final item in items) {
      final id = item['item_id'];
      if (id is int) await _repository.deleteItem(id);
    }
    await _loadItems();
    _showMessage('مجموعه حذف شد.');
  }

  Future<void> _exportCollection(String title, List<Map<String, dynamic>> items) async {
    final content = items.map((item) => item['item_title']?.toString().trim() ?? '').where((v) => v.isNotEmpty).join('\n');
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'خروجی مجموعه $title', fileName: '${safe.isEmpty ? 'collection' : safe}.txt',
      type: FileType.custom, allowedExtensions: ['txt'], bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path != null) _showMessage('خروجی TXT مجموعه ذخیره شد.');
  }

  Widget _buildCollectionCard(String title, List<Map<String, dynamic>> items) {
    final allEnabled = items.every((item) => item['is_enabled'] == 1);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${numbers.formatInteger(items.length)} مورد • ${allEnabled ? 'فعال' : 'دارای مورد غیرفعال'}'),
        children: [
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 6, runSpacing: 6, children: [
            OutlinedButton.icon(onPressed: () => _addItem(folderName: title == 'بدون مجموعه' ? '' : title), icon: const Icon(Icons.add), label: const Text('افزودن مورد')),
            OutlinedButton.icon(onPressed: () => _renameCollection(title, items), icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش نام')),
            OutlinedButton.icon(onPressed: () => _toggleCollection(items), icon: Icon(allEnabled ? Icons.visibility_off_outlined : Icons.visibility_outlined), label: Text(allEnabled ? 'غیرفعال‌سازی' : 'فعال‌سازی')),
            OutlinedButton.icon(onPressed: () => _exportCollection(title, items), icon: const Icon(Icons.download_outlined), label: const Text('خروجی TXT')),
            TextButton.icon(onPressed: () => _deleteCollection(title, items), icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text('حذف مجموعه', style: TextStyle(color: Colors.redAccent))),
          ])),
          for (var i = 0; i < items.length; i++) _buildItemCard(items[i], i),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> get _groupedItems {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in _items) {
      final raw = item['folder_name']?.toString().trim() ?? '';
      final title = raw.isEmpty ? 'بدون مجموعه' : raw;
      groups.putIfAbsent(title, () => <Map<String, dynamic>>[]).add(item);
    }
    return groups;
  }

  Future<void> _bulkSetEnabled(bool enabled) async {
    if (_selectedItemIds.isEmpty) return;
    for (final id in _selectedItemIds) {
      await _repository.setEnabled(id, enabled);
    }
    _selectedItemIds.clear();
    await _loadItems();
  }

  Future<void> _bulkDelete() async {
    if (_selectedItemIds.isEmpty) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('حذف گروهی'),
              content: Text(
                  '${numbers.formatInteger(_selectedItemIds.length)} مورد حذف شود؟'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('لغو')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('حذف'))
              ],
            ));
    if (ok != true) return;
    for (final id in _selectedItemIds.toList()) {
      await _repository.deleteItem(id);
    }
    _selectedItemIds.clear();
    await _loadItems();
  }

  Future<void> _exportSelectedItems() async {
    if (_selectedItemIds.isEmpty) return;
    final content = _items
        .where((item) => _selectedItemIds.contains(item['item_id']))
        .map((item) => item['item_title']?.toString() ?? '')
        .join('\n');
    final bytes = Uint8List.fromList(utf8.encode(content));
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'خروجی گروه انتخاب‌شده',
        fileName: 'selected_${_currentCategory}.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes);
    if (path != null) _showMessage('خروجی موارد انتخاب‌شده ذخیره شد.');
  }

  // =========================================================
  // EDIT
  // =========================================================

  Future<void> _editItem(
    Map<String, dynamic> item,
  ) async {
    final itemId = item['item_id'] as int?;

    if (itemId == null) {
      return;
    }

    final result = await _showItemDialog(
      existingTitle: item['item_title']?.toString() ?? '',
      existingRequired: item['is_required'] == 1,
      existingFolderName: item['folder_name']?.toString() ?? '',
    );

    if (result == null) {
      return;
    }

    try {
      await _repository.updateItem(
        itemId: itemId,
        title: result.title,
        category: _currentCategory,
        itemType: _currentItemType,
        isRequired: result.isRequired,
        folderName: result.folderName,
      );

      await _loadItems();

      _showMessage(
        'مورد با موفقیت ویرایش شد.',
      );
    } catch (error) {
      _showMessage(
        'خطا در ویرایش مورد: $error',
      );
    }
  }

  // =========================================================
  // ENABLE / DISABLE
  // =========================================================

  Future<void> _toggleItem(
    Map<String, dynamic> item,
  ) async {
    final itemId = item['item_id'] as int?;

    if (itemId == null) {
      return;
    }

    final currentEnabled = item['is_enabled'] == 1;

    try {
      await _repository.setEnabled(
        itemId,
        !currentEnabled,
      );

      await _loadItems();
    } catch (error) {
      _showMessage(
        'خطا در تغییر وضعیت: $error',
      );
    }
  }

  // =========================================================
  // DELETE
  // =========================================================

  Future<void> _deleteItem(
    Map<String, dynamic> item,
  ) async {
    final itemId = item['item_id'] as int?;

    if (itemId == null) {
      return;
    }

    final title = item['item_title']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'حذف مورد',
          ),
          content: Text(
            'آیا از حذف «$title» مطمئن هستید؟\n\n'
            'پاسخ‌های ثبت‌شده این مورد در معاملات قبلی نیز حذف خواهند شد.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'انصراف',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'حذف',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _repository.deleteItem(
        itemId,
      );

      await _loadItems();

      _showMessage(
        'مورد حذف شد.',
      );
    } catch (error) {
      _showMessage(
        'خطا در حذف مورد: $error',
      );
    }
  }

  // =========================================================
  // MOVE UP
  // =========================================================

  Future<void> _moveUp(
    Map<String, dynamic> item,
  ) async {
    final itemId = item['item_id'] as int?;

    if (itemId == null) {
      return;
    }

    try {
      await _repository.moveItemUp(
        itemId,
      );

      await _loadItems();
    } catch (error) {
      _showMessage(
        'خطا در تغییر ترتیب: $error',
      );
    }
  }

  // =========================================================
  // MOVE DOWN
  // =========================================================

  Future<void> _moveDown(
    Map<String, dynamic> item,
  ) async {
    final itemId = item['item_id'] as int?;

    if (itemId == null) {
      return;
    }

    try {
      await _repository.moveItemDown(
        itemId,
      );

      await _loadItems();
    } catch (error) {
      _showMessage(
        'خطا در تغییر ترتیب: $error',
      );
    }
  }

  Future<void> _exportItem(Map<String, dynamic> item) async {
    final title = item['item_title']?.toString() ?? 'item';
    final folder = item['folder_name']?.toString() ?? '';
    final content = '$title\n';
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'خروجی یک مورد',
      fileName: '${safe.isEmpty ? 'item' : safe}.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path != null)
      _showMessage(folder.isEmpty
          ? 'مورد صادر شد.'
          : 'مورد از پوشهٔ «$folder» صادر شد.');
  }

  Future<void> _importItemsForFolder(Map<String, dynamic> item) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'ورود TXT به پوشهٔ ${item['folder_name'] ?? ''}',
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    final lines = utf8
        .decode(bytes, allowMalformed: true)
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final line in lines) {
      await _repository.createItem(
        title: line,
        category: _currentCategory,
        itemType: _currentItemType,
        isRequired: false,
        isEnabled: true,
        folderName: item['folder_name']?.toString() ?? '',
      );
    }
    await _loadItems();
    _showMessage('${numbers.formatInteger(lines.length)} مورد وارد شد.');
  }

  // =========================================================
  // ITEM DIALOG
  // =========================================================

  Future<_ItemDialogResult?> _showItemDialog({
    String existingTitle = '',
    bool existingRequired = false,
    String existingFolderName = '',
  }) async {
    final controller = TextEditingController(
      text: existingTitle,
    );

    bool isRequired = existingRequired;
    final folderController = TextEditingController(text: existingFolderName);

    final result = await showDialog<_ItemDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                existingTitle.isEmpty ? 'افزودن مورد جدید' : 'ویرایش مورد',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: folderController,
                      decoration: const InputDecoration(
                          labelText: 'موضوع / پوشه (اختیاری)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText:
                            _selectedCategory == 2 ? 'سؤال' : 'عنوان آیتم',
                        hintText: _selectedCategory == 2
                            ? 'مثلاً آیا شرایط ورود طبق استراتژی من است؟'
                            : 'مثلاً قبل از ورود احساساتم را کنترل کرده‌ام',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'اجباری باشد',
                      ),
                      subtitle: Text(
                        _selectedCategory == 2
                            ? 'کاربر باید به این سؤال پاسخ دهد.'
                            : 'کاربر باید این مورد را تأیید کند.',
                      ),
                      value: isRequired,
                      onChanged: (
                        value,
                      ) {
                        setDialogState(() {
                          isRequired = value;
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
                    );
                  },
                  child: const Text(
                    'انصراف',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final title = controller.text.trim();

                    if (title.isEmpty) {
                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'لطفاً عنوان را وارد کنید.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _ItemDialogResult(
                        title: title,
                        isRequired: isRequired,
                        folderName: folderController.text.trim(),
                      ),
                    );
                  },
                  child: Text(
                    existingTitle.isEmpty ? 'افزودن' : 'ذخیره',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    folderController.dispose();

    return result;
  }

  // =========================================================
  // MESSAGE
  // =========================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }

  // =========================================================
  // CATEGORY BUTTON
  // =========================================================

  Widget _buildCategoryButton({
    required int index,
    required String title,
  }) {
    final selected = _selectedCategory == index;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
        ),
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: selected
                ? AppColors.navigationSelected.withValues(
                    alpha: 0.18,
                  )
                : null,
            foregroundColor: selected ? AppColors.navigationSelected : null,
            padding: const EdgeInsets.symmetric(
              vertical: 14,
            ),
          ),
          onPressed: () {
            if (_selectedCategory == index) {
              return;
            }

            setState(() {
              _selectedCategory = index;
            });

            _loadItems();
          },
          child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                ),
              ),
        ),
      ),
    );
  }

  // =========================================================
  // ITEM CARD
  // =========================================================

  Widget _buildItemCard(
    Map<String, dynamic> item,
    int index,
  ) {
    final title = item['item_title']?.toString() ?? '';

    final enabled = item['is_enabled'] == 1;

    final required = item['is_required'] == 1;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Checkbox(
              value: _selectedItemIds.contains(item['item_id']),
              onChanged: (value) => setState(() {
                final id = item['item_id'];
                if (id is int) {
                  if (value == true)
                    _selectedItemIds.add(id);
                  else
                    _selectedItemIds.remove(id);
                }
              }),
            ),
            CircleAvatar(
              radius: 19,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: enabled ? AppColors.text : AppColors.disabledText,
                    ),
                  ),
                  if ((item['folder_name']?.toString() ?? '').trim().isNotEmpty)
                    Text('موضوع: ${item['folder_name']}',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.secondaryText)),
                  const SizedBox(
                    height: 6,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildSmallTag(
                        enabled ? 'فعال' : 'غیرفعال',
                        enabled,
                      ),
                      if (required)
                        _buildSmallTag(
                          'اجباری',
                          true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (
                value,
              ) async {
                switch (value) {
                  case 'up':
                    await _moveUp(
                      item,
                    );
                    break;

                  case 'down':
                    await _moveDown(
                      item,
                    );
                    break;

                  case 'edit':
                    await _editItem(
                      item,
                    );
                    break;

                  case 'toggle':
                    await _toggleItem(
                      item,
                    );
                    break;

                  case 'delete':
                    await _deleteItem(
                      item,
                    );
                    break;

                  case 'export':
                    await _exportItem(item);
                    break;

                  case 'import':
                    await _importItemsForFolder(item);
                    break;
                }
              },
              itemBuilder: (
                context,
              ) {
                return [
                  const PopupMenuItem(
                    value: 'up',
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'انتقال به بالا',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'down',
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'انتقال به پایین',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'ویرایش',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          enabled ? Icons.visibility_off : Icons.visibility,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Text(
                          enabled ? 'غیرفعال کردن' : 'فعال کردن',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(children: [
                      Icon(Icons.file_download_outlined),
                      SizedBox(width: 8),
                      Text('خروجی این مورد')
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: Row(children: [
                      Icon(Icons.file_upload_outlined),
                      SizedBox(width: 8),
                      Text('ورود TXT به پوشه')
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'حذف',
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallTag(
    String text,
    bool active,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          20,
        ),
        color: active
            ? AppColors.navigationSelected.withValues(
                alpha: 0.18,
              )
            : AppColors.boxBackground,
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color:
              active ? AppColors.navigationSelected : AppColors.secondaryText,
        ),
      ),
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            Text(
              'هنوز موردی اضافه نشده است.',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              _selectedCategory == 2
                  ? 'سؤال‌هایی که می‌خواهی قبل از معامله پاسخ بدهی اضافه کن.'
                  : 'موارد چک‌لیست موردنظر خودت را اضافه کن.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(
              height: 18,
            ),
            FilledButton.icon(
              onPressed: _addItem,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'افزودن اولین مورد',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final groups = _groupedItems;
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت سوالات و چک‌لیست‌ها')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 12, 10, 4), child: Row(children: [
          _buildCategoryButton(index: 0, title: 'چک لیست های غیر معاملاتی'),
          _buildCategoryButton(index: 1, title: 'چک لیست های معاملاتی'),
          _buildCategoryButton(index: 2, title: 'سوالات قبل از معامله'),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: Wrap(
          spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton.icon(onPressed: _createCollection, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('ایجاد مجموعه')),
            IconButton(tooltip: 'ورود TXT (هر خط یک مورد)', onPressed: _importCurrentItems, icon: const Icon(Icons.file_open_outlined)),
            IconButton(tooltip: 'خروجی TXT همه موارد این بخش', onPressed: _exportCurrentItems, icon: const Icon(Icons.file_download_outlined)),
            IconButton(tooltip: 'افزودن چند مورد به یک موضوع', onPressed: _addManyItems, icon: const Icon(Icons.playlist_add)),
          ])),
        if (_selectedItemIds.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 8, children: [
            Chip(label: Text('${numbers.formatInteger(_selectedItemIds.length)} انتخاب‌شده')),
            TextButton.icon(onPressed: () => _bulkSetEnabled(true), icon: const Icon(Icons.check_circle_outline), label: const Text('فعال‌سازی')),
            TextButton.icon(onPressed: () => _bulkSetEnabled(false), icon: const Icon(Icons.pause_circle_outline), label: const Text('غیرفعال‌سازی')),
            TextButton.icon(onPressed: _exportSelectedItems, icon: const Icon(Icons.file_download_outlined), label: const Text('خروجی')),
            TextButton.icon(onPressed: _bulkDelete, icon: const Icon(Icons.delete_outline), label: const Text('حذف')),
          ])),
        Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.button))
          : RefreshIndicator(color: AppColors.button, backgroundColor: AppColors.cardBackground, onRefresh: _loadItems,
              child: groups.isEmpty
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [_buildEmptyState()])
                : ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    children: [for (final entry in groups.entries) _buildCollectionCard(entry.key, entry.value)]))),
      ])),
    );
  }
}

class _ItemDialogResult {
  final String title;
  final bool isRequired;
  final String folderName;

  const _ItemDialogResult({
    required this.title,
    required this.isRequired,
    this.folderName = '',
  });
}
