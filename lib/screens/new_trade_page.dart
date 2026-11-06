import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notes_appearance_settings.dart';
import 'notes_appearance_settings_page.dart';

/// A note is an ordered sequence of text, image and audio blocks.
class NoteBlock {
  final String type;
  final String value;
  const NoteBlock(this.type, this.value);
  Map<String, dynamic> toJson() => {'type': type, 'value': value};
  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
        (json['type'] ?? 'text').toString(),
        (json['value'] ?? '').toString(),
      );
}

class NoteFolder {
  final String id;
  final String name;
  final String? parentId;
  const NoteFolder({required this.id, required this.name, this.parentId});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'parentId': parentId};
  factory NoteFolder.fromJson(Map<String, dynamic> json) => NoteFolder(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        parentId: json['parentId']?.toString(),
      );
}

class NoteItem {
  final String id;
  final String title;
  final List<NoteBlock> blocks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? folderId;
  const NoteItem(
      {required this.id,
      required this.title,
      required this.blocks,
      required this.createdAt,
      required this.updatedAt,
      this.folderId});
  String get searchableText =>
      blocks.where((b) => b.type == 'text').map((b) => b.value).join(' ');
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'folderId': folderId,
      };
  factory NoteItem.fromJson(Map<String, dynamic> j) {
    List<NoteBlock> blocks;
    if (j['blocks'] is List) {
      blocks = (j['blocks'] as List)
          .map((e) => NoteBlock.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      // Migrate notes created by the previous editor without losing their content.
      blocks = [NoteBlock('text', (j['content'] ?? '').toString())];
      for (final image in (j['images'] as List? ?? [])) {
        blocks.add(NoteBlock('image', image.toString()));
      }
      for (final audio in (j['audioPaths'] as List? ?? [])) {
        blocks.add(NoteBlock('audio', audio.toString()));
      }
    }
    if (blocks.isEmpty) blocks = [const NoteBlock('text', '')];
    return NoteItem(
      id: (j['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
      title: (j['title'] ?? '').toString(),
      blocks: blocks,
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((j['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
      folderId: j['folderId']?.toString(),
    );
  }
}

class TradeNotesPage extends StatefulWidget {
  const TradeNotesPage({super.key});
  @override
  State<TradeNotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<TradeNotesPage> {
  static const _key = 'notes_v1';
  static const _foldersKey = 'notes_folders_v1';
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final ScrollController _editorScrollController = ScrollController();
  final List<GlobalKey> _draftBlockKeys = [];
  final List<NoteBlock> _draft = [];
  final List<TextEditingController> _textControllers = [];
  final List<FocusNode> _focusNodes = [];
  List<NoteItem> _notes = [];
  List<NoteFolder> _folders = [];
  String? _currentFolderId;
  String? _editingFolderId;
  bool _loading = true, _editing = false, _recording = false, _saving = false;
  String? _editingId;
  DateTime? _created;
  int _activeText = 0;
  String? _playing;

  @override
  void initState() {
    super.initState();
    NotesAppearanceSettings.load();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    _recorder.dispose();
    _player.dispose();
    _editorScrollController.dispose();
    _disposeTextFields();
    super.dispose();
  }

  void _disposeTextFields() {
    for (final c in _textControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _textControllers.clear();
    _focusNodes.clear();
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(99999)}';
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'cheek_list_notes'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        _notes = (jsonDecode(raw) as List)
            .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      final foldersRaw = prefs.getString(_foldersKey);
      if (foldersRaw != null) {
        _folders = (jsonDecode(foldersRaw) as List)
            .map(
                (e) => NoteFolder.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      _message('خواندن یادداشت‌ها ناموفق بود: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
        _key, jsonEncode(_notes.map((n) => n.toJson()).toList()));
    if (!ok) throw Exception('ذخیره‌سازی انجام نشد');
    final foldersOk = await prefs.setString(
        _foldersKey, jsonEncode(_folders.map((f) => f.toJson()).toList()));
    if (!foldersOk) throw Exception('ذخیره پوشه‌ها انجام نشد');
  }

  NoteFolder? _folderById(String? id) {
    if (id == null) return null;
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  List<NoteFolder> _childrenOf(String? parentId) =>
      _folders.where((f) => f.parentId == parentId).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  String _folderPath(String? folderId) {
    if (folderId == null) return 'یادداشت‌های من';
    final parts = <String>[];
    String? id = folderId; // Keep nullable: parentId may be null at the root.
    var guard = 0;
    while (id != null && guard++ < 50) {
      final folder = _folderById(id);
      if (folder == null) break;
      parts.insert(0, folder.name);
      id = folder.parentId;
    }
    return parts.join(' / ');
  }

  Future<void> _exportAllNotesZip() async {
    try {
      final archive = Archive();
      final all = <Map<String, dynamic>>[];
      var i = 0;
      for (final n in _notes) {
        final data = n.toJson();
        final blocks = <Map<String, dynamic>>[];
        for (final b in n.blocks) {
          var value = b.value;
          if ((b.type == 'image' || b.type == 'audio') && await File(value).exists()) {
            final name = 'media/${i++}${p.extension(value)}';
            final bytes = await File(value).readAsBytes();
            archive.addFile(ArchiveFile(name, bytes.length, bytes));
            value = name;
          }
          blocks.add({'type': b.type, 'value': value});
        }
        data['blocks'] = blocks; all.add(data);
      }
      final bytesJson = utf8.encode(jsonEncode({'format':'portfolio_notes_backup','notes':all,'folders':_folders.map((x)=>x.toJson()).toList()}));
      archive.addFile(ArchiveFile('backup.json', bytesJson.length, bytesJson));
      final bytes = ZipEncoder().encode(archive); if (bytes == null) throw StateError('ZIP error');
      final temp = await getTemporaryDirectory();
      final file = File(p.join(temp.path, 'notes_backup.zip')); await file.writeAsBytes(bytes, flush:true);
      await Share.shareXFiles([XFile(file.path)], text:'پشتیبان یادداشت‌ها');
    } catch(e) { _message('خروجی ZIP ناموفق بود: $e'); }
  }

  Future<void> _importNotesZip() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type:FileType.custom, allowedExtensions:['zip'], withData:true);
      if (picked == null || picked.files.single.bytes == null) return;
      final archive = ZipDecoder().decodeBytes(picked.files.single.bytes!);
      final entry = archive.files.where((x)=>x.name=='backup.json').firstOrNull;
      if (entry == null) throw FormatException('فایل پشتیبان معتبر نیست');
      final data = jsonDecode(utf8.decode(entry.content as List<int>));
      if (data is! Map || data['format'] != 'portfolio_notes_backup') throw FormatException('ساختار فایل معتبر نیست');
      final dir = await _dir(); final imported = <NoteItem>[];
      for (final raw in data['notes'] as List? ?? []) {
        final map = Map<String,dynamic>.from(raw as Map); final blocks = <Map<String,dynamic>>[];
        for (final rawBlock in map['blocks'] as List? ?? []) {
          final b = Map<String,dynamic>.from(rawBlock as Map); final value = (b['value']??'').toString();
          if ((b['type']=='image'||b['type']=='audio') && value.startsWith('media/')) {
            final media = archive.files.where((x)=>x.name==value).firstOrNull;
            if (media != null) { final dest=p.join(dir.path,'import_${DateTime.now().microsecondsSinceEpoch}${p.extension(value)}'); await File(dest).writeAsBytes(media.content as List<int>,flush:true); b['value']=dest; }
          }
          blocks.add(b);
        }
        map['blocks']=blocks; imported.add(NoteItem.fromJson(map));
      }
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('وارد کردن یادداشت‌ها'),content:Text('${imported.length} یادداشت اضافه شود؟'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text('افزودن'))]));
      if(ok!=true)return; final ids=_notes.map((x)=>x.id).toSet();
      for(final n in imported){_notes.add(ids.contains(n.id)?NoteItem(id:'${n.id}_imported_${DateTime.now().microsecondsSinceEpoch}',title:n.title,blocks:n.blocks,createdAt:n.createdAt,updatedAt:n.updatedAt,folderId:n.folderId):n);}
      await _persist(); if(mounted)setState((){}); _message('یادداشت‌ها وارد شدند.');
    } catch(e) { _message('ورود ZIP ناموفق بود: $e'); }
  }

  Future<void> _importDocx() async {
    try {
      final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['docx'],withData:true);
      if(picked==null||picked.files.single.bytes==null)return;
      final archive=ZipDecoder().decodeBytes(picked.files.single.bytes!);
      final entry=archive.files.where((x)=>x.name=='word/document.xml').firstOrNull;
      if(entry==null)throw FormatException('فایل Word معتبر نیست');
      final xml=utf8.decode(entry.content as List<int>);
      final lines=RegExp(r'<w:p(?:\s[^>]*)?>(.*?)</w:p>',dotAll:true).allMatches(xml).map((m)=>RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>',dotAll:true).allMatches(m.group(1)!).map((t)=>t.group(1)!).join()).where((x)=>x.isNotEmpty).toList();
      final now=DateTime.now(); final title=lines.isEmpty?p.basenameWithoutExtension(picked.files.single.name):lines.first;
      _notes.insert(0,NoteItem(id:'${now.microsecondsSinceEpoch}',title:title,blocks:[NoteBlock('text',lines.skip(1).join('\n'))],createdAt:now,updatedAt:now,folderId:_currentFolderId));
      await _persist(); if(mounted)setState((){}); _message('فایل Word وارد شد.');
    } catch(e) { _message('ورود DOCX ناموفق بود: $e'); }
  }

  Future<void> _addCustomFont() async {
    try {
      final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['ttf','otf'],withData:true);
      if(picked==null||picked.files.single.bytes==null)return;
      final bytes=Uint8List.fromList(picked.files.single.bytes!); final family='CustomFont_${DateTime.now().millisecondsSinceEpoch}';
      final loader=FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes))); await loader.load();
      await NotesAppearanceSettings.setFonts(NotesAppearanceSettings.fonts.value.copyWith(appFontFamily:family,inputFontFamily:family));
      if(mounted)setState((){}); _message('فونت شخصی فعال شد.');
    } catch(e) { _message('افزودن فونت ناموفق بود: $e'); }
  }

  Future<void> _editFontSizes() async {
    var app=NotesAppearanceSettings.fonts.value.appTextSize.round().clamp(8,32); var input=NotesAppearanceSettings.fonts.value.inputTextSize.round().clamp(8,32); var step=1;
    final result=await showDialog<List<int>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(title:Text('اندازه نوشته‌ها'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      SegmentedButton<int>(segments:[ButtonSegment(value:1,label:Text('۱ پیکسل')),ButtonSegment(value:2,label:Text('۲ پیکسل'))],selected:{step},onSelectionChanged:(v)=>refresh(()=>step=v.first)),
      Text('متن برنامه: $app px'),Slider(value:app.toDouble(),min:8,max:32,divisions:24~/step,onChanged:(v)=>refresh(()=>app=(8+((v.round()-8)/step).round()*step).clamp(8,32))),
      Text('متن ورودی: $input px'),Slider(value:input.toDouble(),min:8,max:32,divisions:24~/step,onChanged:(v)=>refresh(()=>input=(8+((v.round()-8)/step).round()*step).clamp(8,32)))
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(ctx,[app,input]),child:Text('ذخیره'))])));
    if(result==null)return; await NotesAppearanceSettings.setFonts(NotesAppearanceSettings.fonts.value.copyWith(appTextSize:result[0].toDouble(),inputTextSize:result[1].toDouble()));
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('پوشه جدید'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(hintText: 'نام پوشه')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('ایجاد'))
                ]));
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (_childrenOf(_currentFolderId)
        .any((f) => f.name.toLowerCase() == name.toLowerCase())) {
      _message('پوشه‌ای با این نام در این مسیر وجود دارد.');
      return;
    }
    _folders.add(NoteFolder(id: _id(), name: name, parentId: _currentFolderId));
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _renameFolder(NoteFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('تغییر نام پوشه'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    textDirection: TextDirection.rtl),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('ذخیره'))
                ]));
    controller.dispose();
    if (name == null || name.isEmpty) return;
    folderIndexReplace(folder, name);
    await _persist();
    if (mounted) setState(() {});
  }

  void folderIndexReplace(NoteFolder folder, String name) {
    final i = _folders.indexWhere((f) => f.id == folder.id);
    if (i >= 0)
      _folders[i] =
          NoteFolder(id: folder.id, name: name, parentId: folder.parentId);
  }

  Future<void> _deleteFolder(NoteFolder folder) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('حذف پوشه'),
                content: Text(
                    'پوشه «${folder.name}» حذف شود؟ یادداشت‌ها و زیرپوشه‌ها به سطح پوشه والد منتقل می‌شوند.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('حذف'))
                ]));
    if (ok != true) return;
    for (var i = 0; i < _notes.length; i++) {
      if (_notes[i].folderId == folder.id) {
        final n = _notes[i];
        _notes[i] = NoteItem(
            id: n.id,
            title: n.title,
            blocks: n.blocks,
            createdAt: n.createdAt,
            updatedAt: n.updatedAt,
            folderId: folder.parentId);
      }
    }
    for (var i = 0; i < _folders.length; i++) {
      final f = _folders[i];
      if (f.parentId == folder.id)
        _folders[i] =
            NoteFolder(id: f.id, name: f.name, parentId: folder.parentId);
    }
    _folders.removeWhere((f) => f.id == folder.id);
    if (_currentFolderId == folder.id) _currentFolderId = folder.parentId;
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _moveNote(NoteItem note) async {
    final selected = await showDialog<String?>(
        context: context,
        builder: (ctx) {
          String? value = note.folderId;
          return StatefulBuilder(
              builder: (ctx, refresh) => AlertDialog(
                      title: const Text('انتقال یادداشت'),
                      content: SizedBox(
                          width: double.maxFinite,
                          child: DropdownButtonFormField<String?>(
                              value: value,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'مقصد'),
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('یادداشت‌های من (بدون پوشه)')),
                                ..._folders.map((f) =>
                                    DropdownMenuItem<String?>(
                                        value: f.id,
                                        child: Text(_folderPath(f.id))))
                              ],
                              onChanged: (v) => refresh(() => value = v))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('انصراف')),
                        FilledButton(
                            onPressed: () =>
                                Navigator.pop(ctx, value ?? '__root__'),
                            child: const Text('انتقال'))
                      ]));
        });
    if (selected == null) return;
    final target = selected == '__root__' ? null : selected;
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i >= 0) {
      _notes[i] = NoteItem(
          id: note.id,
          title: note.title,
          blocks: note.blocks,
          createdAt: note.createdAt,
          updatedAt: DateTime.now(),
          folderId: target);
      await _persist();
      if (mounted) setState(() {});
    }
  }

  void _message(String s) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _newText({String value = ''}) {
    _draft.add(NoteBlock('text', value));
    _textControllers.add(TextEditingController(text: value));
    _focusNodes.add(FocusNode());
    _activeText = _textControllers.length - 1;
  }

  void _startNew() {
    _disposeTextFields();
    _draft.clear();
    _draftBlockKeys.clear();
    _newText();
    _draftBlockKeys.add(GlobalKey());
    _title.clear();
    _editingId = _id();
    _created = DateTime.now();
    _editingFolderId = _currentFolderId;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes.isNotEmpty) _focusNodes[0].requestFocus();
    });
  }

  void _edit(NoteItem note, {String? searchTerm}) {
    _disposeTextFields();
    _draft.clear();
    _draftBlockKeys.clear();
    _title.text = note.title;
    _editingId = note.id;
    _created = note.createdAt;
    _editingFolderId = note.folderId;
    var targetBlock = -1;
    var targetOffset = 0;
    final query = (searchTerm ?? '').trim();
    for (var i = 0; i < note.blocks.length; i++) {
      final b = note.blocks[i];
      _draft.add(b);
      _draftBlockKeys.add(GlobalKey());
      if (b.type == 'text') {
        _textControllers.add(TextEditingController(text: b.value));
        _focusNodes.add(FocusNode());
        if (targetBlock < 0 && query.isNotEmpty) {
          final found = b.value.toLowerCase().indexOf(query.toLowerCase());
          if (found >= 0) {
            targetBlock = i;
            targetOffset = found;
          }
        }
      }
    }
    if (targetBlock < 0 &&
        query.isNotEmpty &&
        note.title.toLowerCase().contains(query.toLowerCase())) {
      targetBlock = -2;
      targetOffset = note.title.toLowerCase().indexOf(query.toLowerCase());
    }
    if (_textControllers.isEmpty) _newText();
    if (_draftBlockKeys.length < _draft.length)
      _draftBlockKeys.addAll(List.generate(
          _draft.length - _draftBlockKeys.length, (_) => GlobalKey()));
    _activeText = _textControllers.length - 1;
    setState(() => _editing = true);
    if (targetBlock == -2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final end =
            (targetOffset + query.length).clamp(0, _title.text.length).toInt();
        _title.selection = TextSelection(
            baseOffset: targetOffset.clamp(0, _title.text.length).toInt(),
            extentOffset: end);
      });
    }
    if (targetBlock >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || targetBlock >= _draftBlockKeys.length) return;
        final key = _draftBlockKeys[targetBlock];
        final ctx = key.currentContext;
        if (ctx != null)
          await Scrollable.ensureVisible(ctx,
              alignment: .35,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut);
        var ti = 0;
        for (var i = 0; i < targetBlock; i++) {
          if (_draft[i].type == 'text') ti++;
        }
        if (ti < _textControllers.length && mounted) {
          final c = _textControllers[ti];
          final end =
              (targetOffset + query.length).clamp(0, c.text.length).toInt();
          c.selection = TextSelection(
              baseOffset: targetOffset.clamp(0, c.text.length).toInt(),
              extentOffset: end);
          _activeText = ti;
          _focusNodes[ti].requestFocus();
        }
      });
    }
  }

  int _draftIndexForText(int textIndex) {
    var n = 0;
    for (var i = 0; i < _draft.length; i++) {
      if (_draft[i].type == 'text') {
        if (n == textIndex) return i;
        n++;
      }
    }
    return _draft.length;
  }

  Future<void> _addImage() async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 95);
      if (picked == null) return;
      final dir = await _dir();
      final dest = p.join(dir.path,
          'image_${_id()}${p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path)}');
      await File(picked.path).copy(dest);
      final ti = _activeText.clamp(0, _textControllers.length - 1);
      final controller = _textControllers[ti];
      final sel = controller.selection;
      final start = sel.isValid
          ? sel.start.clamp(0, controller.text.length).toInt()
          : controller.text.length;
      final end = sel.isValid
          ? sel.end.clamp(start, controller.text.length).toInt()
          : start;
      final before = controller.text.substring(0, start),
          after = controller.text.substring(end);
      controller.text = before;
      controller.selection = TextSelection.collapsed(offset: before.length);
      final at = _draftIndexForText(ti);
      _draft.insert(at + 1, NoteBlock('image', dest));
      _draftBlockKeys.insert(at + 1, GlobalKey());
      final afterIndex = ti + 1;
      _textControllers.insert(afterIndex, TextEditingController(text: after));
      _focusNodes.insert(afterIndex, FocusNode());
      _draft.insert(at + 2, NoteBlock('text', after));
      _draftBlockKeys.insert(at + 2, GlobalKey());
      _activeText = afterIndex;
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNodes[afterIndex].requestFocus();
      });
    } catch (e) {
      _message('افزودن تصویر ناموفق بود: $e');
    }
  }

  Future<void> _drawOnImage(int blockIndex) async {
    final path = _draft[blockIndex].value;
    final paintKey = GlobalKey();
    final strokes = <_DrawingStroke>[];
    final currentPoints = <Offset>[];
    var hue = 0.0;
    var thickness = 4.0;
    var eraser = false;

    // Decode the source dimensions first so the drawing surface can use the
    // exact same aspect ratio as the image (without a scrolling/zooming parent).
    final sourceBytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(sourceBytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final imageWidth = sourceImage.width.toDouble();
    final imageHeight = sourceImage.height.toDouble();
    sourceImage.dispose();
    codec.dispose();

    if (!mounted) return;
    final screen = MediaQuery.sizeOf(context);
    final maxCanvasWidth = screen.width * .88;
    final maxCanvasHeight = screen.height * .55;
    final scale =
        math.min(maxCanvasWidth / imageWidth, maxCanvasHeight / imageHeight);
    final canvasWidth = imageWidth * scale;
    final canvasHeight = imageHeight * scale;

    final saved = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) {
        final ink = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
        void finishStroke() {
          if (currentPoints.isNotEmpty) {
            strokes.add(_DrawingStroke(
              List<Offset>.from(currentPoints),
              eraser ? Colors.transparent : ink,
              thickness,
              eraser,
            ));
            currentPoints.clear();
          }
        }

        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: screen.width * .92,
            height: screen.height * .88,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text('نقاشی روی تصویر',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                // This canvas has a fixed size and is deliberately NOT inside
                // SingleChildScrollView or InteractiveViewer. Touch drags are
                // therefore consumed only by the drawing surface.
                Expanded(
                  child: Center(
                    child: RepaintBoundary(
                      key: paintKey,
                      child: SizedBox(
                        width: canvasWidth,
                        height: canvasHeight,
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(path),
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) => refresh(() {
                                  currentPoints
                                    ..clear()
                                    ..add(details.localPosition);
                                }),
                                onPanUpdate: (details) => refresh(() {
                                  currentPoints.add(Offset(
                                    details.localPosition.dx
                                        .clamp(0.0, canvasWidth)
                                        .toDouble(),
                                    details.localPosition.dy
                                        .clamp(0.0, canvasHeight)
                                        .toDouble(),
                                  ));
                                }),
                                onPanEnd: (_) => refresh(finishStroke),
                                child: CustomPaint(
                                  painter: _InkPainter(
                                      strokes,
                                      currentPoints,
                                      eraser ? Colors.transparent : ink,
                                      thickness,
                                      eraser),
                                  size: Size(canvasWidth, canvasHeight),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      ChoiceChip(
                          label: const Text('قلم'),
                          selected: !eraser,
                          onSelected: (_) => refresh(() => eraser = false)),
                      ChoiceChip(
                          label: const Text('پاک‌کن'),
                          selected: eraser,
                          onSelected: (_) => refresh(() => eraser = true)),
                      IconButton(
                          tooltip: 'واگرد',
                          onPressed: strokes.isEmpty
                              ? null
                              : () => refresh(strokes.removeLast),
                          icon: const Icon(Icons.undo)),
                      IconButton(
                          tooltip: 'پاک کردن همه',
                          onPressed: strokes.isEmpty
                              ? null
                              : () => refresh(strokes.clear),
                          icon: const Icon(Icons.delete_sweep_outlined)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('رنگ'),
                    Expanded(
                        child: Slider(
                            value: hue,
                            min: 0,
                            max: 360,
                            onChanged: (v) => refresh(() {
                                  hue = v;
                                  eraser = false;
                                }))),
                    Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                            color: ink,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('ضخامت'),
                    Expanded(
                        child: Slider(
                            value: thickness,
                            min: 1,
                            max: 24,
                            onChanged: (v) => refresh(() => thickness = v))),
                    Text(thickness.toStringAsFixed(0)),
                  ]),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('انصراف')),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () async {
                            finishStroke();
                            try {
                              final boundary = paintKey.currentContext!
                                  .findRenderObject() as RenderRepaintBoundary;
                              final pixelRatio =
                                  math.min(3.0, imageWidth / canvasWidth);
                              final rendered = await boundary.toImage(
                                  pixelRatio: pixelRatio);
                              final data = await rendered.toByteData(
                                  format: ui.ImageByteFormat.png);
                              rendered.dispose();
                              if (data != null && ctx.mounted) {
                                Navigator.pop(ctx, data.buffer.asUint8List());
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    content:
                                        Text('ذخیره تصویر ناموفق بود: $e')));
                              }
                            }
                          },
                          child: const Text('ذخیره تصویر')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    if (saved == null) return;
    final dir = await _dir();
    final output = p.join(dir.path, 'drawn_${_id()}.png');
    await File(output).writeAsBytes(saved, flush: true);
    if (!mounted) return;
    setState(() => _draft[blockIndex] = NoteBlock('image', output));
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        if (path != null) {
          final insertAt = _draftIndexForText(_activeText) + 1;
          _draft.insert(insertAt, NoteBlock('audio', path));
          _draftBlockKeys.insert(insertAt, GlobalKey());
          if (insertAt == _draft.length - 1 || _draft.last.type != 'text') {
            _draft.add(const NoteBlock('text', ''));
            _draftBlockKeys.add(GlobalKey());
            _textControllers.add(TextEditingController());
            _focusNodes.add(FocusNode());
          }
          if (mounted) setState(() => _recording = false);
        } else if (mounted) setState(() => _recording = false);
        return;
      }
      if (!await _recorder.hasPermission()) {
        _message('دسترسی میکروفون داده نشده است.');
        return;
      }
      final dir = await _dir();
      final path = p.join(dir.path, 'voice_${_id()}.m4a');
      await _recorder.start(
          const RecordConfig(
              encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
          path: path);
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (mounted) setState(() => _recording = false);
      _message('ضبط ویس ناموفق بود: $e');
    }
  }

  Future<void> _play(String path) async {
    try {
      if (_playing == path) {
        await _player.stop();
        setState(() => _playing = null);
      } else {
        await _player.stop();
        await _player.play(DeviceFileSource(path));
        setState(() => _playing = path);
        _player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _playing = null);
        });
      }
    } catch (e) {
      _message('پخش ویس ناموفق بود: $e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final blocks = <NoteBlock>[];
    var ti = 0;
    for (final b in _draft) {
      if (b.type == 'text') {
        blocks.add(NoteBlock('text', _textControllers[ti++].text));
      } else {
        blocks.add(b);
      }
    }
    if (title.isEmpty && blocks.every((b) => b.value.trim().isEmpty)) {
      _message('یادداشت خالی است.');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final note = NoteItem(
          id: _editingId ?? _id(),
          title: title.isEmpty ? 'بدون عنوان' : title,
          blocks: blocks,
          createdAt: _created ?? now,
          updatedAt: now,
          folderId: _editingFolderId);
      final i = _notes.indexWhere((n) => n.id == note.id);
      if (i < 0) {
        _notes.add(note);
      } else {
        _notes[i] = note;
      }
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _persist();
      if (mounted)
        setState(() {
          _editing = false;
          _editingId = null;
        });
      _message('یادداشت ذخیره شد.');
    } catch (e) {
      _message('ذخیره یادداشت ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(NoteItem note) async {
    _notes.removeWhere((n) => n.id == note.id);
    await _persist();
    if (mounted) setState(() {});
  }

  String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  Future<void> _exportDocx(NoteItem note) async {
    try {
      final archive = Archive();
      final relationships = <String>[];
      final media = <String, Uint8List>{};
      final contentTypes = <String>{};
      var rel = 1;
      final body = StringBuffer();
      body.write(
          '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>${_xml(note.title)}</w:t></w:r></w:p>');
      for (final b in note.blocks) {
        if (b.type == 'text') {
          for (final line in b.value.split('\n')) {
            body.write(
                '<w:p><w:r><w:t xml:space="preserve">${_xml(line)}</w:t></w:r></w:p>');
          }
        } else if (b.type == 'image' && await File(b.value).exists()) {
          final ext =
              p.extension(b.value).toLowerCase() == '.png' ? 'png' : 'jpg';
          final name = 'image${media.length + 1}.$ext';
          final rid = 'rId${rel++}';
          media[name] = await File(b.value).readAsBytes();
          contentTypes.add(ext);
          relationships.add(
              '<Relationship Id="$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
          body.write(
              '<w:p><w:r><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><wp:extent cx="5486400" cy="3657600"/><wp:docPr id="${rel}" name="$name"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="${rel}" name="$name"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$rid" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="5486400" cy="3657600"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>');
        } else if (b.type == 'audio') {
          body.write(
              '<w:p><w:r><w:t>${_xml('فایل صوتی: ${p.basename(b.value)} — فایل در برنامه ذخیره شده است: ${b.value}')}</w:t></w:r></w:p>');
        }
      }
      final doc =
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body.toString()}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/></w:sectPr></w:body></w:document>''';
      final rels =
          '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId0" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>${relationships.join()}</Relationships>''';
      final types = StringBuffer(
          '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>');
      for (final ext in contentTypes) {
        types.write(
            '<Default Extension="$ext" ContentType="image/${ext == 'jpg' ? 'jpeg' : ext}"/>');
      }
      types.write('</Types>');
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add('[Content_Types].xml', utf8.encode(types.toString()));
      add('_rels/.rels', utf8.encode(rels));
      add('word/document.xml', utf8.encode(doc));
      if (relationships.isNotEmpty)
        add(
            'word/_rels/document.xml.rels',
            utf8.encode(
                '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${relationships.join()}</Relationships>'''));
      for (final e in media.entries) {
        add('word/media/${e.key}', e.value);
      }
      final bytes = ZipEncoder().encode(archive);
      if (bytes == null) {
        throw StateError('ساخت فایل Word ناموفق بود.');
      }
      final temp = await getTemporaryDirectory();
      final file = File(p.join(temp.path, 'note_${note.id}.docx'));
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [
          XFile(file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
        ],
        text: 'خروجی Word یادداشت ${note.title}',
      );
    } catch (e) {
      _message('خروجی DOCX ناموفق بود: $e');
    }
  }

  List<NoteItem> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _notes.where((n) {
      final matches = q.isEmpty ||
          n.title.toLowerCase().contains(q) ||
          n.searchableText.toLowerCase().contains(q);
      return matches && (q.isNotEmpty || n.folderId == _currentFolderId);
    }).toList();
  }

  List<NoteFolder> get _visibleFolders =>
      _search.text.trim().isNotEmpty ? const [] : _childrenOf(_currentFolderId);
  void _openFolder(NoteFolder folder) {
    setState(() => _currentFolderId = folder.id);
  }

  Widget _editorBlock(int index) {
    final block = _draft[index];
    Widget child;
    if (block.type == 'text') {
      var textIndex = 0;
      for (var i = 0; i < index; i++) {
        if (_draft[i].type == 'text') textIndex++;
      }
      child = TextField(
        controller: _textControllers[textIndex],
        focusNode: _focusNodes[textIndex],
        onTap: () => _activeText = textIndex,
        onChanged: (_) =>
            _draft[index] = NoteBlock('text', _textControllers[textIndex].text),
        maxLines: null,
        minLines: 2,
        textDirection: TextDirection.rtl,
        style: TextStyle(
            fontFamily: NotesAppearanceSettings.fonts.value.inputFontFamily,
            fontSize: NotesAppearanceSettings.fonts.value.inputTextSize,
            color: NotesAppearanceSettings.color('inputText')),
        decoration: const InputDecoration(
            hintText: 'متن یادداشت را بنویسید...',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5)),
      );
    } else if (block.type == 'image') {
      child = Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(block.value),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Text('تصویر در دسترس نیست'))),
            Align(
                alignment: Alignment.centerLeft,
                child: Wrap(children: [
                  TextButton.icon(
                      onPressed: () => _drawOnImage(index),
                      icon: const Icon(Icons.draw),
                      label: const Text('نقاشی')),
                  IconButton(
                      tooltip: 'حذف تصویر',
                      onPressed: () => setState(() {
                            _draft.removeAt(index);
                            _draftBlockKeys.removeAt(index);
                          }),
                      icon: Icon(Icons.delete_outline,
                          color: NotesAppearanceSettings.color('delete')))
                ])),
          ]));
    } else {
      child = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(children: [
            const Icon(Icons.mic),
            const SizedBox(width: 8),
            Expanded(
                child: Text(p.basename(block.value),
                    textDirection: TextDirection.ltr)),
            IconButton(
                tooltip: _playing == block.value ? 'توقف' : 'پخش ویس',
                icon: Icon(
                    _playing == block.value ? Icons.stop : Icons.play_arrow),
                onPressed: () => _play(block.value)),
            IconButton(
                tooltip: 'حذف ویس',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() {
                      _draft.removeAt(index);
                      _draftBlockKeys.removeAt(index);
                    }))
          ]));
    }
    return KeyedSubtree(key: _draftBlockKeys[index], child: child);
  }

  Widget _buildEditor() => Scaffold(
        appBar: AppBar(
            title: const Text('یادداشت'),
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  if (_recording) _toggleRecording();
                  setState(() => _editing = false);
                }),
            actions: [
              IconButton(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  tooltip: 'ذخیره')
            ]),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                  controller: _title,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontFamily:
                          NotesAppearanceSettings.fonts.value.inputFontFamily,
                      fontSize:
                          NotesAppearanceSettings.fonts.value.inputTextSize + 3,
                      fontWeight: FontWeight.bold,
                      color: NotesAppearanceSettings.color('inputText')),
                  decoration: const InputDecoration(
                      hintText: 'عنوان یادداشت', border: InputBorder.none))),
          const Divider(height: 1),
          Expanded(
              child: SingleChildScrollView(
                  controller: _editorScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                        color: NotesAppearanceSettings.color('inputBackground'),
                        border: Border.all(
                            color:
                                NotesAppearanceSettings.color('inputBorder')),
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        IconButton(tooltip:'فونت و اندازه نوشته',onPressed:_editFontSizes,icon:const Icon(Icons.format_size)),
                      ]))),
        ])),
      );
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Color>>(
      valueListenable: NotesAppearanceSettings.colors,
      builder: (context, colors, _) {
        return ValueListenableBuilder<NotesFontSettings>(
          valueListenable: NotesAppearanceSettings.fonts,
          builder: (context, fonts, _) {
            final base = Theme.of(context);
            final scale = fonts.appTextSize / 14.0;
            final themed = base.copyWith(
              scaffoldBackgroundColor:
                  NotesAppearanceSettings.color('pageBackground'),
              appBarTheme: base.appBarTheme.copyWith(
                backgroundColor:
                    NotesAppearanceSettings.color('appBarBackground'),
                foregroundColor: NotesAppearanceSettings.color('appBarText'),
                iconTheme: IconThemeData(
                    color: NotesAppearanceSettings.color('appBarIcon')),
                titleTextStyle: TextStyle(
                    fontFamily: fonts.appFontFamily,
                    fontSize: fonts.appTextSize * 1.35,
                    color: NotesAppearanceSettings.color('appBarText'),
                    fontWeight: FontWeight.w600),
              ),
              cardTheme: base.cardTheme.copyWith(
                  color: NotesAppearanceSettings.color('cardBackground')),
              iconTheme:
                  IconThemeData(color: NotesAppearanceSettings.color('icon')),
              dividerColor: NotesAppearanceSettings.color('divider'),
              textTheme: base.textTheme.apply(
                fontFamily: fonts.appFontFamily,
                fontSizeFactor: scale,
                bodyColor: NotesAppearanceSettings.color('primaryText'),
                displayColor: NotesAppearanceSettings.color('primaryText'),
              ),
              inputDecorationTheme: base.inputDecorationTheme.copyWith(
                filled: true,
                fillColor: NotesAppearanceSettings.color('inputBackground'),
                hintStyle: TextStyle(
                    fontFamily: fonts.appFontFamily,
                    fontSize: fonts.appTextSize,
                    color: NotesAppearanceSettings.color('hintText')),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: NotesAppearanceSettings.color('inputBorder'))),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: NotesAppearanceSettings.color('icon'),
                        width: 2)),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor:
                    NotesAppearanceSettings.color('floatingButtonBackground'),
                foregroundColor:
                    NotesAppearanceSettings.color('floatingButtonText'),
              ),
              filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          NotesAppearanceSettings.color('buttonBackground'),
                      foregroundColor:
                          NotesAppearanceSettings.color('buttonText'))),
              elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          NotesAppearanceSettings.color('buttonBackground'),
                      foregroundColor:
                          NotesAppearanceSettings.color('buttonText'))),
              textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                      foregroundColor:
                          NotesAppearanceSettings.color('buttonBackground'))),
              dialogTheme: base.dialogTheme.copyWith(
                  backgroundColor:
                      NotesAppearanceSettings.color('dialogBackground')),
              popupMenuTheme: base.popupMenuTheme.copyWith(
                  color: NotesAppearanceSettings.color('menuBackground')),
              snackBarTheme: base.snackBarTheme.copyWith(
                  backgroundColor:
                      NotesAppearanceSettings.color('snackbarBackground'),
                  contentTextStyle: TextStyle(
                      fontFamily: fonts.appFontFamily,
                      fontSize: fonts.appTextSize,
                      color: NotesAppearanceSettings.color('snackbarText'))),
            );
            return Theme(
              data: themed,
              child: Builder(
                  builder: (themedContext) =>
                      _buildNotesPage(themedContext, fonts)),
            );
          },
        );
      },
    );
  }

  Widget _buildNotesPage(BuildContext context, NotesFontSettings fonts) {
    if (_editing) return _buildEditor();
    final notes = _filtered;
    final folders = _visibleFolders;
    final searching = _search.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: NotesAppearanceSettings.color('pageBackground'),
      appBar: AppBar(
        title: Text(searching
            ? 'نتایج جستجو'
            : (_currentFolderId == null
                ? 'یادداشت‌های من'
                : _folderPath(_currentFolderId))),
        centerTitle: true,
        leading: _currentFolderId == null || searching
            ? null
            : IconButton(
                tooltip: 'بازگشت به پوشه والد',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  final current = _folderById(_currentFolderId);
                  setState(() => _currentFolderId = current?.parentId);
                },
              ),
        actions: [
          IconButton(tooltip:'خروجی ZIP همه یادداشت‌ها',onPressed:_exportAllNotesZip,icon:const Icon(Icons.folder_zip_outlined)),
          PopupMenuButton<String>(tooltip:'وارد کردن فایل',icon:const Icon(Icons.file_upload_outlined),onSelected:(v){if(v=='zip')_importNotesZip();if(v=='docx')_importDocx();},itemBuilder:(_)=>const [PopupMenuItem(value:'zip',child:Text('وارد کردن ZIP')),PopupMenuItem(value:'docx',child:Text('وارد کردن Word'))]),
          IconButton(tooltip:'افزودن فونت شخصی',onPressed:_addCustomFont,icon:const Icon(Icons.font_download_outlined)),
          IconButton(tooltip:'اندازه نوشته‌ها',onPressed:_editFontSizes,icon:const Icon(Icons.format_size)),
          IconButton(tooltip:'ساخت پوشه',onPressed:searching?null:_createFolder,icon:const Icon(Icons.create_new_folder_outlined)),
          IconButton(tooltip:'تنظیمات رنگ و فونت',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const NotesAppearanceSettingsPage())),icon:const Icon(Icons.tune)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _startNew,
          icon: const Icon(Icons.add),
          label: const Text('یادداشت جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: fonts.inputFontFamily,
                          fontSize: fonts.inputTextSize,
                          color: NotesAppearanceSettings.color('inputText')),
                      decoration: InputDecoration(
                          hintText: 'جست‌وجو در همه یادداشت‌ها',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close)),
                          filled: true,
                          fillColor:
                              NotesAppearanceSettings.color('inputBackground'),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none)),
                    )),
                if (!searching && _currentFolderId != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(_folderPath(_currentFolderId),
                              textDirection: TextDirection.rtl,
                              style: Theme.of(context).textTheme.bodySmall))),
                Expanded(
                    child: folders.isEmpty && notes.isEmpty
                        ? Center(
                            child: Text(searching
                                ? 'نتیجه‌ای پیدا نشد.'
                                : 'این پوشه خالی است.'))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                            children: [
                                for (final folder in folders)
                                  Card(
                                    color: NotesAppearanceSettings.color(
                                        'cardBackground'),
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    child: ListTile(
                                        leading:
                                            const Icon(Icons.folder_outlined),
                                        title: Text(folder.name,
                                            textDirection: TextDirection.rtl),
                                        subtitle: Text(
                                            '${_notes.where((n) => n.folderId == folder.id).length} یادداشت مستقیم'),
                                        onTap: () => _openFolder(folder),
                                        trailing: PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'rename')
                                                _renameFolder(folder);
                                              if (v == 'delete')
                                                _deleteFolder(folder);
                                            },
                                            itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                      value: 'rename',
                                                      child: Text('تغییر نام')),
                                                  PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('حذف پوشه'))
                                                ])),
                                  ),
                                for (final n in notes)
                                  Builder(builder: (context) {
                                    final preview = n.searchableText.trim();
                                    final imageCount = n.blocks
                                        .where((b) => b.type == 'image')
                                        .length;
                                    final audioCount = n.blocks
                                        .where((b) => b.type == 'audio')
                                        .length;
                                    return Card(
                                        color: NotesAppearanceSettings.color(
                                            'cardBackground'),
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        child: ListTile(
                                          onTap: () => _edit(n,
                                              searchTerm: _search.text.trim()),
                                          title: Text(n.title,
                                              textDirection: TextDirection.rtl,
                                              style: TextStyle(
                                                  fontFamily:
                                                      fonts.inputFontFamily,
                                                  fontSize: fonts.inputTextSize,
                                                  fontWeight: FontWeight.bold,
                                                  color: NotesAppearanceSettings
                                                      .color('inputText'))),
                                          subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (preview.isNotEmpty)
                                                  Text(preview,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textDirection:
                                                          TextDirection.rtl,
                                                      style: TextStyle(
                                                          fontFamily: fonts
                                                              .inputFontFamily,
                                                          fontSize: fonts
                                                              .inputTextSize,
                                                          color: NotesAppearanceSettings
                                                              .color(
                                                                  'inputText'))),
                                                if (searching &&
                                                    n.folderId != null)
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 3),
                                                      child: Text(
                                                          'پوشه: ${_folderPath(n.folderId)}',
                                                          textDirection:
                                                              TextDirection.rtl,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall)),
                                                const SizedBox(height: 5),
                                                Text(
                                                    '${n.updatedAt.year}/${n.updatedAt.month}/${n.updatedAt.day}  •  $imageCount تصویر  •  $audioCount ویس',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                            color: NotesAppearanceSettings
                                                                .color(
                                                                    'secondaryText')))
                                              ]),
                                          trailing: PopupMenuButton<String>(
                                              onSelected: (v) {
                                                if (v == 'docx') _exportDocx(n);
                                                if (v == 'delete') _delete(n);
                                                if (v == 'move') _moveNote(n);
                                              },
                                              itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                        value: 'move',
                                                        child: Text(
                                                            'انتقال به پوشه')),
                                                    PopupMenuItem(
                                                        value: 'docx',
                                                        child:
                                                            Text('خروجی DOCX')),
                                                    PopupMenuItem(
                                                        value: 'delete',
                                                        child:
                                                            Text('حذف یادداشت'))
                                                  ]),
                                        ));
                                  }),
                              ])),
              ]),
            ),
    );
  }
}

class _DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool eraser;
  const _DrawingStroke(this.points, this.color, this.width, this.eraser);
}

class _InkPainter extends CustomPainter {
  final List<_DrawingStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final bool currentEraser;
  _InkPainter(this.strokes, this.currentPoints, this.currentColor,
      this.currentWidth, this.currentEraser);

  @override
  void paint(Canvas canvas, Size size) {
    void draw(List<Offset> points, Color color, double width, bool eraser) {
      if (points.isEmpty) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = eraser ? BlendMode.clear : BlendMode.srcOver;
      if (points.length == 1) {
        canvas.drawCircle(
            points.first, width / 2, paint..style = PaintingStyle.fill);
        return;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      draw(stroke.points, stroke.color, stroke.width, stroke.eraser);
    }
    draw(currentPoints, currentColor, currentWidth, currentEraser);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}
