import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

class CustomImageGalleryPage extends StatefulWidget {
  const CustomImageGalleryPage({super.key});

  @override
  State<CustomImageGalleryPage> createState() => _CustomImageGalleryPageState();
}

class _CustomImageGalleryPageState extends State<CustomImageGalleryPage> {
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _topics = [];
  List<Map<String, dynamic>> _images = [];
  int? _selectedTopicId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('custom_gallery_topics', orderBy: 'topic_name COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _topics = rows;
      if (_selectedTopicId == null ||
          !_topics.any((topic) => topic['topic_id'] == _selectedTopicId)) {
        _selectedTopicId = _topics.isEmpty ? null : _topics.first['topic_id'] as int;
      }
      _loading = false;
    });
    await _loadImages();
  }

  Future<void> _loadImages() async {
    final topicId = _selectedTopicId;
    if (topicId == null) {
      if (mounted) setState(() => _images = []);
      return;
    }
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'custom_gallery_images',
      where: 'topic_id = ?',
      whereArgs: [topicId],
      orderBy: 'image_order ASC, image_id DESC',
    );
    if (mounted) setState(() => _images = rows);
  }

  Future<void> _addTopic() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('موضوع جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'نام موضوع',
            hintText: 'مثلاً الگوهای معاملاتی',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final db = await AppDatabase.instance.database;
    final existing = await db.query(
      'custom_gallery_topics',
      where: 'topic_name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      _showMessage('این موضوع از قبل وجود دارد.');
      return;
    }
    final id = await db.insert('custom_gallery_topics', {
      'topic_name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    setState(() => _selectedTopicId = id);
    await _loadTopics();
  }

  Future<void> _pickImages() async {
    if (_selectedTopicId == null || _busy) return;
    try {
      final selected = await _picker.pickMultiImage(imageQuality: 92);
      if (selected.isEmpty) return;
      setState(() => _busy = true);

      final db = await AppDatabase.instance.database;
      final appDir = await getApplicationDocumentsDirectory();
      final galleryDir = Directory(p.join(
        appDir.path,
        'custom_gallery',
        _selectedTopicId.toString(),
      ));
      await galleryDir.create(recursive: true);

      for (final image in selected) {
        final extension = p.extension(image.path).isNotEmpty
            ? p.extension(image.path)
            : '.jpg';
        final fileName = '${DateTime.now().microsecondsSinceEpoch}_${selected.indexOf(image)}$extension';
        final destination = p.join(galleryDir.path, fileName);
        await File(image.path).copy(destination);
        await db.insert('custom_gallery_images', {
          'topic_id': _selectedTopicId,
          'image_path': destination,
          'image_order': 0,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await _loadImages();
      _showMessage('${selected.length} عکس به گالری اضافه شد.');
    } catch (error) {
      _showMessage('افزودن عکس انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteImage(Map<String, dynamic> image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف عکس'),
        content: const Text('این عکس از گالری حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await AppDatabase.instance.database;
    await db.delete('custom_gallery_images', where: 'image_id = ?', whereArgs: [image['image_id']]);
    final path = image['image_path']?.toString() ?? '';
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _loadImages();
  }

  Future<void> _deleteTopic() async {
    final topicId = _selectedTopicId;
    if (topicId == null) return;
    final topic = _topics.firstWhere((item) => item['topic_id'] == topicId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف موضوع'),
        content: Text('موضوع «${topic['topic_name']}» و تمام عکس‌های آن حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف موضوع')),
        ],
      ),
    );
    if (confirmed != true) return;

    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'custom_gallery_images',
      columns: ['image_path'],
      where: 'topic_id = ?',
      whereArgs: [topicId],
    );
    await db.delete('custom_gallery_topics', where: 'topic_id = ?', whereArgs: [topicId]);
    for (final row in rows) {
      final path = row['image_path']?.toString() ?? '';
      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    if (!mounted) return;
    setState(() => _selectedTopicId = null);
    await _loadTopics();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openImage(int index) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _GalleryImageViewer(
        images: _images,
        initialIndex: index,
        topicId: _selectedTopicId!,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final selectedTopic = _topics.where((item) => item['topic_id'] == _selectedTopicId).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('گالری عکس'),
        centerTitle: true,
        actions: [
          if (_selectedTopicId != null)
            IconButton(
              tooltip: 'حذف موضوع',
              onPressed: _deleteTopic,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      floatingActionButton: _selectedTopicId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _pickImages,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_busy ? 'در حال افزودن...' : 'افزودن عکس'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _topics.isEmpty
                            ? const Text('هنوز موضوعی ایجاد نشده است.')
                            : DropdownButtonFormField<int>(
                                value: _selectedTopicId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'انتخاب موضوع',
                                  border: OutlineInputBorder(),
                                ),
                                items: _topics.map((topic) => DropdownMenuItem<int>(
                                  value: topic['topic_id'] as int,
                                  child: Text(topic['topic_name'].toString()),
                                )).toList(),
                                onChanged: (value) async {
                                  setState(() => _selectedTopicId = value);
                                  await _loadImages();
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'ایجاد موضوع',
                        onPressed: _addTopic,
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _selectedTopicId == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library_outlined, size: 58, color: Colors.grey),
                                const SizedBox(height: 12),
                                const Text('برای شروع، یک موضوع بسازید.'),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _addTopic,
                                  icon: const Icon(Icons.add),
                                  label: const Text('ایجاد موضوع'),
                                ),
                              ],
                            ),
                          )
                        : _images.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo_outlined, size: 58, color: Colors.grey),
                                    const SizedBox(height: 12),
                                    Text('گالری «${selectedTopic.first['topic_name']}» خالی است.'),
                                    const SizedBox(height: 8),
                                    const Text('با دکمه افزودن عکس، چند تصویر انتخاب کنید.'),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.only(bottom: 88),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: _images.length,
                                itemBuilder: (context, index) {
                                  final image = _images[index];
                                  final path = image['image_path'].toString();
                                  return GestureDetector(
                                    onTap: () => _openImage(index),
                                    onLongPress: () => _deleteImage(image),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.file(
                                            File(path),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const ColoredBox(
                                              color: Colors.black12,
                                              child: Icon(Icons.broken_image_outlined),
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: Material(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(20),
                                              child: InkWell(
                                                onTap: () => _deleteImage(image),
                                                borderRadius: BorderRadius.circular(20),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(5),
                                                  child: Icon(Icons.delete_outline, size: 17, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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

class _GalleryImageViewer extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  final int topicId;

  const _GalleryImageViewer({
    required this.images,
    required this.initialIndex,
    required this.topicId,
  });

  @override
  State<_GalleryImageViewer> createState() => _GalleryImageViewerState();
}

class _GalleryImageViewerState extends State<_GalleryImageViewer> {
  final GlobalKey _paintBoundaryKey = GlobalKey();
  late int _currentIndex;
  final List<Offset?> _points = [];
  Color _selectedColor = Colors.red;
  double _strokeWidth = 4;
  bool _drawingMode = false;
  bool _saving = false;

  static const List<Color> _colors = [
    Colors.red,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.white,
    Colors.black,
  ];

  String get _currentPath =>
      widget.images[_currentIndex]['image_path'].toString();

  void _changeImage(int delta) {
    final next = _currentIndex + delta;
    if (next < 0 || next >= widget.images.length) return;
    setState(() {
      _currentIndex = next;
      _points.clear();
      _drawingMode = false;
    });
  }

  Future<void> _saveDrawing() async {
    if (_saving || _points.isEmpty) {
      _showMessage('ابتدا روی عکس نقاشی کنید.');
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary = _paintBoundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw Exception('تبدیل تصویر انجام نشد.');

      final appDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory(p.join(
        appDir.path,
        'custom_gallery',
        widget.topicId.toString(),
      ));
      await outputDir.create(recursive: true);
      final outputPath = p.join(
        outputDir.path,
        'edited_\${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await File(outputPath).writeAsBytes(byteData.buffer.asUint8List());

      final db = await AppDatabase.instance.database;
      await db.insert('custom_gallery_images', {
        'topic_id': widget.topicId,
        'image_path': outputPath,
        'image_order': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      _showMessage('نسخه ویرایش‌شده به گالری اضافه شد.');
      setState(() {
        _points.clear();
        _drawingMode = false;
      });
    } catch (error) {
      _showMessage('ذخیره تصویر انجام نشد: \$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('\${_currentIndex + 1} از \${widget.images.length}'),
        actions: [
          IconButton(
            tooltip: 'نقاشی روی عکس',
            onPressed: () => setState(() {
              _drawingMode = !_drawingMode;
              if (!_drawingMode) _points.clear();
            }),
            icon: Icon(
              _drawingMode ? Icons.edit_off : Icons.draw_outlined,
              color: _drawingMode ? Colors.amber : Colors.white,
            ),
          ),
          if (_drawingMode) ...[
            IconButton(
              tooltip: 'برگشت یک مرحله',
              onPressed: _points.isEmpty
                  ? null
                  : () {
                      setState(() {
                        while (_points.isNotEmpty && _points.last != null) {
                          _points.removeLast();
                        }
                        if (_points.isNotEmpty) _points.removeLast();
                      });
                    },
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'پاک کردن نقاشی',
              onPressed: () => setState(() => _points.clear()),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
            IconButton(
              tooltip: 'ذخیره نسخه نقاشی‌شده',
              onPressed: _saving ? null : _saveDrawing,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'عکس قبلی',
                  onPressed: _currentIndex > 0 ? () => _changeImage(-1) : null,
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  icon: const Icon(Icons.chevron_left, size: 38),
                ),
                Expanded(
                  child: Center(
                    child: RepaintBoundary(
                      key: _paintBoundaryKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onPanStart: _drawingMode
                                ? (details) => setState(() {
                                      _points.add(details.localPosition);
                                    })
                                : null,
                            onPanUpdate: _drawingMode
                                ? (details) => setState(() {
                                      _points.add(details.localPosition);
                                    })
                                : null,
                            onPanEnd: _drawingMode
                                ? (_) => setState(() => _points.add(null))
                                : null,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(_currentPath),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                  CustomPaint(
                                    painter: _GalleryDrawingPainter(
                                      points: _points,
                                      color: _selectedColor,
                                      strokeWidth: _strokeWidth,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'عکس بعدی',
                  onPressed: _currentIndex < widget.images.length - 1
                      ? () => _changeImage(1)
                      : null,
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  icon: const Icon(Icons.chevron_right, size: 38),
                ),
              ],
            ),
          ),
          if (_drawingMode)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Colors.black87,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _colors.map((color) {
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedColor == color
                                    ? Colors.amber
                                    : Colors.white54,
                                width: _selectedColor == color ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.brush, color: Colors.white70),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 18,
                            value: _strokeWidth,
                            onChanged: (value) =>
                                setState(() => _strokeWidth = value),
                          ),
                        ),
                        Text(
                          _strokeWidth.toStringAsFixed(0),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    const Text(
                      'برای نقاشی، انگشت خود را روی عکس حرکت دهید؛ سپس ذخیره را بزنید.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GalleryDrawingPainter extends CustomPainter {
  final List<Offset?> points;
  final Color color;
  final double strokeWidth;

  const _GalleryDrawingPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, paint);
      } else if (current != null) {
        canvas.drawPoints(ui.PointMode.points, [current], paint);
      }
    }
    if (points.isNotEmpty && points.last != null) {
      canvas.drawPoints(ui.PointMode.points, [points.last!], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GalleryDrawingPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
