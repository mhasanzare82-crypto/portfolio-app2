import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:archive/archive.dart';
import 'package:docx_dart/docx_dart.dart' as docx;
import 'package:docx_dart/src/shared.dart' show Inches;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../calculators/pnl_calculator.dart';
import '../models/custom_field.dart';
import '../models/experience.dart';
import '../models/trade.dart';
import '../utils/number_formatter.dart' as numbers;
import '../repositories/custom_field_repository.dart';
import '../repositories/experience_repository.dart';
import '../repositories/pre_trade_repository.dart';
import '../repositories/trade_repository.dart';
import '../repositories/trade_note_repository.dart';
import '../repositories/note_subject_repository.dart';
import 'color_settings_page.dart';
import 'image_annotation_page.dart';
import '../widgets/trade_price_chart_section.dart';

class _ExperienceInlineController extends TextEditingController {
  List<String> imagePaths = [];
  List<String> audioPaths = [];
  void Function(String path)? onImageTap;
  void Function(String path)? onAudioTap;

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final children = <InlineSpan>[];
    final plain = StringBuffer();
    void flush() {
      if (plain.isNotEmpty) {
        children.add(TextSpan(text: plain.toString(), style: style));
        plain.clear();
      }
    }

    for (final rune in text.runes) {
      if (rune >= 0xE000 && rune < 0xF000) {
        flush();
        final index = rune - 0xE000;
        final path =
            index >= 0 && index < imagePaths.length ? imagePaths[index] : '';
        children.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: path.isNotEmpty && File(path).existsSync()
                  ? GestureDetector(
                      onTap: () => onImageTap?.call(path),
                      child: Image.file(File(path),
                          width: 220, height: 150, fit: BoxFit.contain))
                  : const Icon(Icons.broken_image_outlined),
            )));
      } else if (rune >= 0xF000 && rune < 0xF8FF) {
        flush();
        final index = rune - 0xF000;
        final path =
            index >= 0 && index < audioPaths.length ? audioPaths[index] : '';
        children.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: OutlinedButton.icon(
              onPressed: path.isEmpty ? null : () => onAudioTap?.call(path),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(path.isEmpty ? 'ویس در دسترس نیست' : p.basename(path),
                  overflow: TextOverflow.ellipsis),
            )));
      } else {
        plain.write(String.fromCharCode(rune));
      }
    }
    flush();
    return TextSpan(style: style, children: children);
  }
}

class TradeDetailsPage extends StatefulWidget {
  final Trade trade;
  final double livePrice;
  final VoidCallback onChanged;

  const TradeDetailsPage({
    super.key,
    required this.trade,
    required this.livePrice,
    required this.onChanged,
  });

  @override
  State<TradeDetailsPage> createState() => _TradeDetailsPageState();
}

class _TradeDetailsPageState extends State<TradeDetailsPage> {
  final TradeRepository _tradeRepository = TradeRepository();
  final ExperienceRepository _experienceRepository = ExperienceRepository();
  final CustomFieldRepository _customFieldRepository = CustomFieldRepository();
  final PreTradeRepository _preTradeRepository = PreTradeRepository();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TradeNoteRepository _noteRepository = TradeNoteRepository.instance;
  final NoteSubjectRepository _subjectRepository = NoteSubjectRepository.instance;
  final TextEditingController _entryTitleController = TextEditingController();
  final TextEditingController _entryContentController = TextEditingController();
  String? _activeEntryType;
  bool _showMistakes = true;
  bool _showExperiencesSection = true;
  bool _showTradeNotes = true;
  bool _showTradeImages = true;
  List<Map<String, dynamic>> _tradeNotes = [];

  late Trade _trade;

  bool _saving = false;
  bool _loadingCustomFields = true;
  bool _loadingPreTrade = true;
  bool _loadingExperiences = true;

  List<CustomField> _customFields = [];
  Map<int, String> _customFieldValues = {};

  List<Map<String, dynamic>> _preTradeItems = [];
  Map<int, String> _preTradeValues = {};

  List<Experience> _experiences = [];
  List<Map<String, String>> _mistakes = [];
  static const String _mistakesKeyPrefix = 'trade_mistakes_v1_';

  static const String _orderPreferenceKey = 'trade_details_parameter_order';

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static const List<String> _defaultParameterOrder = [
    'direction',
    'type',
    'marginMode',
    'timeframe',
    'status',
    'entryDate',
    'exitDate',
    'margin',
    'leverage',
    'volume',
    'fee',
    'entry',
    'currentPrice',
    'exit',
    'stop',
    'target',
    'riskDistance',
    'rewardDistance',
    'riskValue',
    'rewardValue',
    'targetRR',
    'liveRR',
    'priceChange',
    'pnl',
    'roiPercent',
    'roiDollar',
    'marginEffect',
    'riskToStop',
    'maxDrawdown',
    'maxDrawdownDollar',
    'drawdownMargin',
    'finalPnl',
    'finalRoi',
    'finalRoiDollar',
    'finalRR',
    'duration',
    'setup',
    'reason',
    'motivation',
    'scenario',
  ];

  List<String> _parameterOrder = [
    ..._defaultParameterOrder,
  ];

  bool _loadingParameterOrder = true;

  @override
  void initState() {
    super.initState();

    _trade = widget.trade;

    _loadCustomFieldValues();
    _loadPreTradeValues();
    _loadParameterOrder();
    _loadExperiences();
    _loadMistakes();
    _loadTradeNotes();
  }

