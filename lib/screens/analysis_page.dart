import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docx_dart/docx_dart.dart' as docx;
import 'package:docx_dart/src/shared.dart' show Inches;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';

import '../database/app_database.dart';
import '../models/ticker.dart';
import '../services/lbank_service.dart';
import '../services/notification_service.dart';
import '../utils/number_formatter.dart' as numbers;

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final AppDatabase _database = AppDatabase.instance;
  final Map<String, LBankService> _services = {};
  final Map<String, StreamSubscription<Ticker>> _subscriptions = {};
  final Map<String, double> _prices = {};
  final Map<String, double> _previousPrices = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Map<String, Object?>> _analyses = [];
  bool _loading = true;
  bool _showWebsite = true;
  bool _websiteScrollLocked = false;
  String _websiteUrl = 'https://www.tradingview.com/chart/';
  List<String> _savedWebsites = <String>['https://www.tradingview.com/chart/'];
  final Set<String> _selectedAnalysisIds = <String>{};
  WebViewController? _websiteController;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSavedWebsites();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    for (final service in _services.values) {
      service.dispose();
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSavedWebsites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('analysis_saved_websites') ?? <String>[];
    if (!mounted) return;
    setState(() {
      _savedWebsites =
          <String>{'https://www.tradingview.com/chart/', ...saved}.toList();
    });
  }

  Future<void> _saveWebsite(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      _message('آدرس سایت باید با http:// یا https:// شروع شود.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _savedWebsites = <String>{..._savedWebsites, url}.toList();
    await prefs.setStringList('analysis_saved_websites', _savedWebsites);
    _websiteUrl = url;
    _loadWebsite();
    if (mounted) setState(() {});
  }

  Future<void> _addWebsiteDialog() async {
    final c = TextEditingController(text: 'https://');
    final url = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('افزودن سایت'),
              content: TextField(
                  controller: c,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'آدرس سایت')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('لغو')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, c.text.trim()),
                    child: const Text('ذخیره و نمایش'))
              ],
            ));
    c.dispose();
    if (url != null && url.isNotEmpty) await _saveWebsite(url);
  }

  Future<void> _load() async {
    try {
      final db = await _database.database;
      final rows = await db.query('analyses', orderBy: 'created_at DESC');
      if (!mounted) return;
      setState(() {
        _analyses = rows;
        _loading = false;
      });
      _syncPriceServices();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _message('بارگذاری تحلیل‌ها ناموفق بود: $e');
    }
  }

  void _syncPriceServices() {
    final symbols = <String>{'GOLDUSDT'}..addAll(_analyses
        .where((a) =>
            a['status'] == 'valid' &&
            a['target_price'] != null &&
            (a['alert_enabled'] == null ||
                a['alert_enabled'] == 1 ||
                a['alert_enabled'] == true))
        .map((a) =>
            (a['asset_symbol']?.toString() ?? 'GOLDUSDT').toUpperCase()));
    for (final symbol in symbols) {
      if (_services.containsKey(symbol)) continue;
      final service = LBankService();
      _services[symbol] = service;
      _subscriptions[symbol] = service.tickerStream.listen((ticker) {
        if (!mounted) return;
        final previous = _prices[symbol];
        setState(() {
          _previousPrices[symbol] = previous ?? ticker.price;
          _prices[symbol] = ticker.price;
        });
        _checkTargets(symbol, previous, ticker.price);
      });
      service.connect(symbol);
    }
    final removed = _services.keys.where((s) => !symbols.contains(s)).toList();
    for (final symbol in removed) {
      _subscriptions.remove(symbol)?.cancel();
      _services.remove(symbol)?.dispose();
      _prices.remove(symbol);
      _previousPrices.remove(symbol);
    }
  }

  Future<void> _checkTargets(
      String symbol, double? previous, double current) async {
    if (previous == null || previous == current) return;
    final toTrigger = _analyses.where((a) {
      if (a['status'] != 'valid' ||
          (a['alert_enabled'] != null &&
              a['alert_enabled'] != 1 &&
              a['alert_enabled'] != true) ||
          (a['asset_symbol']?.toString() ?? '').toUpperCase() != symbol ||
          a['target_price'] == null) return false;
      final target = (a['target_price'] as num).toDouble();
      return (previous <= target && current >= target) ||
          (previous >= target && current <= target);
    }).toList();
    if (toTrigger.isEmpty) return;
    final db = await _database.database;
    for (final analysis in toTrigger) {
      final id = analysis['analysis_id']?.toString();
      if (id == null) continue;
      await db.update(
          'analyses',
          {
            'status': 'invalid',
            'triggered_at': DateTime.now().toIso8601String(),
          },
          where: 'analysis_id = ?',
          whereArgs: [id]);
      final target = (analysis['target_price'] as num).toDouble();
      final label =
          (analysis['target_title']?.toString().trim().isNotEmpty ?? false)
              ? analysis['target_title'].toString()
              : (analysis['title']?.toString() ?? 'تحلیل');
      try {
        await NotificationService.instance.showPriceAlert(
          symbol: symbol,
          targetPrice: target,
          currentPrice: current,
          title: 'تحلیل فعال شد: $label',
          note: 'قیمت به سطح تعیین‌شده رسید؛ تحلیل به بخش نامعتبر منتقل شد.',
        );
      } catch (_) {}
    }
    await _load();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _newAnalysis() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => _AnalysisEditor(currentPrice: _prices['GOLDUSDT'])),
    );
    if (result == null) return;
    try {
      final db = await _database.database;
      await db.insert('analyses', {
        'analysis_id': DateTime.now().microsecondsSinceEpoch.toString(),
        'asset_symbol': result['symbol'],
        'timeframe': result['timeframe'],
        'title': result['title'],
        'content': result['content'],
        'target_price': result['target_price'],
        'target_title': result['target_title'],
        'alert_enabled': result['alert_enabled'] == false ? 0 : 1,
        'analysis_sections':
            jsonEncode(result['analysis_sections'] ?? <Map<String, dynamic>>[]),
        'website_url': result['website_url'],
        'image_paths': jsonEncode(result['image_paths'] ?? <String>[]),
        'audio_paths': jsonEncode(result['audio_paths'] ?? <String>[]),
        'status': 'valid',
        'created_at': DateTime.now().toIso8601String(),
        'triggered_at': null,
      });
      final site = result['website_url']?.toString().trim() ?? '';
      if (site.isNotEmpty) await _saveWebsite(site);
      await _load();
    } catch (e) {
      _message('ذخیرهٔ تحلیل ناموفق بود: $e');
    }
  }

  Future<void> _editAnalysis(Map<String, Object?> analysis) async {
    final symbol =
        (analysis['asset_symbol']?.toString() ?? 'GOLDUSDT').toUpperCase();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => _AnalysisEditor(
                currentPrice: _prices[symbol],
                initial: analysis,
              )),
    );
    if (result == null) return;
    try {
      final db = await _database.database;
      await db.update(
          'analyses',
          {
            'asset_symbol': result['symbol'],
            'timeframe': result['timeframe'],
            'title': result['title'],
            'content': result['content'],
            'target_price': result['target_price'],
            'target_title': result['target_title'],
            'alert_enabled': result['alert_enabled'] == false ? 0 : 1,
            'analysis_sections': jsonEncode(
                result['analysis_sections'] ?? <Map<String, dynamic>>[]),
            'website_url': result['website_url'],
            'image_paths': jsonEncode(result['image_paths'] ?? <String>[]),
            'audio_paths': jsonEncode(result['audio_paths'] ?? <String>[]),
          },
          where: 'analysis_id = ?',
          whereArgs: [analysis['analysis_id']]);
      final site = result['website_url']?.toString().trim() ?? '';
      if (site.isNotEmpty) await _saveWebsite(site);
      await _load();
    } catch (e) {
      _message('ویرایش تحلیل ناموفق بود: $e');
    }
  }

  void _loadWebsite() {
    final uri = Uri.tryParse(_websiteUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      _message('آدرس سایت باید با http:// یا https:// شروع شود.');
      return;
    }
    _websiteController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(uri);
    if (mounted) setState(() {});
  }

  Future<void> _toggleStatus(Map<String, Object?> analysis) async {
    final id = analysis['analysis_id']?.toString();
    if (id == null) return;
    final next = analysis['status'] == 'valid' ? 'invalid' : 'valid';
    final db = await _database.database;
    await db.update('analyses', {'status': next, 'triggered_at': null},
        where: 'analysis_id = ?', whereArgs: [id]);
    await _load();
  }

  Future<void> _delete(Map<String, Object?> analysis) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف تحلیل'),
        content: Text('تحلیل «${analysis['title'] ?? ''}» حذف شود؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final db = await _database.database;
    await db.delete('analyses',
        where: 'analysis_id = ?', whereArgs: [analysis['analysis_id']]);
    await _load();
  }

  Future<void> _export(Map<String, Object?> a) async {
    try {
      final document = docx.loadDocxDocument();
      document.addHeading(text: 'گزارش تحلیل', level: 1);
      document.addParagraph(text: 'دارایی: ${a['asset_symbol'] ?? ''}');
      document.addParagraph(text: 'تایم‌فریم: ${a['timeframe'] ?? ''}');
      document.addParagraph(text: 'عنوان: ${a['title'] ?? ''}');
      document.addParagraph(
          text: 'وضعیت: ${a['status'] == 'valid' ? 'معتبر' : 'نامعتبر'}');
      document.addParagraph(
          text: 'قیمت هدف: ${a['target_price'] ?? 'تعیین نشده'}');
      document.addParagraph(text: 'عنوان هشدار: ${a['target_title'] ?? ''}');
      for (final section in _decodeSections(a['analysis_sections'])) {
        document.addHeading(
            text: section['heading']?.toString() ?? '', level: 2);
        document.addParagraph(text: section['body']?.toString() ?? '');
      }
      document.addParagraph(
          text:
              'متن تحلیل: ${(a['content']?.toString() ?? '').replaceAll(RegExp(r'\[\[IMAGE:\d+\]\]'), '[تصویر پیوست]')}');
      final images = _decodePaths(a['image_paths']);
      final audios = _decodePaths(a['audio_paths']);
      if (images.isNotEmpty) {
        document.addHeading(text: 'تصاویر پیوست', level: 2);
        for (final path in images) {
          document.addParagraph(text: p.basename(path));
          if (await File(path).exists()) {
            try {
              document.addPicture(path, width: Inches(4));
            } catch (_) {
              document.addParagraph(
                  text: 'تصویر اصلی در ZIP پیوست است: ${p.basename(path)}');
            }
          }
        }
      }
      if (audios.isNotEmpty) {
        document.addHeading(
            text: 'صداهای پیوست (فایل‌های اصلی در پوشهٔ رسانه)', level: 2);
        for (final path in audios) {
          document.addParagraph(text: p.basename(path));
        }
      }
      final temp = await getTemporaryDirectory();
      final tempPath = p.join(
          temp.path, 'analysis_${DateTime.now().microsecondsSinceEpoch}.docx');
      document.save(tempPath);
      final bytes = await File(tempPath).readAsBytes();
      await File(tempPath).delete();
      await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیرهٔ گزارش تحلیل',
        fileName: 'analysis_${a['timeframe'] ?? 'report'}.docx',
        type: FileType.custom,
        allowedExtensions: ['docx'],
        bytes: bytes,
      );
    } catch (e) {
      _message('خروجی تحلیل ناموفق بود: $e');
    }
  }

  Future<void> _exportBundle(Map<String, Object?> analysis) async {
    try {
      final archive = Archive();
      final images = _decodePaths(analysis['image_paths']);
      final audios = _decodePaths(analysis['audio_paths']);
      final imageArchivePaths = <String>[];
      final audioArchivePaths = <String>[];
      var index = 0;
      Future<List<String>> addMedia(List<String> paths, String folder) async {
        final result = <String>[];
        for (final source in paths) {
          final file = File(source);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final ext = p.extension(source);
          final archivePath = 'media/${folder}_${index++}$ext';
          archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
          result.add(archivePath);
        }
        return result;
      }

      imageArchivePaths.addAll(await addMedia(images, 'image'));
      audioArchivePaths.addAll(await addMedia(audios, 'audio'));
      final record = <String, dynamic>{
        'format': 'lbank_analysis_bundle',
        'version': 1,
        'asset_symbol': analysis['asset_symbol'],
        'timeframe': analysis['timeframe'],
        'title': analysis['title'],
        'content': analysis['content'],
        'target_price': analysis['target_price'],
        'target_title': analysis['target_title'],
        'alert_enabled': analysis['alert_enabled'] ?? 1,
        'analysis_sections': _decodeSections(analysis['analysis_sections']),
        'website_url': analysis['website_url'],
        'status': analysis['status'],
        'created_at': analysis['created_at'],
        'image_files': imageArchivePaths,
        'audio_files': audioArchivePaths,
        'image_names': images.map(p.basename).toList(),
        'audio_names': audios.map(p.basename).toList(),
      };
      final doc = docx.loadDocxDocument();
      doc.addHeading(text: 'گزارش تحلیل', level: 1);
      doc.addParagraph(text: 'دارایی: ${analysis['asset_symbol'] ?? ''}');
      doc.addParagraph(text: 'تایم‌فریم: ${analysis['timeframe'] ?? ''}');
      doc.addParagraph(text: 'عنوان: ${analysis['title'] ?? ''}');
      doc.addParagraph(
          text: 'قیمت هدف: ${analysis['target_price'] ?? 'تعیین نشده'}');
      doc.addParagraph(text: 'عنوان هشدار: ${analysis['target_title'] ?? ''}');
      for (final section in _decodeSections(analysis['analysis_sections'])) {
        doc.addHeading(text: section['heading']?.toString() ?? '', level: 2);
        doc.addParagraph(text: section['body']?.toString() ?? '');
      }
      doc.addParagraph(
          text:
              'متن تحلیل: ${(analysis['content']?.toString() ?? '').replaceAll(RegExp(r'\[\[IMAGE:\d+\]\]'), '[تصویر پیوست]')}');
      for (final path in images) {
        if (await File(path).exists()) {
          doc.addParagraph(text: 'تصویر: ${p.basename(path)}');
          try {
            doc.addPicture(path, width: Inches(4));
          } catch (_) {
            doc.addParagraph(text: 'تصویر اصلی در ZIP پیوست است.');
          }
        }
      }
      for (final path in audios) {
        doc.addParagraph(
            text: 'ویس پیوست: ${p.basename(path)} (فایل اصلی همراه ZIP است)');
      }
      final temp = await getTemporaryDirectory();
      final docPath = p.join(temp.path,
          'analysis_bundle_${DateTime.now().microsecondsSinceEpoch}.docx');
      doc.save(docPath);
      final docBytes = await File(docPath).readAsBytes();
      await File(docPath).delete();
      archive.addFile(ArchiveFile('analysis.docx', docBytes.length, docBytes));
      final jsonBytes =
          utf8.encode(const JsonEncoder.withIndent('  ').convert(record));
      archive
          .addFile(ArchiveFile('analysis.json', jsonBytes.length, jsonBytes));
      final bytes = ZipEncoder().encode(archive);
      if (bytes == null) throw Exception('ساخت بسته ناموفق بود.');
      await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره تحلیل همراه رسانه‌ها',
        fileName: 'analysis_${analysis['timeframe'] ?? 'bundle'}.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Uint8List.fromList(bytes),
      );
    } catch (e) {
      _message('خروجی ZIP تحلیل ناموفق بود: $e');
    }
  }

  Future<void> _importBundle() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = <String, ArchiveFile>{
        for (final file in archive.files)
          if (file.isFile) file.name: file
      };
      final jsonFile = files['analysis.json'];
      if (jsonFile == null)
        throw const FormatException('analysis.json پیدا نشد.');
      final raw = jsonDecode(
          utf8.decode(List<int>.from(jsonFile.content as List<int>)));
      if (raw is! Map ||
          raw['format'] != 'lbank_analysis_bundle' ||
          raw['version'] != 1)
        throw const FormatException('قالب تحلیل معتبر نیست.');
      final directory = await getApplicationDocumentsDirectory();
      final imagePaths = <String>[];
      final audioPaths = <String>[];
      Future<void> restore(List<dynamic> names, List<String> output,
          String kind, List<dynamic> originalNames) async {
        for (var i = 0; i < names.length; i++) {
          final archivePath = names[i].toString();
          if (!archivePath.startsWith('media/') ||
              archivePath.split('/').contains('..')) continue;
          final file = files[archivePath];
          if (file == null) continue;
          final name = i < originalNames.length
              ? originalNames[i].toString()
              : p.basename(archivePath);
          final ext = p.extension(name).isNotEmpty
              ? p.extension(name)
              : p.extension(archivePath);
          final folder =
              Directory(p.join(directory.path, 'analysis_media', kind));
          await folder.create(recursive: true);
          final path = p.join(
              folder.path, '${DateTime.now().microsecondsSinceEpoch}_$i$ext');
          await File(path).writeAsBytes(
              List<int>.from(file.content as List<int>),
              flush: true);
          output.add(path);
        }
      }

      await restore((raw['image_files'] as List? ?? []), imagePaths, 'images',
          (raw['image_names'] as List? ?? []));
      await restore((raw['audio_files'] as List? ?? []), audioPaths, 'audio',
          (raw['audio_names'] as List? ?? []));
      final db = await _database.database;
      await db.insert('analyses', {
        'analysis_id': DateTime.now().microsecondsSinceEpoch.toString(),
        'asset_symbol': raw['asset_symbol']?.toString() ?? 'GOLDUSDT',
        'timeframe': raw['timeframe']?.toString() ?? '15m',
        'title': raw['title']?.toString() ?? '',
        'content': raw['content']?.toString() ?? '',
        'target_price': raw['target_price'],
        'target_title': raw['target_title']?.toString() ?? '',
        'alert_enabled':
            raw['alert_enabled'] == false || raw['alert_enabled'] == 0 ? 0 : 1,
        'analysis_sections':
            jsonEncode(raw['analysis_sections'] ?? <Map<String, dynamic>>[]),
        'website_url': raw['website_url']?.toString() ??
            'https://www.tradingview.com/chart/',
        'image_paths': jsonEncode(imagePaths),
        'audio_paths': jsonEncode(audioPaths),
        'status': raw['status']?.toString() == 'invalid' ? 'invalid' : 'valid',
        'created_at': DateTime.now().toIso8601String(),
        'triggered_at': null,
      });
      await _load();
      _message('تحلیل و فایل‌های رسانه‌ای وارد شدند.');
    } catch (e) {
      _message('ورود بستهٔ تحلیل ناموفق بود: $e');
    }
  }

  List<Map<String, dynamic>> _decodeSections(Object? raw) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '[]');
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<String> _decodePaths(Object? raw) {
    try {
      return (jsonDecode(raw?.toString() ?? '[]') as List)
          .map((e) => e.toString())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Widget _analysisCard(Map<String, Object?> a) {
    final symbol = (a['asset_symbol']?.toString() ?? 'GOLDUSDT').toUpperCase();
    final id = a['analysis_id']?.toString() ?? '';
    final selected = _selectedAnalysisIds.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
            value: selected,
            onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedAnalysisIds.add(id);
                  } else {
                    _selectedAnalysisIds.remove(id);
                  }
                })),
        title: Text(symbol,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('تایم‌فریم: ${a['timeframe'] ?? ''}',
            textDirection: TextDirection.rtl),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => _openAnalysisDetails(a),
      ),
    );
  }

  Future<void> _openAnalysisDetails(Map<String, Object?> a) async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => _AnalysisDetailPage(
                  analysis: a,
                  livePrice: _prices[
                      (a['asset_symbol']?.toString() ?? 'GOLDUSDT')
                          .toUpperCase()],
                  onEdit: () {
                    Navigator.pop(context);
                    _editAnalysis(a);
                  },
                  onExport: () => _export(a),
                  onExportBundle: () => _exportBundle(a),
                  onDelete: () async {
                    Navigator.pop(context);
                    await _delete(a);
                  },
                  onToggleStatus: () async {
                    Navigator.pop(context);
                    await _toggleStatus(a);
                  },
                  decodePaths: _decodePaths,
                  audioPlayer: _audioPlayer,
                )));
  }

  Future<void> _bulkMove(String targetStatus) async {
    if (_selectedAnalysisIds.isEmpty) {
      _message('ابتدا یک یا چند تحلیل را انتخاب کن.');
      return;
    }
    final db = await _database.database;
    for (final id in _selectedAnalysisIds) {
      await db.update(
          'analyses', {'status': targetStatus, 'triggered_at': null},
          where: 'analysis_id = ?', whereArgs: [id]);
    }
    setState(() => _selectedAnalysisIds.clear());
    await _load();
  }

  Widget _websiteTab() {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('کابین تحلیل',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                        value: _savedWebsites.contains(_websiteUrl)
                            ? _websiteUrl
                            : null,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'سایت ذخیره‌شده'),
                        items: _savedWebsites
                            .map((url) => DropdownMenuItem(
                                value: url,
                                child: Text(url,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr)))
                            .toList(),
                        onChanged: (url) {
                          if (url != null) {
                            _websiteUrl = url;
                            _loadWebsite();
                          }
                        }),
                    const SizedBox(height: 8),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      IconButton(
                          tooltip:
                              _showWebsite ? 'پنهان کردن سایت' : 'نمایش سایت',
                          onPressed: () =>
                              setState(() => _showWebsite = !_showWebsite),
                          icon: Icon(_showWebsite
                              ? Icons.visibility_off
                              : Icons.visibility)),
                      IconButton(
                          tooltip: 'افزودن سایت',
                          onPressed: _addWebsiteDialog,
                          icon: const Icon(Icons.add_link)),
                      IconButton(
                          tooltip: 'تحلیل جدید',
                          onPressed: _newAnalysis,
                          icon: const Icon(Icons.add)),
                      IconButton(
                          tooltip: 'تمام‌صفحه',
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _FullScreenWebsite(url: _websiteUrl))),
                          icon: const Icon(Icons.fullscreen)),
                      IconButton(
                          tooltip: 'ورود از ZIP',
                          onPressed: _importBundle,
                          icon: const Icon(Icons.archive_outlined)),
                    ]),
                    Row(children: [
                      Checkbox(
                          value: _websiteScrollLocked,
                          onChanged: (v) => setState(
                              () => _websiteScrollLocked = v ?? false)),
                      const Text('قفل اسکرول سایت')
                    ]),
                    if (_showWebsite)
                      SizedBox(
                          height: 440,
                          child: _websiteController == null
                              ? Center(
                                  child: OutlinedButton(
                                      onPressed: _loadWebsite,
                                      child: const Text('نمایش سایت')))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: WebViewWidget(
                                      controller: _websiteController!,
                                      gestureRecognizers: _websiteScrollLocked
                                          ? <Factory<
                                              OneSequenceGestureRecognizer>>{
                                              Factory<EagerGestureRecognizer>(
                                                  () =>
                                                      EagerGestureRecognizer())
                                            }
                                          : const <Factory<
                                              OneSequenceGestureRecognizer>>{}))),
                  ]))),
    ]);
  }

  Widget _analysisListTab(bool valid) {
    final list = _analyses
        .where((a) => valid ? a['status'] == 'valid' : a['status'] != 'valid')
        .toList();
    final selectedInTab = list
        .where(
            (a) => _selectedAnalysisIds.contains(a['analysis_id']?.toString()))
        .length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(
            child: Text(
                valid
                    ? 'تحلیل‌های معتبر (${numbers.formatInteger(list.length)})'
                    : 'تحلیل‌های نامعتبر (${numbers.formatInteger(list.length)})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17))),
        TextButton(
            onPressed: () => setState(() {
                  for (final a in list) {
                    final id = a['analysis_id']?.toString();
                    if (id != null) _selectedAnalysisIds.add(id);
                  }
                }),
            child: const Text('انتخاب همه'))
      ]),
      if (_selectedAnalysisIds.isNotEmpty)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(spacing: 8, children: [
                  Text('انتخاب‌شده: ${numbers.formatInteger(selectedInTab)}'),
                  TextButton(
                      onPressed: () => _bulkMove(valid ? 'invalid' : 'valid'),
                      child: Text(valid
                          ? 'انتقال گروهی به نامعتبر'
                          : 'انتقال گروهی به معتبر')),
                  TextButton(
                      onPressed: () =>
                          setState(() => _selectedAnalysisIds.clear()),
                      child: const Text('لغو انتخاب')),
                ]))),
      if (list.isEmpty)
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text(valid
                ? 'تحلیل معتبری ثبت نشده است.'
                : 'تحلیل نامعتبری وجود ندارد.')),
      ...list.map(_analysisCard),
      const SizedBox(height: 80),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 3,
        initialIndex: 0,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('تحلیل‌ها'),
              bottom: const TabBar(isScrollable: true, tabs: [
                Tab(text: 'کابین تحلیل', icon: Icon(Icons.public)),
                Tab(
                    text: 'تحلیل‌های معتبر',
                    icon: Icon(Icons.check_circle_outline)),
                Tab(
                    text: 'تحلیل‌های نامعتبر',
                    icon: Icon(Icons.block_outlined)),
              ])),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(children: [
                  _websiteTab(),
                  _analysisListTab(true),
                  _analysisListTab(false),
                ]),
          floatingActionButton: FloatingActionButton(
              tooltip: 'تحلیل جدید',
              onPressed: _newAnalysis,
              child: const Icon(Icons.add)),
        ));
  }
}

