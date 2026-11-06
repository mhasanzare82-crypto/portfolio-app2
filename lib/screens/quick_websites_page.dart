import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

class QuickWebsitesPage extends StatefulWidget {
  final bool embedded;
  const QuickWebsitesPage({super.key, this.embedded = false});
  @override
  State<QuickWebsitesPage> createState() => _QuickWebsitesPageState();
}

class _QuickWebsitesPageState extends State<QuickWebsitesPage> {
  static const String _storageKey = 'quick_websites_v2';
  final List<Map<String, String>> _sites = [];
  final Map<String, WebViewController> _controllers = {};
  final Set<String> _visible = {};
  final Set<String> _locked = {};
  final Set<String> _loading = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final defaults = <Map<String, String>>[
      {
        'name': 'Faraz',
        'url': 'https://faraz.io/dashboard?s=XAU_USD&i=3&a=draft&adj=0'
      },
      {'name': 'TradingView', 'url': 'https://www.tradingview.com/chart/'},
    ];
    var sites = defaults;
    if (raw != null) {
      try {
        sites = (jsonDecode(raw) as List)
            .map((e) =>
                {'name': e['name'].toString(), 'url': e['url'].toString()})
            .toList();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _sites
        ..clear()
        ..addAll(sites);
      _loaded = true;
    });
  }

  Future<void> _saveSites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_sites));
  }

  String _key(Map<String, String> site) => site['url'] ?? '';

  WebViewController _controllerFor(Map<String, String> site) {
    final key = _key(site);
    return _controllers.putIfAbsent(key, () {
      return WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading.add(key));
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading.remove(key));
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _loading.remove(key));
            }
          },
        ));
    });
  }

  Future<void> _showAddSiteDialog({Map<String, String>? existing}) async {
    final name = TextEditingController(text: existing?['name'] ?? '');
    final url = TextEditingController(text: existing?['url'] ?? 'https://');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'افزودن سایت جدید' : 'ویرایش سایت'),
        content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'نام سایت')),
              TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration:
                      const InputDecoration(labelText: 'آدرس کامل سایت')),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () {
                final parsed = Uri.tryParse(url.text.trim());
                if (name.text.trim().isEmpty ||
                    parsed == null ||
                    !parsed.hasScheme ||
                    !{'http', 'https'}.contains(parsed.scheme)) return;
                Navigator.pop(context,
                    {'name': name.text.trim(), 'url': url.text.trim()});
              },
              child: const Text('ذخیره')),
        ],
      ),
    );
    name.dispose();
    url.dispose();
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final index = _sites.indexOf(existing);
        if (index >= 0) _sites[index] = result;
        _controllers.remove(existing['url']);
      } else {
        _sites.add(result);
      }
    });
    await _saveSites();
  }

  Future<void> _removeSite(Map<String, String> site) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('حذف سایت'),
              content: Text('«${site['name']}» از فهرست حذف شود؟'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('لغو')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('حذف'))
              ],
            ));
    if (ok != true) return;
    setState(() {
      _sites.remove(site);
      _controllers.remove(site['url']);
      _visible.remove(site['url']);
      _locked.remove(site['url']);
    });
    await _saveSites();
  }

  Future<void> _openFullScreen(Map<String, String> site) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _FullScreenSite(
                name: site['name'] ?? 'سایت', url: _key(site))));
  }

  Widget _siteCard(Map<String, String> site) {
    final key = _key(site);
    final visible = _visible.contains(key);
    final controller = _controllerFor(site);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(
                  child: Text(site['name'] ?? 'سایت',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(
                  tooltip: 'ویرایش سایت',
                  onPressed: () => _showAddSiteDialog(existing: site),
                  icon: const Icon(Icons.edit_outlined)),
              IconButton(
                  tooltip: 'حذف سایت',
                  onPressed: () => _removeSite(site),
                  icon: const Icon(Icons.delete_outline)),
              IconButton(
                  tooltip: 'تمام‌صفحه',
                  onPressed: () => _openFullScreen(site),
                  icon: const Icon(Icons.fullscreen)),
              Checkbox(
                  value: visible,
                  onChanged: (v) async {
                    setState(() {
                      if (v == true) {
                        _visible.add(key);
                      } else {
                        _visible.remove(key);
                      }
                    });
                    if (v == true) {
                      try {
                        await controller.loadRequest(Uri.parse(key));
                      } catch (_) {}
                    }
                  }),
            ])),
        if (visible) ...[
          const Divider(height: 1),
          CheckboxListTile(
            dense: true,
            value: _locked.contains(key),
            onChanged: (v) => setState(() {
              if (v == true)
                _locked.add(key);
              else
                _locked.remove(key);
            }),
            title: const Text('قفل اسکرول سایت'),
            subtitle: const Text(
                'فعال: اسکرول داخل سایت؛ غیرفعال: اسکرول صفحهٔ برنامه'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_loading.contains(key)) const LinearProgressIndicator(),
          SizedBox(
              height: 360,
              child: WebViewWidget(
                controller: controller,
                gestureRecognizers: _locked.contains(key)
                    ? <Factory<OneSequenceGestureRecognizer>>{
                        Factory<EagerGestureRecognizer>(
                            () => EagerGestureRecognizer())
                      }
                    : const <Factory<OneSequenceGestureRecognizer>>{},
              )),
        ],
      ]),
    );
  }

  Widget _content() {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // در حالت توکار، این ویجت داخل ListView صفحه «معامله جدید» قرار دارد.
    // بنابراین نباید یک ListView عمودی دیگر با ارتفاع نامحدود بسازد؛
    // از Column استفاده می‌کنیم تا رندر این بخش و بخش‌های بعدی صفحه متوقف نشود.
    final children = <Widget>[
      Row(
        children: [
          const Expanded(
            child: Text(
              'دسترسی به سایت',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton.icon(
            onPressed: _showAddSiteDialog,
            icon: const Icon(Icons.add),
            label: const Text('افزودن سایت'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ..._sites.map(_siteCard),
    ];

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _content();
    return Scaffold(
      appBar: AppBar(title: const Text('دسترسی سریع به سایت')),
      body: _content(),
    );
  }
}

class _FullScreenSite extends StatefulWidget {
  final String name;
  final String url;
  const _FullScreenSite({required this.name, required this.url});
  @override
  State<_FullScreenSite> createState() => _FullScreenSiteState();
}

class _FullScreenSiteState extends State<_FullScreenSite> {
  late final WebViewController _controller;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: WebViewWidget(controller: _controller));
}