  Future<void> _loadExperiences() async {
    try {
      final experiences = await _experienceRepository.getExperiencesForTrade(
        _trade.tradeId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _experiences = experiences;
        _loadingExperiences = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingExperiences = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطا در بارگذاری تجربه‌ها: $error',
          ),
        ),
      );
    }
  }


  String get _tradeNoteSource => 'trade_details:${_trade.tradeId}';

  Future<void> _loadTradeNotes() async {
    try {
      final notes = await _noteRepository.getNotesByAsset(_trade.assetSymbol);
      if (!mounted) return;
      setState(() {
        _tradeNotes = notes.where((note) => note['source'] == _tradeNoteSource).toList();
      });
    } catch (e) {
      _message('بارگذاری یادداشت‌های معامله ناموفق بود: $e');
    }
  }

  Future<int> _ensureNoteFolder(String category, String symbol) async {
    var roots = await _subjectRepository.getRootSubjects();
    var root = roots.where((item) =>
      item['subject_name']?.toString().toLowerCase() == category.toLowerCase()).toList();
    final rootId = root.isNotEmpty
      ? (root.first['subject_id'] as num).toInt()
      : await _subjectRepository.createSubject(name: category);

    final children = await _subjectRepository.getChildren(rootId);
    final child = children.where((item) =>
      item['subject_name']?.toString().toLowerCase() == symbol.toLowerCase()).toList();
    if (child.isNotEmpty) return (child.first['subject_id'] as num).toInt();
    return _subjectRepository.createSubject(name: symbol, parentId: rootId);
  }

  Future<void> _saveTradeEntry() async {
    final type = _activeEntryType;
    if (type == null || type == 'photo') return;
    final title = _entryTitleController.text.trim();
    final content = _entryContentController.text.trim();
    if (title.isEmpty) {
      _message('عنوان را وارد کنید.');
      return;
    }
    if (content.isEmpty) {
      _message('متن را وارد کنید.');
      return;
    }

    setState(() => _saving = true);
    try {
      final category = switch (type) {
        'mistake' => 'اشتباهات',
        'experience' => 'تجربیات',
        _ => 'یادداشت‌ها',
      };
      final noteType = switch (type) {
        'mistake' => 'اشتباه',
        'experience' => 'تجربه',
        _ => 'یادداشت معامله',
      };
      final assetFolderId = await _ensureNoteFolder(category, _trade.assetSymbol);
      final roots = await _subjectRepository.getRootSubjects();
      final root = roots.firstWhere((item) =>
        item['subject_name']?.toString().toLowerCase() == category.toLowerCase());
      final rootId = (root['subject_id'] as num).toInt();

      if (type == 'experience') {
        final experience = Experience(
          experienceId: DateTime.now().microsecondsSinceEpoch.toString(),
          tradeId: _trade.tradeId,
          experienceTitle: title,
          experienceDescription: content,
          experienceCreatedAt: DateTime.now(),
        );
        await _experienceRepository.createExperience(experience);
      } else if (type == 'mistake') {
        final mistake = <String, String>{
          'title': title,
          'description': content,
          'createdAt': DateTime.now().toIso8601String(),
        };
        setState(() => _mistakes.insert(0, mistake));
        await _saveMistakes();
      }

      final noteId = await _noteRepository.createNote(
        title: title,
        content: content,
        noteType: noteType,
        assetSymbol: _trade.assetSymbol,
        source: _tradeNoteSource,
        subjectIds: [rootId, assetFolderId],
      );
      final note = await _noteRepository.getNote(noteId);
      if (!mounted) return;
      setState(() {
        if (note != null) _tradeNotes.insert(0, note);
        _entryTitleController.clear();
        _entryContentController.clear();
        _activeEntryType = null;
      });
      if (type == 'experience') await _loadExperiences();
      widget.onChanged();
      _message('مورد با موفقیت در معامله و بخش یادداشت‌ها ذخیره شد.');
    } catch (e) {
      _message('ذخیره مورد ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildEntryComposer() {
    final type = _activeEntryType;
    if (type == null) return const SizedBox.shrink();
    if (type == 'photo') {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('افزودن عکس به معامله', textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : () async {
                await _addTradeImage();
                if (mounted) setState(() => _activeEntryType = null);
              },
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('انتخاب عکس از گالری'),
            ),
          ]),
        ),
      );
    }
    final label = type == 'mistake' ? 'اشتباه جدید' :
      type == 'experience' ? 'تجربه جدید' : 'یادداشت جدید';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: _entryTitleController,
            decoration: const InputDecoration(labelText: 'عنوان', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _entryContentController, minLines: 3, maxLines: 7,
            decoration: const InputDecoration(labelText: 'متن / توضیحات', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: _saving ? null : _saveTradeEntry,
              icon: const Icon(Icons.save_outlined), label: const Text('ذخیره'))),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() {
              _activeEntryType = null;
              _entryTitleController.clear();
              _entryContentController.clear();
            }), child: const Text('انصراف')),
          ]),
        ]),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, bool visible,
      ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(
        child: Text('$title (${numbers.formatInteger(count)})',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      Checkbox(value: visible, onChanged: (value) => onChanged(value ?? false)),
    ]);
  }

  Widget _buildTradeNotesSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildSectionHeader('یادداشت‌های معامله', _tradeNotes.length,
            _showTradeNotes, (value) => setState(() => _showTradeNotes = value)),
        if (_showTradeNotes) ...[
          if (_tradeNotes.isEmpty)
            const Padding(padding: EdgeInsets.all(12),
                child: Text('هنوز یادداشتی برای این معامله ثبت نشده است.', textAlign: TextAlign.right)),
          ..._tradeNotes.map((note) => Card(child: ListTile(
            title: Text(note['title']?.toString() ?? '', textAlign: TextAlign.right),
            subtitle: Text(note['content']?.toString() ?? '', textAlign: TextAlign.right,
                maxLines: 4, overflow: TextOverflow.ellipsis),
            trailing: Text(note['note_type']?.toString() ?? ''),
          ))),
        ],
      ]),
    );
  }

  Widget _buildTopEntryActions() {
    final actions = [
      ('mistake', 'اشتباه جدید', Icons.error_outline),
      ('experience', 'تجربه جدید', Icons.lightbulb_outline),
      ('note', 'یادداشت جدید', Icons.note_add_outlined),
      ('photo', 'عکس جدید', Icons.add_photo_alternate_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(children: [
        Row(
          children: actions.map((action) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: OutlinedButton(
                onPressed: () => setState(() {
                  final next = action.$1;
                  _activeEntryType = _activeEntryType == next ? null : next;
                  _entryTitleController.clear();
                  _entryContentController.clear();
                }),
                style: _activeEntryType == action.$1
                    ? OutlinedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                    : null,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(action.$3, size: 18),
                  const SizedBox(height: 3),
                  FittedBox(fit: BoxFit.scaleDown,
                      child: Text(action.$2, maxLines: 1, softWrap: false)),
                ]),
              ),
            ),
          )).toList(),
        ),
        _buildEntryComposer(),
      ]),
    );
  }

  Future<void> _loadMistakes() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString('trade_mistakes_v1_${_trade.tradeId}');
      if (raw != null && mounted) setState(() => _mistakes = (jsonDecode(raw) as List).map((e) => Map<String, String>.from(e as Map)).toList());
    } catch (_) {}
  }

  Future<void> _saveMistakes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trade_mistakes_v1_${_trade.tradeId}', jsonEncode(_mistakes));
  }

  Future<void> _newMistake() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) =>
      Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
        title: const Text('اشتباه جدید'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان اشتباه')),
          TextField(controller: description, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'شرح اشتباه')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () { if (title.text.trim().isEmpty && description.text.trim().isEmpty) return; Navigator.pop(ctx, {'title': title.text.trim(), 'description': description.text.trim()}); }, child: const Text('ثبت')),
        ],
      )));
    title.dispose(); description.dispose();
    if (result == null) return;
    setState(() => _mistakes.insert(0, result));
    await _saveMistakes();
  }

  Widget _buildTradeImagesSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildSectionHeader('عکس‌های معامله', _trade.imagePaths.length,
            _showTradeImages, (value) => setState(() => _showTradeImages = value)),
        if (_showTradeImages) ...[
          if (_trade.imagePaths.isEmpty)
            const Padding(padding: EdgeInsets.all(12),
                child: Text('هنوز عکسی اضافه نشده است.', textAlign: TextAlign.right)),
          ..._trade.imagePaths.asMap().entries.map((entry) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GestureDetector(
                onTap: () => _openTradeImage(entry.value, entry.key),
                child: Image.file(File(entry.value), width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
              ),
              Wrap(alignment: WrapAlignment.end, children: [
                IconButton(tooltip: 'نقاشی / ویرایش', icon: const Icon(Icons.draw),
                    onPressed: () => _openTradeImage(entry.value, entry.key)),
                IconButton(tooltip: 'ذخیره در گالری', icon: const Icon(Icons.download),
                    onPressed: () => _saveTradeImageToGallery(entry.value)),
                IconButton(tooltip: 'حذف عکس', icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteTradeImage(entry.key)),
              ]),
            ]),
          )),
        ],
      ]),
    );
  }

  Widget _buildMistakesSection() => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildSectionHeader('اشتباهات معامله', _mistakes.length, _showMistakes,
          (value) => setState(() => _showMistakes = value)),
      if (_showMistakes) ...[
        if (_mistakes.isEmpty)
          const Text('هنوز اشتباهی ثبت نشده است.', textAlign: TextAlign.right),
        ..._mistakes.asMap().entries.map((e) => Card(child: ListTile(
          title: Text(e.value['title'] ?? '', textAlign: TextAlign.right),
          subtitle: Text(e.value['description'] ?? '', textAlign: TextAlign.right),
          trailing: IconButton(icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                setState(() => _mistakes.removeAt(e.key));
                await _saveMistakes();
              }),
        ))),
      ],
    ]),
  );

  Future<void> _chooseTradeChecklist() async {
    final all = await _preTradeRepository.getAllItems();
    if (!mounted) return;
    final selected = <int>{..._preTradeItems.map((e) => int.tryParse(e['item_id'].toString())).whereType<int>()};
    final result = await showDialog<Set<int>>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, refresh) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
        title: const Text('انتخاب چک‌لیست‌ها'),
        content: SizedBox(width: double.maxFinite, height: 400, child: ListView(children: all.map((item) {
          final id = int.tryParse(item['item_id'].toString()); if (id == null) return const SizedBox.shrink();
          return CheckboxListTile(value: selected.contains(id), title: Text(item['item_title']?.toString() ?? '', textAlign: TextAlign.right), subtitle: Text(item['category']?.toString() ?? ''),
            onChanged: (v) => refresh(() { if (v == true) selected.add(id); else selected.remove(id); }));
        }).toList())),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('تأیید'))],
      ))));
    if (result == null) return;
    final chosen = all.where((e) => result.contains(int.tryParse(e['item_id'].toString()))).toList();
    final values = Map<int, String>.from(_preTradeValues);
    for (final item in chosen) { final id = int.tryParse(item['item_id'].toString()); if (id != null) values.putIfAbsent(id, () => ''); }
    await _preTradeRepository.saveTradeValues(_trade.tradeId, values);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('trade_selected_checklists_${_trade.tradeId}', result.map((id) => id.toString()).toList());
    if (mounted) setState(() { _preTradeItems = chosen; _preTradeValues = values; });
  }

  Future<void> _saveTradeImageToGallery(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final result = await SaverGallery.saveImage(bytes, fileName: 'trade_${DateTime.now().millisecondsSinceEpoch}${p.extension(path)}', androidRelativePath: 'Pictures/Portfolio', skipIfExists: false);
      _message(result.isSuccess ? 'تصویر در گالری ذخیره شد.' : 'ذخیره تصویر انجام نشد.');
    } catch (e) { _message('ذخیره در گالری ناموفق بود: $e'); }
  }

  Future<void> _deleteTradeImage(int index) async {
    final paths = List<String>.from(_trade.imagePaths)..removeAt(index);
    await _tradeRepository.updateTrade(_trade.copyWith(imagePaths: paths));
    final loaded = await _tradeRepository.getTrade(_trade.tradeId);
    if (loaded != null && mounted) setState(() => _trade = loaded);
    widget.onChanged();
  }

  Future<void> _openTradeImage(String path, int index) async {
    await showDialog<void>(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(8),
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.82,
        width: MediaQuery.of(ctx).size.width,
        child: Column(children: [
        Expanded(child: InteractiveViewer(child: SizedBox(width: double.infinity, child: Image.file(File(path), fit: BoxFit.contain)))),
        Wrap(alignment: WrapAlignment.center, children: [
          IconButton(tooltip: 'نقاشی', icon: const Icon(Icons.draw), onPressed: () async {
            final edited = await Navigator.of(ctx).push<String>(MaterialPageRoute(builder: (_) => ImageAnnotationPage(imagePath: path)));
            if (edited == null) return;
            final saved = await _copyImagePermanently(edited, 'trade_images');
            final paths = List<String>.from(_trade.imagePaths); if (index < paths.length) paths[index] = saved;
            await _tradeRepository.updateTrade(_trade.copyWith(imagePaths: paths));
            final loaded = await _tradeRepository.getTrade(_trade.tradeId);
            if (loaded != null && mounted) setState(() => _trade = loaded);
            if (ctx.mounted) Navigator.pop(ctx);
          }),
          IconButton(tooltip: 'ذخیره در گالری', icon: const Icon(Icons.download), onPressed: () => _saveTradeImageToGallery(path)),
          IconButton(tooltip: 'حذف عکس', icon: const Icon(Icons.delete_outline), onPressed: () async { await _deleteTradeImage(index); if (ctx.mounted) Navigator.pop(ctx); }),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
        ]),
      ])),
    ));
  }

  Future<void> _loadParameterOrder() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      final savedOrder = preferences.getStringList(
        _orderPreferenceKey,
      );

      if (!mounted) {
        return;
      }

      if (savedOrder == null || savedOrder.isEmpty) {
        setState(() {
          _parameterOrder = [
            ..._defaultParameterOrder,
          ];
          _loadingParameterOrder = false;
        });

        return;
      }

      final validSavedOrder = savedOrder
          .where(
            _defaultParameterOrder.contains,
          )
          .toList();

      for (final item in _defaultParameterOrder) {
        if (!validSavedOrder.contains(item)) {
          validSavedOrder.add(item);
        }
      }

      setState(() {
        _parameterOrder = validSavedOrder;
        _loadingParameterOrder = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _parameterOrder = [
          ..._defaultParameterOrder,
        ];
        _loadingParameterOrder = false;
      });
    }
  }

  Future<void> _saveParameterOrder() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setStringList(
      _orderPreferenceKey,
      _parameterOrder,
    );
  }

  Future<void> _resetParameterOrder() async {
    setState(() {
      _parameterOrder = [
        ..._defaultParameterOrder,
      ];
    });

    await _saveParameterOrder();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ترتیب پارامترها به حالت پیش‌فرض بازگردانده شد.',
        ),
      ),
    );
  }

  Future<void> _loadCustomFieldValues() async {
    try {
      final fields = await _customFieldRepository.getAllFields();

      final values = await _customFieldRepository.getTradeValues(
        _trade.tradeId,
      );

      fields.sort(
        (a, b) => a.fieldOrder.compareTo(
          b.fieldOrder,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _customFields = fields;
        _customFieldValues = values;
        _loadingCustomFields = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingCustomFields = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطا در بارگذاری مشخصات : $error',
          ),
        ),
      );
    }
  }

  Future<void> _loadPreTradeValues() async {
    try {
      const categories = [
        'questions',
        'psychology',
        'technical',
      ];

      final List<Map<String, dynamic>> items = [];

      for (final category in categories) {
        final categoryItems = await _preTradeRepository.getEnabledItems(
          category,
        );

        items.addAll(categoryItems);
      }

      items.sort(
        (a, b) {
          final orderA = int.tryParse(
                a['item_order']?.toString() ?? '',
              ) ??
              0;

          final orderB = int.tryParse(
                b['item_order']?.toString() ?? '',
              ) ??
              0;

          return orderA.compareTo(orderB);
        },
      );

      final values = await _preTradeRepository.getTradeValues(
        _trade.tradeId,
      );
      final prefs = await SharedPreferences.getInstance();
      final selectedIds = prefs.getStringList('trade_selected_checklists_${_trade.tradeId}') ?? const <String>[];
      if (selectedIds.isNotEmpty) {
        final allItems = await _preTradeRepository.getAllItems();
        for (final item in allItems) {
          if (selectedIds.contains(item['item_id']?.toString()) &&
              !items.any((existing) => existing['item_id']?.toString() == item['item_id']?.toString())) {
            items.add(item);
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _preTradeItems = items;
        _preTradeValues = values;
        _loadingPreTrade = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingPreTrade = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطا در بارگذاری چک‌لیست قبل از معامله: $error',
          ),
        ),
      );
    }
  }

  Widget _buildCustomFieldsSection() {
    if (_loadingCustomFields) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 20,
        ),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final visibleFields = _customFields.where(
      (field) {
        final fieldId = field.fieldId;

        if (fieldId == null) {
          return false;
        }

        final value = _customFieldValues[fieldId];

        return value != null && value.trim().isNotEmpty;
      },
    ).toList();

    if (visibleFields.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, List<CustomField>> groupedFields = {};

    for (final field in visibleFields) {
      final category =
          field.category.trim().isEmpty ? 'عمومی' : field.category.trim();

      groupedFields.putIfAbsent(
        category,
        () => [],
      );

      groupedFields[category]!.add(
        field,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(
        top: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مشخصات سفارشی',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          ...groupedFields.entries.map(
            (entry) {
              return _buildCustomFieldCategory(
                category: entry.key,
                fields: entry.value,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldCategory({
    required String category,
    required List<CustomField> fields,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: PageStorageKey(
            'trade_details_custom_$category',
          ),
          initiallyExpanded: false,
          maintainState: true,
          title: Text(
            category,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          leading: const Icon(
            Icons.folder_outlined,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            10,
          ),
          children: [
            ...fields.map(
              (field) {
                final fieldId = field.fieldId!;

                final value = _customFieldValues[fieldId] ?? '';

                return _parameterRow(
                  field.fieldName,
                  value,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreTradeSection() {
    if (_loadingPreTrade) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 20,
        ),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_preTradeItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: OutlinedButton.icon(
          onPressed: _chooseTradeChecklist,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('انتخاب چک‌لیست'),
        ),
      );
    }

    final questions = _preTradeItems
        .where(
          (item) => item['category']?.toString() == 'questions',
        )
        .toList();

    final psychology = _preTradeItems
        .where(
          (item) => item['category']?.toString() == 'psychology',
        )
        .toList();

    final technical = _preTradeItems
        .where(
          (item) => item['category']?.toString() == 'technical',
        )
        .toList();

    final widgets = <Widget>[];

    if (questions.isNotEmpty) {
      widgets.add(
        _buildPreTradeCategory(
          categoryKey: 'questions',
          title: 'سوالات قبل از معامله',
          icon: Icons.help_outline,
          items: questions,
        ),
      );
    }

    if (psychology.isNotEmpty) {
      widgets.add(
        _buildPreTradeCategory(
          categoryKey: 'psychology',
          title: 'چک‌لیست روانشناسی',
          icon: Icons.psychology_outlined,
          items: psychology,
        ),
      );
    }

    if (technical.isNotEmpty) {
      widgets.add(
        _buildPreTradeCategory(
          categoryKey: 'technical',
          title: 'چک‌لیست فنی',
          icon: Icons.analytics_outlined,
          items: technical,
        ),
      );
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(
        top: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'موارد قبل از معامله',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: _chooseTradeChecklist,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('انتخاب / تغییر چک‌لیست'),
          )),
          ...widgets,
        ],
      ),
    );
  }

  Widget _buildPreTradeCategory({
    required String categoryKey,
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: PageStorageKey(
            'trade_details_pre_trade_$categoryKey',
          ),
          initiallyExpanded: false,
          maintainState: true,
          leading: Icon(
            icon,
          ),
          title: Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            10,
          ),
          children: [
            ...items.map(
              _buildPreTradeDetailItem,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreTradeDetailItem(
    Map<String, dynamic> item,
  ) {
    final itemId = int.tryParse(
      item['item_id']?.toString() ?? '',
    );

    if (itemId == null) {
      return const SizedBox.shrink();
    }

    final title = item['item_title']?.toString() ??
        item['title']?.toString() ??
        item['item_name']?.toString() ??
        '';

    final itemType =
        item['item_type']?.toString() ?? item['type']?.toString() ?? '';

    final value = _preTradeValues[itemId] ?? '';

    final isQuestion = itemType == 'question' || itemType == 'text';

    if (isQuestion) {
      if (value.trim().isEmpty) {
        return const SizedBox.shrink();
      }

      return _parameterRow(
        title,
        value,
      );
    }

    final checked = value == 'yes' || value == 'true' || value == '1';

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Icon(
            checked ? Icons.check_circle : Icons.radio_button_unchecked,
            color: checked ? AppColors.profit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildExperiencesSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildSectionHeader('تجربه‌های معامله', _experiences.length,
            _showExperiencesSection, (value) => setState(() => _showExperiencesSection = value)),
        if (_showExperiencesSection) ...[
          if (_loadingExperiences)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_experiences.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('هنوز تجربه‌ای ثبت نشده است.', textAlign: TextAlign.right),
            )
          else
            ..._experiences.map(_buildExperienceTile),
        ],
      ]),
    );
  }

  bool _experienceHasInlineMedia(Experience experience) =>
      experience.experienceDescription.runes
          .any((rune) => rune >= 0xE000 && rune < 0xF8FF);

  Widget _buildExperienceDescription(Experience experience) {
    final children = <InlineSpan>[];
    final plain = StringBuffer();
    void flush() {
      if (plain.isNotEmpty) {
        children.add(TextSpan(text: plain.toString()));
        plain.clear();
      }
    }

    for (final rune in experience.experienceDescription.runes) {
      if (rune >= 0xE000 && rune < 0xF000) {
        flush();
        final index = rune - 0xE000;
        final path = index >= 0 && index < experience.imagePaths.length
            ? experience.imagePaths[index]
            : '';
        children.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: path.isNotEmpty && File(path).existsSync()
                  ? GestureDetector(
                      onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                              child: InteractiveViewer(
                                  child: Image.file(File(path),
                                      fit: BoxFit.contain)))),
                      child: Image.file(File(path),
                          width: 220, height: 150, fit: BoxFit.contain))
                  : const Icon(Icons.broken_image_outlined),
            )));
      } else if (rune >= 0xF000 && rune < 0xF8FF) {
        flush();
        final index = rune - 0xF000;
        final path = index >= 0 && index < experience.audioPaths.length
            ? experience.audioPaths[index]
            : '';
        children.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: OutlinedButton.icon(
              onPressed: path.isEmpty
                  ? null
                  : () async {
                      try {
                        await _audioPlayer.play(DeviceFileSource(path));
                      } catch (_) {
                        _message('پخش ویس ممکن نشد.');
                      }
                    },
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(path.isEmpty ? 'ویس در دسترس نیست' : p.basename(path),
                  overflow: TextOverflow.ellipsis),
            )));
      } else {
        plain.write(String.fromCharCode(rune));
      }
    }
    flush();
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Text.rich(TextSpan(children: children)));
  }

  Widget _buildExperienceTile(
    Experience experience,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: PageStorageKey(
            'trade_details_experience_${experience.experienceId}',
          ),
          initiallyExpanded: false,
          maintainState: true,
          leading: const Icon(
            Icons.lightbulb_outline,
          ),
          title: Text(
            experience.experienceTitle,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          subtitle: experience.experienceDescription.trim().isNotEmpty
              ? Text(
                  'برای مشاهده جزئیات باز کنید',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          childrenPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            12,
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _editExperience(experience),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('ویرایش عنوان و توضیحات تجربه'),
              ),
            ),
            if (experience.experienceDescription.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: _buildExperienceDescription(experience),
              ),
            if (experience.imagePaths.isNotEmpty &&
                !_experienceHasInlineMedia(experience)) ...[
              const SizedBox(
                height: 12,
              ),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: experience.imagePaths.length,
                  separatorBuilder: (context, index) {
                    return const SizedBox(
                      width: 8,
                    );
                  },
                  itemBuilder: (context, index) {
                    final path = experience.imagePaths[index];

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => Dialog(
                                child: InteractiveViewer(
                                    child: Image.file(File(path),
                                        fit: BoxFit.contain)))),
                        child: Image.file(
                          File(path),
                          width: 140,
                          height: 100,
                          fit: BoxFit.contain,
                          errorBuilder: (
                            context,
                            error,
                            stackTrace,
                          ) {
                            return Container(
                              width: 100,
                              height: 100,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                              child: const Icon(
                                Icons.broken_image_outlined,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (experience.audioPaths.isNotEmpty &&
                !_experienceHasInlineMedia(experience)) ...[
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: experience.audioPaths
                      .map((audioPath) => OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await _audioPlayer
                                    .play(DeviceFileSource(audioPath));
                              } catch (_) {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('پخش ویس ممکن نشد.')));
                              }
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: Text(p.basename(audioPath),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList()),
            ],
            if (experience.experienceDescription.trim().isEmpty &&
                experience.imagePaths.isEmpty &&
                experience.audioPaths.isEmpty)
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'برای این تجربه توضیح یا تصویری ثبت نشده است.',
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _jalaliDate(DateTime date) {
    final jalali = Jalali.fromDateTime(
      date,
    );

    return numbers.formatDigits(
        '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}');
  }

  String _gregorianDate(DateTime date) {
    return numbers.formatDigits('${date.year.toString().padLeft(4, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}');
  }

  String _time(DateTime date) {
    return numbers.formatDigits('${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}');
  }

  String _dateValue(DateTime date) {
    return '${_jalaliDate(date)}'
        '    ${_gregorianDate(date)}'
        '    ${_time(date)}';
  }

  double get _currentPrice {
    if (_trade.tradeStatus == TradeStatus.closed && _trade.exitPrice != null) {
      return _trade.exitPrice!;
    }

    return widget.livePrice;
  }

  double get _pnl {
    if (_currentPrice <= 0) {
      return 0;
    }

    return PnlCalculator.netPnl(
      _trade,
      _currentPrice,
    );
  }

  double _calculatePriceChangePercent(
    double currentPrice,
  ) {
    final entry = _trade.entryPrice;

    if (entry == null || entry <= 0 || currentPrice <= 0) {
      return 0;
    }

    if (_trade.tradeDirection == TradeDirection.long) {
      return ((currentPrice - entry) / entry) * 100;
    }

    return ((entry - currentPrice) / entry) * 100;
  }

  double _calculateLiveRiskReward(
    double currentPrice,
  ) {
    final stop = _trade.stopPrice;
    final target = _trade.targetPrice;

    if (stop == null || target == null || currentPrice <= 0) {
      return 0;
    }

    double distanceToStop;
    double distanceToTarget;

    if (_trade.tradeDirection == TradeDirection.long) {
      distanceToStop = (currentPrice - stop).abs();
      distanceToTarget = (target - currentPrice).abs();
    } else {
      distanceToStop = (stop - currentPrice).abs();
      distanceToTarget = (currentPrice - target).abs();
    }

    if (distanceToTarget <= 0) {
      return 0;
    }

    return distanceToStop / distanceToTarget;
  }

  double _calculateCurrentDrawdownPercent(
    double currentPrice,
  ) {
    final entry = _trade.entryPrice;

    if (entry == null || entry <= 0 || currentPrice <= 0) {
      return 0;
    }

    double value;

    if (_trade.tradeDirection == TradeDirection.long) {
      value = ((entry - currentPrice) / entry) * 100;
    } else {
      value = ((currentPrice - entry) / entry) * 100;
    }

    if (value < 0) {
      return 0;
    }

    return value;
  }

  int _calculateDurationSeconds(
    DateTime exitTime,
  ) {
    var seconds = exitTime
        .difference(
          _trade.entryTime,
        )
        .inSeconds;

    if (seconds < 0) {
      seconds = 0;
    }

    return seconds;
  }

  String _formatDuration(
    int seconds,
  ) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    return numbers.formatDigits('${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}');
  }

  String _formatNumber(
    double value, {
    int decimals = 2,
  }) {
    return numbers.formatNumber(value,
        decimals: decimals, trimTrailingZeros: false);
  }

  Color? _valueColor(
    String key,
    double value,
  ) {
    if (key == 'pnl' || key == 'roiPercent' || key == 'roiDollar') {
      if (value > 0) {
        return AppColors.profit;
      }

      if (value < 0) {
        return AppColors.loss;
      }
    }

    if (key == 'priceChange') {
      if (value > 0) {
        return AppColors.profit;
      }

      if (value < 0) {
        return AppColors.loss;
      }
    }

    if (key.contains('drawdown') ||
        key == 'maxDrawdown' ||
        key == 'maxDrawdownDollar') {
      if (value > 0) {
        return AppColors.drawdown;
      }
    }

    return null;
  }

  Widget _parameterRow(
    String title,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(
            width: 20,
          ),
          Expanded(
            flex: 2,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                value,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameter(
    String key, {
    required double currentPrice,
    required double pnlPercent,
    required double rr,
    required double riskValue,
    required double rewardValue,
    required double priceChangePercent,
    required double liveRiskReward,
    required double displayedDrawdown,
    required double displayedDrawdownDollar,
    required double displayedDrawdownMargin,
  }) {
    switch (key) {
      case 'direction':
        return _parameterRow(
          'جهت معامله',
          _trade.tradeDirection == TradeDirection.long ? 'لانگ' : 'شورت',
        );

      case 'type':
        return _parameterRow(
          'نوع معامله',
          _trade.tradeType == TradeType.scalp ? 'اسکالپ' : 'روزانه',
        );

      case 'marginMode':
        return _parameterRow(
          'حالت مارجین',
          _trade.marginMode == 'cross' ? 'کراس' : 'ایزوله',
        );

      case 'timeframe':
        return _parameterRow(
          'بازه زمانی',
          _trade.tradeTimeframe,
        );

      case 'status':
        return _parameterRow(
          'وضعیت معامله',
          _trade.tradeStatus == TradeStatus.open ? 'باز' : 'بسته',
        );

      case 'entryDate':
        return _parameterRow(
          'تاریخ ورود',
          _dateValue(
            _trade.entryTime,
          ),
        );

      case 'exitDate':
        if (_trade.exitTime == null) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'تاریخ خروج',
          _dateValue(
            _trade.exitTime!,
          ),
        );

      case 'margin':
        return _parameterRow(
          'مارجین',
          _formatNumber(
            _trade.marginAmount,
          ),
        );

      case 'leverage':
        return _parameterRow(
          'اهرم',
          '${_formatNumber(_trade.leverageValue)}x',
        );

      case 'volume':
        return _parameterRow(
          'حجم معامله',
          _formatNumber(
            _trade.volumeAmount,
          ),
        );

      case 'fee':
        return _parameterRow(
          'کارمزد',
          _formatNumber(
            _trade.tradeFee,
          ),
        );

      case 'entry':
        return _parameterRow(
          'قیمت ورود',
          _trade.entryPrice == null
              ? '-'
              : _formatNumber(
                  _trade.entryPrice!,
                ),
        );

      case 'currentPrice':
        return _parameterRow(
          'قیمت فعلی',
          currentPrice > 0
              ? _formatNumber(
                  currentPrice,
                )
              : '-',
        );

      case 'exit':
        return _parameterRow(
          'قیمت خروج',
          _trade.exitPrice == null
              ? '-'
              : _formatNumber(
                  _trade.exitPrice!,
                ),
        );

      case 'stop':
        return _parameterRow(
          'حد ضرر',
          _trade.stopPrice == null
              ? '-'
              : _formatNumber(
                  _trade.stopPrice!,
                ),
        );

      case 'target':
        return _parameterRow(
          'هدف',
          _trade.targetPrice == null
              ? '-'
              : _formatNumber(
                  _trade.targetPrice!,
                ),
        );

      case 'riskDistance':
        return _parameterRow(
          'فاصله تا حد ضرر',
          _formatNumber(
            _trade.riskDistance,
          ),
        );

      case 'rewardDistance':
        return _parameterRow(
          'فاصله تا هدف',
          _formatNumber(
            _trade.rewardDistance,
          ),
        );

      case 'riskValue':
        return _parameterRow(
          'مقدار ریسک',
          _formatNumber(
            riskValue,
          ),
        );

      case 'rewardValue':
        return _parameterRow(
          'مقدار سود هدف',
          _formatNumber(
            rewardValue,
          ),
        );

      case 'targetRR':
        return _parameterRow(
          'نسبت ریسک به بازده هدف',
          rr > 0 ? '1 : ${_formatNumber(rr)}' : '-',
        );

      case 'liveRR':
        return _parameterRow(
          _trade.tradeStatus == TradeStatus.closed
              ? 'نسبت ریسک به بازده نهایی'
              : 'نسبت ریسک به بازده لحظه‌ای',
          liveRiskReward > 0 ? '1 : ${_formatNumber(liveRiskReward)}' : '-',
        );

      case 'priceChange':
        return _parameterRow(
          'تغییر قیمت نسبت به ورود',
          '${_formatNumber(priceChangePercent)}%',
          valueColor: _valueColor(
            key,
            priceChangePercent,
          ),
        );

      case 'pnl':
        return _parameterRow(
          'سود و زیان',
          _formatNumber(
            _pnl,
          ),
          valueColor: _valueColor(
            key,
            _pnl,
          ),
        );

      case 'roiPercent':
        return _parameterRow(
          'بازدهی نسبت به مارجین',
          '${_formatNumber(pnlPercent)}%',
          valueColor: _valueColor(
            key,
            pnlPercent,
          ),
        );

      case 'roiDollar':
        return _parameterRow(
          'بازدهی به دلار',
          _formatNumber(
            _pnl,
          ),
          valueColor: _valueColor(
            key,
            _pnl,
          ),
        );

      case 'marginEffect':
        return _parameterRow(
          'اثر روی مارجین',
          '${_formatNumber(_pnl)} USD  |  ${_formatNumber(pnlPercent)}%',
          valueColor: _valueColor(
            key,
            _pnl,
          ),
        );

      case 'riskToStop':
        final riskPercent = _trade.marginAmount > 0
            ? (riskValue / _trade.marginAmount) * 100
            : 0.0;
        return _parameterRow(
          'ریسک تا حد ضرر',
          '${_formatNumber(riskValue)} USD  |  ${_formatNumber(riskPercent)}%',
          valueColor: riskValue > 0 ? AppColors.loss : null,
        );

      case 'maxDrawdown':
        return _parameterRow(
          'بیشترین افت سرمایه',
          '${_formatNumber(displayedDrawdown)}%',
          valueColor: _valueColor(
            key,
            displayedDrawdown,
          ),
        );

      case 'maxDrawdownDollar':
        return _parameterRow(
          'بیشترین افت سرمایه به دلار',
          _formatNumber(
            displayedDrawdownDollar,
          ),
          valueColor: _valueColor(
            key,
            displayedDrawdownDollar,
          ),
        );

      case 'drawdownMargin':
        return _parameterRow(
          'افت سرمایه نسبت به مارجین',
          '${_formatNumber(displayedDrawdownMargin)}%',
          valueColor: displayedDrawdownMargin > 0 ? AppColors.drawdown : null,
        );

      case 'finalPnl':
        if (_trade.tradeStatus != TradeStatus.closed) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'سود و زیان نهایی',
          _formatNumber(
            _trade.finalPnl,
          ),
          valueColor: _valueColor(
            key,
            _trade.finalPnl,
          ),
        );

      case 'finalRoi':
        if (_trade.tradeStatus != TradeStatus.closed) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'بازدهی نهایی',
          '${_formatNumber(_trade.finalRoiPercent)}%',
          valueColor: _valueColor(
            key,
            _trade.finalRoiPercent,
          ),
        );

      case 'finalRoiDollar':
        if (_trade.tradeStatus != TradeStatus.closed) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'بازدهی نهایی به دلار',
          _formatNumber(
            _trade.finalRoiDollar,
          ),
          valueColor: _valueColor(
            key,
            _trade.finalRoiDollar,
          ),
        );

      case 'finalRR':
        if (_trade.tradeStatus != TradeStatus.closed) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'نسبت ریسک به بازده نهایی',
          _trade.finalRiskReward > 0
              ? '1 : ${_formatNumber(_trade.finalRiskReward)}'
              : '-',
        );

      case 'duration':
        final durationSeconds = _trade.tradeStatus == TradeStatus.closed
            ? _trade.durationSeconds
            : DateTime.now().difference(_trade.entryTime).inSeconds;
        return _parameterRow(
          'مدت معامله',
          _formatDuration(durationSeconds < 0 ? 0 : durationSeconds),
        );

      case 'setup':
        if (_trade.entrySetup.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'ستاپ ورود',
          _trade.entrySetup,
        );

      case 'reason':
        if (_trade.entryReason.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'دلیل ورود',
          _trade.entryReason,
        );

      case 'motivation':
        if (_trade.entryMotivation.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'انگیزه ورود',
          _trade.entryMotivation,
        );

      case 'scenario':
        if (_trade.expectedScenario.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return _parameterRow(
          'سناریوی مورد انتظار',
          _trade.expectedScenario,
        );
    }

    return const SizedBox.shrink();
  }

  Future<void> _closeTrade() async {
    if (_trade.tradeStatus == TradeStatus.closed) {
      return;
    }

    final exitPrice = widget.livePrice;

    if (exitPrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'قیمت فعلی معتبر نیست.',
            ),
          ),
        );
      }

      return;
    }

    double closePercent = 100;
    final selectedPercent = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('بستن معامله به‌صورت کامل یا جزئی'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                'قیمت خروج: ${numbers.formatNumber(exitPrice, decimals: 4, trimTrailingZeros: false)}'),
            const SizedBox(height: 10),
            Text(
                'درصد حجم برای بستن: ${numbers.formatNumber(closePercent, decimals: 0, trimTrailingZeros: false)}٪'),
            Slider(
              value: closePercent,
              min: 0,
              max: 100,
              divisions: 100,
              label:
                  '${numbers.formatNumber(closePercent, decimals: 0, trimTrailingZeros: false)}٪',
              onChanged: (value) => setDialogState(() => closePercent = value),
            ),
            Text(
                'حجم بسته‌شونده: ${numbers.formatNumber((_trade.volumeAmount * closePercent / 100), decimals: 2, trimTrailingZeros: false)} USD'),
            Text(
                'مارجین مربوط: ${numbers.formatNumber((_trade.marginAmount * closePercent / 100), decimals: 2, trimTrailingZeros: false)} USD'),
            const SizedBox(height: 4),
            const Text(
                'بخش بسته‌شده به‌عنوان معاملهٔ بسته‌شدهٔ جداگانه در ژورنال ثبت می‌شود.'),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('لغو')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, closePercent),
                child: const Text('تأیید بستن')),
          ],
        ),
      ),
    );
    if (selectedPercent == null || selectedPercent <= 0) return;
    closePercent = selectedPercent;
    final closeRatio = closePercent / 100;
    final isPartialClose = closePercent < 99.999;
    final closedVolume = _trade.volumeAmount * closeRatio;
    final closedMargin = _trade.marginAmount * closeRatio;
    final closedTrade = _trade.copyWith(
      tradeId: isPartialClose
          ? '${_trade.tradeId}_partial_${DateTime.now().microsecondsSinceEpoch}'
          : _trade.tradeId,
      volumeAmount: closedVolume,
      marginAmount: closedMargin,
      tradeFee: _trade.tradeFee * closeRatio,
      imagePaths: isPartialClose ? const <String>[] : _trade.imagePaths,
    );

    setState(() {
      _saving = true;
    });

    try {
      final exitTime = DateTime.now();

      final finalPnl = PnlCalculator.netPnl(
        closedTrade,
        exitPrice,
      );

      final finalRoiPercent = closedTrade.marginAmount > 0
          ? (finalPnl / closedTrade.marginAmount) * 100
          : 0.0;

      final finalRoiDollar = finalPnl;

      final finalRiskReward = _calculateLiveRiskReward(
        exitPrice,
      );

      final currentDrawdownPercent = _calculateCurrentDrawdownPercent(
        exitPrice,
      );

      final maxDrawdownPercent =
          currentDrawdownPercent > _trade.maxDrawdownPricePercent
              ? currentDrawdownPercent
              : _trade.maxDrawdownPricePercent;

      final maxDrawdownDollar =
          closedTrade.volumeAmount * maxDrawdownPercent / 100;

      final maxDrawdownMarginPercent = closedTrade.marginAmount > 0
          ? (maxDrawdownDollar / closedTrade.marginAmount) * 100
          : 0.0;

      final durationSeconds = _calculateDurationSeconds(
        exitTime,
      );

      final updatedTrade = closedTrade.copyWith(
        tradeStatus: TradeStatus.closed,
        exitPrice: exitPrice,
        exitTime: exitTime,
        finalPnl: finalPnl,
        finalRoiPercent: finalRoiPercent,
        finalRoiDollar: finalRoiDollar,
        finalRiskReward: finalRiskReward,
        maxDrawdownPricePercent: maxDrawdownPercent,
        maxDrawdownDollar: maxDrawdownDollar,
        maxDrawdownMarginPercent: maxDrawdownMarginPercent,
        durationSeconds: durationSeconds,
      );

      if (isPartialClose) {
        final remainingTrade = _trade.copyWith(
          volumeAmount: (_trade.volumeAmount - closedVolume)
              .clamp(0.0, double.infinity)
              .toDouble(),
          marginAmount: (_trade.marginAmount - closedMargin)
              .clamp(0.0, double.infinity)
              .toDouble(),
          tradeFee: _trade.tradeFee * (1 - closeRatio),
        );
        await _tradeRepository.createTrade(updatedTrade);
        await _tradeRepository.updateTrade(remainingTrade);
        if (mounted)
          setState(() {
            _trade = remainingTrade;
          });
      } else {
        await _tradeRepository.updateTrade(updatedTrade);
        final updated = await _tradeRepository.getTrade(_trade.tradeId);
        if (updated != null && mounted)
          setState(() {
            _trade = updated;
          });
      }

      widget.onChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${finalPnl >= 0 ? (isPartialClose ? 'بستن جزئی انجام شد — سود: ' : 'معامله بسته شد — سود: ') : (isPartialClose ? 'بستن جزئی انجام شد — ضرر: ' : 'معامله بسته شد — ضرر: ')}${numbers.formatNumber(finalPnl.abs(), decimals: 2, trimTrailingZeros: false)}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطا در بستن معامله: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<String> _copyImagePermanently(
    String sourcePath,
    String folder,
  ) async {
    final directory = await getApplicationDocumentsDirectory();

    final targetDirectory = Directory(
      '${directory.path}/$folder',
    );

    if (!await targetDirectory.exists()) {
      await targetDirectory.create(
        recursive: true,
      );
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}_'
        '${sourcePath.split('/').last}';

    final targetPath = '${targetDirectory.path}/$fileName';

    final copied = await File(sourcePath).copy(
      targetPath,
    );

    return copied.path;
  }

  Future<void> _addTradeImage() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (image == null) {
      return;
    }

    final permanentPath = await _copyImagePermanently(
      image.path,
      'trade_images',
    );

    final paths = [
      ..._trade.imagePaths,
      permanentPath,
    ];

    final updated = _trade.copyWith(
      imagePaths: paths,
    );

    await _tradeRepository.updateTrade(
      updated,
    );

    final loaded = await _tradeRepository.getTrade(
      _trade.tradeId,
    );

    if (loaded != null && mounted) {
      setState(() {
        _trade = loaded;
      });
    }

    widget.onChanged();
  }

  Future<void> _replaceTradeImage(int index) async {
    if (index < 0 || index >= _trade.imagePaths.length) return;
    final editedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) =>
              ImageAnnotationPage(imagePath: _trade.imagePaths[index])),
    );
    if (editedPath == null) return;
    final permanentPath =
        await _copyImagePermanently(editedPath, 'trade_images');
    final paths = List<String>.from(_trade.imagePaths);
    paths[index] = permanentPath;
    final updated = _trade.copyWith(imagePaths: paths);
    await _tradeRepository.updateTrade(updated);
    final loaded = await _tradeRepository.getTrade(_trade.tradeId);
    if (loaded != null && mounted) setState(() => _trade = loaded);
    widget.onChanged();
  }

  Future<void> _exportTradeBundle() async {
    try {
      final archive = Archive();
      final mediaManifest = <Map<String, dynamic>>[];
      var index = 0;
      Future<void> addMedia(String path, String type, String name,
          {String? experienceId}) async {
        final file = File(path);
        if (!await file.exists()) return;
        final bytes = await file.readAsBytes();
        final ext = p.extension(name).isNotEmpty
            ? p.extension(name)
            : p.extension(path);
        final archivePath = 'media/${type}_${index++}$ext';
        archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
        mediaManifest.add({
          'type': type,
          'name': name,
          'archive_path': archivePath,
          if (experienceId != null) 'experience_id': experienceId
        });
      }

      for (final path in _trade.imagePaths) {
        await addMedia(path, 'trade_image', p.basename(path));
      }
      for (final experience in _experiences) {
        for (final path in experience.imagePaths) {
          await addMedia(path, 'experience_image', p.basename(path),
              experienceId: experience.experienceId);
        }
        for (final path in experience.audioPaths) {
          await addMedia(path, 'experience_audio', p.basename(path),
              experienceId: experience.experienceId);
        }
      }
      final report = docx.loadDocxDocument();
      report.addHeading(text: 'گزارش معامله', level: 1);
      report.addParagraph(text: 'دارایی: ${_trade.assetSymbol}');
      report.addParagraph(
          text:
              'جهت: ${_trade.tradeDirection == TradeDirection.long ? 'لانگ' : 'شورت'}');
      report.addParagraph(
          text:
              'وضعیت: ${_trade.tradeStatus == TradeStatus.open ? 'باز' : 'بسته'}');
      report.addParagraph(
          text:
              'نوع معامله: ${_trade.tradeType == TradeType.scalp ? 'اسکالپ' : 'روزانه'}');
      report.addParagraph(
          text:
              'حالت مارجین: ${_trade.marginMode == 'cross' ? 'کراس' : 'ایزوله'}');
      report.addParagraph(text: 'تایم‌فریم: ${_trade.tradeTimeframe}');
      report.addParagraph(text: 'قیمت ورود: ${_trade.entryPrice ?? '—'}');
      report.addParagraph(text: 'قیمت خروج: ${_trade.exitPrice ?? '—'}');
      report.addParagraph(
          text:
              'مارجین: ${numbers.formatNumber(_trade.marginAmount, decimals: 2, trimTrailingZeros: false)} USD');
      report.addParagraph(
          text:
              'حجم: ${numbers.formatNumber(_trade.volumeAmount, decimals: 2, trimTrailingZeros: false)} USD');
      report.addParagraph(text: 'اهرم: ${_trade.leverageValue}');
      report.addParagraph(text: 'حد ضرر: ${_trade.stopPrice ?? '—'}');
      report.addParagraph(text: 'حد سود: ${_trade.targetPrice ?? '—'}');
      report.addParagraph(
          text:
              'سود و زیان نهایی: ${numbers.formatNumber(_trade.finalPnl, decimals: 2, trimTrailingZeros: false)} USD');
      if (_trade.imagePaths.isNotEmpty) {
        report.addHeading(text: 'تصاویر معامله', level: 2);
        for (final path in _trade.imagePaths) {
          report.addParagraph(text: p.basename(path));
          if (await File(path).exists()) {
            try {
              report.addPicture(path, width: Inches(4));
            } catch (_) {
              report.addParagraph(text: 'تصویر اصلی در ZIP پیوست است.');
            }
          }
        }
      }
      for (final experience in _experiences) {
        if (experience.imagePaths.isNotEmpty)
          report.addHeading(
              text: 'تصاویر تجربه: ${experience.experienceTitle}', level: 3);
        for (final path in experience.imagePaths) {
          report.addParagraph(text: p.basename(path));
          if (await File(path).exists()) {
            try {
              report.addPicture(path, width: Inches(4));
            } catch (_) {
              report.addParagraph(text: 'تصویر اصلی در ZIP پیوست است.');
            }
          }
        }
        for (final path in experience.audioPaths) {
          report.addParagraph(
              text: 'ویس: ${p.basename(path)} (فایل اصلی همراه ZIP است)');
        }
      }
      if (mediaManifest.isNotEmpty) {
        report.addHeading(text: 'رسانه‌های پیوست در بسته ZIP', level: 2);
        for (final media in mediaManifest
            .where((m) => m['type'].toString().contains('audio'))) {
          report.addParagraph(text: 'ویس: ${media['name']}');
        }
      }
      final temp = await getTemporaryDirectory();
      final docPath = p.join(
          temp.path, 'trade_${DateTime.now().microsecondsSinceEpoch}.docx');
      report.save(docPath);
      final docBytes = await File(docPath).readAsBytes();
      await File(docPath).delete();
      archive.addFile(ArchiveFile('trade.docx', docBytes.length, docBytes));
      final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'format': 'lbank_trade_bundle',
        'version': 1,
        'trade': _trade.toMap(),
        'media': mediaManifest,
        'custom_values': _customFieldValues
            .map((key, value) => MapEntry(key.toString(), value)),
        'pre_trade_values': _preTradeValues
            .map((key, value) => MapEntry(key.toString(), value)),
        'experiences': _experiences
            .map((e) => {
                  'experience_id': e.experienceId,
                  'title': e.experienceTitle,
                  'description': e.experienceDescription,
                  'created_at': e.experienceCreatedAt.toIso8601String()
                })
            .toList()
      }));
      archive.addFile(ArchiveFile('trade.json', jsonBytes.length, jsonBytes));
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw Exception('ساخت بسته ناموفق بود.');
      await FilePicker.platform.saveFile(
          dialogTitle: 'ذخیره گزارش معامله همراه رسانه‌ها',
          fileName: 'trade_${_trade.assetSymbol}_${_trade.tradeId}.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
          bytes: Uint8List.fromList(encoded));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خروجی معامله ناموفق بود: $e')));
    }
  }

  Future<void> _editTrade() async {
    final result = await showDialog<_TradeEditResult>(
      context: context,
      builder: (context) {
        return _EditTradeDialog(
          trade: _trade,
          customFields: _customFields,
          customValues: _customFieldValues,
          preTradeItems: _preTradeItems,
          preTradeValues: _preTradeValues,
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _tradeRepository.updateTrade(result.trade);
      await _customFieldRepository.saveTradeValues(
          result.trade.tradeId, result.customValues);
      await _preTradeRepository.saveTradeValues(
          result.trade.tradeId, result.preTradeValues);

      final updated = await _tradeRepository.getTrade(result.trade.tradeId);
      final customValues =
          await _customFieldRepository.getTradeValues(result.trade.tradeId);
      final preTradeValues =
          await _preTradeRepository.getTradeValues(result.trade.tradeId);

      if (updated != null && mounted) {
        setState(() {
          _trade = updated;
          _customFieldValues = customValues;
          _preTradeValues = preTradeValues;
        });
      }

      widget.onChanged();
      if (mounted) _message('همه تغییرات معامله با موفقیت ذخیره شد.');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطا در ویرایش معامله: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _editExperience(Experience experience) async {
    final edited = await showDialog<Experience>(
      context: context,
      builder: (_) => _EditExperienceDialog(experience: experience),
    );
    if (edited == null) return;
    try {
      await _experienceRepository.updateExperience(edited);
      await _loadExperiences();
      widget.onChanged();
      _message('تجربه با موفقیت ویرایش شد.');
    } catch (error) {
      _message('خطا در ویرایش تجربه: $error');
    }
  }

  Future<void> _newExperience() async {
    final result = await showDialog<Experience>(
      context: context,
      builder: (context) {
        return _NewExperienceDialog(
          tradeId: _trade.tradeId,
          copyImage: _copyImagePermanently,
        );
      },
    );

    if (result == null) {
      return;
    }

    try {
      await _experienceRepository.createExperience(
        result,
      );

      final experiences = await _experienceRepository.getExperiencesForTrade(
        _trade.tradeId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _experiences = experiences;
        _loadingExperiences = false;
      });

      widget.onChanged();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تجربه با موفقیت ثبت شد.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطا در ثبت تجربه: $error',
          ),
        ),
      );
    }
  }

  Future<void> _showExperiences() async {
    await _loadExperiences();

    if (!mounted) {
      return;
    }

    final experiences = List<Experience>.from(
      _experiences,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .75,
            maxChildSize: .95,
            minChildSize: .4,
            builder: (
              context,
              scrollController,
            ) {
              if (experiences.isEmpty) {
                return const Center(
                  child: Text(
                    'هنوز تجربه‌ای ثبت نشده است.',
                  ),
                );
              }

              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(
                  16,
                ),
                itemCount: experiences.length,
                itemBuilder: (
                  context,
                  index,
                ) {
                  final experience = experiences[index];

                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 16,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: ExpansionTile(
                        key: PageStorageKey(
                          'bottom_experience_${experience.experienceId}',
                        ),
                        initiallyExpanded: false,
                        maintainState: true,
                        leading: const Icon(
                          Icons.lightbulb_outline,
                        ),
                        title: Text(
                          experience.experienceTitle,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          if (experience.experienceDescription
                              .trim()
                              .isNotEmpty)
                            Align(
                              alignment: Alignment.centerRight,
                              child: _buildExperienceDescription(experience),
                            ),
                          if (experience.imagePaths.isNotEmpty &&
                              !_experienceHasInlineMedia(experience)) ...[
                            const SizedBox(
                              height: 12,
                            ),
                            ...experience.imagePaths.map(
                              (
                                path,
                              ) =>
                                  Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 8,
                                ),
                                child: Image.file(
                                  File(path),
                                  width: double.infinity,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final pnlPercent =
        _trade.marginAmount > 0 ? (_pnl / _trade.marginAmount) * 100 : 0.0;

    final rr = PnlCalculator.calculatedRiskReward(
      _trade,
    );

    final riskValue = PnlCalculator.riskValue(
      _trade,
    );

    final rewardValue = PnlCalculator.rewardValue(
      _trade,
    );

    final currentPrice = _currentPrice;

    final priceChangePercent = _calculatePriceChangePercent(
      currentPrice,
    );

    final liveRiskReward = _calculateLiveRiskReward(
      currentPrice,
    );

    final currentDrawdownPercent = _calculateCurrentDrawdownPercent(
      currentPrice,
    );

    final displayedDrawdown =
        currentDrawdownPercent > _trade.maxDrawdownPricePercent
            ? currentDrawdownPercent
            : _trade.maxDrawdownPricePercent;

    final displayedDrawdownDollar =
        _trade.volumeAmount * displayedDrawdown / 100;

    final displayedDrawdownMargin = _trade.marginAmount > 0
        ? (displayedDrawdownDollar / _trade.marginAmount) * 100
        : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _trade.assetSymbol,
            textDirection: TextDirection.ltr,
          ),
          actions: [
            IconButton(
              tooltip: 'خروجی ZIP همراه رسانه‌ها',
              onPressed: _saving ? null : _exportTradeBundle,
              icon: const Icon(Icons.folder_zip_outlined),
            ),
            IconButton(
              tooltip: 'بازگردانی ترتیب',
              onPressed: _loadingParameterOrder ? null : _resetParameterOrder,
              icon: const Icon(
                Icons.restart_alt,
              ),
            ),
            IconButton(
              onPressed: _saving ? null : _editTrade,
              icon: const Icon(
                Icons.edit,
              ),
              tooltip: 'ویرایش معامله',
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'جزئیات معامله',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.drag_indicator,
                    size: 20,
                  ),
                  const SizedBox(
                    width: 4,
                  ),
                  Text(
                    'برای جابه‌جایی بکشید',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.dragHelper,
                    ),
                  ),
                ],
              ),
            ),
            _buildTopEntryActions(),
            Expanded(
              child: _loadingParameterOrder
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        20,
                      ),
                      itemCount: _parameterOrder.length,
                      footer: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TradePriceChartSection(
                            symbol: _trade.assetSymbol,
                            entryPrice: _trade.entryPrice ?? 0,
                            entryTime: _trade.entryTime,
                          ),
                          _buildPreTradeSection(),
                          _buildCustomFieldsSection(),
                          _buildMistakesSection(),
                          _buildExperiencesSection(),
                          _buildTradeNotesSection(),
                          _buildTradeImagesSection(),
                        ],
                      ),
                      onReorder: (
                        oldIndex,
                        newIndex,
                      ) async {
                        if (newIndex > oldIndex) {
                          newIndex--;
                        }

                        final item = _parameterOrder.removeAt(
                          oldIndex,
                        );

                        _parameterOrder.insert(
                          newIndex,
                          item,
                        );

                        setState(() {});

                        await _saveParameterOrder();
                      },
                      itemBuilder: (
                        context,
                        index,
                      ) {
                        final key = _parameterOrder[index];

                        return Container(
                          key: ValueKey(
                            key,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.parameterDivider,
                              ),
                            ),
                          ),
                          child: _buildParameter(
                            key,
                            currentPrice: currentPrice,
                            pnlPercent: pnlPercent,
                            rr: rr,
                            riskValue: riskValue,
                            rewardValue: rewardValue,
                            priceChangePercent: priceChangePercent,
                            liveRiskReward: liveRiskReward,
                            displayedDrawdown: displayedDrawdown,
                            displayedDrawdownDollar: displayedDrawdownDollar,
                            displayedDrawdownMargin: displayedDrawdownMargin,
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      height: 8,
                    ),
                    if (_trade.tradeStatus == TradeStatus.open) ...[
                      const SizedBox(
                        height: 8,
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _closeTrade,
                        icon: const Icon(
                          Icons.check_circle,
                        ),
                        label: const Text(
                          'بستن معامله',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _entryTitleController.dispose();
    _entryContentController.dispose();
    super.dispose();
  }
}

class _TradeEditResult {
  final Trade trade;
  final Map<int, String> customValues;
  final Map<int, String> preTradeValues;
  const _TradeEditResult(this.trade, this.customValues, this.preTradeValues);
}

class _EditTradeDialog extends StatefulWidget {
  final Trade trade;
  final List<CustomField> customFields;
  final Map<int, String> customValues;
  final List<Map<String, dynamic>> preTradeItems;
  final Map<int, String> preTradeValues;

  const _EditTradeDialog({
    required this.trade,
    required this.customFields,
    required this.customValues,
    required this.preTradeItems,
    required this.preTradeValues,
  });

  @override
  State<_EditTradeDialog> createState() => _EditTradeDialogState();
}

class _EditTradeDialogState extends State<_EditTradeDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<int, TextEditingController> _customControllers = {};
  final Map<int, TextEditingController> _preTradeControllers = {};
  late TradeDirection _direction;
  late TradeType _type;
  late TradeStatus _status;
  String _marginMode = 'isolated';

  static const _numericFields = <String, String>{
    'marginAmount': 'مارجین',
    'leverageValue': 'اهرم',
    'volumeAmount': 'حجم معامله',
    'feePerHundred': 'کارمزد به‌ازای هر ۱۰۰',
    'tradeFee': 'کارمزد معامله',
    'entryPrice': 'قیمت ورود',
    'exitPrice': 'قیمت خروج / بسته‌شدن',
    'stopPrice': 'حد ضرر',
    'targetPrice': 'حد سود',
    'riskDistance': 'فاصله ریسک',
    'rewardDistance': 'فاصله سود',
    'riskValue': 'مقدار ریسک',
    'rewardValue': 'مقدار سود هدف',
    'tradeRiskReward': 'نسبت ریسک به ریوارد',
    'finalPnl': 'سود و زیان نهایی',
    'finalRoiPercent': 'بازده نهایی درصد',
    'finalRoiDollar': 'بازده نهایی دلاری',
    'finalRiskReward': 'نسبت ریسک به ریوارد نهایی',
    'maxDrawdownPricePercent': 'بیشترین افت قیمت درصد',
    'maxDrawdownDollar': 'بیشترین افت دلاری',
    'maxDrawdownMarginPercent': 'افت نسبت به مارجین درصد',
  };

  static const _textFields = <String, String>{
    'assetSymbol': 'نماد',
    'tradeTimeframe': 'تایم‌فریم',
    'entrySetup': 'ستاپ ورود',
    'entryReason': 'دلیل ورود',
    'entryMotivation': 'انگیزه ورود',
    'expectedScenario': 'سناریوی مورد انتظار',
  };

  @override
  void initState() {
    super.initState();
    final t = widget.trade;
    _direction = t.tradeDirection;
    _type = t.tradeType;
    _status = t.tradeStatus;
    _marginMode = t.marginMode;
    final values = <String, Object?>{
      ..._textFields.keys
          .fold<Map<String, Object?>>({}, (m, k) => m..[k] = _readText(t, k)),
      'marginAmount': t.marginAmount,
      'leverageValue': t.leverageValue,
      'volumeAmount': t.volumeAmount,
      'feePerHundred': t.feePerHundred,
      'tradeFee': t.tradeFee,
      'entryPrice': t.entryPrice,
      'exitPrice': t.exitPrice,
      'stopPrice': t.stopPrice,
      'targetPrice': t.targetPrice,
      'riskDistance': t.riskDistance,
      'rewardDistance': t.rewardDistance,
      'riskValue': t.riskValue,
      'rewardValue': t.rewardValue,
      'tradeRiskReward': t.tradeRiskReward,
      'finalPnl': t.finalPnl,
      'finalRoiPercent': t.finalRoiPercent,
      'finalRoiDollar': t.finalRoiDollar,
      'finalRiskReward': t.finalRiskReward,
      'maxDrawdownPricePercent': t.maxDrawdownPricePercent,
      'maxDrawdownDollar': t.maxDrawdownDollar,
      'maxDrawdownMarginPercent': t.maxDrawdownMarginPercent,
      'durationSeconds': t.durationSeconds,
      'entryTime': t.entryTime.toIso8601String(),
      'exitTime': t.exitTime?.toIso8601String() ?? '',
    };
    for (final e in values.entries) {
      _controllers[e.key] =
          TextEditingController(text: e.value?.toString() ?? '');
    }
    for (final f in widget.customFields) {
      if (f.fieldId != null) {
        _customControllers[f.fieldId!] =
            TextEditingController(text: widget.customValues[f.fieldId!] ?? '');
      }
    }
    for (final item in widget.preTradeItems) {
      final id = int.tryParse(item['item_id']?.toString() ?? '');
      if (id != null) {
        _preTradeControllers[id] =
            TextEditingController(text: widget.preTradeValues[id] ?? '');
      }
    }
  }

  String _readText(Trade t, String key) {
    switch (key) {
      case 'assetSymbol':
        return t.assetSymbol;
      case 'tradeTimeframe':
        return t.tradeTimeframe;
      case 'entrySetup':
        return t.entrySetup;
      case 'entryReason':
        return t.entryReason;
      case 'entryMotivation':
        return t.entryMotivation;
      default:
        return t.expectedScenario;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _customControllers.values) {
      c.dispose();
    }
    for (final c in _preTradeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(String key) => _controllers[key]?.text.trim() ?? '';
  double _d(String key, double fallback) {
    final raw = numbers.normalizeNumberInput(_v(key)).replaceAll(',', '');
    return raw.isEmpty ? fallback : (double.tryParse(raw) ?? fallback);
  }

  double? _nullableDouble(String key, double? fallback) {
    final raw = numbers.normalizeNumberInput(_v(key)).replaceAll(',', '');
    return raw.isEmpty ? null : double.tryParse(raw);
  }

  DateTime? _date(String key, DateTime? fallback) {
    final raw = _v(key);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw) ?? fallback;
  }

  Widget _field(String key, String label,
          {bool numeric = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _controllers[key],
          minLines: lines,
          maxLines: lines,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true, signed: true)
              : TextInputType.text,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.trade;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ویرایش کامل معامله'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('مشخصات معامله',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _field('assetSymbol', 'نماد'),
                  DropdownButtonFormField<TradeDirection>(
                      value: _direction,
                      decoration:
                          const InputDecoration(labelText: 'جهت معامله'),
                      items: const [
                        DropdownMenuItem(
                            value: TradeDirection.long,
                            child: Text('Long / خرید')),
                        DropdownMenuItem(
                            value: TradeDirection.short,
                            child: Text('Short / فروش')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _direction = v);
                      }),
                  DropdownButtonFormField<TradeType>(
                      value: _type,
                      decoration:
                          const InputDecoration(labelText: 'نوع معامله'),
                      items: const [
                        DropdownMenuItem(
                            value: TradeType.scalp, child: Text('اسکالپ')),
                        DropdownMenuItem(
                            value: TradeType.day, child: Text('روزانه')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _type = v);
                      }),
                  DropdownButtonFormField<TradeStatus>(
                      value: _status,
                      decoration:
                          const InputDecoration(labelText: 'وضعیت معامله'),
                      items: const [
                        DropdownMenuItem(
                            value: TradeStatus.open, child: Text('باز')),
                        DropdownMenuItem(
                            value: TradeStatus.closed, child: Text('بسته')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _status = v);
                      }),
                  _field('tradeTimeframe', 'تایم‌فریم'),
                  DropdownButtonFormField<String>(
                      value: _marginMode,
                      decoration:
                          const InputDecoration(labelText: 'حالت مارجین'),
                      items: const [
                        DropdownMenuItem(
                            value: 'isolated', child: Text('ایزوله')),
                        DropdownMenuItem(value: 'cross', child: Text('کراس')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _marginMode = v);
                      }),
                  const SizedBox(height: 14),
                  const Text('قیمت‌ها و مدیریت سرمایه',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._numericFields.entries
                      .where((e) => [
                            'marginAmount',
                            'leverageValue',
                            'volumeAmount',
                            'feePerHundred',
                            'tradeFee',
                            'entryPrice',
                            'exitPrice',
                            'stopPrice',
                            'targetPrice'
                          ].contains(e.key))
                      .map((e) => _field(e.key, e.value, numeric: true)),
                  const Text('محاسبات و نتایج معامله',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._numericFields.entries
                      .where((e) => ![
                            'marginAmount',
                            'leverageValue',
                            'volumeAmount',
                            'feePerHundred',
                            'tradeFee',
                            'entryPrice',
                            'exitPrice',
                            'stopPrice',
                            'targetPrice'
                          ].contains(e.key))
                      .map((e) => _field(e.key, e.value, numeric: true)),
                  _field('durationSeconds', 'مدت معامله (ثانیه)',
                      numeric: true),
                  const SizedBox(height: 14),
                  const Text('زمان‌بندی (قالب ISO-8601)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _field('entryTime', 'زمان ورود / بازشدن'),
                  _field('exitTime', 'زمان خروج / بسته‌شدن (خالی = بدون زمان)'),
                  const SizedBox(height: 14),
                  const Text('اطلاعات و تحلیل ورود',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _field('entrySetup', 'ستاپ ورود', lines: 2),
                  _field('entryReason', 'دلیل ورود', lines: 2),
                  _field('entryMotivation', 'انگیزه ورود', lines: 2),
                  _field('expectedScenario', 'سناریوی مورد انتظار', lines: 3),
                  if (widget.customFields.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text('فیلدهای سفارشی',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ...widget.customFields
                        .where((f) => f.fieldId != null)
                        .map((f) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextField(
                                  controller: _customControllers[f.fieldId],
                                  decoration: InputDecoration(
                                      labelText: f.fieldName,
                                      border: const OutlineInputBorder(),
                                      isDense: true)),
                            )),
                  ],
                  if (widget.preTradeItems.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text('چک‌لیست و پاسخ‌های قبل از معامله',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ...widget.preTradeItems.map((item) {
                      final id =
                          int.tryParse(item['item_id']?.toString() ?? '');
                      if (id == null || !_preTradeControllers.containsKey(id))
                        return const SizedBox.shrink();
                      final title =
                          item['item_title']?.toString() ?? 'مورد چک‌لیست';
                      final type = item['item_type']?.toString() ?? '';
                      final mode = item['display_mode']?.toString() ?? 'box';
                      final legacyMode = mode != 'box' && mode != 'choice';
                      if (mode == 'box' || (legacyMode && type == 'question')) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: _preTradeControllers[id],
                            decoration: InputDecoration(
                                labelText: title,
                                border: const OutlineInputBorder(),
                                isDense: true),
                            minLines: 2,
                            maxLines: 4,
                          ),
                        );
                      }
                      if (type == 'question') {
                        return DropdownButtonFormField<String>(
                          value: const ['yes', 'no', '']
                                  .contains(_preTradeControllers[id]!.text)
                              ? _preTradeControllers[id]!.text
                              : '',
                          decoration: InputDecoration(labelText: title),
                          items: const [
                            DropdownMenuItem(
                                value: '', child: Text('پاسخ ثبت‌نشده')),
                            DropdownMenuItem(value: 'yes', child: Text('بله')),
                            DropdownMenuItem(value: 'no', child: Text('خیر')),
                          ],
                          onChanged: (v) => setState(
                              () => _preTradeControllers[id]!.text = v ?? ''),
                        );
                      }
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(title),
                        value: _preTradeControllers[id]!.text == 'yes',
                        onChanged: (checked) => setState(() =>
                            _preTradeControllers[id]!.text =
                                checked == true ? 'yes' : ''),
                      );
                    }),
                  ],
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () {
                for (final key in [
                  'entryPrice',
                  'exitPrice',
                  'stopPrice',
                  'targetPrice'
                ]) {
                  final raw =
                      numbers.normalizeNumberInput(_v(key)).replaceAll(',', '');
                  if (raw.isNotEmpty && double.tryParse(raw) == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('مقدار واردشده برای $key معتبر نیست.')),
                    );
                    return;
                  }
                }
                final entryTime = _date('entryTime', t.entryTime);
                final exitTime = _date('exitTime', t.exitTime);
                if (entryTime == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('زمان ورود معتبر نیست.')));
                  return;
                }
                final updated = t.copyWith(
                  assetSymbol: _v('assetSymbol'),
                  tradeDirection: _direction,
                  tradeType: _type,
                  tradeStatus: _status,
                  tradeTimeframe: _v('tradeTimeframe'),
                  marginMode: _marginMode,
                  marginAmount: _d('marginAmount', t.marginAmount),
                  leverageValue: _d('leverageValue', t.leverageValue),
                  volumeAmount: _d('volumeAmount', t.volumeAmount),
                  feePerHundred: _d('feePerHundred', t.feePerHundred),
                  tradeFee: _d('tradeFee', t.tradeFee),
                  entryPrice: _nullableDouble('entryPrice', t.entryPrice),
                  exitPrice: _nullableDouble('exitPrice', t.exitPrice),
                  stopPrice: _nullableDouble('stopPrice', t.stopPrice),
                  targetPrice: _nullableDouble('targetPrice', t.targetPrice),
                  riskDistance: _d('riskDistance', t.riskDistance),
                  rewardDistance: _d('rewardDistance', t.rewardDistance),
                  riskValue: _d('riskValue', t.riskValue),
                  rewardValue: _d('rewardValue', t.rewardValue),
                  tradeRiskReward: _d('tradeRiskReward', t.tradeRiskReward),
                  finalPnl: _d('finalPnl', t.finalPnl),
                  finalRoiPercent: _d('finalRoiPercent', t.finalRoiPercent),
                  finalRoiDollar: _d('finalRoiDollar', t.finalRoiDollar),
                  finalRiskReward: _d('finalRiskReward', t.finalRiskReward),
                  maxDrawdownPricePercent:
                      _d('maxDrawdownPricePercent', t.maxDrawdownPricePercent),
                  maxDrawdownDollar:
                      _d('maxDrawdownDollar', t.maxDrawdownDollar),
                  maxDrawdownMarginPercent: _d(
                      'maxDrawdownMarginPercent', t.maxDrawdownMarginPercent),
                  durationSeconds:
                      int.tryParse(_v('durationSeconds')) ?? t.durationSeconds,
                  entrySetup: _v('entrySetup'),
                  entryReason: _v('entryReason'),
                  entryMotivation: _v('entryMotivation'),
                  expectedScenario: _v('expectedScenario'),
                  entryTime: entryTime,
                  exitTime: exitTime,
                );
                final custom = <int, String>{
                  for (final e in _customControllers.entries)
                    e.key: e.value.text
                };
                final preTrade = <int, String>{
                  for (final e in _preTradeControllers.entries)
                    e.key: e.value.text
                };
                Navigator.pop(
                    context, _TradeEditResult(updated, custom, preTrade));
              },
              child: const Text('ذخیره همه تغییرات')),
        ],
      ),
    );
  }
}