class _AnalysisSectionDraft {
  final TextEditingController heading;
  final TextEditingController body;
  _AnalysisSectionDraft({String headingText = '', String bodyText = ''})
      : heading = TextEditingController(text: headingText),
        body = TextEditingController(text: bodyText);
  void dispose() {
    heading.dispose();
    body.dispose();
  }

  Map<String, dynamic> toJson() => {'heading': heading.text, 'body': body.text};
}

class _AnalysisEditorSegment {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  String? imagePath;

  _AnalysisEditorSegment.text(String text)
      : controller = TextEditingController(text: text),
        focusNode = FocusNode(),
        imagePath = null;

  _AnalysisEditorSegment.image(String path)
      : controller = null,
        focusNode = null,
        imagePath = path;

  bool get isImage => imagePath != null;

  void dispose() {
    controller?.dispose();
    focusNode?.dispose();
  }
}

/// A block-based editor is used instead of WidgetSpan inside TextField.
/// WidgetSpan changes the visual character offsets and causes cursor/IME bugs,
/// especially while typing Persian text around images.
class _AnalysisRichEditor extends StatefulWidget {
  final String initialContent;
  final List<String> initialImages;
  final void Function(String content, List<String> imagePaths) onChanged;
  final Future<void> Function(int index) onImageTap;

