import 'dart:convert';
import 'dart:io';

/// Keeps the public LBank USDT perpetual contract list in memory for this run.
class LBankFuturesSymbolsService {
  LBankFuturesSymbolsService._();

  static final LBankFuturesSymbolsService instance =
      LBankFuturesSymbolsService._();

  List<String> _symbols = const [];
  Future<List<String>>? _loading;

  List<String> get symbols => List.unmodifiable(_symbols);

  Future<List<String>> load() {
    if (_symbols.isNotEmpty) return Future.value(symbols);
    return _loading ??= _fetch();
  }

  Future<List<String>> _fetch() async {
    final client = HttpClient();
    try {
      final uri = Uri.https(
        'lbkperp.lbank.com',
        '/cfd/openApi/v1/pub/instrument',
        {'productGroup': 'SwapU'},
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'LBank futures symbols request failed: HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      final dynamic rows = decoded is List
          ? decoded
          : decoded is Map
              ? (decoded['data'] ?? decoded['result'] ?? const [])
              : const [];

      if (rows is! List) {
        throw const FormatException('Unexpected LBank instrument response.');
      }

      final symbols = <String>{};
      for (final row in rows) {
        if (row is Map) {
          final value = (row['symbol'] ?? row['symbolName'])
              ?.toString()
              .trim()
              .toUpperCase();
          if (value != null && value.isNotEmpty) symbols.add(value);
        }
      }

      if (symbols.isEmpty) {
        throw const FormatException('LBank returned no futures symbols.');
      }

      _symbols = symbols.toList()..sort();
      return symbols;
    } finally {
      client.close(force: true);
      _loading = null;
    }
  }
}
