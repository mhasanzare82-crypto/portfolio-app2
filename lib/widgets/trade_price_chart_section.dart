import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class _TradeCandle {
  final DateTime time;
  final double open, high, low, close;
  const _TradeCandle(this.time, this.open, this.high, this.low, this.close);
}

class TradePriceChartSection extends StatefulWidget {
  final String symbol;
  final double entryPrice;
  const TradePriceChartSection({super.key, required this.symbol, required this.entryPrice});
  @override
  State<TradePriceChartSection> createState() => _TradePriceChartSectionState();
}

class _TradePriceChartSectionState extends State<TradePriceChartSection> {
  static const frames = <String, String>{'1 دقیقه':'1min','3 دقیقه':'3min','5 دقیقه':'5min','15 دقیقه':'15min','30 دقیقه':'30min','1 ساعت':'1hr','2 ساعت':'2hr','4 ساعت':'4hr'};
  String frame = '5 دقیقه';
  String rangeMode = 'کندل';
  final TextEditingController rangeController = TextEditingController(text: '100');
  static const rangeModes = <String, String>{'دقیقه':'دقیقه','ساعت':'ساعت','کندل':'کندل'};
  double upper = 5, lower = 5;
  bool loading = false;
  String? error;
  List<_TradeCandle> candles = [];
  DateTime? fetchedAt;
  double get minPrice => widget.entryPrice * (1 - lower / 100);
  double get maxPrice => widget.entryPrice * (1 + upper / 100);