  const _AnalysisRichEditor({
    super.key,
    required this.initialContent,
    required this.initialImages,
    required this.onChanged,
    required this.onImageTap,
  });

  @override
  State<_AnalysisRichEditor> createState() => _AnalysisRichEditorState();
}

class _AnalysisRichEditorState extends State<_AnalysisRichEditor> {
  final List<_AnalysisEditorSegment> _segments = <_AnalysisEditorSegment>[];
  int? _activeSegment;

  @override
  void initState() {
    super.initState();
    _parse(widget.initialContent, widget.initialImages);
    _emit();
  }

  @override
  void didUpdateWidget(covariant _AnalysisRichEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent is only a storage mirror; do not reparse on each keystroke.
  }

  void _parse(String content, List<String> images) {
    final marker = RegExp(r'\[\[IMAGE:(\d+)\]\]');
    var cursor = 0;
    for (final match in marker.allMatches(content)) {
      if (match.start > cursor) {
        _segments.add(_AnalysisEditorSegment.text(
            content.substring(cursor, match.start)));
      }
      final index = int.tryParse(match.group(1) ?? '');
      if (index != null && index >= 0 && index < images.length) {
        _segments.add(_AnalysisEditorSegment.image(images[index]));
      } else {
        _segments.add(_AnalysisEditorSegment.text('[تصویر در دسترس نیست]'));
      }
      cursor = match.end;
    }
    if (cursor < content.length) {
      _segments.add(_AnalysisEditorSegment.text(content.substring(cursor)));
    }
    if (_segments.isEmpty) _segments.add(_AnalysisEditorSegment.text(''));
  }

