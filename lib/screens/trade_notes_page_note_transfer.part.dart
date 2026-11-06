part of 'trade_notes_page.dart';

extension _TradeNotesTransferMethods on _NewTradePageState {
  // ZIP / DOCX backup and custom typography
  Future<void> _loadNoteDisplaySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble('trade_notes_font_size') ?? 14;
    final fontPath = prefs.getString('trade_notes_custom_font_path');
    String? loadedPath;
    if (fontPath != null && await File(fontPath).exists()) {
      try {
        final bytes = await File(fontPath).readAsBytes();
        await (services.FontLoader(_customNoteFontFamily)
              ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
            .load();
        loadedPath = fontPath;
      } catch (error) {
        debugPrint('Custom font load failed: $error');
      }
    }
    if (!mounted) return;
    setState(() {
      _noteFontSize = size.clamp(8.0, 32.0).toDouble();
      _customNoteFontPath = loadedPath;
    });
  }

  Future<void> _showNoteFontSettings() async {
    var size = _noteFontSize;
    final selected = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تنظیم فونت یادداشت‌ها'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('اندازه نوشته: ${size.round()} px'),
            Slider(
              min: 8, max: 32, divisions: 24, value: size,
              label: '${size.round()} px',
              onChanged: (value) => setDialogState(() => size = value),
            ),
            const Text('اندازه از ۸ تا ۳۲ پیکسل، با گام یک‌واحدی'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _pickCustomNoteFont();
              },
              icon: const Icon(Icons.font_download_outlined),
              label: const Text('افزودن فونت TTF / OTF'),
            ),
            if (_customNoteFontPath != null)
              Text(p.basename(_customNoteFontPath!), maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('لغو')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, size),
                child: const Text('ذخیره')),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('trade_notes_font_size', selected);
    if (mounted) setState(() => _noteFontSize = selected);
  }

  Future<void> _pickCustomNoteFont() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['ttf', 'otf'], withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) throw Exception('فایل فونت خالی است.');
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(docs.path, 'custom_fonts'));
      await folder.create(recursive: true);
      final ext = p.extension(picked.name).toLowerCase();
      final target = p.join(folder.path,
          'notes_font_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(target).writeAsBytes(bytes, flush: true);
      await (services.FontLoader(_customNoteFontFamily)
            ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
          .load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trade_notes_custom_font_path', target);
      if (!mounted) return;
      setState(() => _customNoteFontPath = target);
      _showMessage('فونت سفارشی اضافه شد.');
    } catch (error) {
      _showMessage('خطا در افزودن فونت: $error');
    }
  }

  Future<void> _exportNotesZip() async {
    if (_noteTransferInProgress) return;
    setState(() => _noteTransferInProgress = true);
    try {
      final notes = await _tradeNoteRepository.getAllNotes();
      final archive = Archive();
      final exported = <Map<String, dynamic>>[];
      for (final raw in notes) {
        final note = Map<String, dynamic>.from(raw);
        final id = note['id'] is num ? (note['id'] as num).toInt() : 0;
        note['export_subject_names'] =
            id > 0 ? await _tradeNoteRepository.getSubjectNamesForNote(id) : [];
        note['export_tag_names'] =
            id > 0 ? await _tradeNoteRepository.getTagNamesForNote(id) : [];
        final mediaManifest = <Map<String, dynamic>>[];
        if (id > 0) {
          final media = await _tradeNoteRepository.getMediaForNote(id);
          for (var i = 0; i < media.length; i++) {
            final item = media[i];
            final path = item['file_path']?.toString() ?? '';
            final source = File(path);
            if (!await source.exists()) continue;
            final archivePath = 'media/$id/${i}_${p.basename(path)}';
            final data = await source.readAsBytes();
            archive.addFile(ArchiveFile(archivePath, data.length, data));
            mediaManifest.add({
              'archive_path': archivePath,
              'media_type': item['media_type']?.toString() ?? 'image',
              'file_name': item['file_name']?.toString() ?? p.basename(path),
              'media_order': item['media_order'] ?? i,
            });
          }
        }
        note['export_media'] = mediaManifest;
        exported.add(note);
      }
      final jsonBytes = utf8.encode(jsonEncode({
        'format': 'portfolio_trade_notes', 'version': 1, 'notes': exported,
      }));
      archive.addFile(ArchiveFile('notes.json', jsonBytes.length, jsonBytes));
      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) throw Exception('ساخت ZIP ناموفق بود.');
      final temp = await getTemporaryDirectory();
      final output = File(p.join(temp.path,
          'trade_notes_backup_${DateTime.now().millisecondsSinceEpoch}.zip'));
      await output.writeAsBytes(zipped, flush: true);
      await Share.shareXFiles([XFile(output.path)],
          text: 'پشتیبان یادداشت‌های معاملاتی');
      _showMessage('فایل ZIP آماده شد.');
    } catch (error) {
      _showMessage('خطا در خروجی ZIP: $error');
    } finally {
      if (mounted) setState(() => _noteTransferInProgress = false);
    }
  }

  Future<void> _importNotesZip() async {
    if (_noteTransferInProgress) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      setState(() => _noteTransferInProgress = true);
      final picked = selection.files.single;
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw Exception('خواندن فایل ممکن نشد.');
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? lookup(String name) {
        for (final entry in archive.files) {
          if (entry.name == name) return entry;
        }
        return null;
      }
      final manifest = lookup('notes.json');
      if (manifest == null) throw Exception('این ZIP پشتیبان یادداشت نیست.');
      final data = jsonDecode(utf8.decode(manifest.content as List<int>));
      if (data is! Map || data['format'] != 'portfolio_trade_notes' ||
          data['notes'] is! List) throw Exception('ساختار ZIP معتبر نیست.');
      final docs = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(docs.path, 'imported_note_media'));
      await mediaDir.create(recursive: true);
      var count = 0;
      for (final raw in data['notes'] as List) {
        if (raw is! Map) continue;
        final note = Map<String, dynamic>.from(raw);
        final newId = await _tradeNoteRepository.createNote(
          title: note['title']?.toString() ?? 'یادداشت واردشده',
          content: note['content']?.toString() ?? '',
          subject: note['subject']?.toString(),
          noteType: note['note_type']?.toString(),
          assetSymbol: note['asset_symbol']?.toString(),
          source: note['source']?.toString(),
          sourceFileName: note['source_file_name']?.toString(),
        );
        final subjectIds = <int>[];
        for (final rawName in (note['export_subject_names'] as List? ?? [])) {
          final name = rawName.toString().trim();
          if (name.isEmpty) continue;
          var subjects = await _noteSubjectRepository.getAllSubjects();
          var match = subjects.where((row) =>
              (row['subject_name']?.toString() ?? '').toLowerCase() == name.toLowerCase());
          if (match.isEmpty) {
            try {
              await _noteSubjectRepository.createSubject(name: name);
            } catch (_) {}
            subjects = await _noteSubjectRepository.getAllSubjects();
            match = subjects.where((row) =>
                (row['subject_name']?.toString() ?? '').toLowerCase() == name.toLowerCase());
          }
          if (match.isNotEmpty) subjectIds.add((match.first['subject_id'] as num).toInt());
        }
        if (subjectIds.isNotEmpty) {
          await _tradeNoteRepository.setNoteSubjects(newId, subjectIds);
        }
        final tagIds = <int>[];
        for (final rawName in (note['export_tag_names'] as List? ?? [])) {
          final name = rawName.toString().trim();
          if (name.isEmpty) continue;
          final tagId = await _noteTagRepository.createTag(name);
          tagIds.add(tagId);
        }
        if (tagIds.isNotEmpty) {
          await _tradeNoteRepository.setNoteTags(newId, tagIds);
        }
        for (final rawMedia in (note['export_media'] as List? ?? [])) {
          if (rawMedia is! Map) continue;
          final archivePath = rawMedia['archive_path']?.toString() ?? '';
          final entry = lookup(archivePath);
          if (entry == null) continue;
          final name = p.basename(rawMedia['file_name']?.toString() ?? 'attachment');
          final target = File(p.join(mediaDir.path,
              '${newId}_${DateTime.now().microsecondsSinceEpoch}_$name'));
          await target.writeAsBytes(entry.content as List<int>, flush: true);
          await _tradeNoteRepository.addMedia(
            noteId: newId,
            mediaType: rawMedia['media_type']?.toString() == 'audio' ? 'audio' : 'image',
            filePath: target.path,
            fileName: name,
            mediaOrder: (rawMedia['media_order'] as num?)?.toInt(),
          );
        }
        count++;
      }
      await _loadTradeNotes();
      _showMessage('$count یادداشت از ZIP وارد شد.');
    } catch (error) {
      _showMessage('خطا در ورود ZIP: $error');
    } finally {
      if (mounted) setState(() => _noteTransferInProgress = false);
    }
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;').replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  Future<void> _exportNotesDocx() async {
    if (_noteTransferInProgress) return;
    setState(() => _noteTransferInProgress = true);
    try {
      final notes = await _tradeNoteRepository.getAllNotes();
      final body = StringBuffer();
      for (final note in notes) {
        body.write('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t xml:space="preserve">${_xmlEscape(note['title']?.toString() ?? 'بدون عنوان')}</w:t></w:r></w:p>');
        for (final line in (note['content']?.toString() ?? '').split(RegExp(r'\r?\n'))) {
          body.write('<w:p><w:r><w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>');
        }
        body.write('<w:p/>');
      }
      final archive = Archive();
      void addXml(String name, String value) {
        final bytes = utf8.encode(value);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
      addXml('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>''');
      addXml('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''');
      addXml('word/document.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>''');
      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) throw Exception('ساخت DOCX ناموفق بود.');
      final temp = await getTemporaryDirectory();
      final output = File(p.join(temp.path,
          'trade_notes_${DateTime.now().millisecondsSinceEpoch}.docx'));
      await output.writeAsBytes(zipped, flush: true);
      await Share.shareXFiles([XFile(output.path)],
          text: 'خروجی Word یادداشت‌های معاملاتی');
      _showMessage('فایل DOCX آماده شد.');
    } catch (error) {
      _showMessage('خطا در خروجی DOCX: $error');
    } finally {
      if (mounted) setState(() => _noteTransferInProgress = false);
    }
  }

  String _decodeXmlText(String value) => value
      .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"').replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  Future<void> _importNotesDocx() async {
    if (_noteTransferInProgress) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['docx'], withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      setState(() => _noteTransferInProgress = true);
      final picked = selection.files.single;
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw Exception('خواندن فایل ممکن نشد.');
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? document;
      for (final entry in archive.files) {
        if (entry.name == 'word/document.xml') { document = entry; break; }
      }
      if (document == null) throw Exception('فایل DOCX معتبر نیست.');
      final xml = utf8.decode(document.content as List<int>);
      final body = RegExp(r'<w:body[^>]*>([\s\S]*?)</w:body>')
          .firstMatch(xml)?.group(1) ?? xml;
      final paragraphs = RegExp(r'<w:p(?:\s[^>]*)?>([\s\S]*?)</w:p>')
          .allMatches(body);
      final lines = <String>[];
      for (final paragraph in paragraphs) {
        final value = RegExp(r'<w:t(?:\s[^>]*)?>([\s\S]*?)</w:t>')
            .allMatches(paragraph.group(1)!)
            .map((match) => _decodeXmlText(match.group(1)!)).join();
        lines.add(value);
      }
      final content = lines.join('\n').trim();
      if (content.isEmpty) throw Exception('متنی در فایل Word پیدا نشد.');
      await _tradeNoteRepository.createNote(
        title: p.basenameWithoutExtension(picked.name).isEmpty
            ? 'یادداشت واردشده از Word'
            : p.basenameWithoutExtension(picked.name),
        content: content,
        noteType: 'واردشده از Word',
        source: 'docx_import',
        sourceFileName: picked.name,
      );
      await _loadTradeNotes();
      _showMessage('محتوای Word به‌صورت یک یادداشت وارد شد.');
    } catch (error) {
      _showMessage('خطا در ورود DOCX: $error');
    } finally {
      if (mounted) setState(() => _noteTransferInProgress = false);
    }
  }
}
