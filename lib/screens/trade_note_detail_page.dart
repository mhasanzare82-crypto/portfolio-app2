// lib/screens/trade_note_detail_page.dart

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/number_formatter.dart' as numbers;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'image_annotation_page.dart';

import '../repositories/note_subject_repository.dart';
import '../repositories/note_tag_repository.dart';
import '../repositories/trade_note_repository.dart';

class _InlineMediaTextController extends TextEditingController {
  List<String> imagePaths = [];
  List<String> audioPaths = [];
  double? inlineMaxWidth;
  void Function(String path)? onImageTap;
  void Function(String path)? onAudioTap;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = <InlineSpan>[];
    final plain = StringBuffer();
    void flushPlain() {
      if (plain.isNotEmpty) {
        children.add(TextSpan(text: plain.toString(), style: style));
        plain.clear();
      }
    }

    for (final rune in text.runes) {
      if (rune >= 0xE000 && rune < 0xF000) {
        flushPlain();
        final index = rune - 0xE000;
        final path =
            index >= 0 && index < imagePaths.length ? imagePaths[index] : '';
        final availableWidth = inlineMaxWidth != null &&
                inlineMaxWidth!.isFinite &&
                inlineMaxWidth! > 0
            ? inlineMaxWidth!
            : MediaQuery.sizeOf(context).width;
        final width =
            (availableWidth - 36).clamp(1.0, availableWidth).toDouble();
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: path.isNotEmpty && File(path).existsSync()
                ? GestureDetector(
                    onTap: () => onImageTap?.call(path),
                    child: SizedBox(
                      width: width,
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 80,
                          child:
                              Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    ),
                  )
                : SizedBox(
                    width: width,
                    height: 80,
                    child:
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
          ),
        ));
      } else if (rune >= 0xF000 && rune < 0xF8FF) {
        flushPlain();
        final index = rune - 0xF000;
        final path =
            index >= 0 && index < audioPaths.length ? audioPaths[index] : '';
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: OutlinedButton.icon(
              onPressed: path.isEmpty ? null : () => onAudioTap?.call(path),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(
                path.isEmpty ? 'فایل صوتی در دسترس نیست' : 'پخش فایل صوتی',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ));
      } else {
        plain.write(String.fromCharCode(rune));
      }
    }
    flushPlain();
    return TextSpan(style: style, children: children);
  }
}

class TradeNoteDetailPage extends StatefulWidget {
  final int noteId;

  const TradeNoteDetailPage({
    super.key,
    required this.noteId,
  });

  @override
  State<TradeNoteDetailPage> createState() => _TradeNoteDetailPageState();
}

class _TradeNoteDetailPageState extends State<TradeNoteDetailPage> {
  final repository = TradeNoteRepository.instance;
  final subjectRepository = NoteSubjectRepository.instance;
  final tagRepository = NoteTagRepository.instance;

  final titleController = TextEditingController();
  final _InlineMediaTextController contentController =
      _InlineMediaTextController();
  final FocusNode contentFocusNode = FocusNode();
  final assetController = TextEditingController();

  final imagePicker = ImagePicker();
  final recorder = AudioRecorder();
  final audioPlayer = AudioPlayer();

  List<Map<String, Object?>> subjects = [];
  List<Map<String, Object?>> tags = [];
  List<Map<String, Object?>> media = [];

  Set<int> selectedSubjectIds = {};
  Set<String> selectedTagNames = {};