  @override
  void dispose() {
    for (final segment in _segments) {
      segment.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final buffer = StringBuffer();
    final images = <String>[];
    for (final segment in _segments) {
      if (segment.isImage) {
        buffer.write('[[IMAGE:${images.length}]]');
        images.add(segment.imagePath!);
      } else {
        buffer.write(segment.controller!.text);
      }
    }
    widget.onChanged(buffer.toString(), images);
  }

  int _nextTextIndex(int start) {
    for (var i = start; i < _segments.length; i++) {
      if (!_segments[i].isImage) return i;
    }
    return -1;
  }

  int _lastTextIndex() {
    for (var i = _segments.length - 1; i >= 0; i--) {
      if (!_segments[i].isImage) return i;
    }
    return -1;
  }

  void insertImage(String path) {
    // Prefer the segment the user was editing. If focus was lost while the
    // picker was open, fall back to the last editable text block, not only the
    // final segment (which may be an image block).
    var index = _activeSegment ?? -1;
    if (index < 0 || index >= _segments.length || _segments[index].isImage) {
      index = _lastTextIndex();
    }
    if (index < 0) {
      _segments.add(_AnalysisEditorSegment.text(''));
      index = _segments.length - 1;
    }

    final old = _segments[index];
    final controller = old.controller!;
    final text = controller.text;
    final selection = controller.selection;
    final hasSelection = selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0 &&
        selection.start <= text.length &&
        selection.end <= text.length;
    final startOffset = hasSelection
        ? selection.start.clamp(0, text.length) as int
        : text.length;
    final endOffset = hasSelection
        ? selection.end.clamp(startOffset, text.length) as int
        : startOffset;
    var before = text.substring(0, startOffset);
    var after = text.substring(endOffset);
    if (before.isNotEmpty && !before.endsWith('\n')) before += '\n';
    if (!after.startsWith('\n')) after = '\n$after';

    old.dispose();
    _segments.replaceRange(index, index + 1, <_AnalysisEditorSegment>[
      _AnalysisEditorSegment.text(before),
      _AnalysisEditorSegment.image(path),
      _AnalysisEditorSegment.text(after),
    ]);
    final afterIndex = index + 2;
    _activeSegment = afterIndex;
    setState(() {});
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || afterIndex >= _segments.length) return;
      final next = _segments[afterIndex];
      if (!next.isImage) {
        next.focusNode!.requestFocus();
        next.controller!.selection = const TextSelection.collapsed(offset: 0);
      }
    });
  }

  void replaceImage(int imageIndex, String path) {
    var seen = 0;
    for (final segment in _segments) {
      if (!segment.isImage) continue;
      if (seen == imageIndex) {
        setState(() => segment.imagePath = path);
        _emit();
        return;
      }
      seen++;
    }
  }

  void removeImage(int imageIndex) {
    var seen = 0;
    var segmentIndex = -1;
    for (var i = 0; i < _segments.length; i++) {
      if (!_segments[i].isImage) continue;
      if (seen == imageIndex) {
        segmentIndex = i;
        break;
      }
      seen++;
    }
    if (segmentIndex < 0) return;
    final removed = _segments.removeAt(segmentIndex);
    removed.dispose();
    // Merge neighbouring text blocks so typing can continue naturally.
    if (segmentIndex > 0 &&
        segmentIndex < _segments.length &&
        !_segments[segmentIndex - 1].isImage &&
        !_segments[segmentIndex].isImage) {
      final left = _segments[segmentIndex - 1];
      final right = _segments[segmentIndex];
      final mergedText = left.controller!.text + right.controller!.text;
      left.dispose();
      right.dispose();
      _segments.replaceRange(segmentIndex - 1, segmentIndex + 1,
          <_AnalysisEditorSegment>[_AnalysisEditorSegment.text(mergedText)]);
      _activeSegment = segmentIndex - 1;
    } else if (_segments.isEmpty) {
      _segments.add(_AnalysisEditorSegment.text(''));
      _activeSegment = 0;
    } else {
      final next =
          _nextTextIndex(segmentIndex.clamp(0, _segments.length - 1) as int);
      _activeSegment = next >= 0 ? next : _nextTextIndex(0);
    }
    setState(() {});
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _segments.length; i++)
          if (_segments[i].isImage)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LayoutBuilder(builder: (context, constraints) {
                final path = _segments[i].imagePath!;
                final imageIndex =
                    _segments.take(i).where((s) => s.isImage).length;
                final maxWidth = constraints.maxWidth;
                return GestureDetector(
                  onTap: () => widget.onImageTap(imageIndex),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: maxWidth, maxHeight: 600),
                    child: Image.file(
                      File(path),
                      width: maxWidth,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                );
              }),
            )
          else
            TextField(
              controller: _segments[i].controller,
              focusNode: _segments[i].focusNode,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.start,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 5),
                hintText: i == 0 ? 'متن تحلیل را بنویسید…' : null,
              ),
              onTap: () => _activeSegment = i,
              onChanged: (_) => _emit(),
            ),
      ],
    );
  }
}