class _EditExperienceDialog extends StatefulWidget {
  final Experience experience;
  const _EditExperienceDialog({required this.experience});
  @override
  State<_EditExperienceDialog> createState() => _EditExperienceDialogState();
}

class _EditExperienceDialogState extends State<_EditExperienceDialog> {
  late final TextEditingController _title;
  late final _ExperienceInlineController _description;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.experience.experienceTitle);
    _description = _ExperienceInlineController();
    _description.text = widget.experience.experienceDescription;
    _description.imagePaths = List<String>.from(widget.experience.imagePaths);
    _description.audioPaths = List<String>.from(widget.experience.audioPaths);
    _description.onImageTap = (path) => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
              child: InteractiveViewer(
                  child: Image.file(File(path), fit: BoxFit.contain))),
        );
    _description.onAudioTap = (path) async {
      try {
        await _player.play(DeviceFileSource(path));
      } catch (_) {}
    };
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ویرایش تجربه معامله'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: _title,
                    decoration:
                        const InputDecoration(labelText: 'عنوان تجربه')),
                const SizedBox(height: 10),
                TextField(
                    controller: _description,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                        labelText: 'توضیحات و تجربه',
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                const Text(
                    'تصاویر و ویس‌های درون متن حفظ می‌شوند؛ برای مشاهده روی آن‌ها بزنید.'),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    Experience(
                      experienceId: widget.experience.experienceId,
                      tradeId: widget.experience.tradeId,
                      experienceTitle: _title.text.trim(),
                      experienceDescription: _description.text,
                      imagePaths: widget.experience.imagePaths,
                      audioPaths: widget.experience.audioPaths,
                      experienceCreatedAt:
                          widget.experience.experienceCreatedAt,
                    )),
                child: const Text('ذخیره')),
          ],
        ),
      );
}

