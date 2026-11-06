import 'package:flutter/material.dart';
import '../utils/number_formatter.dart' as numbers;

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مدیریت سؤال‌ها و چک‌لیست‌ها',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF20B8A6)),
        scaffoldBackgroundColor: const Color(0xFF101820),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101820),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: QuestionChecklistDemoPage(),
      ),
    );
  }
}

enum CollectionKind { questions, checklists }

enum AnswerMode { checkbox, choices }

class EntryItem {
  EntryItem({required this.text, this.visible = true, this.checked = false});
  String text;
  bool visible;
  bool checked;
}

class EntryCollection {
  EntryCollection({
    required this.title,
    required this.kind,
    required this.answerMode,
    List<EntryItem>? items,
    this.visible = true,
  }) : items = items ?? [];

  String title;
  CollectionKind kind;
  AnswerMode answerMode;
  List<EntryItem> items;
  bool visible;
}

class QuestionChecklistDemoPage extends StatefulWidget {
  const QuestionChecklistDemoPage({super.key});

  @override
  State<QuestionChecklistDemoPage> createState() =>
      _QuestionChecklistDemoPageState();
}

class _QuestionChecklistDemoPageState extends State<QuestionChecklistDemoPage> {
  int _tab = 1;
  final List<EntryCollection> _collections = [
    EntryCollection(
      title: 'کنترل احساسات',
      kind: CollectionKind.checklists,
      answerMode: AnswerMode.checkbox,
      items: [
        EntryItem(text: 'بدون عجله وارد معامله می‌شوم'),
        EntryItem(text: 'برای جبران ضرر معامله نمی‌کنم'),
        EntryItem(text: 'به برنامه معاملاتی پایبندم'),
      ],
    ),
    EntryCollection(
      title: 'سؤالات قبل از ورود',
      kind: CollectionKind.questions,
      answerMode: AnswerMode.choices,
      items: [
        EntryItem(text: 'آیا روند بازار مشخص است؟'),
        EntryItem(text: 'آیا حد ضرر مشخص شده است؟'),
      ],
    ),
  ];

  List<EntryCollection> get _visibleTabCollections => _collections
      .where((c) => _tab == 0
          ? c.kind == CollectionKind.questions
          : _tab == 1
              ? c.kind == CollectionKind.checklists
              : true)
      .toList();

  Future<void> _createCollection() async {
    final isQuestion = _tab == 0;
    if (_tab == 2) {
      _showMessage(
          'در نمونهٔ فعلی، ورود و خروج فایل TXT در مرحلهٔ بعد اضافه می‌شود.');
      return;
    }
    final result = await showDialog<EntryCollection>(
      context: context,
      builder: (_) => CollectionEditorDialog(
        kind: isQuestion ? CollectionKind.questions : CollectionKind.checklists,
      ),
    );
    if (result != null) setState(() => _collections.insert(0, result));
  }

  Future<void> _editCollection(EntryCollection collection) async {
    final result = await showDialog<EntryCollection>(
      context: context,
      builder: (_) =>
          CollectionEditorDialog(existing: collection, kind: collection.kind),
    );
    if (result != null) {
      setState(() {
        collection.title = result.title;
        collection.answerMode = result.answerMode;
        collection.items = result.items;
      });
    }
  }

