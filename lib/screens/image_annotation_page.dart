import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

class ImageAnnotationPage extends StatefulWidget {
  final String imagePath;
  const ImageAnnotationPage({super.key, required this.imagePath});

  @override
  State<ImageAnnotationPage> createState() => _ImageAnnotationPageState();
}

class _ImageAnnotationPageState extends State<ImageAnnotationPage> {
  final GlobalKey _paintKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  final List<Color> _strokeColors = [];
  final List<double> _strokeWidths = [];
  Color _color = Colors.red;
  double _width = 4;
  Size? _sourceImageSize;
  bool _loadingImage = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _sourceImageSize = size;
        _loadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بارگذاری تصویر ناموفق بود: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _paintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final sourceSize = _sourceImageSize;
      if (boundary == null || sourceSize == null || boundary.size.width <= 0) {
        throw StateError('محدوده‌ی تصویر برای ذخیره آماده نیست.');
      }

      // نسبت پیکسل تصویر اصلی به اندازه‌ی نمایشی باعث می‌شود خروجی دقیقاً
      // محدوده‌ی خود تصویر باشد، نه کل فضای خالی صفحه.
      final pixelRatio = sourceSize.width / boundary.size.width;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('تبدیل تصویر به PNG ناموفق بود.');

      final Uint8List bytes = byteData.buffer.asUint8List();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/annotated_${DateTime.now().microsecondsSinceEpoch}.png';
      await File(path).writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ذخیره تصویر انجام نشد: $e')),
      );
    }
  }

  Size _fitImage(Size source, Size available) {
    if (source.width <= 0 ||
        source.height <= 0 ||
        available.width <= 0 ||
        available.height <= 0) {
      return Size.zero;
    }
    final scale = (available.width / source.width)
        .clamp(0.0, available.height / source.height)
        .toDouble();
    return Size(source.width * scale, source.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نقاشی روی تصویر'),
        actions: [
          IconButton(
            onPressed: _saving || _loadingImage || _sourceImageSize == null
                ? null
                : _save,
            tooltip: 'ذخیره تصویر',
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final color in [
                Colors.red,
                Colors.blue,
                Colors.green,
                Colors.yellow,
                Colors.white,
                Colors.black,
              ])
                IconButton(
                  tooltip: 'انتخاب رنگ',
                  onPressed: () => setState(() => _color = color),
                  icon: Icon(Icons.circle, color: color, size: 26),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        _color == color ? Colors.grey.shade300 : null,
                  ),
                ),
              IconButton(
                tooltip: 'پاک کردن آخرین خط',
                onPressed: _strokes.isEmpty
                    ? null
                    : () => setState(() {
                          _strokes.removeLast();
                          _strokeColors.removeLast();
                          _strokeWidths.removeLast();
                        }),
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'پاک کردن همه',
                onPressed: _strokes.isEmpty
                    ? null
                    : () => setState(() {
                          _strokes.clear();
                          _strokeColors.clear();
                          _strokeWidths.clear();
                        }),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          Expanded(
            child: _loadingImage
                ? const Center(child: CircularProgressIndicator())
                : _sourceImageSize == null
                    ? const Center(child: Text('تصویر قابل بارگذاری نیست.'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final fittedSize = _fitImage(
                            _sourceImageSize!,
                            Size(constraints.maxWidth, constraints.maxHeight),
                          );
                          if (fittedSize == Size.zero) {
                            return const SizedBox.shrink();
                          }
                          return Center(
                            child: RepaintBoundary(
                              key: _paintKey,
                              child: SizedBox(
                                width: fittedSize.width,
                                height: fittedSize.height,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (details) => setState(() {
                                    _strokes.add([details.localPosition]);
                                    _strokeColors.add(_color);
                                    _strokeWidths.add(_width);
                                  }),
                                  onPanUpdate: (details) {
                                    if (_strokes.isEmpty) return;
                                    setState(() => _strokes.last
                                        .add(details.localPosition));
                                  },
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(
                                        File(widget.imagePath),
                                        fit: BoxFit.fill,
                                        filterQuality: FilterQuality.high,
                                      ),
                                      CustomPaint(
                                        painter: _StrokePainter(
                                          _strokes,
                                          _strokeColors,
                                          _strokeWidths,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('ضخامت قلم'),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 1,
                    max: 12,
                    onChanged: (value) => setState(() => _width = value),
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      _saving || _loadingImage || _sourceImageSize == null
                          ? null
                          : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('ذخیره'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Color> colors;
  final List<double> widths;
  const _StrokePainter(this.strokes, this.colors, this.widths);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < strokes.length; i++) {
      final points = strokes[i];
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = colors[i]
        ..strokeWidth = widths[i]
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (points.length == 1) {
        canvas.drawCircle(
          points.first,
          widths[i] / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