class _AnalysisEditor extends StatefulWidget {
  final double? currentPrice;
  final Map<String, Object?>? initial;
  const _AnalysisEditor({this.currentPrice, this.initial});
  @override
  State<_AnalysisEditor> createState() => _AnalysisEditorState();
}

class _AnalysisEditorState extends State<_AnalysisEditor> {
  late final TextEditingController _symbol;
  late final TextEditingController _timeframe;
  late final TextEditingController _title;
  late final TextEditingController _content;
  final GlobalKey<_AnalysisRichEditorState> _editorKey =
      GlobalKey<_AnalysisRichEditorState>();
  late final TextEditingController _target;
  late final TextEditingController _targetTitle;
  final List<_AnalysisSectionDraft> _sections = <_AnalysisSectionDraft>[];
  bool _alertEnabled = true;
  final List<String> _images = [];
  final List<String> _audios = [];
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _saving = false;
  double? _livePrice;
  LBankService? _livePriceService;
  StreamSubscription<Ticker>? _livePriceSubscription;
  Timer? _symbolDebounce;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _symbol = TextEditingController(
        text: a?['asset_symbol']?.toString() ?? 'GOLDUSDT');
    _timeframe =
        TextEditingController(text: a?['timeframe']?.toString() ?? '15m');
    _title = TextEditingController(text: a?['title']?.toString() ?? '');
    _content = TextEditingController(text: a?['content']?.toString() ?? '');
    _alertEnabled = a?['alert_enabled'] == null ||
        a?['alert_enabled'] == 1 ||
        a?['alert_enabled'] == true;
    try {
      final rawSections =
          jsonDecode(a?['analysis_sections']?.toString() ?? '[]');
      if (rawSections is List) {
        for (final item in rawSections.whereType<Map>()) {
          _sections.add(_AnalysisSectionDraft(
              headingText: item['heading']?.toString() ?? '',
              bodyText: item['body']?.toString() ?? ''));
        }
      }
    } catch (_) {}
    if (_sections.isEmpty) _sections.add(_AnalysisSectionDraft());
    _target = TextEditingController(
        text: a?['target_price']?.toString() ??
            widget.currentPrice?.toString() ??
            '');
    _targetTitle =
        TextEditingController(text: a?['target_title']?.toString() ?? '');
    _images.addAll(_decodeEditorPaths(a?['image_paths']));
    _audios.addAll(_decodeEditorPaths(a?['audio_paths']));
    // Preserve legacy attachments by placing missing image markers at the end of the text.
    for (var i = 0; i < _images.length; i++) {
      if (!_content.text.contains('[[IMAGE:$i]]')) {
        _content.text =
            '${_content.text}${_content.text.trim().isEmpty ? '' : '\n\n'}[[IMAGE:$i]]';
      }
    }
    _livePrice = widget.currentPrice;
    _symbol.addListener(_scheduleLivePriceConnect);
    _connectLivePrice();
  }

  void _scheduleLivePriceConnect() {
    _symbolDebounce?.cancel();
    _symbolDebounce =
        Timer(const Duration(milliseconds: 500), _connectLivePrice);
  }

  void _connectLivePrice() {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty ||
        (_livePriceService != null && _connectedSymbol == symbol)) return;
    _livePriceSubscription?.cancel();
    _livePriceService?.dispose();
    _connectedSymbol = symbol;
    final service = LBankService();
    _livePriceService = service;
    _livePriceSubscription = service.tickerStream.listen((ticker) {
      if (!mounted) return;
      setState(() => _livePrice = ticker.price);
    });
    service.connect(symbol);
  }

  String? _connectedSymbol;

  List<String> _decodeEditorPaths(Object? raw) {
    if (raw == null) return <String>[];
    try {
      return (jsonDecode(raw.toString()) as List)
          .map((e) => e.toString())
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  @override
  void dispose() {
    _symbol.removeListener(_scheduleLivePriceConnect);
    _symbolDebounce?.cancel();
    _livePriceSubscription?.cancel();
    _livePriceService?.dispose();
    for (final c in [
      _symbol,
      _timeframe,
      _title,
      _content,
      _target,
      _targetTitle
    ]) {
      c.dispose();
    }
    for (final section in _sections) {
      section.dispose();
    }
    _recorder.dispose();
    super.dispose();
  }

  Future<String> _copy(String path, String kind) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'analysis_media', kind));
    await folder.create(recursive: true);
    final ext = p.extension(path).isNotEmpty ? p.extension(path) : '.bin';
    final out =
        p.join(folder.path, '${DateTime.now().microsecondsSinceEpoch}$ext');
    await File(path).copy(out);
    return out;
  }

  Future<void> _addImage() async {
    // The rich editor keeps the active text segment and its selection even while
    // the image picker is open, so insertion does not jump to the end.
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (file == null) return;
    final saved = await _copy(file.path, 'images');
    final editor = _editorKey.currentState;
    if (editor != null) {
      editor.insertImage(saved);
    } else {
      final index = _images.length;
      _images.add(saved);
      final text = _content.text;
      final offset =
          _content.selection.isValid ? _content.selection.start : text.length;
      final prefix = offset > 0 && text[offset - 1] != '\n' ? '\n' : '';
      final suffix = offset < text.length && text[offset] != '\n' ? '\n' : '';
      _content.text =
          text.replaceRange(offset, offset, '$prefix[[IMAGE:$index]]$suffix');
    }
  }

  Future<void> _editImage(int index) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('جایگزینی تصویر'),
                  onTap: () => Navigator.pop(context, 'replace')),
              ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('حذف تصویر'),
                  onTap: () => Navigator.pop(context, 'delete')),
            ])));
    if (action == 'replace') {
      final file = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (file != null) {
        final saved = await _copy(file.path, 'images');
        _editorKey.currentState?.replaceImage(index, saved);
      }
    } else if (action == 'delete') {
      _editorKey.currentState?.removeImage(index);
    }
  }

  void _onEditorChanged(String content, List<String> imagePaths) {
    _content.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: content.length),
    );
    _images
      ..clear()
      ..addAll(imagePaths);
  }

  Future<void> _addAudio() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', '3gp'],
        withData: false);
    final path = result?.files.single.path;
    if (path == null) return;
    _audios.add(await _copy(path, 'audio'));
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        if (path != null) _audios.add(await _copy(path, 'audio'));
        if (mounted) setState(() => _recording = false);
      } else {
        if (!await _recorder.hasPermission()) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('مجوز میکروفون داده نشده است.')));
          return;
        }
        final dir = await getApplicationDocumentsDirectory();
        final path = p.join(dir.path, 'analysis_media', 'audio',
            'voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
        await Directory(p.dirname(path)).create(recursive: true);
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
            path: path);
        if (mounted) setState(() => _recording = true);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ضبط ویس انجام نشد: $e')));
    }
  }

  void _save() {
    final target = double.tryParse(
        numbers.normalizeNumberInput(_target.text).trim().replaceAll(',', ''));
    final url = widget.initial?['website_url']?.toString() ?? '';
    Navigator.pop(context, {
      'symbol': _symbol.text.trim().toUpperCase().isEmpty
          ? 'GOLDUSDT'
          : _symbol.text.trim().toUpperCase(),
      'timeframe': _timeframe.text.trim().isEmpty
          ? 'بدون تایم‌فریم'
          : _timeframe.text.trim(),
      'title': _title.text.trim(),
      'content': _content.text,
      'target_price': target,
      'target_title': _targetTitle.text.trim(),
      'alert_enabled': _alertEnabled,
      'analysis_sections':
          _sections.map((section) => section.toJson()).toList(),
      'website_url': url,
      'image_paths': _images.where((e) => e.isNotEmpty).toList(),
      'audio_paths': _audios,
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.initial == null ? 'تحلیل جدید' : 'ویرایش تحلیل'),
            actions: [
              IconButton(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save))
            ]),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
              controller: _symbol,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'نام نماد')),
          TextField(
              controller: _timeframe,
              decoration: const InputDecoration(
                  labelText:
                      'تایم‌فریم (متن آزاد، مانند 15m، 4h یا عبارت دلخواه)')),
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'عنوان تحلیل')),
          const SizedBox(height: 12),
          const Text('متن تحلیل',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _AnalysisRichEditor(
              key: _editorKey,
              initialContent: _content.text,
              initialImages: _images,
              onChanged: _onEditorChanged,
              onImageTap: _editImage,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _addImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('افزودن تصویر در محل مکان‌نما')),
            OutlinedButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(_recording ? 'پایان ضبط ویس' : 'ضبط ویس')),
            OutlinedButton.icon(
                onPressed: _addAudio,
                icon: const Icon(Icons.audio_file),
                label: const Text('افزودن فایل صوتی')),
          ]),
          if (_recording)
            const Padding(
                padding: EdgeInsets.all(8), child: Text('در حال ضبط ویس…')),
          if (_audios.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('ویس‌ها و فایل‌های صوتی'),
            ..._audios.asMap().entries.map((e) => ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(p.basename(e.value)),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _audios.removeAt(e.key))))),
          ],
          const Divider(height: 28),
          LayoutBuilder(builder: (context, constraints) {
            final firstSection = _sections.isNotEmpty ? _sections.first : null;
            final priceField = TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'قیمت هدف / هشدار'),
            );
            final alertSwitch =
                Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('فعال‌سازی هشدار', style: TextStyle(fontSize: 11)),
              Switch(
                  value: _alertEnabled,
                  onChanged: (value) => setState(() => _alertEnabled = value)),
            ]);
            final firstBoxField = firstSection == null
                ? const SizedBox.shrink()
                : TextField(
                    controller: firstSection.heading,
                    minLines: 1,
                    maxLines: 2,
                    textDirection: TextDirection.rtl,
                    decoration:
                        const InputDecoration(labelText: 'متن اصلی باکس اول'),
                    onChanged: (_) => setState(() {}),
                  );
            if (constraints.maxWidth >= 560 && firstSection != null) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 2, child: priceField),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: firstBoxField),
                    const SizedBox(width: 8),
                    alertSwitch,
                  ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(child: priceField),
                    const SizedBox(width: 8),
                    alertSwitch,
                  ]),
                  if (firstSection != null) firstBoxField,
                ]);
          }),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'قیمت لحظه‌ای: ${_livePrice == null ? 'در حال دریافت' : numbers.formatNumber(_livePrice!, decimals: 4, trimTrailingZeros: false)}',
                  textDirection: TextDirection.ltr)),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed: _livePrice == null
                      ? null
                      : () => setState(
                          () => _target.text = _livePrice!.toStringAsFixed(4)),
                  icon: const Icon(Icons.price_check),
                  label: const Text('قرار دادن قیمت لحظه‌ای در قیمت هدف'))),
          TextField(
              controller: _targetTitle,
              decoration: const InputDecoration(labelText: 'عنوان هشدار')),
          const Divider(height: 28),
          Row(children: [
            const Expanded(
                child: Text('باکس‌های متنی تحلیل',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _sections.add(_AnalysisSectionDraft())),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('افزودن باکس'),
            ),
          ]),
          const SizedBox(height: 8),
          ..._sections.asMap().entries.map((entry) {
            final index = entry.key;
            final section = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('باکس ${index + 1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                        IconButton(
                            tooltip: 'حذف باکس',
                            onPressed: () => setState(() {
                                  _sections.removeAt(index).dispose();
                                }),
                            icon: const Icon(Icons.delete_outline)),
                      ]),
                      if (index != 0) ...[
                        TextField(
                          controller: section.heading,
                          minLines: 1,
                          maxLines: null,
                          textDirection: TextDirection.rtl,
                          decoration:
                              const InputDecoration(labelText: 'متن اصلی باکس'),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            section.heading.text.isEmpty
                                ? 'متن واردشده در این قسمت نمایش داده می‌شود'
                                : section.heading.text,
                            textDirection: TextDirection.rtl),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: section.body,
                        minLines: 2,
                        maxLines: null,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                            labelText: 'متن آزاد زیر باکس'),
                      ),
                    ]),
              ),
            );
          }),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('ذخیره تحلیل')),
        ])),
      );
}

