import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ticker.dart';
import 'price_alert_service.dart';

class LBankService {
  static const String _url =
      'https://lbkperp.lbank.com/cfd/openApi/v1/pub/marketData';

  // دریافت قیمت هر 1 ثانیه
  static const Duration _pollInterval = Duration(seconds: 1);

  Timer? _timer;

  bool _disposed = false;
  bool _loading = false;
  bool _active = true;

  String _symbol = 'GOLDUSDT';

  final StreamController<Ticker> _tickerController =
      StreamController<Ticker>.broadcast();

  Stream<Ticker> get tickerStream => _tickerController.stream;

  bool get isActive => _active;

  Future<void> connect([
    String symbol = 'GOLDUSDT',
  ]) async {
    if (_disposed) return;

    _symbol = symbol.trim().toUpperCase();

    _active = true;

    debugPrint(
      '🟡 LBANK CONNECT: $_symbol',
    );

    await _getPrice();

    if (_disposed || !_active) return;

    _startTimer();
  }

  Future<void> changeSymbol(
    String symbol,
  ) async {
    if (_disposed) return;

    _symbol = symbol.trim().toUpperCase();

    // قیمت قبلی این نماد پاک شود
    // تا تشخیص عبور از سطح برای نماد جدید
    // از وضعیت قبلی استفاده نکند.
    PriceAlertService.instance.clearPreviousPrice(_symbol);

    debugPrint(
      '🟡 LBANK SYMBOL CHANGED: $_symbol',
    );

    if (!_active) return;

    await _getPrice();
  }

  Future<void> resume() async {
    if (_disposed) return;

    if (_active && _timer != null) {
      return;
    }

    _active = true;

    debugPrint(
      '🟢 LBANK RESUME: $_symbol',
    );

    await _getPrice();

    if (_disposed || !_active) return;

    _startTimer();
  }

  Future<void> pause() async {
    if (_disposed) return;

    _active = false;

    _timer?.cancel();
    _timer = null;

    debugPrint(
      '🔴 LBANK PAUSED: $_symbol',
    );
  }

  void _startTimer() {
    if (_disposed || !_active) return;

    _timer?.cancel();

    _timer = Timer.periodic(
      _pollInterval,
      (_) {
        if (_disposed || !_active) {
          return;
        }

        _getPrice();
      },
    );

    debugPrint(
      '🟢 LBANK TIMER STARTED: '
      '$_symbol / $_pollInterval',
    );
  }

  Future<void> _getPrice() async {
    if (_disposed || !_active || _loading) {
      return;
    }

    _loading = true;

    try {
      final uri = Uri.parse(_url).replace(
        queryParameters: {
          'productGroup': 'SwapU',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      );

      if (_disposed || !_active) {
        return;
      }

      debugPrint(
        'LBank HTTP: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        debugPrint(
          'LBank HTTP ERROR: '
          '${response.body}',
        );
        return;
      }

      final decoded = jsonDecode(response.body);

      Map<String, dynamic>? target;

      if (decoded is List) {
        target = _findSymbol(
          decoded,
          _symbol,
        );
      }

      if (decoded is Map) {
        final root = Map<String, dynamic>.from(
          decoded,
        );

        target = _findSymbolAnywhere(
          root,
          _symbol,
        );
      }

      if (target == null) {
        debugPrint(
          '$_symbol NOT FOUND '
          'IN LBANK RESPONSE',
        );
        return;
      }

      final rawPrice = target['lastPrice'] ??
          target['last'] ??
          target['price'] ??
          target['close'];

      final price = double.tryParse(
        rawPrice?.toString() ?? '',
      );

      if (price == null || price <= 0) {
        debugPrint(
          'INVALID $_symbol PRICE: '
          '$rawPrice',
        );
        return;
      }

      if (!_active || _disposed) {
        return;
      }

      debugPrint(
        '💰 LBANK PRICE: '
        '$_symbol = $price',
      );

      // ============================================================
      // مهم:
      // قیمت دریافت‌شده از LBank مستقیماً به موتور هشدار ارسال می‌شود.
      // ============================================================

      unawaited(
        PriceAlertService.instance.checkPrice(
          symbol: _symbol,
          currentPrice: price,
        ),
      );

      debugPrint(
        '🔔 PRICE SENT TO ALERT SERVICE: '
        '$_symbol = $price',
      );

      // ارسال قیمت برای رابط کاربری
      if (!_tickerController.isClosed) {
        _tickerController.add(
          Ticker(
            price: price,
          ),
        );
      }
    } catch (e, stackTrace) {
      if (_active && !_disposed) {
        debugPrint(
          '❌ LBank ERROR: $e',
        );

        debugPrint(
          '$stackTrace',
        );
      }
    } finally {
      _loading = false;
    }
  }

  Map<String, dynamic>? _findSymbolAnywhere(
    Map<String, dynamic> map,
    String symbol,
  ) {
    final currentSymbol = map['symbol']?.toString().toUpperCase();

    if (currentSymbol == symbol) {
      return map;
    }

    for (final value in map.values) {
      if (value is Map) {
        final result = _findSymbolAnywhere(
          Map<String, dynamic>.from(
            value,
          ),
          symbol,
        );

        if (result != null) {
          return result;
        }
      }

      if (value is List) {
        final result = _findSymbol(
          value,
          symbol,
        );

        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _findSymbol(
    List<dynamic> list,
    String symbol,
  ) {
    for (final item in list) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(
        item,
      );

      final currentSymbol = map['symbol']?.toString().toUpperCase();

      if (currentSymbol == symbol) {
        return map;
      }

      final nested = _findSymbolAnywhere(
        map,
        symbol,
      );

      if (nested != null) {
        return nested;
      }
    }

    return null;
  }

  Future<void> disconnect() async {
    _active = false;

    _timer?.cancel();
    _timer = null;

    debugPrint(
      '🔴 LBANK DISCONNECTED: '
      '$_symbol',
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _active = false;

    _timer?.cancel();
    _timer = null;

    PriceAlertService.instance.clearPreviousPrice(
      _symbol,
    );

    await _tickerController.close();
  }
}
