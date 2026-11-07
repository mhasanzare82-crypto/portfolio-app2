import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class _PricePoint {
  final DateTime time;
  final double price;
  const _PricePoint(this.time, this.price);
}

class _TradeCandle {
  final DateTime time;
  final double close;
  const _TradeCandle(this.time, this.close);
}

class TradePriceChartSection extends StatefulWidget {
  final String symbol;
  final double entryPrice;
  const TradePriceChartSection({super.key, required this.symbol, required this.entryPrice});
  @override
  State<TradePriceChartSection> createState() => _TradePriceChartSectionState();
}

class _TradePriceChartSectionState extends State<TradePriceChartSection> {
  static const frames = <String, String>{
    '1 دقیقه': '1min', '5 دقیقه': '5min', '15 دقیقه': '15min',
    '30 دقیقه': '30min', '1 ساعت': '1hr', '4 ساعت': '4hr',
  };
  String frame = '5 دقیقه';
  late DateTime startAt;
  late DateTime endAt;
  bool loading = false;
  String? error;
  List<_PricePoint> points = [];
  DateTime? fetchedAt;

  @override
  void initState() {
    super.initState();
    endAt = DateTime.now();
    startAt = endAt.subtract(const Duration(hours: 24));
  }

  String _pair(String symbol) {
    final value = symbol.trim().toLowerCase().replaceAll('/', '_').replaceAll('-', '_');
    return value.contains('_') ? value : value.replaceAll('usdt', '_usdt');
  }

  double? _number(dynamic value) => value == null ? null : double.tryParse(value.toString());