class _AnalysisDetailPage extends StatelessWidget {
  final Map<String, Object?> analysis;
  final double? livePrice;
  final VoidCallback onEdit;
  final Future<void> Function() onExport;
  final Future<void> Function() onExportBundle;
  final Future<void> Function() onDelete;
  final Future<void> Function() onToggleStatus;
  final List<String> Function(Object?) decodePaths;
  final AudioPlayer audioPlayer;
  const _AnalysisDetailPage(
      {required this.analysis,
      required this.livePrice,
      required this.onEdit,
      required this.onExport,
      required this.onExportBundle,
      required this.onDelete,
      required this.onToggleStatus,
      required this.decodePaths,
      required this.audioPlayer});

  @override
  Widget build(BuildContext context) {
    final images = decodePaths(analysis['image_paths']);
    final audios = decodePaths(analysis['audio_paths']);
    return Scaffold(
        appBar: AppBar(title: const Text('جزئیات تحلیل'), actions: [
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit))
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${analysis['asset_symbol'] ?? ''}',
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.titleLarge),
          Text('تایم‌فریم: ${analysis['timeframe'] ?? ''}'),
          Text('عنوان: ${analysis['title'] ?? ''}'),
          Text('وضعیت: ${analysis['status'] == 'valid' ? 'معتبر' : 'نامعتبر'}'),
          Text(
              'قیمت لحظه‌ای: ${livePrice == null ? 'در حال دریافت' : numbers.formatNumber(livePrice!, decimals: 4, trimTrailingZeros: false)}',
              textDirection: TextDirection.ltr),
          if (analysis['target_price'] != null)
            Text(
                'قیمت هدف: ${analysis['target_price']} (هشدار: ${(analysis['alert_enabled'] == null || analysis['alert_enabled'] == 1 || analysis['alert_enabled'] == true) ? 'فعال' : 'غیرفعال'})',
                textDirection: TextDirection.ltr),
          if ((analysis['target_title']?.toString() ?? '').isNotEmpty)
            Text('عنوان هشدار: ${analysis['target_title']}'),
          const Divider(),
          const Text('متن تحلیل',
              style: TextStyle(fontWeight: FontWeight.bold)),
          _InlineAnalysisContent(
              content: analysis['content']?.toString() ?? '', images: images),
          ..._decodeAnalysisSections(analysis['analysis_sections'])
              .asMap()
              .entries
              .map((entry) => Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(entry.value['heading']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  textDirection: TextDirection.rtl),
                              const SizedBox(height: 6),
                              Text(entry.value['body']?.toString() ?? '',
                                  textDirection: TextDirection.rtl),
                            ])),
                  )),
          ...audios.map((path) => ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(p.basename(path)),
              onTap: () async {
                try {
                  await audioPlayer.play(DeviceFileSource(path));
                } catch (_) {}
              })),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
                label: const Text('ویرایش')),
            OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.description),
                label: const Text('خروجی DOCX')),
            OutlinedButton.icon(
                onPressed: onExportBundle,
                icon: const Icon(Icons.folder_zip),
                label: const Text('خروجی ZIP همراه رسانه‌ها')),
            OutlinedButton.icon(
                onPressed: onToggleStatus,
                icon: const Icon(Icons.swap_horiz),
                label: Text(analysis['status'] == 'valid'
                    ? 'انتقال به نامعتبر'
                    : 'بازگردانی به معتبر')),
            OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف')),
          ]),
        ]));
  }
}

