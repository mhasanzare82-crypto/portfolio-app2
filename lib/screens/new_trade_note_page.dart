import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/number_formatter.dart' as numbers;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../repositories/note_subject_repository.dart';
import '../repositories/note_tag_repository.dart';
import '../repositories/trade_note_repository.dart';
import 'image_annotation_page.dart';

class _InlineImageTextController extends TextEditingController {
  List<String> imagePaths = [];
  List<String> audioPaths = [];
  double? inlineMaxWidth;
  void Function(String path)? onAudioTap;
  void Function(String path)? onImageTap;

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
        // Keep inline media inside the editable field on both narrow phones
        // and wide desktop layouts. A large WidgetSpan can otherwise overflow
        // the TextField and make the cursor/next paragraph appear displaced.
        final measuredWidth = inlineMaxWidth != null &&
                inlineMaxWidth!.isFinite &&
                inlineMaxWidth! > 0
            ? inlineMaxWidth!
            : MediaQuery.sizeOf(context).width;
        final availableWidth = measuredWidth > 0 ? measuredWidth : 1.0;
        // عرض تصویر از عرض واقعی ویرایشگر محاسبه می‌شود؛ حداقل ثابت ۱۸۰
        // پیکسل روی گوشی‌های باریک باعث سرریز و جابه‌جایی مکان‌نما می‌شد.
        final imageWidth =
            (availableWidth - 36).clamp(1.0, availableWidth).toDouble();
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: path.isNotEmpty && File(path).existsSync()
                ? GestureDetector(
                    onTap: () => onImageTap?.call(path),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: imageWidth,
                        maxHeight: 360,
                      ),
                      child: Image.file(
                        File(path),
                        width: imageWidth,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 120,
                          height: 80,
                          child:
                              Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    ),
                  )
                : SizedBox(
                    width: imageWidth,
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
            child: SizedBox(
              width: 156,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: path.isEmpty ? null : () => onAudioTap?.call(path),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(
                  path.isEmpty ? 'ویس در دسترس نیست' : 'پخش ویس',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

class NewTradeNotePage extends StatefulWidget {
  final Map<String, dynamic>? note;
  final bool embedded;
  final VoidCallback? onSaved;
  final String? initialSearchTerm;
  final String? initialMatchField;
  final int? initialMatchOffset;

  const NewTradeNotePage({
    super.key,
    this.note,
    this.embedded = false,
    this.onSaved,
    this.initialSearchTerm,
    this.initialMatchField,
    this.initialMatchOffset,
  });

  @override
  State<NewTradeNotePage> createState() => _NewTradeNotePageState();
}

class _NewTradeNotePageState extends State<NewTradeNotePage> {
  final _repository = TradeNoteRepository.instance;
  final _subjectRepository = NoteSubjectRepository.instance;
  final _tagRepository = NoteTagRepository.instance;

  final _titleController = TextEditingController();
  final _InlineImageTextController _contentController =
      _InlineImageTextController();
  final _assetController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  final ScrollController _contentScrollController = ScrollController();

  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingAudioPath;
  bool _audioIsPlaying = false;

  // رسانه‌هایی که در همین صفحه انتخاب شده‌اند
  final List<String> _imagePaths = [];
  final List<String> _audioPaths = [];

  // رسانه‌هایی که قبلاً در دیتابیس ذخیره شده‌اند
  List<Map<String, Object?>> _existingMedia = [];

  // شناسه رسانه‌هایی که در حال حذف هستند
  final Set<int> _deletingMediaIds = {};

  List<Map<String, Object?>> _subjects = [];
  List<Map<String, Object?>> _tags = [];

  final Set<int> _selectedSubjectIds = {};
  final Set<String> _selectedTagNames = {};

  bool _saving = false;
  bool _recording = false;
  bool _loadingExistingMedia = false;

  @override
  void initState() {
    super.initState();
    _contentController.onAudioTap = _toggleAudioPlayback;
    _contentController.onImageTap = _editInlineImage;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      _subjects = await _subjectRepository.getAllSubjects();
    } catch (e) {
      debugPrint('خطا در بارگذاری موضوعات: $e');
      _subjects = [];
    }

    try {
      _tags = await _tagRepository.getAllTags();
    } catch (e) {
      debugPrint('خطا در بارگذاری برچسب‌ها: $e');
      _tags = [];
    }

    final note = widget.note;

    if (note != null) {
      _titleController.text = note['title']?.toString() ?? '';
      _contentController.text = note['content']?.toString() ?? '';
      _assetController.text = note['asset_symbol']?.toString() ?? '';

      final noteId = (note['id'] as num).toInt();

      if (mounted) {
        setState(() {
          _loadingExistingMedia = true;
        });
      }

      try {
        final media = await _repository.getMediaForNote(noteId);

        if (mounted) {
          setState(() {
            _existingMedia = media
                .map<Map<String, Object?>>(
                  (item) => Map<String, Object?>.from(item),
                )
                .toList();
            _contentController.imagePaths = _existingMedia
                .where((item) => item['media_type']?.toString() == 'image')
                .map((item) => item['file_path']?.toString() ?? '')
                .toList();
            _contentController.audioPaths = _existingMedia
                .where((item) => item['media_type']?.toString() == 'audio')
                .map((item) => item['file_path']?.toString() ?? '')
                .toList();

            // یادداشت‌های قدیمی ممکن است رسانه را فقط در جدول پیوست‌ها داشته
            // باشند و نشانگر در متن نداشته باشند. نشانگرهای مفقود را به انتهای
            // متن اضافه می‌کنیم تا از این پس رسانه‌ها داخل جریان متن دیده شوند.
            _ensureInlineMediaMarkers();
            _loadingExistingMedia = false;
          });
        }
      } catch (e) {
        debugPrint('خطا در بارگذاری رسانه‌های یادداشت: $e');

        if (mounted) {
          setState(() {
            _loadingExistingMedia = false;
          });
        }
      }

      try {
        final subjectIds = await _repository.getSubjectIdsForNote(noteId);

        _selectedSubjectIds
          ..clear()
          ..addAll(subjectIds);
      } catch (e) {
        debugPrint('خطا در بارگذاری موضوعات یادداشت: $e');
      }

      try {
        final tagNames = await _repository.getTagNamesForNote(noteId);

        _selectedTagNames
          ..clear()
          ..addAll(tagNames);
      } catch (e) {
        debugPrint('خطا در بارگذاری برچسب‌های یادداشت: $e');
      }
    }

    if (mounted) {
      setState(() {});
      _focusInitialMatch();
    }
  }

  void _ensureInlineMediaMarkers() {
    var currentText = _contentController.text;
    final missingMarkers = <String>[];
    var imageIndex = 0;
    var audioIndex = 0;

    // برای رسانه‌های قدیمی ترتیب ذخیره‌شده در دیتابیس حفظ می‌شود؛
    // ابتدا همه‌ی تصاویر و سپس صداها قرار نمی‌گیرند.
    for (final media in _existingMedia) {
      final type = media['media_type']?.toString();
      if (type == 'image') {
        final marker = String.fromCharCode(0xE000 + imageIndex++);
        if (!currentText.contains(marker)) missingMarkers.add(marker);
      } else if (type == 'audio') {
        final marker = String.fromCharCode(0xF000 + audioIndex++);
        if (!currentText.contains(marker)) missingMarkers.add(marker);
      }
    }

    // رسانه‌های موقتی جدید معمولاً هنگام انتخاب، نشانگر می‌گیرند؛ این حلقه
    // فقط برای بازیابی نشانگر احتمالیِ مفقودشده است.
    for (; imageIndex < _contentController.imagePaths.length; imageIndex++) {
      final marker = String.fromCharCode(0xE000 + imageIndex);
      if (!currentText.contains(marker)) missingMarkers.add(marker);
    }
    for (; audioIndex < _contentController.audioPaths.length; audioIndex++) {
      final marker = String.fromCharCode(0xF000 + audioIndex);
      if (!currentText.contains(marker)) missingMarkers.add(marker);
    }

    if (missingMarkers.isEmpty) return;
    final separator =
        currentText.isNotEmpty && !currentText.endsWith('\n') ? '\n' : '';
    currentText = '$currentText$separator${missingMarkers.join('\n')}';
    _contentController.value = TextEditingValue(
      text: currentText,
      selection: TextSelection.collapsed(offset: currentText.length),
    );
  }

  void _focusInitialMatch() {
    final term = widget.initialSearchTerm;
    final field = widget.initialMatchField;

    if (term == null || term.isEmpty || field != 'content') return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final content = _contentController.text;
      final offset = widget.initialMatchOffset;

      if (offset == null || offset < 0 || offset >= content.length) return;

      final end = (offset + term.length).clamp(0, content.length).toInt();
      _contentController.selection = TextSelection(
        baseOffset: offset,
        extentOffset: end,
      );
      _contentFocusNode.requestFocus();

      if (_contentScrollController.hasClients) {
        final estimatedOffset = (offset / 40) * 24.0;
        _contentScrollController.jumpTo(
          estimatedOffset
              .clamp(
                0.0,
                _contentScrollController.position.maxScrollExtent,
              )
              .toDouble(),
        );
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _assetController.dispose();
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _editInlineImage(String path) async {
    try {
      final editedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => ImageAnnotationPage(imagePath: path)),
      );
      if (editedPath == null || !mounted) return;

      final imageIndex = _contentController.imagePaths.indexOf(path);
      if (imageIndex < 0) return;

      var replacementPath = editedPath;
      if (_imagePaths.contains(path)) {
        final pendingIndex = _imagePaths.indexOf(path);
        _imagePaths[pendingIndex] = editedPath;
      } else if (widget.note != null) {
        final noteId = (widget.note!['id'] as num).toInt();
        final matches = _existingMedia
            .where((item) =>
                item['media_type']?.toString() == 'image' &&
                item['file_path']?.toString() == path)
            .toList();
        if (matches.isNotEmpty) {
          final media = matches.first;
          final saved = await _repository.copyMediaToNoteStorage(
            noteId: noteId,
            sourcePath: editedPath,
            mediaType: 'image',
            extension: p.extension(editedPath),
          );
          final rawMediaId = media['media_id'];
          if (rawMediaId is num) {
            final mediaId = rawMediaId.toInt();
            await _repository.updateMediaPath(
              mediaId: mediaId,
              filePath: saved,
              fileName: p.basename(saved),
            );
            final mediaIndex = _existingMedia.indexWhere(
              (item) => item['media_id'] == mediaId,
            );
            if (mediaIndex >= 0) {
              _existingMedia[mediaIndex] = {
                ..._existingMedia[mediaIndex],
                'file_path': saved,
                'file_name': p.basename(saved),
              };
            }
            // باید مسیر آرایه‌ی نشانگر هم با مسیر ثبت‌شده در دیتابیس یکی باشد؛
            // در غیر این صورت حذف یا ویرایش بعدی تصویر آن را پیدا نمی‌کند.
            replacementPath = saved;
          }
        }
      }

      setState(() {
        _contentController.imagePaths[imageIndex] = replacementPath;
      });
    } catch (e) {
      _message('ویرایش تصویر ناموفق بود: $e');
    }
  }

  void _removeInlineImageByPath(String path) {
    final index = _contentController.imagePaths.indexOf(path);
    if (index < 0) return;
    final oldText = _contentController.text;
    final out = StringBuffer();
    for (final rune in oldText.runes) {
      if (rune == 0xE000 + index) continue;
      if (rune > 0xE000 + index &&
          rune < 0xE000 + _contentController.imagePaths.length) {
        out.write(String.fromCharCode(rune - 1));
      } else {
        out.write(String.fromCharCode(rune));
      }
    }
    final updated = out.toString();
    final selectionOffset = _contentController.selection.baseOffset
        .clamp(0, updated.length)
        .toInt();
    _contentController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: selectionOffset),
    );
    _contentController.imagePaths.removeAt(index);
  }

  void _removeInlineAudioByPath(String path) {
    final index = _contentController.audioPaths.indexOf(path);
    if (index < 0) return;
    final updated = StringBuffer();
    for (final rune in _contentController.text.runes) {
      if (rune == 0xF000 + index) continue;
      if (rune > 0xF000 + index &&
          rune < 0xF000 + _contentController.audioPaths.length) {
        updated.write(String.fromCharCode(rune - 1));
      } else {
        updated.write(String.fromCharCode(rune));
      }
    }
    final text = updated.toString();
    _contentController.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    _contentController.audioPaths.removeAt(index);
  }

  void _insertAudioAtCursor(String path) {
    final oldText = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, oldText.length).toInt()
        : oldText.length;
    final end = selection.isValid
        ? selection.end.clamp(start, oldText.length).toInt()
        : oldText.length;
    final before = oldText.substring(0, start);
    final after = oldText.substring(end);

    final index = _contentController.audioPaths.length;
    _contentController.audioPaths.add(path);
    final marker = String.fromCharCode(0xF000 + index);
    final prefix = before.isNotEmpty && !before.endsWith('\n') ? '\n' : '';
    final suffix = after.isEmpty || !after.startsWith('\n') ? '\n' : '';
    final inserted = '$prefix$marker$suffix';
    final newText = '$before$inserted$after';
    final cursorOffset = (start +
            inserted.length +
            (suffix.isEmpty && after.startsWith('\n') ? 1 : 0))
        .clamp(0, newText.length)
        .toInt();
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    _contentFocusNode.requestFocus();
  }

  // تأیید حذف یک رسانه ذخیره‌شده
  Future<bool> _confirmDeleteMedia({
    required String name,
    required String type,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('حذف رسانه'),
          content: Text(
            'آیا از حذف این $type مطمئن هستید؟\n\n$name\n\n'
            'این عملیات فایل رسانه را از حافظه گوشی و رکورد آن را '
            'از دیتابیس حذف می‌کند.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  // حذف امن رسانه ذخیره‌شده با استفاده از مخزن دیتابیس
  Future<void> _deleteExistingMedia(
    Map<String, Object?> media,
  ) async {
    if (_saving) return;

    final rawId = media['media_id'];

    if (rawId is! num) {
      _message('شناسه این رسانه معتبر نیست؛ رسانه حذف نشد.');
      return;
    }

    final mediaId = rawId.toInt();

    if (_deletingMediaIds.contains(mediaId)) return;

    final mediaType = media['media_type']?.toString() ?? '';
    final isImage = mediaType == 'image';
    final isAudio = mediaType == 'audio';

    if (!isImage && !isAudio) {
      _message('نوع این رسانه برای حذف پشتیبانی نمی‌شود.');
      return;
    }

    final path = media['file_path']?.toString() ?? '';
    final storedName = media['file_name']?.toString() ?? '';
    final name = storedName.isNotEmpty
        ? storedName
        : (path.isNotEmpty ? p.basename(path) : 'رسانه بدون نام');

    final confirmed = await _confirmDeleteMedia(
      name: name,
      type: isImage ? 'تصویر' : 'فایل صوتی',
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _deletingMediaIds.add(mediaId);
    });

    try {
      // حذف از حافظه و دیتابیس توسط repository انجام می‌شود.
      await _repository.deleteMedia(mediaId);

      if (!mounted) return;

      setState(() {
        if (isImage) _removeInlineImageByPath(path);
        if (isAudio) _removeInlineAudioByPath(path);
        _existingMedia.removeWhere((item) {
          final itemId = item['media_id'];
          return itemId is num && itemId.toInt() == mediaId;
        });

        _deletingMediaIds.remove(mediaId);
      });

      _message(
        isImage ? 'تصویر حذف شد.' : 'فایل صوتی حذف شد.',
      );
    } catch (e) {
      debugPrint('خطا در حذف رسانه با شناسه $mediaId: $e');

      if (!mounted) return;

      setState(() {
        _deletingMediaIds.remove(mediaId);
      });

      _message('حذف رسانه انجام نشد:\n$e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    final content = _contentController.text;

    if (title.isEmpty) {
      _message('عنوان یادداشت را وارد کنید.');
      return;
    }

    if (content.trim().isEmpty &&
        _imagePaths.isEmpty &&
        _audioPaths.isEmpty &&
        _existingMedia.isEmpty) {
      _message('متن یا رسانه‌ای برای ذخیره وجود ندارد.');
      return;
    }

    if (_recording) {
      _message('ابتدا ضبط صدا را متوقف کنید.');
      return;
    }

    if (_deletingMediaIds.isNotEmpty) {
      _message('لطفاً صبر کنید تا حذف رسانه‌ها تمام شود.');
      return;
    }

    setState(() => _saving = true);

    try {
      final selectedTagIds = _tags
          .where(
            (tag) => _selectedTagNames.contains(
              tag['tag_name']?.toString() ?? '',
            ),
          )
          .map((tag) => (tag['tag_id'] as num).toInt())
          .toList();

      final existingNote = widget.note;
      final int noteId;

      if (existingNote != null) {
        noteId = (existingNote['id'] as num).toInt();

        await _repository.updateNote(
          noteId: noteId,
          title: title,
          content: content,
          assetSymbol: _assetController.text.trim(),
          tagIds: selectedTagIds,
          subjectIds: _selectedSubjectIds.toList(),
        );
      } else {
        noteId = await _repository.createNote(
          title: title,
          content: content,
          assetSymbol: _assetController.text.trim(),
          tagIds: selectedTagIds,
          subjectIds: _selectedSubjectIds.toList(),
        );
      }

      // فقط رسانه‌های جدید ذخیره می‌شوند.
      for (final path in _imagePaths) {
        final saved = await _repository.copyMediaToNoteStorage(
          noteId: noteId,
          sourcePath: path,
          extension: p.extension(path).replaceFirst('.', ''),
        );

        await _repository.addMedia(
          noteId: noteId,
          mediaType: 'image',
          filePath: saved,
          fileName: p.basename(saved),
        );
      }

      for (final path in _audioPaths) {
        final saved = await _repository.copyMediaToNoteStorage(
          noteId: noteId,
          sourcePath: path,
          extension: p.extension(path).replaceFirst('.', ''),
        );

        await _repository.addMedia(
          noteId: noteId,
          mediaType: 'audio',
          filePath: saved,
          fileName: p.basename(saved),
        );
      }

      if (!mounted) return;

      if (widget.embedded) {
        _titleController.clear();
        _contentController.clear();
        _assetController.clear();

        _imagePaths.clear();
        _audioPaths.clear();
        _contentController.imagePaths = [];
        _contentController.audioPaths = [];
        _selectedSubjectIds.clear();
        _selectedTagNames.clear();
        _existingMedia.clear();

        await _loadInitialData();

        if (mounted) {
          widget.onSaved?.call();

          _message('یادداشت ذخیره شد.');
        }
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _message('خطا در ذخیره یادداشت:\n$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      // محدوده‌ی انتخاب‌شده و مکان‌نما قبل از بازشدن انتخاب‌گر ثبت می‌شود؛
      // بنابراین بازگشت از انتخاب‌گر/صفحه‌ی نشانه‌گذاری مکان درج را جابه‌جا نمی‌کند.
      final selection = _contentController.selection;
      final originalText = _contentController.text;
      final insertionStart = selection.isValid
          ? selection.start.clamp(0, originalText.length).toInt()
          : originalText.length;
      final insertionEnd = selection.isValid
          ? selection.end.clamp(insertionStart, originalText.length).toInt()
          : originalText.length;

      final images = await _imagePicker.pickMultiImage(imageQuality: 90);
      if (!mounted || images.isEmpty) return;

      final markerCodes = <String>[];
      for (final image in images) {
        final annotated = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ImageAnnotationPage(imagePath: image.path),
          ),
        );
        if (!mounted) return;
        final path = annotated ?? image.path;
        final imageIndex = _contentController.imagePaths.length;
        setState(() {
          _imagePaths.add(path);
          _contentController.imagePaths.add(path);
        });
        markerCodes.add(String.fromCharCode(0xE000 + imageIndex));
      }

      final before = originalText.substring(0, insertionStart);
      final after = originalText.substring(insertionEnd);
      final prefix = before.isNotEmpty && !before.endsWith('\n') ? '\n' : '';
      final suffix = after.isEmpty || !after.startsWith('\n') ? '\n' : '';
      final markerText = markerCodes.join('\n');
      final inserted = '$prefix$markerText$suffix';
      final newText = '$before$inserted$after';
      // اگر متن بعدی از قبل با newline شروع می‌شود، مکان‌نما را از آن هم
      // عبور می‌دهیم تا تایپ بعد از تصویر و در خط بعدی ادامه پیدا کند.
      final cursorOffset = (insertionStart +
              inserted.length +
              (suffix.isEmpty && after.startsWith('\n') ? 1 : 0))
          .clamp(0, newText.length)
          .toInt();
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursorOffset),
      );
      _contentFocusNode.requestFocus();
    } catch (e) {
      _message('خطا در انتخاب یا ویرایش تصاویر:\n$e');
    }
  }

  Future<void> _toggleAudioPlayback(String path) async {
    if (!File(path).existsSync()) {
      _message('فایل صوتی پیدا نشد.');
      return;
    }
    try {
      if (_playingAudioPath == path && _audioIsPlaying) {
        await _audioPlayer.pause();
        if (mounted) setState(() => _audioIsPlaying = false);
        return;
      }
      if (_playingAudioPath == path) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(path));
      }
      if (mounted)
        setState(() {
          _playingAudioPath = path;
          _audioIsPlaying = true;
        });
      _audioPlayer.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _audioIsPlaying = false);
      });
    } catch (e) {
      _message('پخش فایل صوتی انجام نشد: $e');
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (!mounted ||
          result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return;
      }

      final path = result.files.single.path!;
      setState(() => _audioPaths.add(path));
      _insertAudioAtCursor(path);
    } catch (e) {
      _message('خطا در انتخاب فایل صوتی:\n$e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      try {
        final path = await _audioRecorder.stop();

        if (!mounted) return;

        setState(() {
          _recording = false;

          if (path != null && path.isNotEmpty) {
            _audioPaths.add(path);
          }
        });
        if (path != null && path.isNotEmpty) _insertAudioAtCursor(path);

        if (path == null || path.isEmpty) {
          _message('فایل ضبط‌شده ایجاد نشد.');
        }
      } catch (e) {
        if (mounted) {
          setState(() => _recording = false);
        }
        _message('خطا در توقف ضبط صدا:\n$e');
      }

      return;
    }

    try {
      final hasPermission = await _audioRecorder.hasPermission();

      if (!hasPermission) {
        _message('دسترسی میکروفون داده نشده است.');
        return;
      }

      final directory = await getTemporaryDirectory();

      final path = p.join(
        directory.path,
        'trade_note_${DateTime.now().microsecondsSinceEpoch}.m4a',
      );

      await _audioRecorder.start(
        const RecordConfig(),
        path: path,
      );

      if (!mounted) {
        await _audioRecorder.stop();
        return;
      }

      setState(() => _recording = true);
    } catch (e) {
      _message('خطا در شروع ضبط صدا:\n$e');
    }
  }

  Future<void> _selectSubjects() async {
    final selected = Set<int>.from(_selectedSubjectIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _SubjectPicker(
          selectedIds: selected,
          onChanged: (id, value) {
            if (value) {
              selected.add(id);
            } else {
              selected.remove(id);
            }
          },
          onCreate: () async {
            final name = await _textDialog(
              title: 'موضوع جدید',
              label: 'نام موضوع',
            );

            if (name == null || name.isEmpty) return;

            try {
              final id = await _subjectRepository.createSubject(
                name: name,
              );

              selected.add(id);
              await _loadSubjects();
            } catch (e) {
              _message('خطا در ایجاد موضوع:\n$e');
            }
          },
        );
      },
    );

    if (!mounted) return;

    setState(() {
      _selectedSubjectIds
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _selectTags() async {
    final selected = Set<String>.from(_selectedTagNames);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _TagPicker(
          selectedNames: selected,
          onChanged: (name, value) {
            if (value) {
              selected.add(name);
            } else {
              selected.remove(name);
            }
          },
          onCreate: () async {
            final name = await _textDialog(
              title: 'برچسب جدید',
              label: 'نام برچسب',
            );

            if (name == null || name.isEmpty) return;

            try {
              final id = await _tagRepository.createTag(name);
              final tag = await _tagRepository.getTag(id);

              if (tag != null) {
                selected.add(
                  tag['tag_name']?.toString() ?? name,
                );
              }

              await _loadTags();
            } catch (e) {
              _message('خطا در ایجاد برچسب:\n$e');
            }
          },
        );
      },
    );

    if (!mounted) return;

    setState(() {
      _selectedTagNames
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await _subjectRepository.getAllSubjects();

      if (!mounted) return;

      setState(() {
        _subjects = subjects;
      });
    } catch (e) {
      debugPrint('خطا در بارگذاری موضوعات: $e');
      _message('خطا در بارگذاری موضوعات.');
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _tagRepository.getAllTags();

      if (!mounted) return;

      setState(() {
        _tags = tags;
      });
    } catch (e) {
      debugPrint('خطا در بارگذاری برچسب‌ها: $e');
      _message('خطا در بارگذاری برچسب‌ها.');
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
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

  void _message(String value) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Widget _buildExistingMedia() {
    if (_loadingExistingMedia) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_existingMedia.isEmpty) {
      return const SizedBox.shrink();
    }

    final images = _existingMedia.where((media) {
      return media['media_type']?.toString() == 'image';
    }).toList();

    final audios = _existingMedia.where((media) {
      return media['media_type']?.toString() == 'audio';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'رسانه‌های ذخیره‌شده',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),

        // تصاویر ذخیره‌شده
        if (images.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final media = images[index];
                final path = media['file_path']?.toString() ?? '';
                final file = File(path);

                final rawId = media['media_id'];
                final mediaId = rawId is num ? rawId.toInt() : -1;
                final deleting = _deletingMediaIds.contains(mediaId);

                return SizedBox(
                  width: 100,
                  height: 120,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 20,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: file.existsSync()
                              ? Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return _mediaErrorTile(
                                      Icons.broken_image_outlined,
                                      'تصویر در دسترس نیست',
                                    );
                                  },
                                )
                              : _mediaErrorTile(
                                  Icons.broken_image_outlined,
                                  'فایل پیدا نشد',
                                ),
                        ),
                      ),
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withOpacity(0.92),
                          shape: const CircleBorder(),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: deleting
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : IconButton(
                                    padding: EdgeInsets.zero,
                                    tooltip: 'حذف تصویر',
                                    iconSize: 18,
                                    onPressed: _saving
                                        ? null
                                        : () => _deleteExistingMedia(media),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Text(
                          'تصویر ذخیره‌شده',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],

        // فایل‌های صوتی ذخیره‌شده
        if (audios.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...audios.map((media) {
            final path = media['file_path']?.toString() ?? '';

            final name = media['file_name']?.toString().isNotEmpty == true
                ? media['file_name'].toString()
                : p.basename(path);

            final exists = path.isNotEmpty && File(path).existsSync();

            final rawId = media['media_id'];
            final mediaId = rawId is num ? rawId.toInt() : -1;
            final deleting = _deletingMediaIds.contains(mediaId);

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                exists ? Icons.audiotrack_outlined : Icons.audio_file_outlined,
              ),
              title: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                exists ? 'ذخیره‌شده' : 'فایل در مسیر ثبت‌شده پیدا نشد',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _playingAudioPath == path && _audioIsPlaying
                        ? 'مکث'
                        : 'پخش',
                    onPressed: exists ? () => _toggleAudioPlayback(path) : null,
                    icon: Icon(_playingAudioPath == path && _audioIsPlaying
                        ? Icons.pause
                        : Icons.play_arrow),
                  ),
                  deleting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          tooltip: 'حذف فایل صوتی',
                          onPressed: _saving
                              ? null
                              : () => _deleteExistingMedia(media),
                          icon: Icon(Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error),
                        ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _mediaErrorTile(IconData icon, String text) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _mediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'رسانه',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickImages,
              icon: const Icon(Icons.image_outlined),
              label: const Text('افزودن عکس'),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickAudioFile,
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('فایل صوتی'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _toggleRecording,
              icon: Icon(
                _recording ? Icons.stop : Icons.mic_none_outlined,
              ),
              label: Text(
                _recording ? 'توقف ضبط' : 'ضبط ویس',
              ),
            ),
          ],
        ),

        // رسانه‌های ذخیره‌شده
        _buildExistingMedia(),

        // تصاویر جدید انتخاب‌شده
        if (_imagePaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('تصاویر جدید'),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              itemBuilder: (context, index) {
                final path = _imagePaths[index];

                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(path),
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 90,
                              height: 90,
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: CircleAvatar(
                          radius: 14,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() {
                                      _removeInlineImageByPath(path);
                                      _imagePaths.removeAt(index);
                                    });
                                  },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],

        // فایل‌های صوتی جدید انتخاب‌شده
        if (_audioPaths.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('فایل‌های صوتی جدید'),
          ...List.generate(
            _audioPaths.length,
            (index) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.audiotrack_outlined),
                title: Text(
                  p.basename(_audioPaths[index]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _playingAudioPath == _audioPaths[index] &&
                              _audioIsPlaying
                          ? 'مکث'
                          : 'پخش',
                      onPressed: () => _toggleAudioPlayback(_audioPaths[index]),
                      icon: Icon(_playingAudioPath == _audioPaths[index] &&
                              _audioIsPlaying
                          ? Icons.pause
                          : Icons.play_arrow),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _audioPaths.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final formChildren = <Widget>[
      TextField(
        controller: _titleController,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(
          labelText: 'عنوان',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _assetController,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(
          labelText: 'دارایی',
          hintText: 'مثلاً GOLDUSDT',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectSubjects,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(
                _selectedSubjectIds.isEmpty
                    ? 'انتخاب موضوع'
                    : '${numbers.formatInteger(_selectedSubjectIds.length)} موضوع انتخاب شده',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'موضوع جدید',
            onPressed: () async {
              final name = await _textDialog(
                title: 'موضوع جدید',
                label: 'نام موضوع',
              );

              if (name == null || name.isEmpty) return;

              try {
                final id = await _subjectRepository.createSubject(
                  name: name,
                );

                if (!mounted) return;

                setState(() {
                  _selectedSubjectIds.add(id);
                });

                await _loadSubjects();
              } catch (e) {
                _message('خطا در ایجاد موضوع:\n$e');
              }
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _selectedSubjectIds.map((id) {
          final matching = _subjects.where(
            (subject) => (subject['subject_id'] as num?)?.toInt() == id,
          );

          final name = matching.isEmpty
              ? id.toString()
              : matching.first['subject_name']?.toString() ?? id.toString();

          return Chip(
            label: Text(name),
            onDeleted: () {
              setState(() {
                _selectedSubjectIds.remove(id);
              });
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectTags,
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(
                _selectedTagNames.isEmpty
                    ? 'انتخاب برچسب'
                    : '${numbers.formatInteger(_selectedTagNames.length)} برچسب انتخاب شده',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'برچسب جدید',
            onPressed: () async {
              final name = await _textDialog(
                title: 'برچسب جدید',
                label: 'نام برچسب',
              );

              if (name == null || name.isEmpty) return;

              try {
                final id = await _tagRepository.createTag(name);
                final tag = await _tagRepository.getTag(id);

                if (!mounted) return;

                setState(() {
                  _selectedTagNames.add(
                    tag?['tag_name']?.toString() ?? name,
                  );
                });

                await _loadTags();
              } catch (e) {
                _message('خطا در ایجاد برچسب:\n$e');
              }
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _selectedTagNames.map((tag) {
          return Chip(
            label: Text(tag),
            onDeleted: () {
              setState(() {
                _selectedTagNames.remove(tag);
              });
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          _contentController.inlineMaxWidth = constraints.maxWidth;
          return TextField(
            controller: _contentController,
            focusNode: _contentFocusNode,
            scrollController: _contentScrollController,
            minLines: 12,
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
      _mediaSection(),
    ];

    // حالت توکار: بدون Scaffold و بدون اسکرول داخلی
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...formChildren,
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('ذخیره یادداشت'),
              ),
            ),
          ],
        ),
      );
    }

    // حالت مستقل: صفحه معمولی یادداشت
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.note == null ? 'یادداشت جدید' : 'ویرایش یادداشت',
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            tooltip: 'ذخیره یادداشت',
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: formChildren,
      ),
    );
  }
}

// ============================================================
// انتخاب موضوعات
// ============================================================
class _SubjectPicker extends StatefulWidget {
  final Set<int> selectedIds;
  final void Function(int id, bool value) onChanged;
  final Future<void> Function() onCreate;

  const _SubjectPicker({
    required this.selectedIds,
    required this.onChanged,
    required this.onCreate,
  });

  @override
  State<_SubjectPicker> createState() => _SubjectPickerState();
}

class _SubjectPickerState extends State<_SubjectPicker> {
  final repository = NoteSubjectRepository.instance;
  final controller = TextEditingController();

  List<Map<String, Object?>> roots = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      roots = await repository.getRootSubjects();
    } catch (e) {
      debugPrint('خطا در بارگذاری فهرست موضوعات: $e');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim().toLowerCase();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'موضوعات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await widget.onCreate();
                      await _load();
                    },
                    tooltip: 'موضوع جدید',
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: controller,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'جستجوی موضوع',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : roots.isEmpty
                      ? const Center(
                          child: Text('هنوز موضوعی ثبت نشده است.'),
                        )
                      : ListView(
                          children: roots.map((root) {
                            final name = root['subject_name']?.toString() ?? '';

                            final matches = query.isEmpty ||
                                name.toLowerCase().contains(query);

                            if (!matches && query.isNotEmpty) {
                              return const SizedBox.shrink();
                            }

                            return _SubjectNode(
                              key: ValueKey(root['subject_id']),
                              subject: root,
                              selectedIds: widget.selectedIds,
                              onChanged: widget.onChanged,
                            );
                          }).toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectNode extends StatefulWidget {
  final Map<String, Object?> subject;
  final Set<int> selectedIds;
  final void Function(int id, bool value) onChanged;

  const _SubjectNode({
    super.key,
    required this.subject,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<_SubjectNode> createState() => _SubjectNodeState();
}

class _SubjectNodeState extends State<_SubjectNode> {
  final repository = NoteSubjectRepository.instance;

  List<Map<String, Object?>> children = [];
  bool expanded = false;
  bool loading = true;

  int get id => (widget.subject['subject_id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    try {
      children = await repository.getChildren(id);
    } catch (e) {
      debugPrint('خطا در بارگذاری زیرموضوعات: $e');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: PageStorageKey('subject_$id'),
      initiallyExpanded: expanded,
      onExpansionChanged: (value) {
        setState(() => expanded = value);
      },
      leading: Checkbox(
        value: widget.selectedIds.contains(id),
        onChanged: (value) {
          widget.onChanged(id, value ?? false);
          setState(() {});
        },
      ),
      title: Text(
        widget.subject['subject_name']?.toString() ?? '',
      ),
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ...children.map((child) {
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: _SubjectNode(
              key: ValueKey(child['subject_id']),
              subject: child,
              selectedIds: widget.selectedIds,
              onChanged: widget.onChanged,
            ),
          );
        }),
      ],
    );
  }
}

class _TagPicker extends StatefulWidget {
  final Set<String> selectedNames;
  final void Function(String name, bool value) onChanged;
  final Future<void> Function() onCreate;

  const _TagPicker({
    required this.selectedNames,
    required this.onChanged,
    required this.onCreate,
  });

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  final repository = NoteTagRepository.instance;
  final controller = TextEditingController();

  List<Map<String, Object?>> tags = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      tags = await repository.getAllTags();
    } catch (e) {
      debugPrint('خطا در بارگذاری برچسب‌ها: $e');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim().toLowerCase();

    final filtered = tags.where((tag) {
      final name = tag['tag_name']?.toString() ?? '';
      return query.isEmpty || name.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'برچسب‌ها',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await widget.onCreate();
                      await _load();
                    },
                    tooltip: 'برچسب جدید',
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: controller,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'جستجوی برچسب',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('برچسبی پیدا نشد.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final tag = filtered[index];
                            final name = tag['tag_name']?.toString() ?? '';

                            return CheckboxListTile(
                              value: widget.selectedNames.contains(name),
                              title: Text(name),
                              onChanged: (value) {
                                widget.onChanged(name, value ?? false);
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