  bool loading = true;
  bool saving = false;
  bool recording = false;
  int? _recordingInsertOffset;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    assetController.dispose();
    recorder.dispose();
    audioPlayer.dispose();
    contentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    try {
      final note = await repository.getNote(widget.noteId);

      if (note == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      titleController.text = note['title']?.toString() ?? '';

      contentController.text = note['content']?.toString() ?? '';

      assetController.text = note['asset_symbol']?.toString() ?? '';

      final selectedSubjects =
          await repository.getSubjectsForNote(widget.noteId);

      final selectedTags = await repository.getTagsForNote(widget.noteId);

      subjects = await subjectRepository.getAllSubjects();
      tags = await tagRepository.getAllTags();
      media = await repository.getMediaForNote(widget.noteId);
      contentController.imagePaths = media
          .where((item) => item['media_type']?.toString() == 'image')
          .map((item) => item['file_path']?.toString() ?? '')
          .toList();
      contentController.audioPaths = media
          .where((item) => item['media_type']?.toString() == 'audio')
          .map((item) => item['file_path']?.toString() ?? '')
          .toList();
      contentController.onImageTap = _editInlineImage;
      contentController.onAudioTap = _playAudio;
      _ensureInlineMediaMarkers();

      selectedSubjectIds =
          selectedSubjects.map((e) => e['subject_id'] as int).toSet();

      selectedTagNames = selectedTags
          .map((e) => e['tag_name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (titleController.text.trim().isEmpty) {
      _message('عنوان نمی‌تواند خالی باشد.');
      return;
    }

    setState(() => saving = true);

    try {
      // تبدیل نام برچسب‌های انتخاب‌شده به شناسه‌های واقعی
      final selectedTagIds = tags
          .where(
            (tag) => selectedTagNames.contains(
              tag['tag_name']?.toString() ?? '',
            ),
          )
          .map(
            (tag) => tag['tag_id'] as int,
          )
          .toList();

      await repository.updateNote(
        noteId: widget.noteId,
        title: titleController.text,
        content: contentController.text,
        assetSymbol: assetController.text,
        tagIds: selectedTagIds,
        subjectIds: selectedSubjectIds.toList(),
      );

      await _load();

      if (mounted) {
        _message('یادداشت ذخیره شد.');
      }
    } catch (e) {
      _message('خطا در ذخیره:\n$e');
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  void _ensureInlineMediaMarkers() {
    var text = contentController.text;
    final missing = <String>[];
    var imageIndex = 0;
    var audioIndex = 0;
    for (final item in media) {
      final type = item['media_type']?.toString();
      if (type == 'image') {
        final marker = String.fromCharCode(0xE000 + imageIndex++);
        if (!text.contains(marker)) missing.add(marker);
      } else if (type == 'audio') {
        final marker = String.fromCharCode(0xF000 + audioIndex++);
        if (!text.contains(marker)) missing.add(marker);
      }
    }
    if (missing.isEmpty) return;
    final separator = text.isNotEmpty && !text.endsWith('\n') ? '\n' : '';
    text = '$text$separator${missing.join('\n')}';
    contentController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  int _insertMarkerAtCursor(String marker, {int? requestedOffset}) {
    final oldText = contentController.text;
    final selection = contentController.selection;
    final offset = (requestedOffset ??
            (selection.isValid ? selection.baseOffset : oldText.length))
        .clamp(0, oldText.length)
        .toInt();
    final before = oldText.substring(0, offset);
    final after = oldText.substring(offset);
    final prefix = before.isNotEmpty && !before.endsWith('\n') ? '\n' : '';
    final suffix = after.isNotEmpty && !after.startsWith('\n') ? '\n' : '';
    final inserted = '$prefix$marker$suffix';
    final newText = '$before$inserted$after';
    final cursorOffset = (offset +
            inserted.length +
            (suffix.isEmpty && after.startsWith('\n') ? 1 : 0))
        .clamp(0, newText.length)
        .toInt();
    contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    contentFocusNode.requestFocus();
    return cursorOffset;
  }

  void _removeInlineMedia(String path, {required bool image}) {
    final paths =
        image ? contentController.imagePaths : contentController.audioPaths;
    final startCode = image ? 0xE000 : 0xF000;
    final index = paths.indexOf(path);
    if (index < 0) return;
    final updated = StringBuffer();
    for (final rune in contentController.text.runes) {
      if (rune == startCode + index) continue;
      if (rune > startCode + index && rune < startCode + paths.length) {
        updated.write(String.fromCharCode(rune - 1));
      } else {
        updated.write(String.fromCharCode(rune));
      }
    }
    paths.removeAt(index);
    final text = updated.toString();
    contentController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: contentController.selection.baseOffset
            .clamp(0, text.length)
            .toInt(),
      ),
    );
  }

  Future<void> _pickImages() async {
    try {
      final selection = contentController.selection;
      final images = await imagePicker.pickMultiImage(imageQuality: 90);
      if (!mounted || images.isEmpty) return;
      var insertionOffset = selection.isValid
          ? selection.baseOffset
          : contentController.text.length;
      insertionOffset =
          insertionOffset.clamp(0, contentController.text.length).toInt();

      for (final image in images) {
        final annotated = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ImageAnnotationPage(imagePath: image.path),
          ),
        );
        if (!mounted) return;
        final sourcePath = annotated ?? image.path;
        final saved = await repository.copyMediaToNoteStorage(
          noteId: widget.noteId,
          sourcePath: sourcePath,
          mediaType: 'image',
          extension: p.extension(sourcePath),
        );
        await repository.addMedia(
          noteId: widget.noteId,
          mediaType: 'image',
          filePath: saved,
          fileName: p.basename(saved),
        );
        final index = contentController.imagePaths.length;
        contentController.imagePaths.add(saved);
        insertionOffset = _insertMarkerAtCursor(
          String.fromCharCode(0xE000 + index),
          requestedOffset: insertionOffset,
        );
      }
      await repository.updateNote(
        noteId: widget.noteId,
        content: contentController.text,
      );
      await _load();
    } catch (e) {
      _message('افزودن تصویر ناموفق بود: $e');
    }
  }

  Future<void> _pickAudio() async {
    try {
      final selection = contentController.selection;
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = result?.files.single.path;
      if (path == null) return;
      final saved = await repository.copyMediaToNoteStorage(
        noteId: widget.noteId,
        sourcePath: path,
        mediaType: 'audio',
        extension: p.extension(path),
      );
      await repository.addMedia(
        noteId: widget.noteId,
        mediaType: 'audio',
        filePath: saved,
        fileName: p.basename(saved),
      );
      final index = contentController.audioPaths.length;
      contentController.audioPaths.add(saved);
      _insertMarkerAtCursor(
        String.fromCharCode(0xF000 + index),
        requestedOffset: selection.isValid
            ? selection.baseOffset
            : contentController.text.length,
      );
      await repository.updateNote(
        noteId: widget.noteId,
        content: contentController.text,
      );
      await _load();
    } catch (e) {
      _message('افزودن فایل صوتی ناموفق بود: $e');
    }
  }

  Future<void> _recordAudio() async {
    if (recording) {
      try {
        final path = await recorder.stop();
        if (mounted) setState(() => recording = false);
        final offset = _recordingInsertOffset;
        _recordingInsertOffset = null;
        if (path == null || path.isEmpty) return;
        final saved = await repository.copyMediaToNoteStorage(
          noteId: widget.noteId,
          sourcePath: path,
          mediaType: 'audio',
          extension: p.extension(path),
        );
        await repository.addMedia(
          noteId: widget.noteId,
          mediaType: 'audio',
          filePath: saved,
          fileName: p.basename(saved),
        );
        final index = contentController.audioPaths.length;
        contentController.audioPaths.add(saved);
        _insertMarkerAtCursor(
          String.fromCharCode(0xF000 + index),
          requestedOffset: offset ?? contentController.text.length,
        );
        await repository.updateNote(
          noteId: widget.noteId,
          content: contentController.text,
        );
        await _load();
      } catch (e) {
        _message('ذخیره صدای ضبط‌شده ناموفق بود: $e');
      }
      return;
    }

    if (!await recorder.hasPermission()) {
      _message('دسترسی میکروفون داده نشده است.');
      return;
    }
    final temp = await getTemporaryDirectory();
    final path = p.join(
      temp.path,
      'note_${widget.noteId}_${DateTime.now().microsecondsSinceEpoch}.m4a',
    );
    _recordingInsertOffset = contentController.selection.isValid
        ? contentController.selection.baseOffset
        : contentController.text.length;
    await recorder.start(const RecordConfig(), path: path);
    if (mounted) setState(() => recording = true);
  }

  Future<void> _deleteMedia(Map<String, Object?> item) async {
    try {
      final id = item['media_id'] as int;
      final path = item['file_path']?.toString() ?? '';
      final image = item['media_type']?.toString() == 'image';
      _removeInlineMedia(path, image: image);
      await repository.deleteMedia(id);
      await repository.updateNote(
        noteId: widget.noteId,
        content: contentController.text,
      );
      await _load();
    } catch (e) {
      _message('حذف رسانه ناموفق بود: $e');
    }
  }

  Future<void> _editInlineImage(String path) async {
    try {
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => ImageAnnotationPage(imagePath: path)),
      );
      if (edited == null || !mounted) return;
      final index = contentController.imagePaths.indexOf(path);
      if (index < 0) return;
      final saved = await repository.copyMediaToNoteStorage(
        noteId: widget.noteId,
        sourcePath: edited,
        mediaType: 'image',
        extension: p.extension(edited),
      );
      final match = media.where((item) =>
          item['media_type']?.toString() == 'image' &&
          item['file_path']?.toString() == path);
      if (match.isNotEmpty) {
        final rawId = match.first['media_id'];
        if (rawId is num) {
          await repository.updateMediaPath(
            mediaId: rawId.toInt(),
            filePath: saved,
            fileName: p.basename(saved),
          );
        }
      }
      contentController.imagePaths[index] = saved;
      await repository.updateNote(
        noteId: widget.noteId,
        content: contentController.text,
      );
      await _load();
    } catch (e) {
      _message('ویرایش تصویر ناموفق بود: $e');
    }
  }

  Future<void> _playAudio(String path) async {
    if (!File(path).existsSync()) {
      _message('فایل صوتی پیدا نشد.');
      return;
    }
    try {
      await audioPlayer.stop();
      await audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      _message('پخش فایل صوتی ناموفق بود: $e');
    }
  }

  Future<void> _selectSubjects() async {
    final selected = Set<int>.from(selectedSubjectIds);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return _SubjectMultiPicker(
          selected: selected,
          onCreate: () async {
            final name = await _textDialog(
              'موضوع جدید',
            );

            if (name == null) return;

            try {
              final id = await subjectRepository.createSubject(
                name: name,
              );

              selected.add(id);
              subjects = await subjectRepository.getAllSubjects();

              if (mounted) setState(() {});
            } catch (e) {
              _message('خطا:\n$e');
            }
          },
        );
      },
    );

    setState(() {
      selectedSubjectIds = selected;
    });
  }

  Future<void> _selectTags() async {
    final selected = Set<String>.from(selectedTagNames);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return _TagMultiPicker(
          selected: selected,
          onCreate: () async {
            final name = await _textDialog(
              'برچسب جدید',
            );

            if (name == null) return;

            try {
              final id = await tagRepository.createTag(name);

              final tag = await tagRepository.getTag(id);

              selected.add(
                tag?['tag_name']?.toString() ?? name,
              );

              tags = await tagRepository.getAllTags();

              if (mounted) setState(() {});
            } catch (e) {
              _message('خطا:\n$e');
            }
          },
        );
      },
    );

    setState(() {
      selectedTagNames = selected;
    });
  }

  Future<String?> _textDialog(
    String title,
  ) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'نام',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  controller.text.trim(),
                );
              },
              child: const Text('افزودن'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    return result;
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ویرایش یادداشت'),
        actions: [
          IconButton(
            onPressed: saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: assetController,
                  decoration: const InputDecoration(
                    labelText: 'دارایی',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _selectSubjects,
                  icon: const Icon(
                    Icons.account_tree_outlined,
                  ),
                  label: Text(
                    'موضوعات: ${numbers.formatInteger(selectedSubjectIds.length)}',
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: selectedSubjectIds.map((id) {
                    final found = subjects.where(
                      (e) => e['subject_id'] == id,
                    );

                    return Chip(
                      label: Text(
                        found.isEmpty
                            ? '$id'
                            : found.first['subject_name'].toString(),
                      ),
                      onDeleted: () {
                        setState(() {
                          selectedSubjectIds.remove(id);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _selectTags,
                  icon: const Icon(
                    Icons.local_offer_outlined,
                  ),
                  label: Text(
                    'برچسب‌ها: ${numbers.formatInteger(selectedTagNames.length)}',
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: selectedTagNames.map(
                    (tag) {
                      return Chip(
                        label: Text(tag),
                        onDeleted: () {
                          setState(() {
                            selectedTagNames.remove(tag);
                          });
                        },
                      );
                    },
                  ).toList(),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    contentController.inlineMaxWidth = constraints.maxWidth;
                    return TextField(
                      controller: contentController,
                      focusNode: contentFocusNode,
                      minLines: 14,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.start,
                      decoration: const InputDecoration(
                        labelText: 'متن یادداشت',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickImages,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('افزودن عکس'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickAudio,
                      icon: const Icon(
                        Icons.audio_file_outlined,
                      ),
                      label: const Text('فایل صوتی'),
                    ),
                    FilledButton.icon(
                      onPressed: _recordAudio,
                      icon: Icon(
                        recording ? Icons.stop : Icons.mic_none,
                      ),
                      label: Text(
                        recording ? 'توقف ضبط' : 'ضبط ویس',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...media.map(
                  (item) {
                    final type = item['media_type']?.toString();

                    final path = item['file_path']?.toString() ?? '';

                    final id = item['media_id'] as int;

                    if (type == 'image') {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(path),
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => _deleteMedia(item),
                                icon: const Icon(
                                  Icons.delete_outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(
                          Icons.audiotrack_outlined,
                        ),
                        title: Text(
                          item['file_name']?.toString() ?? 'فایل صوتی',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _playAudio(path),
                              icon: const Icon(
                                Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _deleteMedia(item),
                              icon: const Icon(
                                Icons.delete_outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 100),
              ],
            ),
    );
  }
}

class _SubjectMultiPicker extends StatefulWidget {
  final Set<int> selected;
  final Future<void> Function() onCreate;

  const _SubjectMultiPicker({
    required this.selected,
    required this.onCreate,
  });

  @override
  State<_SubjectMultiPicker> createState() => _SubjectMultiPickerState();
}

class _SubjectMultiPickerState extends State<_SubjectMultiPicker> {
  final repository = NoteSubjectRepository.instance;
  final searchController = TextEditingController();

  List<Map<String, Object?>> subjects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    subjects = await repository.getAllSubjects();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();

    final filtered = subjects.where((item) {
      final name = item['subject_name']?.toString() ?? '';

      return query.isEmpty || name.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .8,
        child: Column(
          children: [
            ListTile(
              title: const Text('انتخاب موضوعات'),
              trailing: IconButton(
                onPressed: widget.onCreate,
                icon: const Icon(Icons.add),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'جستجو',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, index) {
                  final item = filtered[index];
                  final id = item['subject_id'] as int;
                  final name = item['subject_name'].toString();

                  return CheckboxListTile(
                    value: widget.selected.contains(id),
                    title: Text(name),
                    onChanged: (value) {
                      if (value == true) {
                        widget.selected.add(id);
                      } else {
                        widget.selected.remove(id);
                      }

                      setState(() {});
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagMultiPicker extends StatefulWidget {
  final Set<String> selected;
  final Future<void> Function() onCreate;

  const _TagMultiPicker({
    required this.selected,
    required this.onCreate,
  });

  @override
  State<_TagMultiPicker> createState() => _TagMultiPickerState();
}

class _TagMultiPickerState extends State<_TagMultiPicker> {
  final repository = NoteTagRepository.instance;
  final searchController = TextEditingController();

  List<Map<String, Object?>> tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    tags = await repository.getAllTags();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();

    final filtered = tags.where((item) {
      final name = item['tag_name']?.toString() ?? '';

      return query.isEmpty || name.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .8,
        child: Column(
          children: [
            ListTile(
              title: const Text('انتخاب برچسب‌ها'),
              trailing: IconButton(
                onPressed: widget.onCreate,
                icon: const Icon(Icons.add),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'جستجو',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, index) {
                  final item = filtered[index];

                  final name = item['tag_name']?.toString() ?? '';

                  return CheckboxListTile(
                    value: widget.selected.contains(name),
                    title: Text(name),
                    onChanged: (value) {
                      if (value == true) {
                        widget.selected.add(name);
                      } else {
                        widget.selected.remove(name);
                      }

                      setState(() {});
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