  int _minutes(String slot) => const {'1min':1,'3min':3,'5min':5,'15min':15,'30min':30,'1hr':60,'2hr':120,'4hr':240}[slot] ?? 5;
  String _pair(String s) {
    final v=s.trim().toLowerCase().replaceAll('/','_').replaceAll('-','_');
    return v.contains('_') ? v : v.replaceAll('usdt','_usdt');
  }
  double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());
  DateTime? _date(dynamic v) {
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt() < 1000000000000 ? v.toInt()*1000 : v.toInt(), isUtc:true).toLocal();
    return v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  }
  void _parse(dynamic data, List<_TradeCandle> out) {
    if (data is List) {
      if (data.length >= 5 && data[0] is! Map && _date(data[0]) != null) {
        final t=_date(data[0]), o=_num(data[1]), h=_num(data[2]), l=_num(data[3]), c=_num(data[4]);
        if (t!=null && o!=null && h!=null && l!=null && c!=null) out.add(_TradeCandle(t,o,h,l,c));
      } else { for (final x in data) { _parse(x,out); } }
      return;
    }
    if (data is! Map) return;
    final m=Map<String,dynamic>.from(data);
    final nested=m['data'] ?? m['kbar'] ?? m['list'];
    if (nested is List || nested is Map) { _parse(nested,out); return; }
    final t=_date(m['t'] ?? m['time'] ?? m['timestamp']);
    final o=_num(m['o'] ?? m['open']), h=_num(m['h'] ?? m['high']), l=_num(m['l'] ?? m['low']), c=_num(m['c'] ?? m['close']);
    if (t!=null && o!=null && h!=null && l!=null && c!=null) out.add(_TradeCandle(t,o,h,l,c));
  }

  @override
  void dispose() {
    rangeController.dispose();
    super.dispose();
  }

  int _requestedCount(DateTime now) {
    final amount = int.tryParse(rangeController.text.trim()) ?? 0;
    if (amount < 1) throw Exception('مدت یا تعداد کندل باید بیشتر از صفر باشد.');
    final interval = _minutes(frames[frame]!);
    if (rangeMode == 'کندل') return amount.clamp(1, 1000);
    final totalMinutes = rangeMode == 'ساعت' ? amount * 60 : amount;
    return (totalMinutes / interval).ceil().clamp(1, 1000);
  }

  Future<void> _fetch() async {
    if (widget.entryPrice <= 0) { setState(()=>error='قیمت ورود معتبر نیست.'); return; }
    setState(() { loading=true; error=null; });
    WebSocket? ws;
    StreamSubscription? sub;
    Timer? timeout, quiet;
    final rows=< _TradeCandle>[];
    final done=Completer<void>();
    void finish(){ if(!done.isCompleted) done.complete(); }
    try {
      final end=DateTime.now().toUtc();
      final requestedSlot=frames[frame]!;
      final count=_requestedCount(end);
      final start=end.subtract(Duration(minutes: count * _minutes(requestedSlot)));
      final sourceSlot=requestedSlot=='3min'?'1min':requestedSlot=='2hr'?'1hr':requestedSlot;
      ws=await WebSocket.connect('wss://lbkperpws.lbank.com/ws').timeout(const Duration(seconds:12));
      sub=ws.listen((event){
        try {
          final decoded=jsonDecode(event.toString());
          if(decoded is Map && decoded['action']=='ping'){ ws?.add(jsonEncode({'action':'pong','pong':decoded['ping']})); return; }
          _parse(decoded,rows);
          if(rows.isNotEmpty){ quiet?.cancel(); quiet=Timer(const Duration(milliseconds:900),finish); }
        } catch(_){}
      },onError:(_)=>finish(),onDone:finish);
      ws.add(jsonEncode({'action':'request','request':'kbar','kbar':sourceSlot,'pair':_pair(widget.symbol),'start':(start.millisecondsSinceEpoch~/1000).toString(),'end':(end.millisecondsSinceEpoch~/1000).toString(),'size':count.toString()}));
      timeout=Timer(const Duration(seconds:15),finish);
      await done.future;
      if(rows.isEmpty) throw Exception('از سرویس کندل قرارداد داده‌ای دریافت نشد. نماد یا تایم‌فریم ممکن است پشتیبانی نشود.');
      final unique=<int,_TradeCandle>{};
      for(final c in rows){ unique[c.time.millisecondsSinceEpoch]=c; }
      final source=unique.values.toList()..sort((a,b)=>a.time.compareTo(b.time));
      final result=_aggregate(source,requestedSlot);
      if(mounted) setState((){ candles=result; fetchedAt=DateTime.now(); });
    } catch(e) {
      if(mounted) setState(()=>error='دریافت کندل‌ها ناموفق بود: $e');
    } finally {
      timeout?.cancel(); quiet?.cancel(); await sub?.cancel(); await ws?.close();
      if(mounted) setState(()=>loading=false);
    }
  }

  List<_TradeCandle> _aggregate(List<_TradeCandle> source,String slot) {
    final interval=_minutes(slot);
    if(interval==1||interval==60||interval==5||interval==15||interval==30||interval==240) return source;
    final groups=<int,List<_TradeCandle>>{};
    for(final candle in source){
      final minute=candle.time.millisecondsSinceEpoch~/60000;
      final key=minute~/interval;
      (groups[key]??=< _TradeCandle>[]).add(candle);
    }
    return groups.values.map((items){
      items.sort((a,b)=>a.time.compareTo(b.time));
      return _TradeCandle(items.first.time,items.first.open,
        items.map((x)=>x.high).reduce((a,b)=>a>b?a:b),
        items.map((x)=>x.low).reduce((a,b)=>a<b?a:b),items.last.close);
    }).toList()..sort((a,b)=>a.time.compareTo(b.time));
  }

  Widget _percent(String title,double value,ValueChanged<double> change)=>Column(mainAxisSize:MainAxisSize.min,children:[
    Text(title+' '+value.toStringAsFixed(0)+'٪',style:const TextStyle(fontSize:12)),
    Row(mainAxisSize:MainAxisSize.min,children:[
      IconButton(visualDensity:VisualDensity.compact,onPressed:value<=0?null:()=>change((value-1).clamp(0,100)),icon:const Icon(Icons.remove_circle_outline)),
      IconButton(visualDensity:VisualDensity.compact,onPressed:value>=100?null:()=>change((value+1).clamp(0,100)),icon:const Icon(Icons.add_circle_outline)),
    ])]);
  String _fmt(DateTime d)=>d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0')+' '+d.hour.toString().padLeft(2,'0')+':'+d.minute.toString().padLeft(2,'0');

  @override
  Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(top:14,bottom:10),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Text('نمودار قیمتی',textAlign:TextAlign.right,style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    const SizedBox(height:10),
    DropdownButtonFormField<String>(value:frame,decoration:const InputDecoration(labelText:'تایم‌فریم',isDense:true,border:OutlineInputBorder()),items:frames.keys.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:loading?null:(v){if(v!=null)setState(()=>frame=v);}),
    const SizedBox(height:8),
    Row(children:[
      Expanded(child:DropdownButtonFormField<String>(
        value:rangeMode,
        decoration:const InputDecoration(labelText:'نوع بازه',isDense:true,border:OutlineInputBorder()),
        items:rangeModes.keys.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
        onChanged:loading?null:(v){if(v!=null)setState(()=>rangeMode=v);},
      )),
      const SizedBox(width:8),
      Expanded(child:TextField(
        controller:rangeController,
        enabled:!loading,
        keyboardType:TextInputType.number,
        decoration:InputDecoration(labelText:rangeMode=='کندل'?'تعداد کندل':rangeMode=='ساعت'?'تعداد ساعت':'تعداد دقیقه',border:const OutlineInputBorder(),isDense:true),
      )),
    ]),
    const SizedBox(height:6),
    Wrap(alignment:WrapAlignment.spaceAround,runSpacing:4,children:[_percent('محدوده بالای قیمت مرجع',upper,(v)=>setState(()=>upper=v)),_percent('محدوده پایین قیمت مرجع',lower,(v)=>setState(()=>lower=v))]),
    Text('کف: '+minPrice.toStringAsFixed(4)+'   ورود: '+widget.entryPrice.toStringAsFixed(4)+'   سقف: '+maxPrice.toStringAsFixed(4),textDirection:TextDirection.ltr,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)),
    const SizedBox(height:8),
    FilledButton.icon(onPressed:loading?null:_fetch,icon:loading?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.download),label:Text(loading?'در حال دریافت...':'دریافت نمودار از LBank')),
    if(error!=null) Padding(padding:const EdgeInsets.only(top:8),child:Text(error!,textAlign:TextAlign.right,style:TextStyle(color:Theme.of(context).colorScheme.error))),
    if(candles.isNotEmpty)...[
      const SizedBox(height:10),
      SizedBox(height:250,child:CustomPaint(painter:_CandlePainter(candles,minPrice,maxPrice,widget.entryPrice,Theme.of(context).colorScheme.onSurface,Theme.of(context).dividerColor),child:const SizedBox.expand())),
      Text(candles.length.toString()+' کندل | از '+_fmt(candles.first.time)+' تا '+_fmt(candles.last.time),textAlign:TextAlign.center,style:const TextStyle(fontSize:11)),
      if(fetchedAt!=null) Text('آخرین دریافت: '+_fmt(fetchedAt!),textAlign:TextAlign.center,style:const TextStyle(fontSize:10)),
      const SizedBox(height:8),
      Wrap(alignment:WrapAlignment.spaceAround,children:[
        _ohlc('بازشدن',candles.last.open),_ohlc('بیشترین',candles.last.high),_ohlc('کمترین',candles.last.low),_ohlc('بسته‌شدن',candles.last.close),
      ]),
    ],
  ])));

  Widget _ohlc(String label,double value)=>Column(children:[Text(label,style:const TextStyle(fontSize:10)),Text(value.toStringAsFixed(4),textDirection:TextDirection.ltr,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600))]);
}