  DateTime? _date(dynamic value) {
    if (value is num) {
      final ms = value.toInt() < 1000000000000 ? value.toInt() * 1000 : value.toInt();
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    return value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  }

  void _parse(dynamic data, List<_TradeCandle> result) {
    if (data is List) {
      if (data.length >= 5 && data[0] is! Map && _date(data[0]) != null) {
        final time = _date(data[0]);
        final close = _number(data[4]);
        if (time != null && close != null && close > 0) result.add(_TradeCandle(time, close));
      } else {
        for (final item in data) { _parse(item, result); }
      }
      return;
    }
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final nested = map['data'] ?? map['kbar'] ?? map['list'];
    if (nested is List || nested is Map) { _parse(nested, result); return; }
    final time = _date(map['t'] ?? map['time'] ?? map['timestamp']);
    final close = _number(map['c'] ?? map['close']);
    if (time != null && close != null && close > 0) result.add(_TradeCandle(time, close));
  }

  Future<void> _chooseDateTime(bool isStart) async {
    final current = isStart ? startAt : endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    final selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) { startAt = selected; } else { endAt = selected; }
      error = null;
    });
  }

  String _format(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    if (endAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      setState(() => error = 'زمان پایان نمی‌تواند در آینده باشد.');
      return;
    }
    if (!endAt.isAfter(startAt)) {
      setState(() => error = 'زمان پایان باید بعد از زمان شروع باشد.');
      return;
    }
    final slot = frames[frame]!;
    final interval = const {'1min': 1, '5min': 5, '15min': 15, '30min': 30, '1hr': 60, '4hr': 240}[slot]!;
    final requested = (endAt.difference(startAt).inSeconds / (interval * 60)).ceil() + 2;
    if (requested > 1000) {
      setState(() => error = 'این بازه بیش از ۱۰۰۰ نقطه نیاز دارد؛ بازه کوتاه‌تر یا تایم‌فریم بزرگ‌تر انتخاب کنید.');
      return;
    }

    setState(() { loading = true; error = null; points = []; });
    WebSocket? socket;
    StreamSubscription? subscription;
    Timer? timeout, quietTimer;
    final candles = <_TradeCandle>[];
    final completed = Completer<void>();
    void finish() { if (!completed.isCompleted) completed.complete(); }

    try {
      socket = await WebSocket.connect('wss://lbkperpws.lbank.com/ws').timeout(const Duration(seconds: 12));
      subscription = socket.listen((event) {
        try {
          final decoded = jsonDecode(event.toString());
          if (decoded is Map && decoded['action'] == 'ping') {
            socket?.add(jsonEncode({'action': 'pong', 'pong': decoded['ping']}));
            return;
          }
          _parse(decoded, candles);
          if (candles.isNotEmpty) {
            quietTimer?.cancel();
            quietTimer = Timer(const Duration(milliseconds: 900), finish);
          }
        } catch (_) {}
      }, onError: (_) => finish(), onDone: finish);

      socket.add(jsonEncode({
        'action': 'request', 'request': 'kbar', 'kbar': slot,
        'pair': _pair(widget.symbol),
        'start': (startAt.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
        'end': (endAt.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
        'size': requested.toString(),
      }));
      timeout = Timer(const Duration(seconds: 15), finish);
      await completed.future;

      final from = startAt.millisecondsSinceEpoch;
      final to = endAt.millisecondsSinceEpoch;
      final unique = <int, _TradeCandle>{};
      for (final candle in candles) {
        final stamp = candle.time.millisecondsSinceEpoch;
        if (stamp >= from && stamp <= to) unique[stamp] = candle;
      }
      final sorted = unique.values.toList()..sort((a, b) => a.time.compareTo(b.time));
      if (sorted.isEmpty) throw Exception('برای این نماد و بازه از LBank داده‌ای دریافت نشد.');
      if (mounted) {
        setState(() {
          points = sorted.map((c) => _PricePoint(c.time, c.close)).toList();
          fetchedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'دریافت قیمت از LBank ناموفق بود: $e');
    } finally {
      timeout?.cancel();
      quietTimer?.cancel();
      await subscription?.cancel();
      await socket?.close();
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _dateButton(String label, DateTime value, VoidCallback action) => Expanded(
    child: OutlinedButton(
      onPressed: loading ? null : action,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        Text(_format(value), textAlign: TextAlign.center, textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 14, bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('نمودار خطی قیمت', textAlign: TextAlign.right,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: frame,
            decoration: const InputDecoration(labelText: 'فاصله زمانی نقاط نمودار', isDense: true, border: OutlineInputBorder()),
            items: frames.keys.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: loading ? null : (v) { if (v != null) setState(() => frame = v); },
          ),
          const SizedBox(height: 8),
          Row(children: [
            _dateButton('از تاریخ و ساعت', startAt, () => _chooseDateTime(true)),
            const SizedBox(width: 8),
            _dateButton('تا تاریخ و ساعت', endAt, () => _chooseDateTime(false)),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: loading ? null : _fetch,
            icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.show_chart),
            label: Text(loading ? 'در حال دریافت قیمت‌ها...' : 'نمایش نمودار این بازه'),
          ),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, textAlign: TextAlign.right, style: TextStyle(color: colors.error)),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(height: 280, child: CustomPaint(
              painter: _PriceLinePainter(points, colors.onSurface, Theme.of(context).dividerColor, colors.primary),
              child: const SizedBox.expand(),
            )),
            const SizedBox(height: 8),
            Text('${points.length} نقطه قیمت | ${_format(points.first.time)} تا ${_format(points.last.time)}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            Text('آخرین قیمت: ${points.last.price.toStringAsFixed(4)}',
              textAlign: TextAlign.center, textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (fetchedAt != null) Text('آخرین دریافت: ${_format(fetchedAt!)}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
          ],
        ]),
      ),
    );
  }
}

class _PriceLinePainter extends CustomPainter {
  final List<_PricePoint> points;
  final Color foreground, gridColor, lineColor;
  _PriceLinePainter(this.points, this.foreground, this.gridColor, this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    const left = 58.0, right = 8.0, top = 12.0, bottom = 42.0;
    final chart = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    if (chart.width <= 0 || chart.height <= 0) return;
    final minTime = points.first.time.millisecondsSinceEpoch.toDouble();
    final maxTime = points.last.time.millisecondsSinceEpoch.toDouble();
    var low = points.map((p) => p.price).reduce((a, b) => a < b ? a : b);
    var high = points.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    if (high == low) {
      final pad = high.abs() * 0.001;
      low -= pad == 0 ? 1 : pad;
      high += pad == 0 ? 1 : pad;
    } else {
      final pad = (high - low) * 0.08;
      low -= pad;
      high += pad;
    }
    double x(DateTime t) => maxTime == minTime ? chart.left + chart.width / 2 :
      chart.left + (t.millisecondsSinceEpoch - minTime) / (maxTime - minTime) * chart.width;
    double y(double p) => chart.bottom - (p - low) / (high - low) * chart.height;

    final grid = Paint()..color = gridColor.withOpacity(0.55)..strokeWidth = 0.7;
    for (var i = 0; i <= 4; i++) {
      final py = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, py), Offset(chart.right, py), grid);
      final price = high - (high - low) * i / 4;
      final label = TextPainter(
        text: TextSpan(text: price.toStringAsFixed(2), style: TextStyle(color: foreground, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left - 6);
      label.paint(canvas, Offset(0, py - label.height / 2));
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = Offset(x(points[i].time), y(points[i].price));
      if (i == 0) { path.moveTo(point.dx, point.dy); } else { path.lineTo(point.dx, point.dy); }
    }
    canvas.drawPath(path, Paint()..color = lineColor..style = PaintingStyle.stroke..strokeWidth = 2
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset(chart.left, y(points.first.price)), 3.5, Paint()..color = lineColor);
    canvas.drawCircle(Offset(chart.right, y(points.last.price)), 3.5, Paint()..color = lineColor);

    final middle = DateTime.fromMillisecondsSinceEpoch(((minTime + maxTime) / 2).round());
    final labels = [(points.first.time, 0), (middle, 1), (points.last.time, 2)];
    for (final item in labels) {
      final t = item.$1;
      final position = item.$2;
      final label = TextPainter(
        text: TextSpan(
          text: '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}\n${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          style: TextStyle(color: foreground, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
        textAlign: position == 0 ? TextAlign.left : position == 2 ? TextAlign.right : TextAlign.center,
      )..layout(maxWidth: 70);
      final dx = position == 0 ? chart.left : position == 2 ? chart.right - label.width : chart.left + (chart.width - label.width) / 2;
      label.paint(canvas, Offset(dx, chart.bottom + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _PriceLinePainter old) =>
    old.points != points || old.foreground != foreground || old.gridColor != gridColor || old.lineColor != lineColor;
}