class _NewExperienceDialog extends StatefulWidget {
  final String tradeId;

  final Future<String> Function(
    String sourcePath,
    String folder,
  ) copyImage;

  const _NewExperienceDialog({
    required this.tradeId,
    required this.copyImage,
  });

  @override
  State<_NewExperienceDialog> createState() => _NewExperienceDialogState();
}

class _NewExperienceDialogState extends State<_NewExperienceDialog> {
  final _titleController = TextEditingController();

  final _ExperienceInlineController _descriptionController =
      _ExperienceInlineController();

  final List<String> _imagePaths = [];
  final List<String> _audioPaths = [];
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _experienceAudioPlayer = AudioPlayer();
  bool _isRecordingVoice = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.onImageTap = _editExperienceImage;
    _descriptionController.onAudioTap = _playExperienceAudio;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    _experienceAudioPlayer.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final selection = _descriptionController.selection;
    final images = await ImagePicker().pickMultiImage(imageQuality: 95);
    if (images.isEmpty || !mounted) return;
    var offset = (selection.isValid
            ? selection.baseOffset
            : _descriptionController.text.length)
        .clamp(0, _descriptionController.text.length)
        .toInt();
    for (final image in images) {
      final annotated = await Navigator.of(context).push<String>(
          MaterialPageRoute(
              builder: (_) => ImageAnnotationPage(imagePath: image.path)));
      if (!mounted) return;
      final saved =
          await widget.copyImage(annotated ?? image.path, 'experience_images');
      final index = _descriptionController.imagePaths.length;
      _imagePaths.add(saved);
      _descriptionController.imagePaths.add(saved);
      final marker = String.fromCharCode(0xE000 + index);
      final old = _descriptionController.text;
      final newText =
          '${old.substring(0, offset)}$marker ${old.substring(offset)}';
      _descriptionController.value = TextEditingValue(
          text: newText,
          selection:
              TextSelection.collapsed(offset: offset + marker.length + 1));
      offset += marker.length + 1;
    }
    _descriptionController.selection = TextSelection.collapsed(offset: offset);
    if (mounted) setState(() {});
  }

  Future<void> _editExperienceImage(String path) async {
    final edited = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => ImageAnnotationPage(imagePath: path)));
    if (edited == null || !mounted) return;
    final saved = await widget.copyImage(edited, 'experience_images');
    final index = _descriptionController.imagePaths.indexOf(path);
    if (index >= 0) _descriptionController.imagePaths[index] = saved;
    final pendingIndex = _imagePaths.indexOf(path);
    if (pendingIndex >= 0) _imagePaths[pendingIndex] = saved;
    final oldText = _descriptionController.text;
    final markerIndex = oldText.runes.toList().indexOf(0xE000 + index);
    if (index >= 0 && markerIndex >= 0) {
      final runes = oldText.runes.toList();
      runes[markerIndex] = 0xE000 + index;
      _descriptionController.value = TextEditingValue(
          text: String.fromCharCodes(runes),
          selection: _descriptionController.selection);
    }
    setState(() {});
  }

  Future<void> _playExperienceAudio(String path) async {
    try {
      await _experienceAudioPlayer.play(DeviceFileSource(path));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('پخش ویس ممکن نشد.')));
    }
  }

  void _insertAudioMarker(String path) {
    final selection = _descriptionController.selection;
    final offset = (selection.isValid
            ? selection.baseOffset
            : _descriptionController.text.length)
        .clamp(0, _descriptionController.text.length)
        .toInt();
    final index = _descriptionController.audioPaths.length;
    _descriptionController.audioPaths.add(path);
    final marker = String.fromCharCode(0xF000 + index);
    final old = _descriptionController.text;
    final newText =
        '${old.substring(0, offset)}$marker ${old.substring(offset)}';
    _descriptionController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset + marker.length + 1));
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', '3gp'],
    );
    final source = result?.files.single.path;
    if (source == null) return;
    final saved = await widget.copyImage(source, 'experience_audio');
    _audioPaths.add(saved);
    _insertAudioMarker(saved);
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoiceRecording() async {
    try {
      if (_isRecordingVoice) {
        final path = await _voiceRecorder.stop();
        if (path != null) {
          final saved = await widget.copyImage(path, 'experience_audio');
          _audioPaths.add(saved);
          _insertAudioMarker(saved);
        }
        if (mounted) setState(() => _isRecordingVoice = false);
        return;
      }
      if (!await _voiceRecorder.hasPermission()) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('مجوز ضبط صدا داده نشده است.')));
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = p.join(directory.path,
          'experience_voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
      await _voiceRecorder
          .start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (mounted) setState(() => _isRecordingVoice = true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ضبط ویس شروع نشد: $e')));
    }
  }

  void _save() {
    if (_titleController.text.trim().isEmpty) {
      return;
    }

    final experience = Experience(
      experienceId: DateTime.now().microsecondsSinceEpoch.toString(),
      tradeId: widget.tradeId,
      experienceTitle: _titleController.text.trim(),
      experienceDescription: _descriptionController.text.trim(),
      imagePaths: List.unmodifiable(
        _imagePaths,
      ),
      audioPaths: List.unmodifiable(_audioPaths),
      experienceCreatedAt: DateTime.now(),
    );

    Navigator.pop(
      context,
      experience,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text(
          'تجربه جدید',
        ),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'موضوع تجربه',
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              TextField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'توضیحات',
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(
                  Icons.image,
                ),
                label: const Text(
                  'افزودن عکس',
                ),
              ),
              if (_imagePaths.isNotEmpty)
                Text(
                  '${numbers.formatInteger(_imagePaths.length)} عکس انتخاب شده',
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: _pickAudio,
                    icon: const Icon(Icons.audio_file),
                    label: const Text('انتخاب فایل صوتی')),
                FilledButton.tonalIcon(
                    onPressed: _toggleVoiceRecording,
                    icon: Icon(_isRecordingVoice ? Icons.stop : Icons.mic),
                    label:
                        Text(_isRecordingVoice ? 'توقف ضبط ویس' : 'ضبط ویس')),
              ]),
              if (_audioPaths.isNotEmpty)
                Text(
                    '${numbers.formatInteger(_audioPaths.length)} فایل صوتی انتخاب شده'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.pop(
                      context,
                    ),
            child: const Text(
              'لغو',
            ),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text(
              'ذخیره',
            ),
          ),
        ],
      ),
    );
  }
}