List<Map<String, dynamic>> _decodeAnalysisSections(Object? raw) {
  try {
    final decoded = jsonDecode(raw?.toString() ?? '[]');
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

class _InlineAnalysisContent extends StatelessWidget {
  final String content;
  final List<String> images;
  const _InlineAnalysisContent({required this.content, required this.images});

  @override
  Widget build(BuildContext context) {
    final marker = RegExp(r'\[\[IMAGE:(\d+)\]\]');
    final children = <Widget>[];
    var cursor = 0;
    for (final match in marker.allMatches(content)) {
      final text = content.substring(cursor, match.start);
      if (text.trim().isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(text, textDirection: TextDirection.rtl),
        ));
      }
      final index = int.tryParse(match.group(1) ?? '');
      if (index != null &&
          index >= 0 &&
          index < images.length &&
          images[index].isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(builder: (context, constraints) {
            final image = Image.file(
              File(images[index]),
              width: constraints.maxWidth,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
            );
            return GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                      child:
                          Image.file(File(images[index]), fit: BoxFit.contain)),
                ),
              ),
              child: image,
            );
          }),
        ));
      }
      cursor = match.end;
    }
    final rest = content.substring(cursor);
    if (rest.trim().isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(rest, textDirection: TextDirection.rtl),
      ));
    }
    if (!marker.hasMatch(content)) {
      for (final path in images) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
              builder: (context, constraints) => Image.file(
                    File(path),
                    width: constraints.maxWidth,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image),
                  )),
        ));
      }
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _FullScreenWebsite extends StatefulWidget {
  final String url;
  const _FullScreenWebsite({required this.url});
  @override
  State<_FullScreenWebsite> createState() => _FullScreenWebsiteState();
}

class _FullScreenWebsiteState extends State<_FullScreenWebsite> {
  late final WebViewController controller;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('وب‌سایت تحلیل')),
      body: WebViewWidget(controller: controller));
}