class _CandlePainter extends CustomPainter {
  final List<_TradeCandle> candles;
  final double min,max,entry;
  final Color foreground,gridColor;
  _CandlePainter(this.candles,this.min,this.max,this.entry,this.foreground,this.gridColor);
  @override
  void paint(Canvas canvas,Size size){
    if(candles.isEmpty||max<=min)return;
    const pad=8.0;
    final r=Rect.fromLTRB(pad,pad,size.width-pad,size.height-18);
    double y(double p)=>r.bottom-(p-min)/(max-min)*r.height;
    final grid=Paint()..color=gridColor.withValues(alpha:.45)..strokeWidth=.7;
    for(int i=0;i<=4;i++){final py=r.top+r.height*i/4;canvas.drawLine(Offset(r.left,py),Offset(r.right,py),grid);final price=max-(max-min)*i/4;final tp=TextPainter(text:TextSpan(text:price.toStringAsFixed(2),style:TextStyle(color:foreground,fontSize:9)),textDirection:TextDirection.ltr)..layout(maxWidth:r.width);tp.paint(canvas,Offset(r.left+2,py+1));}
    canvas.drawLine(Offset(r.left,y(entry)),Offset(r.right,y(entry)),Paint()..color=Colors.amber..strokeWidth=1.2);
    final visible=candles.where((c)=>c.high>=min&&c.low<=max).toList();
    if(visible.isEmpty)return;
    final slot=r.width/visible.length, body=(slot*.62).clamp(1.0,12.0);
    for(int i=0;i<visible.length;i++){
      final c=visible[i],x=r.left+slot*(i+.5),up=c.close>=c.open;
      final paint=Paint()..strokeWidth=1;
      paint.color=up?const Color(0xff16a34a):const Color(0xffef4444);
      canvas.drawLine(Offset(x,y(c.high)),Offset(x,y(c.low)),paint);
      final top=y(up?c.close:c.open),bottom=y(up?c.open:c.close);
      canvas.drawRect(Rect.fromLTRB(x-body/2,top,x+body/2,bottom-top<1?top+1:bottom),paint);
    }
  }
  @override
  bool shouldRepaint(covariant _CandlePainter old)=>old.candles!=candles||old.min!=min||old.max!=max||old.entry!=entry||old.foreground!=foreground||old.gridColor!=gridColor;
}