  Future<void> _editItem(EntryCollection collection, EntryItem item) async {
    final controller = TextEditingController(text: item.text);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ویرایش مورد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'متن مورد'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('ذخیره')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) setState(() => item.text = value);
  }

  void _deleteCollection(EntryCollection collection) {
    setState(() => _collections.remove(collection));
    _showMessage('مجموعه حذف شد.');
  }

  void _exportTxt(EntryCollection collection) {
    final lines = <String>[
      'عنوان: ${collection.title}',
      'نوع: ${collection.kind == CollectionKind.questions ? 'سؤالات' : 'چک‌لیست'}',
      'حالت پاسخ: ${collection.answerMode == AnswerMode.checkbox ? 'باکس سؤال' : 'گزینه‌های انتخابی'}',
      ...collection.items
          .map((item) => '${item.visible ? '[نمایش]' : '[مخفی]'} ${item.text}'),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('پیش‌نمایش خروجی TXT'),
        content: SingleChildScrollView(child: SelectableText(lines.join('\n'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('بستن'))
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final collections = _visibleTabCollections;
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت سؤال‌ها و چک‌لیست‌ها')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('سؤالات')),
                ButtonSegment(value: 1, label: Text('چک‌لیست‌ها')),
                ButtonSegment(value: 2, label: Text('ورود و خروج')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
          if (_tab != 2)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _createCollection,
                  icon: const Icon(Icons.add),
                  label:
                      Text(_tab == 0 ? 'ایجاد سؤالات جدید' : 'ایجاد چک‌لیست'),
                ),
              ),
            ),
          Expanded(
            child: _tab == 2
                ? _buildImportExportTab()
                : collections.isEmpty
                    ? const Center(
                        child: Text('هنوز مجموعه‌ای ایجاد نشده است.',
                            style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: collections.length,
                        itemBuilder: (_, index) =>
                            _buildCollectionCard(collections[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportExportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('ورود و خروج فایل‌های متنی',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'در این نمونه، خروجی TXT به شکل پیش‌نمایش نمایش داده می‌شود. انتخاب فایل و ذخیرهٔ واقعی فایل در نسخهٔ بعدی متصل می‌شود.',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
            onPressed: () =>
                _showMessage('ورود TXT هنوز به انتخاب‌گر فایل متصل نشده است.'),
            icon: const Icon(Icons.upload_file),
            label: const Text('ورود TXT به سؤالات')),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
            onPressed: () =>
                _showMessage('ورود TXT هنوز به انتخاب‌گر فایل متصل نشده است.'),
            icon: const Icon(Icons.upload_file),
            label: const Text('ورود TXT به چک‌لیست‌ها')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: () =>
                _showMessage('برای خروجی، از منوی هر کارت استفاده کن.'),
            icon: const Icon(Icons.download),
            label: const Text('راهنمای خروجی TXT')),
      ],
    );
  }

  Widget _buildCollectionCard(EntryCollection collection) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF1A2630),
      child: ExpansionTile(
        key: ObjectKey(collection),
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(collection.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${numbers.formatInteger(collection.items.length)} مورد · ${collection.visible ? 'نمایش فعال' : 'مخفی'}'),
        trailing: const Icon(Icons.keyboard_arrow_down),
        children: [
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('نمایش مجموعه در معامله جدید'),
            value: collection.visible,
            onChanged: (value) => setState(() => collection.visible = value),
          ),
          ListTile(
            title: const Text('نوع پاسخ'),
            subtitle: Text(collection.answerMode == AnswerMode.checkbox
                ? 'باکس سؤال'
                : 'گزینه‌های انتخابی'),
            trailing: IconButton(
                tooltip: 'ویرایش عنوان و نوع',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editCollection(collection)),
          ),
          if (collection.items.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('هنوز موردی اضافه نشده است.')),
          ...collection.items.map((item) => _buildItemRow(collection, item)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                    onPressed: () => _addItem(collection),
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن مورد')),
                OutlinedButton.icon(
                    onPressed: () => _exportTxt(collection),
                    icon: const Icon(Icons.download),
                    label: const Text('خروجی TXT')),
                OutlinedButton.icon(
                    onPressed: () => _editCollection(collection),
                    icon: const Icon(Icons.edit),
                    label: const Text('ویرایش مجموعه')),
                TextButton.icon(
                    onPressed: () => _confirmDeleteCollection(collection),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    label: const Text('حذف مجموعه',
                        style: TextStyle(color: Colors.redAccent))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(EntryCollection collection, EntryItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          if (collection.answerMode == AnswerMode.checkbox)
            CheckboxListTile(
              value: item.checked,
              onChanged: item.visible
                  ? (value) => setState(() => item.checked = value ?? false)
                  : null,
              title: Text(item.text,
                  style: TextStyle(
                      color: item.visible ? Colors.white : Colors.white38)),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            )
          else
            RadioListTile<bool>(
              value: true,
              groupValue: item.checked,
              onChanged: item.visible
                  ? (_) => setState(() {
                        for (final other in collection.items) {
                          other.checked = false;
                        }
                        item.checked = true;
                      })
                  : null,
              title: Text(item.text,
                  style: TextStyle(
                      color: item.visible ? Colors.white : Colors.white38)),
              dense: true,
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                    tooltip: 'نمایش/عدم نمایش مورد',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => item.visible = !item.visible),
                    icon: Icon(item.visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined)),
                IconButton(
                    tooltip: 'ویرایش مورد',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editItem(collection, item),
                    icon: const Icon(Icons.edit_outlined)),
                IconButton(
                    tooltip: 'حذف مورد',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => collection.items.remove(item)),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem(EntryCollection collection) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('افزودن مورد'),
        content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'متن مورد')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('افزودن')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty)
      setState(() => collection.items.add(EntryItem(text: value)));
  }

  Future<void> _confirmDeleteCollection(EntryCollection collection) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف مجموعه؟'),
        content:
            Text('مجموعهٔ «${collection.title}» و تمام موارد آن حذف می‌شود.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (yes == true) _deleteCollection(collection);
  }
}

class CollectionEditorDialog extends StatefulWidget {
  const CollectionEditorDialog({super.key, required this.kind, this.existing});
  final CollectionKind kind;
  final EntryCollection? existing;

  @override
  State<CollectionEditorDialog> createState() => _CollectionEditorDialogState();
}

class _CollectionEditorDialogState extends State<CollectionEditorDialog> {
  late final TextEditingController _titleController;
  late AnswerMode _mode;
  late List<EntryItem> _items;
  final TextEditingController _itemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.existing?.title ?? '');
    _mode = widget.existing?.answerMode ?? AnswerMode.checkbox;
    _items = widget.existing == null
        ? []
        : widget.existing!.items
            .map((item) => EntryItem(
                text: item.text, visible: item.visible, checked: item.checked))
            .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _itemController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(EntryItem(text: text));
      _itemController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isQuestion = widget.kind == CollectionKind.questions;
    return AlertDialog(
      title: Text(widget.existing == null
          ? (isQuestion ? 'ایجاد سؤالات جدید' : 'ایجاد چک‌لیست')
          : 'ویرایش مجموعه'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'عنوان مجموعه')),
              const SizedBox(height: 14),
              const Text('نوع پاسخ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<AnswerMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('باکس سؤال'),
                  subtitle: const Text('هر مورد مستقل علامت زده می‌شود'),
                  value: AnswerMode.checkbox,
                  groupValue: _mode,
                  onChanged: (value) => setState(() => _mode = value!)),
              RadioListTile<AnswerMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('گزینه‌های انتخابی'),
                  subtitle: const Text('از میان موارد، یک گزینه انتخاب می‌شود'),
                  value: AnswerMode.choices,
                  groupValue: _mode,
                  onChanged: (value) => setState(() => _mode = value!)),
              const Divider(),
              const Text('موارد مجموعه',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: _itemController,
                          decoration: const InputDecoration(
                              hintText: 'متن مورد را وارد کن'),
                          onSubmitted: (_) => _addItem())),
                  IconButton(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_circle,
                          color: Color(0xFF20B8A6))),
                ],
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                const Text('هنوز موردی اضافه نشده است.',
                    style: TextStyle(color: Colors.grey)),
              ..._items.asMap().entries.map((entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        radius: 13,
                        child: Text('${entry.key + 1}',
                            style: const TextStyle(fontSize: 12))),
                    title: Text(entry.value.text),
                    trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        onPressed: () =>
                            setState(() => _items.removeAt(entry.key))),
                  )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('لغو')),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
                context,
                EntryCollection(
                    title: title,
                    kind: widget.kind,
                    answerMode: _mode,
                    items: _items));
          },
          child: Text(isQuestion ? 'ذخیرهٔ سؤالات' : 'ذخیرهٔ چک‌لیست'),
        ),
      ],
    );
  }
}
