import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' as services;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../models/ticker.dart';
import '../utils/number_formatter.dart' as numbers;
import '../models/custom_field.dart';
import '../models/price_alert.dart';
import '../models/trade.dart';
import '../repositories/asset_repository.dart';
import '../repositories/custom_field_repository.dart';
import '../repositories/pre_trade_repository.dart';
import '../repositories/price_alert_repository.dart';
import '../repositories/trade_repository.dart';
import '../services/lbank_service.dart';
import '../services/lbank_futures_symbols_service.dart';
import 'color_settings_page.dart';
import '../repositories/trade_note_repository.dart';
import '../repositories/note_subject_repository.dart';
import '../repositories/note_tag_repository.dart';
import 'new_trade_note_page.dart';
import 'new_trade_page.dart' as notes_manager;
import 'quick_websites_page.dart';

class NewTradePage extends StatefulWidget {
  const NewTradePage({
    super.key,
  });

  @override
  State<NewTradePage> createState() => _NewTradePageState();
}

class _NewTradePageState extends State<NewTradePage> {
  final _formKey = GlobalKey<FormState>();

  final TradeRepository _tradeRepository = TradeRepository();
  final PreTradeRepository _preTradeRepository = PreTradeRepository();
  final CustomFieldRepository _customFieldRepository = CustomFieldRepository();
  final AssetRepository _assetRepository = AssetRepository();

  final PriceAlertRepository _priceAlertRepository =
      PriceAlertRepository.instance;

  final LBankService _lbankService = LBankService();

  final ImagePicker _imagePicker = ImagePicker();
  final TradeNoteRepository _tradeNoteRepository = TradeNoteRepository.instance;
  final NoteSubjectRepository _noteSubjectRepository = NoteSubjectRepository.instance;
  final NoteTagRepository _noteTagRepository = NoteTagRepository.instance;

  List<Map<String, dynamic>> _tradeNotes = [];
  bool _tradeNotesLoading = false;
  String? _tradeNotesError;

  double _noteFontSize = 14;
  String? _customNoteFontPath;
  static const String _customNoteFontFamily = 'PortfolioCustomNoteFont';
  bool _noteTransferInProgress = false;

  final TextEditingController _noteSearchController = TextEditingController();
  List<Map<String, dynamic>> _noteSearchResults = [];
  bool _noteSearchLoading = false;
  String? _noteSearchError;
  int _searchRequestId = 0;
  int? _selectedNoteResultIndex;

  // ============================================================
  // کنترلرهای اصلی معامله
  // ============================================================

  final TextEditingController _symbolController =
      TextEditingController(text: 'GOLDUSDT');
  final FocusNode _symbolFocusNode = FocusNode();
  List<String> _savedAssetSymbols = ['GOLDUSDT'];
  List<String> _futuresAssetSymbols = [];
  bool _loadingFuturesAssets = false;

  final TextEditingController _marginController = TextEditingController();
  final TextEditingController _dollarRateController = TextEditingController();

  final TextEditingController _volumeController = TextEditingController();

  final TextEditingController _leverageController =
      TextEditingController(text: '1');

  final TextEditingController _entryController = TextEditingController();

  final TextEditingController _stopController = TextEditingController();

  final TextEditingController _targetController = TextEditingController();

  final TextEditingController _feeController = TextEditingController(text: '0');

  final TextEditingController _rrController = TextEditingController(text: '2');

  int _priceDecimalDigits = 0;
  double? _entryPreciseValue;
  double? _stopPreciseValue;
  double? _targetPreciseValue;

  double? _exactPriceFor(TextEditingController controller) {
    if (identical(controller, _entryController))
      return _entryPreciseValue ?? _toDoubleNullable(controller.text);
    if (identical(controller, _stopController))
      return _stopPreciseValue ?? _toDoubleNullable(controller.text);
    if (identical(controller, _targetController))
      return _targetPreciseValue ?? _toDoubleNullable(controller.text);
    return _toDoubleNullable(controller.text);
  }

  void _onPriceChanged(TextEditingController controller, String value) {
    final parsed = _toDoubleNullable(value);
    if (identical(controller, _entryController)) _entryPreciseValue = parsed;
    if (identical(controller, _stopController)) _stopPreciseValue = parsed;
    if (identical(controller, _targetController)) _targetPreciseValue = parsed;
  }

  void _applyPriceDisplayPrecision() {
    void update(TextEditingController controller, double? precise) {
      if (precise == null || !precise.isFinite) return;
      final formatted = _formatAssetPrice(precise);
      if (controller.text == formatted) return;
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    update(_entryController, _entryPreciseValue);
    update(_stopController, _stopPreciseValue);
    update(_targetController, _targetPreciseValue);
    _recalculate();
  }

  // ============================================================
  // وضعیت اصلی معامله
  // ============================================================

  TradeDirection _direction = TradeDirection.long;

  TradeType _tradeType = TradeType.scalp;
  String _marginMode = 'isolated';

  DateTime _entryTime = DateTime.now();

  double? _livePrice;

  double _volume = 0;
  double _tradeFee = 0;

  double _riskDistance = 0;
  double _rewardDistance = 0;

  double _riskValue = 0;
  double _rewardValue = 0;

  double _livePnl = 0;
  double _liveRoiPercent = 0;
  double _liveRoiDollar = 0;

  double _liveRiskPercent = 0;
  double _liveRiskDollar = 0;

  double _liveRiskReward = 0;

  double _priceChangePercent = 0;

  double _marginEffectDollar = 0;
  double _marginEffectPercent = 0;

  double _maxDrawdownPricePercent = 0;
  double _maxDrawdownDollar = 0;
  double _maxDrawdownMarginPercent = 0;

  double _minPriceSeen = 0;
  double _maxPriceSeen = 0;

  double _profitAtTarget = 0;
  double _lossAtStop = 0;

  double _liquidationDistancePercent = 0;
  double _liquidationPrice = 0;

  int _durationSeconds = 0;

  bool _loading = true;
  bool _saving = false;

  bool _targetAlertEnabled = false;
  bool _stopAlertEnabled = false;

  double _stopTargetStepPercent = 0.1;

  StreamSubscription<Ticker>? _tickerSubscription;
  Timer? _uiTimer;

  static const Duration _uiUpdateInterval = Duration(milliseconds: 300);

  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  double? _pendingLivePrice;
  bool _uiUpdateScheduled = false;

  // ============================================================
  // فیلدهای سفارشی
  // ============================================================

  List<CustomField> _customFields = [];

  final Map<int, TextEditingController> _customTextControllers = {};

  final Map<int, String> _customValues = {};

  // ============================================================
  // سوالات و چک‌لیست قبل از معامله
  // ============================================================

  final Map<int, String> _preTradeValues = {};

  final Map<int, TextEditingController> _preTradeControllers = {};

  List<Map<String, dynamic>> _preTradeItems = [];
  final Map<String, bool> _preTradeCollectionVisibility = {};
  static const String _preTradeCollectionVisibilityKey =
      'trade_pre_trade_collection_visibility';

  bool _showQuestionsSection = true;
  bool _showChecklistsSection = true;
  bool _showWebsitesSection = true;
  // نمایش پیش‌فرض باید فهرست یادداشت‌های ذخیره‌شده باشد، نه فرم ساخت یادداشت.
  // فرم ایجاد یادداشت فقط با انتخاب صریح کاربر باز می‌شود.
  bool _showNewNoteSection = false;
  bool _showNoteSearchSection = true;
  bool _showSavedNotesSection = true;

  // ============================================================
  // تصاویر
  // ============================================================

  final List<String> _imagePaths = [];

  @override
  void initState() {
    super.initState();
    _loadTradeNotes();
    _loadNoteDisplaySettings();

    _entryTime = DateTime.now();

    _startDurationTimer();

    _marginController.addListener(_recalculate);
    _leverageController.addListener(_recalculate);
    _entryController.addListener(_recalculate);
    _stopController.addListener(_recalculate);
    _targetController.addListener(_recalculate);
    _feeController.addListener(_recalculate);
    _rrController.addListener(_recalculate);

    _loadPage();
  }

  Future<void> _loadPage() async {
    try {
      await Future.wait([
        _loadCustomFields(),
        _loadPreTradeItems(),
        _loadSavedAssetSymbols(),
        _loadFuturesAssetSymbols(),
        _connectToTicker(),
      ]);
    } catch (error) {
      _showMessage(
        'خطا در آماده‌سازی صفحه: $error',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
    });

    _recalculate();
  }

  Future<void> _loadSavedAssetSymbols() async {
    final assets = await _assetRepository.getAllAssets();
    _savedAssetSymbols = assets
        .map((asset) => asset.assetSymbol.trim().toUpperCase())
        .where((symbol) => symbol.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _loadFuturesAssetSymbols() async {
    if (_futuresAssetSymbols.isEmpty) {
      setState(() => _loadingFuturesAssets = true);
    }
    try {
      final symbols = await LBankFuturesSymbolsService.instance.load();
      if (!mounted) return;
      setState(() {
        _futuresAssetSymbols = symbols;
        _loadingFuturesAssets = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFuturesAssets = false;
        _futuresAssetSymbols = [];
      });
      debugPrint('LBank futures symbols load error: $error');
    }
  }

  Future<void> _selectFuturesAsset(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return;

    _symbolController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );

    // قیمت‌ها و مقادیر وابسته به نماد قبلی نباید برای نماد جدید باقی بمانند.
    _livePrice = null;
    _pendingLivePrice = null;
    _minPriceSeen = 0;
    _maxPriceSeen = 0;
    _entryPreciseValue = null;
    _entryController.clear();
    _priceChangePercent = 0;
    _recalculate();

    await _changeSymbol();
  }

  // ============================================================
  // بارگذاری فیلدهای سفارشی
  // ============================================================

  Future<void> _loadCustomFields() async {
    final fields = await _customFieldRepository.getEnabledFields();

    if (!mounted) {
      return;
    }

    setState(() {
      _customFields = fields;
    });

    for (final field in fields) {
      final id = field.fieldId;

      if (id == null) {
        continue;
      }

      if (field.fieldType == CustomFieldType.text ||
          field.fieldType == CustomFieldType.number ||
          field.fieldType == CustomFieldType.percentage ||
          field.fieldType == CustomFieldType.money) {
        _customTextControllers[id] = TextEditingController();
      }
    }
  }

  // ============================================================
  // بارگذاری سوالات و چک‌لیست‌ها
  // ============================================================

  Future<void> _loadPreTradeItems() async {
    final categories = [
      'questions',
      'psychology',
      'technical',
    ];

    final allItems = <Map<String, dynamic>>[];

    for (final category in categories) {
      final items = await _preTradeRepository.getEnabledItems(
        category,
      );

      allItems.addAll(items);
    }

    allItems.sort(
      (a, b) {
        final aOrder = a['item_order'] is int ? a['item_order'] as int : 0;

        final bOrder = b['item_order'] is int ? b['item_order'] as int : 0;

        return aOrder.compareTo(bOrder);
      },
    );

    if (!mounted) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedVisibility =
        prefs.getString(_preTradeCollectionVisibilityKey);
    if (savedVisibility != null && savedVisibility.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedVisibility);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            _preTradeCollectionVisibility[entry.key] = entry.value == true;
          }
        }
      } catch (error) {
        debugPrint('Pre-trade collection visibility load error: $error');
      }
    }

    setState(() {
      _preTradeItems = allItems;
    });

    for (final item in allItems) {
      final id = item['item_id'];

      if (id is int &&
          (item['display_mode']?.toString() == 'box' ||
              (item['display_mode']?.toString() != 'choice' &&
                  item['item_type']?.toString() == 'question'))) {
        _preTradeControllers[id] = TextEditingController();
      }
    }
  }

  // ============================================================
  // اتصال قیمت لحظه‌ای
  // ============================================================

  Future<void> _connectToTicker() async {
    _tickerSubscription = _lbankService.tickerStream.listen(
      (ticker) {
        if (!mounted) {
          return;
        }

        final price = ticker.price;

        if (price <= 0) {
          return;
        }

        _pendingLivePrice = price;

        if (_minPriceSeen == 0 || price < _minPriceSeen) {
          _minPriceSeen = price;
        }

        if (_maxPriceSeen == 0 || price > _maxPriceSeen) {
          _maxPriceSeen = price;
        }

        _scheduleUiUpdate();
      },
    );

    await _lbankService.connect(
      _symbolController.text.trim().toUpperCase(),
    );
  }

  void _scheduleUiUpdate() {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();

    final elapsed = now.difference(_lastUiUpdate);

    if (elapsed >= _uiUpdateInterval) {
      _applyPendingPrice();
      return;
    }

    if (_uiUpdateScheduled) {
      return;
    }

    _uiUpdateScheduled = true;

    final remaining = _uiUpdateInterval - elapsed;

    Future.delayed(
      remaining,
      () {
        _uiUpdateScheduled = false;

        if (!mounted) {
          return;
        }

        _applyPendingPrice();
      },
    );
  }

  void _applyPendingPrice() {
    if (!mounted) {
      return;
    }

    final price = _pendingLivePrice;

    if (price == null || price <= 0) {
      return;
    }

    _lastUiUpdate = DateTime.now();

    if (_entryController.text.trim().isEmpty) {
      _entryPreciseValue = price;
      _entryController.text = _formatAssetPrice(price);
    }

    _livePrice = price;

    _recalculate(
      updateUi: false,
    );

    _updateDrawdown(
      updateUi: false,
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _changeSymbol() async {
    final symbol = _symbolController.text.trim().toUpperCase();

    if (symbol.isEmpty) {
      return;
    }

    await _lbankService.changeSymbol(symbol);
  }

  // ============================================================
  // مارجین و اهرم
  // ============================================================

  void _setMargin(double value) {
    if (value < 0) {
      value = 0;
    }

    _marginController.text = _formatNumber(value);
  }

  void _changeMargin(double amount) {
    final current = _toDouble(_marginController.text);

    _setMargin(
      current + amount,
    );
  }

  void _setLeverage(double value) {
    if (value < 1) {
      value = 1;
    }

    _leverageController.text = _formatNumber(value);
  }

  void _changeLeverage(double amount) {
    final current = _toDouble(_leverageController.text);

    _setLeverage(
      current + amount,
    );
  }

  // ============================================================
  // قیمت
  // ============================================================

  void _setLivePriceToTradeLevels() {
    if (_livePrice == null || _livePrice! <= 0) {
      _showMessage(
        'قیمت لحظه‌ای هنوز دریافت نشده است.',
      );
      return;
    }

    _entryPreciseValue = _livePrice!;
    _stopPreciseValue = _livePrice!;
    _targetPreciseValue = _livePrice!;
    final value = _formatAssetPrice(_livePrice!);
    _entryController.text = value;
    _stopController.text = value;
    _targetController.text = value;

    _recalculate();

    _showMessage(
      'قیمت لحظه‌ای در هر سه قیمت ورود، حد ضرر و حد سود قرار گرفت.',
    );
  }

  void _changePriceByPercent(
    TextEditingController controller,
    double percent,
  ) {
    final current = _exactPriceFor(controller);

    if (current == null || current <= 0) {
      return;
    }

    final factor = 1 + (percent / 100);

    final newValue = current * factor;

    if (identical(controller, _entryController)) _entryPreciseValue = newValue;
    if (identical(controller, _stopController)) _stopPreciseValue = newValue;
    if (identical(controller, _targetController))
      _targetPreciseValue = newValue;
    controller.text = _formatAssetPrice(newValue);

    _recalculate();
  }

  void _increasePrice(
    TextEditingController controller,
  ) {
    _changePriceByPercent(
      controller,
      _stopTargetStepPercent,
    );
  }

  void _decreasePrice(
    TextEditingController controller,
  ) {
    _changePriceByPercent(
      controller,
      -_stopTargetStepPercent,
    );
  }

  // ============================================================
  // محاسبات اصلی
  // ============================================================

  void _recalculate({
    bool updateUi = true,
  }) {
    final margin = _toDouble(_marginController.text);

    final leverage = _toDouble(_leverageController.text);

    final entry =
        _entryPreciseValue ?? _toDoubleNullable(_entryController.text);
    final stop = _stopPreciseValue ?? _toDoubleNullable(_stopController.text);
    final target =
        _targetPreciseValue ?? _toDoubleNullable(_targetController.text);

    final feePercent = _toDouble(_feeController.text);

    // ==========================================================
    // Volume = Margin × Leverage
    // ==========================================================

    final double volume = margin > 0 && leverage > 0 ? margin * leverage : 0.0;

    final formattedVolume = _formatNumber(volume);

    if (_volumeController.text != formattedVolume) {
      _volumeController.value = _volumeController.value.copyWith(
        text: formattedVolume,
        selection: TextSelection.collapsed(
          offset: formattedVolume.length,
        ),
        composing: TextRange.empty,
      );
    }

    double riskDistance = 0;
    double rewardDistance = 0;

    if (entry != null && stop != null) {
      riskDistance = (entry - stop).abs();
    }

    if (entry != null && target != null) {
      rewardDistance = (target - entry).abs();
    }

    double riskValue = 0;
    double rewardValue = 0;

    if (entry != null && entry > 0) {
      riskValue = volume * (riskDistance / entry);

      rewardValue = volume * (rewardDistance / entry);
    }

    final fee = volume * feePercent / 100;

    double pnl = 0;
    double roiPercent = 0;
    double priceChangePercent = 0;
    double marginEffectDollar = 0;
    double marginEffectPercent = 0;

    if (_livePrice != null && entry != null && entry > 0) {
      final currentPrice = _livePrice!;

      if (_direction == TradeDirection.long) {
        priceChangePercent = ((currentPrice - entry) / entry) * 100;
      } else {
        priceChangePercent = ((entry - currentPrice) / entry) * 100;
      }

      pnl = volume * priceChangePercent / 100;

      roiPercent = margin > 0 ? (pnl / margin) * 100 : 0;

      marginEffectDollar = pnl;
      marginEffectPercent = roiPercent;
    }

    double riskPercent = 0;
    double riskDollar = 0;

    if (margin > 0) {
      riskDollar = riskValue;

      riskPercent = (riskDollar / margin) * 100;
    }

    double liveRr = 0;

    if (_livePrice != null && stop != null && target != null) {
      final current = _livePrice!;

      double distanceToStop;
      double distanceToTarget;

      if (_direction == TradeDirection.long) {
        distanceToStop = (current - stop).abs();

        distanceToTarget = (target - current).abs();
      } else {
        distanceToStop = (stop - current).abs();

        distanceToTarget = (current - target).abs();
      }

      if (distanceToTarget > 0) {
        liveRr = distanceToStop / distanceToTarget;
      }
    }

    // ==========================================================
    // فاصله و قیمت لیکویید
    // ==========================================================

    double liquidationDistance = 0;
    double liquidationPrice = 0;

    if (leverage > 0) {
      liquidationDistance = 100 / leverage;

      if (entry != null && entry > 0) {
        if (_direction == TradeDirection.long) {
          liquidationPrice = entry * (1 - liquidationDistance / 100);
        } else {
          liquidationPrice = entry * (1 + liquidationDistance / 100);
        }
      }
    }

    // ==========================================================
    // سود و ضرر در Target / Stop
    // ==========================================================

    double profitAtTarget = 0;
    double lossAtStop = 0;

    if (entry != null && entry > 0) {
      if (target != null) {
        final targetPercent = _direction == TradeDirection.long
            ? ((target - entry) / entry) * 100
            : ((entry - target) / entry) * 100;

        profitAtTarget = volume * targetPercent / 100;
      }

      if (stop != null) {
        final stopPercent = _direction == TradeDirection.long
            ? ((stop - entry) / entry) * 100
            : ((entry - stop) / entry) * 100;

        lossAtStop = volume * stopPercent / 100;
      }
    }

    void apply() {
      _volume = volume;
      _tradeFee = fee;

      _riskDistance = riskDistance;

      _rewardDistance = rewardDistance;

      _riskValue = riskValue;

      _rewardValue = rewardValue;

      _livePnl = pnl;

      _liveRoiPercent = roiPercent;

      _liveRoiDollar = pnl;

      _liveRiskPercent = riskPercent;

      _liveRiskDollar = riskDollar;

      _liveRiskReward = liveRr;

      _priceChangePercent = priceChangePercent;

      _marginEffectDollar = marginEffectDollar;

      _marginEffectPercent = marginEffectPercent;

      _liquidationDistancePercent = liquidationDistance;

      _liquidationPrice = liquidationPrice;

      _profitAtTarget = profitAtTarget;

      _lossAtStop = lossAtStop;
    }

    if (!updateUi) {
      apply();
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      apply();
    });
  }

  void _autoCalculateTarget() {
    final entry =
        _entryPreciseValue ?? _toDoubleNullable(_entryController.text);
    final stop = _stopPreciseValue ?? _toDoubleNullable(_stopController.text);

    final rr = _toDouble(_rrController.text);

    if (entry == null || stop == null || entry <= 0 || rr <= 0) {
      return;
    }

    final riskDistance = (entry - stop).abs();

    double target;

    if (_direction == TradeDirection.long) {
      target = entry + (riskDistance * rr);
    } else {
      target = entry - (riskDistance * rr);
    }

    _targetPreciseValue = target;
    _targetController.text = _formatAssetPrice(target);

    _recalculate();
  }

  // ============================================================
  // هشدارها
  // ============================================================

  void _toggleTargetAlert() {
    setState(() {
      _targetAlertEnabled = !_targetAlertEnabled;
    });
  }

  void _toggleStopAlert() {
    setState(() {
      _stopAlertEnabled = !_stopAlertEnabled;
    });
  }

  Future<void> _createTradeAlerts({
    required String tradeId,
    required String symbol,
    required double target,
    required double stop,
  }) async {
    final now = DateTime.now();

    if (_targetAlertEnabled) {
      final targetTriggerOnRise = _direction == TradeDirection.long;

      final targetAlert = PriceAlert(
        id: '${tradeId}_target',
        symbol: symbol,
        title: 'حد سود معامله',
        note: 'هشدار رسیدن قیمت به حد سود معامله $tradeId',
        type: PriceAlertType.tradeTarget,
        targetPrice: target,
        triggerOnRise: targetTriggerOnRise,
        repeatMode: PriceAlertRepeatMode.once,
        isActive: true,
        isTriggered: false,
        tradeId: tradeId,
        tradePriceType: 'target',
        createdAt: now,
      );

      await _priceAlertRepository.insertAlert(targetAlert);
    }

    if (_stopAlertEnabled) {
      final stopTriggerOnRise = _direction == TradeDirection.short;

      final stopAlert = PriceAlert(
        id: '${tradeId}_stop_loss',
        symbol: symbol,
        title: 'حد ضرر معامله',
        note: 'هشدار رسیدن قیمت به حد ضرر معامله $tradeId',
        type: PriceAlertType.tradeStopLoss,
        targetPrice: stop,
        triggerOnRise: stopTriggerOnRise,
        repeatMode: PriceAlertRepeatMode.once,
        isActive: true,
        isTriggered: false,
        tradeId: tradeId,
        tradePriceType: 'stop_loss',
        createdAt: now,
      );

      await _priceAlertRepository.insertAlert(stopAlert);
    }
  }

  // ============================================================
  // زمان معامله
  // ============================================================

  void _startDurationTimer() {
    _uiTimer?.cancel();

    _uiTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _durationSeconds = DateTime.now().difference(_entryTime).inSeconds;

          if (_durationSeconds < 0) {
            _durationSeconds = 0;
          }
        });
      },
    );
  }

  Future<void> _selectEntryDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _entryTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (date == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _entryTime,
      ),
    );

    if (time == null) {
      return;
    }

    setState(() {
      _entryTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      _durationSeconds = DateTime.now().difference(_entryTime).inSeconds;

      if (_durationSeconds < 0) {
        _durationSeconds = 0;
      }
    });
  }

  String _formatEntryDate() {
    final jalali = Jalali.fromDateTime(
      _entryTime,
    );

    final jy = jalali.year.toString().padLeft(
          4,
          '0',
        );

    final jm = jalali.month.toString().padLeft(
          2,
          '0',
        );

    final jd = jalali.day.toString().padLeft(
          2,
          '0',
        );

    final hh = _entryTime.hour.toString().padLeft(
          2,
          '0',
        );

    final mm = _entryTime.minute.toString().padLeft(
          2,
          '0',
        );

    return '$jy/$jm/$jd  |  $hh:$mm';
  }

  // ============================================================
  // تصاویر
  // ============================================================

  Future<void> _pickImages() async {
    final images = await _imagePicker.pickMultiImage(
      imageQuality: 85,
    );

    if (images.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(p.join(directory.path, 'trade_images'));
    await targetDirectory.create(recursive: true);
    final copiedPaths = <String>[];
    for (final image in images) {
      final extension =
          p.extension(image.path).isNotEmpty ? p.extension(image.path) : '.jpg';
      final target = p.join(targetDirectory.path,
          '${DateTime.now().microsecondsSinceEpoch}_${copiedPaths.length}$extension');
      await File(image.path).copy(target);
      copiedPaths.add(target);
    }
    if (!mounted) return;
    setState(() => _imagePaths.addAll(copiedPaths));
  }

  Future<void> _replaceImage(int index) async {
    if (index < 0 || index >= _imagePaths.length) return;
    final image = await _imagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 95);
    if (image == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(p.join(directory.path, 'trade_images'));
    await targetDirectory.create(recursive: true);
    final extension =
        p.extension(image.path).isNotEmpty ? p.extension(image.path) : '.jpg';
    final target = p.join(targetDirectory.path,
        '${DateTime.now().microsecondsSinceEpoch}_replacement$extension');
    await File(image.path).copy(target);
    if (!mounted) return;
    setState(() => _imagePaths[index] = target);
  }

  void _removeImage(int index) {
    setState(() {
      _imagePaths.removeAt(index);
    });
  }

  // ============================================================
  // ذخیره معامله
  // ============================================================

  Future<void> _saveTrade() async {
    if (_saving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final margin = _toDouble(
      _marginController.text,
    );

    final leverage = _toDouble(
      _leverageController.text,
    );

    final entry =
        _entryPreciseValue ?? _toDoubleNullable(_entryController.text);
    final stop = _stopPreciseValue ?? _toDoubleNullable(_stopController.text);
    final target =
        _targetPreciseValue ?? _toDoubleNullable(_targetController.text);

    if (margin <= 0) {
      _showMessage(
        'مارجین (Margin) باید بیشتر از صفر باشد.',
      );
      return;
    }

    if (leverage <= 0) {
      _showMessage(
        'اهرم (Leverage) باید بیشتر از صفر باشد.',
      );
      return;
    }

    if (_volume <= 0) {
      _showMessage(
        'حجم (Volume) باید بیشتر از صفر باشد.',
      );
      return;
    }

    if (entry == null || entry <= 0) {
      _showMessage(
        'قیمت ورود (Entry Price) معتبر نیست.',
      );
      return;
    }

    if (stop == null || stop <= 0) {
      _showMessage(
        'قیمت حد ضرر (Stop Loss) معتبر نیست.',
      );
      return;
    }

    if (target == null || target <= 0) {
      _showMessage(
        'قیمت حد سود (Take Profit) معتبر نیست.',
      );
      return;
    }

    if (_direction == TradeDirection.long) {
      if (stop >= entry) {
        _showMessage(
          'در خرید (Long)، حد ضرر باید پایین‌تر از قیمت ورود باشد.',
        );
        return;
      }

      if (target <= entry) {
        _showMessage(
          'در خرید (Long)، حد سود باید بالاتر از قیمت ورود باشد.',
        );
        return;
      }
    } else {
      if (stop <= entry) {
        _showMessage(
          'در فروش (Short)، حد ضرر باید بالاتر از قیمت ورود باشد.',
        );
        return;
      }

      if (target >= entry) {
        _showMessage(
          'در فروش (Short)، حد سود باید پایین‌تر از قیمت ورود باشد.',
        );
        return;
      }
    }

    if (!_validateRequiredPreTrade()) {
      return;
    }

    if (!_validateRequiredCustomFields()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final tradeId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();

      final symbol = _symbolController.text.trim().toUpperCase();

      final trade = Trade(
        tradeId: tradeId,
        assetSymbol: symbol,
        tradeDirection: _direction,
        tradeType: _tradeType,
        tradeStatus: TradeStatus.open,
        tradeTimeframe: '',
        marginMode: _marginMode,
        marginAmount: margin,
        leverageValue: leverage,
        volumeAmount: _volume,
        dollarRate: _toDouble(_dollarRateController.text),
        feePerHundred: _toDouble(
          _feeController.text,
        ),
        tradeFee: _tradeFee,
        entryPrice: entry,
        exitPrice: null,
        stopPrice: stop,
        targetPrice: target,
        riskDistance: _riskDistance,
        rewardDistance: _rewardDistance,
        riskValue: _riskValue,
        rewardValue: _rewardValue,
        tradeRiskReward: _rewardValue > 0
            ? _rewardValue / (_riskValue > 0 ? _riskValue : 1)
            : 0,
        finalPnl: 0,
        finalRoiPercent: 0,
        finalRoiDollar: 0,
        finalRiskReward: 0,
        maxDrawdownPricePercent: _maxDrawdownPricePercent,
        maxDrawdownDollar: _maxDrawdownDollar,
        maxDrawdownMarginPercent: _maxDrawdownMarginPercent,
        durationSeconds: _durationSeconds,
        entrySetup: '',
        entryReason: '',
        entryMotivation: '',
        expectedScenario: '',
        imagePaths: List<String>.from(
          _imagePaths,
        ),
        entryTime: _entryTime,
        exitTime: null,
      );

      await _tradeRepository.createTrade(trade);
      await _assetRepository.saveSymbolIfAbsent(symbol);
      if (!_savedAssetSymbols.contains(symbol)) {
        _savedAssetSymbols = [..._savedAssetSymbols, symbol]..sort();
      }

      if (_customValues.isNotEmpty) {
        await _customFieldRepository.saveTradeValues(
          tradeId,
          _customValues,
        );
      }

      if (_preTradeValues.isNotEmpty) {
        await _preTradeRepository.saveTradeValues(
          tradeId,
          _preTradeValues,
        );
      }

      await _createTradeAlerts(
        tradeId: tradeId,
        symbol: symbol,
        target: target,
        stop: stop,
      );

      if (!mounted) {
        return;
      }

      String message = 'معامله با موفقیت ذخیره شد.';

      if (_targetAlertEnabled || _stopAlertEnabled) {
        message = 'معامله و هشدارهای انتخاب‌شده با موفقیت ذخیره شدند.';
      }

      _showMessage(message);

      Navigator.of(context).pop(
        trade,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'خطا در ذخیره معامله: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ============================================================
  // اعتبارسنجی سوالات
  // ============================================================

  bool _validateRequiredPreTrade() {
    for (final item in _preTradeItems) {
      if (item['category'] == 'questions' && !_showQuestionsSection) continue;
      if (item['category'] != 'questions' && !_showChecklistsSection) continue;
      final category = item['category']?.toString() ?? '';
      final folder = (item['folder_name']?.toString() ?? '').trim();
      final collectionName = folder.isEmpty ? 'موارد قبلی' : folder;
      final collectionKey = _preTradeCollectionKey(category, collectionName);
      if (_preTradeCollectionVisibility[collectionKey] == false) continue;
      final required = item['is_required'] == 1;

      if (!required) {
        continue;
      }

      final id = item['item_id'];

      if (id is! int) {
        continue;
      }

      final value = _preTradeValues[id]?.trim() ?? '';

      if (value.isEmpty) {
        _showMessage(
          'لطفاً به موارد اجباری قبل از معامله پاسخ بده.',
        );
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // اعتبارسنجی فیلدهای سفارشی
  // ============================================================

  bool _validateRequiredCustomFields() {
    for (final field in _customFields) {
      if (!field.isRequired) {
        continue;
      }

      final id = field.fieldId;

      if (id == null) {
        continue;
      }

      final value = _customValues[id]?.trim() ?? '';

      if (value.isEmpty) {
        _showMessage(
          'لطفاً فیلد «${field.fieldName}» را تکمیل کن.',
        );
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // بخش سوالات و چک‌لیست
  // ============================================================

  Widget _buildPreTradeSection() {
    final sections = <String, List<Map<String, dynamic>>>{
      'questions': _preTradeItems
          .where((item) => item['category'] == 'questions')
          .toList(),
      'psychology': _preTradeItems
          .where((item) => item['category'] == 'psychology')
          .toList(),
      'technical': _preTradeItems
          .where((item) => item['category'] == 'technical')
          .toList(),
    };
    final titles = <String, String>{
      'questions': 'سوالات',
      'psychology': 'چک‌لیست‌ها',
      'technical': 'ورود و خروج',
    };
    final icons = <String, IconData>{
      'questions': Icons.quiz_outlined,
      'psychology': Icons.psychology_outlined,
      'technical': Icons.compare_arrows,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final category in ['questions', 'psychology', 'technical'])
        if ((category == 'questions' && _showQuestionsSection) ||
            (category != 'questions' && _showChecklistsSection))
          if (sections[category]!.isNotEmpty)
            _buildSection(
              title: titles[category]!,
              icon: icons[category]!,
              children: _buildPreTradeCollections(
                sections[category]!,
                category,
              ),
            ),
    ]);
  }

  String _preTradeCollectionKey(String category, String collectionName) =>
      '$category::$collectionName';

  Future<void> _setPreTradeCollectionVisibility(
    String key,
    bool visible,
  ) async {
    setState(() => _preTradeCollectionVisibility[key] = visible);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preTradeCollectionVisibilityKey,
      jsonEncode(_preTradeCollectionVisibility),
    );
  }

  List<Widget> _buildPreTradeCollections(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final collection = (item['folder_name']?.toString() ?? '').trim();
      final title = collection.isEmpty ? 'موارد قبلی' : collection;
      (grouped[title] ??= []).add(item);
    }

    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      final key = _preTradeCollectionKey(category, entry.key);
      final visible = _preTradeCollectionVisibility[key] ?? true;
      widgets.add(
        CheckboxListTile(
          contentPadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          value: visible,
          onChanged: (value) => _setPreTradeCollectionVisibility(
            key,
            value ?? false,
          ),
        ),
      );
      if (visible) {
        widgets.addAll(entry.value.map(_buildPreTradeItem));
      }
    }
    return widgets;
  }

  Widget _buildOptionalSectionToggles() {
    Widget toggle(String title, bool value, ValueChanged<bool?> onChanged) =>
        SizedBox(
            width: 175,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(title, style: const TextStyle(fontSize: 12)),
              value: value,
              onChanged: onChanged,
            ));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('نمایش بخش‌های اختیاری',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 0, children: [
            toggle('سؤالات', _showQuestionsSection,
                (v) => setState(() => _showQuestionsSection = v ?? false)),
            toggle('چک‌لیست‌ها', _showChecklistsSection,
                (v) => setState(() => _showChecklistsSection = v ?? false)),
            toggle('سایت‌ها', _showWebsitesSection,
                (v) => setState(() => _showWebsitesSection = v ?? false)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildPreTradeItem(Map<String, dynamic> item) {
    final id = item['item_id'];
    if (id is! int) return const SizedBox.shrink();
    final title = item['item_title']?.toString() ?? '';
    final required = item['is_required'] == 1;
    final mode = item['display_mode']?.toString() ?? 'box';
    final label = required ? '$title *' : title;

    final type = item['item_type']?.toString() ?? '';
    final legacyMode = mode != 'box' && mode != 'choice';
    if (mode == 'box' || (legacyMode && type == 'question')) {
      final controller = _preTradeControllers.putIfAbsent(
          id, () => TextEditingController(text: _preTradeValues[id] ?? ''));
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          maxLines: 3,
          onChanged: (value) => _preTradeValues[id] = value,
          decoration: _inputDecoration(label: label),
        ),
      );
    }

    final value = _preTradeValues[id] ?? '';
    if (type == 'question') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('بله'),
              value: 'yes',
              groupValue: value.isEmpty ? null : value,
              onChanged: (v) => setState(() => _preTradeValues[id] = v ?? '')),
          RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('خیر'),
              value: 'no',
              groupValue: value.isEmpty ? null : value,
              onChanged: (v) => setState(() => _preTradeValues[id] = v ?? '')),
        ]),
      );
    }
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: value == 'yes',
      title: Text(label),
      onChanged: (checked) =>
          setState(() => _preTradeValues[id] = checked == true ? 'yes' : ''),
    );
  }

  // ============================================================
  // فیلدهای سفارشی
  // ============================================================

  Widget _buildCustomFieldsSection() {
    if (_customFields.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, List<CustomField>> groupedFields = {};

    for (final field in _customFields) {
      final category =
          field.category.trim().isEmpty ? 'عمومی' : field.category.trim();

      groupedFields.putIfAbsent(
        category,
        () => <CustomField>[],
      );

      groupedFields[category]!.add(field);
    }

    return _buildSection(
      title: 'فیلدهای سفارشی (Custom Fields)',
      icon: Icons.tune,
      children: [
        for (final entry in groupedFields.entries)
          _buildCustomFieldCategory(
            category: entry.key,
            fields: entry.value,
          ),
      ],
    );
  }

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


  Future<void> _loadTradeNotes() async {
    if (!mounted) return;

    setState(() {
      _tradeNotesLoading = true;
      _tradeNotesError = null;
    });

    try {
      final notes = await _tradeNoteRepository.getAllNotes();

      if (!mounted) return;

      setState(() {
        _tradeNotes =
            notes.map((note) => Map<String, dynamic>.from(note)).toList();
        _tradeNotesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _tradeNotesLoading = false;
        _tradeNotesError = 'خطا در بارگذاری یادداشت‌ها: $e';
      });
    }
  }

  Widget _buildCustomFieldCategory({
    required String category,
    required List<CustomField> fields,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: AppColors.boxBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>(
            'custom_field_category_$category',
          ),
          initiallyExpanded: false,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            12,
            4,
            12,
            8,
          ),
          leading: Icon(
            Icons.folder_outlined,
            color: AppColors.button,
          ),
          title: Text(
            category,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          subtitle: Text(
            '${numbers.formatInteger(fields.length)} فیلد',
            style: const TextStyle(
              fontSize: 12,
            ).copyWith(
              color: AppColors.secondaryText,
            ),
          ),
          iconColor: AppColors.button,
          collapsedIconColor: AppColors.secondaryText,
          textColor: AppColors.text,
          collapsedTextColor: AppColors.text,
          backgroundColor: AppColors.boxBackground,
          collapsedBackgroundColor: AppColors.boxBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
          children: [
            for (final field in fields)
              _buildCustomField(
                field,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomField(
    CustomField field,
  ) {
    final id = field.fieldId;

    if (id == null) {
      return const SizedBox.shrink();
    }

    switch (field.fieldType) {
      case CustomFieldType.text:
      case CustomFieldType.number:
      case CustomFieldType.percentage:
      case CustomFieldType.money:
        return Padding(
          padding: const EdgeInsets.only(
            bottom: 14,
          ),
          child: TextField(
            controller: _customTextControllers[id],
            keyboardType: field.fieldType == CustomFieldType.text
                ? TextInputType.text
                : const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
            onChanged: (value) {
              _customValues[id] = value;
            },
            decoration: _inputDecoration(
              label:
                  field.isRequired ? '${field.fieldName} *' : field.fieldName,
              helperText: field.typeName,
            ),
          ),
        );

      case CustomFieldType.boolean:
        final value = _customValues[id] == 'true';

        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            field.isRequired ? '${field.fieldName} *' : field.fieldName,
          ),
          value: value,
          onChanged: (newValue) {
            setState(() {
              _customValues[id] = newValue.toString();
            });
          },
        );

      case CustomFieldType.date:
        final value = _customValues[id] ?? '';

        return Padding(
          padding: const EdgeInsets.only(
            bottom: 14,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              field.isRequired ? '${field.fieldName} *' : field.fieldName,
            ),
            subtitle: Text(
              value.isEmpty ? 'تاریخ انتخاب نشده' : value,
            ),
            trailing: Icon(
              Icons.calendar_month,
              color: AppColors.button,
            ),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: DateTime.now(),
              );

              if (selected == null) {
                return;
              }

              setState(() {
                _customValues[id] = selected.toIso8601String();
              });
            },
          ),
        );

      case CustomFieldType.dropdown:
        final current = _customValues[id];

        return Padding(
          padding: const EdgeInsets.only(
            bottom: 14,
          ),
          child: DropdownButtonFormField<String>(
            value: field.options.contains(
              current,
            )
                ? current
                : null,
            decoration: _inputDecoration(
              label:
                  field.isRequired ? '${field.fieldName} *' : field.fieldName,
            ),
            items: field.options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _customValues[id] = value;
              });
            },
          ),
        );
    }
  }

  Widget _buildMarginModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('حالت مارجین',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(value: 'isolated', label: Text('ایزوله')),
            ButtonSegment<String>(value: 'cross', label: Text('کراس')),
          ],
          selected: {_marginMode},
          onSelectionChanged: (value) =>
              setState(() => _marginMode = value.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 4),
        Text(
          _marginMode == 'isolated'
              ? 'در شبیه‌سازی، رسیدن زیان به مارجین اختصاص‌یافته هشدار/بستن شبیه‌سازی‌شده ایجاد می‌کند.'
              : 'در شبیه‌سازی، زیان با توجه به ماندهٔ قابل‌استفادهٔ حساب ارزیابی می‌شود؛ هیچ سفارش واقعی ارسال نمی‌شود.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ============================================================
  // جهت معامله
  // ============================================================
  Widget _buildDirectionSelector() {
    return SizedBox(
      height: 34,
      width: double.infinity,
      child: SegmentedButton<TradeDirection>(
        segments: const [
          ButtonSegment<TradeDirection>(
            value: TradeDirection.long,
            label: Text(
              'لانگ',
              style: TextStyle(fontSize: 10),
            ),
          ),
          ButtonSegment<TradeDirection>(
            value: TradeDirection.short,
            label: Text(
              'شورت',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ],
        selected: {_direction},
        onSelectionChanged: (selection) {
          setState(() {
            _direction = selection.first;
          });
          _recalculate();
        },
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // خلاصه معامله
  // ============================================================
  Widget _buildTopSummarySection() {
    final tradeRr = _riskValue > 0 ? _rewardValue / _riskValue : 0.0;

    Widget metricBox(
      String title,
      String value, {
      Color? valueColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: AppColors.boxBackground,
          borderRadius: BorderRadius.circular(
            9,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(
              height: 4,
            ),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: valueColor ?? AppColors.text,
              ),
            ),
          ],
        ),
      );
    }

    return _buildSection(
      title: 'خلاصه معامله',
      icon: Icons.dashboard_customize_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: metricBox(
                'درصد لیکویید',
                '${_formatPercent(_liquidationDistancePercent)}%',
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: metricBox(
                'قیمت حد ضرر',
                _formatAssetPrice(_stopPreciseValue ??
                    (_stopController.text.isEmpty
                        ? 0
                        : _toDouble(_stopController.text))),
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: metricBox(
                'قیمت حد سود',
                _formatAssetPrice(_targetPreciseValue ??
                    (_targetController.text.isEmpty
                        ? 0
                        : _toDouble(_targetController.text))),
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 5,
        ),
        Row(
          children: [
            Expanded(
              child: metricBox(
                'قیمت لیکویید',
                _liquidationPrice > 0
                    ? _formatAssetPrice(_liquidationPrice)
                    : '-',
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: metricBox(
                'دلار حد ضرر',
                '${_formatMoney(_lossAtStop.abs())} \$',
                valueColor: AppColors.loss,
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: metricBox(
                'دلار حد سود',
                '${_formatMoney(_profitAtTarget)} \$',
                valueColor: AppColors.profit,
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 5,
        ),
        Row(
          children: [
            Expanded(
              child: metricBox(
                'حجم',
                _formatMoney(_volume),
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: metricBox(
                'ریسک / ریوارد',
                tradeRr > 0 ? '1 : ${_formatNumber(tradeRr)}' : '-',
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: metricBox(
                'PNL',
                '${_formatMoney(_livePnl)} \$',
                valueColor: _livePnl > 0
                    ? AppColors.profit
                    : _livePnl < 0
                        ? AppColors.loss
                        : AppColors.text,
              ),
            ),
          ],
        ),
      ],
    );
  }

// ============================================================
// قیمت‌ها و مدیریت معامله
// ============================================================
  String _formatAssetPrice(double price) {
    return numbers.formatNumber(price,
        decimals: _priceDecimalDigits, trimTrailingZeros: false);
  }

  Widget _buildPriceSection() {
    return _buildSection(
      title: '',
      icon: Icons.show_chart,
      children: [
        // ======================================================
        // قیمت لحظه‌ای + دکمه اعمال قیمت + اعشار قیمت
        // ======================================================

        if (_livePrice != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                // ==============================================
                // قیمت لحظه‌ای
                // ==============================================

                SizedBox(
                  width: 180,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.boxBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_tethering,
                          color: AppColors.livePrice,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'قیمت لحظه‌ای: '
                            '${numbers.formatNumber(_toDouble(_livePrice!.toStringAsFixed(0)), decimals: 0)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.livePrice,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ==============================================
                // دکمه قیمت لحظه‌ای
                // ==============================================

                SizedBox(
                  width: 82,
                  height: 34,
                  child: FilledButton.tonal(
                    onPressed: _setLivePriceToTradeLevels,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: const Text(
                      'قیمت لحظه‌ای',
                      style: TextStyle(
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // ==============================================
                // اعشار قیمت
                // ==============================================

                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اعشار قیمت',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 150,
                      height: 32,
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment<int>(
                            value: 0,
                            label: Text(
                              '0',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                          ButtonSegment<int>(
                            value: 1,
                            label: Text(
                              '1',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                          ButtonSegment<int>(
                            value: 2,
                            label: Text(
                              '2',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                          ButtonSegment<int>(
                            value: 3,
                            label: Text(
                              '3',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                          ButtonSegment<int>(
                            value: 4,
                            label: Text(
                              '4',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                        ],
                        selected: {
                          _priceDecimalDigits,
                        },
                        onSelectionChanged: (selection) {
                          setState(() {
                            _priceDecimalDigits = selection.first;
                          });
                          _applyPriceDisplayPrecision();
                        },
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 1,
                          ),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // ======================================================
        // فاصله
        // ======================================================

        const SizedBox(height: 12),

        // ======================================================
        // سه ستون اصلی
        // ======================================================

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ====================================================
            // ستون چپ
            // حد ضرر
            // - / +
            // انتخاب گام
            // ====================================================

            Expanded(
              child: Column(
                children: [
                  _compactPriceField(
                    controller: _stopController,
                    label: 'حد ضرر',
                    englishLabel: 'Stop',
                  ),

                  const SizedBox(height: 5),

                  Row(
                    children: [
                      Expanded(
                        child: _priceStepButton(
                          label: '−${_formatNumber(_stopTargetStepPercent)}%',
                          onPressed: () {
                            _decreasePrice(_stopController);
                          },
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: _priceStepButton(
                          label: '+${_formatNumber(_stopTargetStepPercent)}%',
                          onPressed: () {
                            _increasePrice(_stopController);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // ==============================================
                  // انتخاب گام
                  // ==============================================

                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: SegmentedButton<double>(
                      segments: const [
                        ButtonSegment<double>(
                          value: 0.1,
                          label: Text(
                            '0.1%',
                            style: TextStyle(fontSize: 9),
                          ),
                        ),
                        ButtonSegment<double>(
                          value: 0.5,
                          label: Text(
                            '0.5%',
                            style: TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                      selected: {
                        _stopTargetStepPercent,
                      },
                      onSelectionChanged: (selection) {
                        setState(() {
                          _stopTargetStepPercent = selection.first;
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                        ),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 5),

            // ====================================================
            // ستون وسط
            // قیمت ورود
            // دارایی
            // ====================================================

            Expanded(
              child: Column(
                children: [
                  _compactPriceField(
                    controller: _entryController,
                    label: 'قیمت ورود',
                    englishLabel: 'Entry',
                  ),
                  const SizedBox(height: 8),
                  RawAutocomplete<String>(
                    textEditingController: _symbolController,
                    focusNode: _symbolFocusNode,
                    displayStringForOption: (option) => option,
                    optionsBuilder: (textEditingValue) {
                      final query = textEditingValue.text.trim().toUpperCase();
                      final availableSymbols = _futuresAssetSymbols.isNotEmpty
                          ? _futuresAssetSymbols
                          : _savedAssetSymbols;
                      if (query.isEmpty) return availableSymbols.take(30);
                      return availableSymbols.where(
                        (symbol) => symbol.contains(query),
                      ).take(50);
                    },
                    onSelected: _selectFuturesAsset,
                    fieldViewBuilder: (
                      context,
                      controller,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.text,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 12),
                        decoration: _inputDecoration(
                          label: 'دارایی',
                          englishLabel: 'Asset',
                          hint: _loadingFuturesAssets
                              ? 'در حال دریافت نمادهای فیوچرز...'
                              : 'جست‌وجوی نماد',
                        ).copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 10,
                          ),
                          labelStyle: const TextStyle(fontSize: 10),
                          floatingLabelStyle: const TextStyle(fontSize: 9),
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 220,
                              minWidth: 150,
                              maxWidth: 240,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  title: Text(
                                    option,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(width: 5),

            // ====================================================
            // ستون راست
            // حد سود
            // - / +
            // لانگ / شورت
            // ====================================================

            Expanded(
              child: Column(
                children: [
                  _compactPriceField(
                    controller: _targetController,
                    label: 'حد سود',
                    englishLabel: 'Target',
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: _priceStepButton(
                          label: '−${_formatNumber(_stopTargetStepPercent)}%',
                          onPressed: () {
                            _decreasePrice(
                              _targetController,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: _priceStepButton(
                          label: '+${_formatNumber(_stopTargetStepPercent)}%',
                          onPressed: () {
                            _increasePrice(
                              _targetController,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildDirectionSelector(),
                ],
              ),
            ),
          ],
        ),

        // ======================================================
        // وضعیت هشدارها
        // ======================================================

        const SizedBox(height: 10),

        if (_targetAlertEnabled || _stopAlertEnabled) ...[
          Row(
            children: [
              Icon(
                Icons.notifications_active,
                size: 18,
                color: AppColors.alertActive,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _buildAlertStatusText(),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
// ============================================================
// فیلد قیمت کوچک
// ============================================================

  Widget _compactPriceField({
    required TextEditingController controller,
    required String label,
    required String englishLabel,
  }) {
    return TextField(
      controller: controller,
      onChanged: (value) => _onPriceChanged(controller, value),
      onEditingComplete: () {
        final exact = _exactPriceFor(controller);
        if (exact != null) {
          final formatted = _formatAssetPrice(exact);
          controller.value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
        FocusScope.of(context).unfocus();
      },
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      style: const TextStyle(
        fontSize: 12,
      ),
      decoration: _inputDecoration(
        label: label,
        englishLabel: englishLabel,
      ).copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 10,
        ),
        labelStyle: const TextStyle(
          fontSize: 10,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 9,
        ),
      ),
    );
  }

// ============================================================
// دکمه تغییر قیمت
// ============================================================

  Widget _priceStepButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(
          0,
          32,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 1,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
        ),
      ),
    );
  }

// ============================================================
// دکمه هشدار
// ============================================================

  Widget _buildAlertButtonWithLabel({
    required String title,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        enabled
            ? Icons.notifications_active
            : Icons.notifications_none_outlined,
        size: 17,
      ),
      label: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 8,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  String _buildAlertStatusText() {
    if (_targetAlertEnabled && _stopAlertEnabled) {
      return 'هشدار حد سود و حد ضرر فعال است.';
    }

    if (_targetAlertEnabled) {
      return 'هشدار حد سود فعال است.';
    }

    return 'هشدار حد ضرر فعال است.';
  }

  // ============================================================
// سرمایه و اهرم
// ============================================================
  Widget _buildCapitalSection() {
    return _buildSection(
      title: '',
      icon: Icons.account_balance_wallet_outlined,
      children: [
        // ============================================================
        // مارجین - حجم - اهرم
        // ============================================================

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================================================
            // مارجین
            // ==================================================

            Expanded(
              child: _compactNumberField(
                controller: _marginController,
                label: 'مارجین',
                englishLabel: 'Margin',
              ),
            ),

            const SizedBox(width: 5),

            // ==================================================
            // حجم
            // ==================================================

            Expanded(
              child: _compactNumberField(
                controller: _volumeController,
                label: 'حجم',
                englishLabel: 'Volume',
                readOnly: true,
              ),
            ),

            const SizedBox(width: 5),

            // ==================================================
            // اهرم
            // ==================================================

            Expanded(
              child: _compactNumberField(
                controller: _leverageController,
                label: 'اهرم',
                englishLabel: 'Leverage',
                suffixText: 'x',
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        _compactNumberField(
          controller: _dollarRateController,
          label: 'قیمت هر دلار به تومان',
          englishLabel: 'USD / Toman',
        ),
        const SizedBox(height: 7),

        // ============================================================
        // دکمه‌های تغییر مارجین و اهرم
        // ============================================================

        Row(
          children: [
            Expanded(
              child: _compactStepButton(
                label: '+5',
                onPressed: () => _changeMargin(5),
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            Expanded(
              child: _compactStepButton(
                label: '+10',
                onPressed: () => _changeMargin(10),
              ),
            ),
            const SizedBox(
              width: 6,
            ),
            const Expanded(
              child: SizedBox(),
            ),
            const SizedBox(
              width: 4,
            ),
            const Expanded(
              child: SizedBox(),
            ),
            const SizedBox(
              width: 6,
            ),
            Expanded(
              child: _compactStepButton(
                label: '+5',
                onPressed: () => _changeLeverage(5),
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            Expanded(
              child: _compactStepButton(
                label: '+10',
                onPressed: () => _changeLeverage(10),
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 5,
        ),

        Row(
          children: [
            Expanded(
              child: _compactStepButton(
                label: '+100',
                onPressed: () => _changeMargin(100),
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            Expanded(
              child: _compactStepButton(
                label: 'RES',
                onPressed: () => _setMargin(0),
              ),
            ),
            const SizedBox(
              width: 6,
            ),
            const Expanded(
              child: SizedBox(),
            ),
            const SizedBox(
              width: 4,
            ),
            const Expanded(
              child: SizedBox(),
            ),
            const SizedBox(
              width: 6,
            ),
            Expanded(
              child: _compactStepButton(
                label: 'RES',
                onPressed: () => _setLeverage(1),
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            const Expanded(
              child: SizedBox(),
            ),
          ],
        ),

        const SizedBox(
          height: 8,
        ),

        // ============================================================
        // کارمزد
        // هم‌اندازه دکمه‌های کوچک
        // ============================================================

        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 82,
            height: 31,
            child: TextField(
              controller: _feeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                fontSize: 10,
              ),
              decoration: _inputDecoration(
                label: 'کارمزد',
                englishLabel: 'Fee',
                suffixText: '%',
              ).copyWith(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 5,
                ),
                labelStyle: const TextStyle(
                  fontSize: 9,
                ),
                floatingLabelStyle: const TextStyle(
                  fontSize: 8,
                ),
                suffixStyle: const TextStyle(
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _compactNumberField({
    required TextEditingController controller,
    required String label,
    required String englishLabel,
    String? suffixText,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      style: const TextStyle(
        fontSize: 13,
      ),
      decoration: _inputDecoration(
        label: label,
        englishLabel: englishLabel,
        suffixText: suffixText,
      ).copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 9,
        ),
        labelStyle: const TextStyle(
          fontSize: 11,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 10,
        ),
        suffixStyle: const TextStyle(
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _compactStepButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 31),
        maximumSize: const Size.fromHeight(
          31,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            7,
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
        ),
      ),
    );
  }

// ============================================================
// دسترسی سریع به سایت‌ها داخل صفحه معامله جدید
// ============================================================

  Widget _buildQuickWebsitesSection() {
    // The website is embedded directly in the page, without a surrounding card.
    return const QuickWebsitesPage(embedded: true);
  }

// ============================================================
// بخش یادداشت جدید
// ============================================================

  Widget _buildNewTradeNoteSection() {
    return _buildSection(
      title: 'یادداشت جدید',
      icon: Icons.note_add_outlined,
      children: [
        const Text(
          'در این بخش می‌توانی یادداشت، تحلیل و نکات معامله را ثبت کنی.',
        ),
        const SizedBox(height: 12),
        NewTradeNotePage(
          key: const ValueKey('new_trade_note_form'),
          embedded: true,
          onSaved: () {
            _loadTradeNotes();
          },
        ),
      ],
    );
  }

// ============================================================
// بخش یادداشت‌ها
// ============================================================

  Future<void> _searchSavedNotes(String value) async {
    final query = value.trim();
    final requestId = ++_searchRequestId;

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _noteSearchResults = [];
        _noteSearchError = null;
        _noteSearchLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _noteSearchLoading = true;
      _noteSearchError = null;
      _selectedNoteResultIndex = null;
    });

    try {
      final results = await _tradeNoteRepository.searchNoteMatches(query);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _noteSearchResults = results;
        _noteSearchLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _noteSearchLoading = false;
        _noteSearchError = 'جست‌وجوی یادداشت‌ها ناموفق بود: $e';
      });
    }
  }

  void _openNoteSearchResult(Map<String, dynamic> result) {
    final index = _noteSearchResults.indexOf(result);
    if (index < 0) return;
    setState(() => _selectedNoteResultIndex = index);
  }

  void _moveNoteMatch(int delta) {
    if (_noteSearchResults.isEmpty) return;
    final current = _selectedNoteResultIndex ?? 0;
    final next =
        (current + delta).clamp(0, _noteSearchResults.length - 1).toInt();
    setState(() => _selectedNoteResultIndex = next);
  }

  Widget _buildSelectedNoteResult() {
    final index = _selectedNoteResultIndex;
    if (index == null || index < 0 || index >= _noteSearchResults.length) {
      return const SizedBox.shrink();
    }
    final result = _noteSearchResults[index];
    final note = Map<String, dynamic>.from(result['note'] as Map);
    final field = result['field']?.toString() ?? '';
    final query = result['query']?.toString() ?? '';
    final rawOffset = result['match_start'];
    final offset = rawOffset is num ? rawOffset.toInt() : null;
    final title = note['title']?.toString().trim().isNotEmpty == true
        ? note['title'].toString()
        : 'بدون عنوان';
    return _buildSection(
      title: 'یادداشت انتخاب‌شده: $title',
      icon: Icons.article_outlined,
      children: [
        Row(children: [
          Expanded(
              child: Text(
                  'نتیجه ${numbers.formatInteger(index + 1)} از ${numbers.formatInteger(_noteSearchResults.length)}')),
          IconButton(
              tooltip: 'کلمه/نتیجه قبلی',
              onPressed: index > 0 ? () => _moveNoteMatch(-1) : null,
              icon: const Icon(Icons.skip_previous)),
          IconButton(
              tooltip: 'کلمه/نتیجه بعدی',
              onPressed: index < _noteSearchResults.length - 1
                  ? () => _moveNoteMatch(1)
                  : null,
              icon: const Icon(Icons.skip_next)),
          IconButton(
              tooltip: 'بستن یادداشت',
              onPressed: () => setState(() => _selectedNoteResultIndex = null),
              icon: const Icon(Icons.close)),
        ]),
        NewTradeNotePage(
          key: ValueKey('searched_note_${note['id']}_${field}_${offset ?? 0}'),
          note: note,
          initialSearchTerm: query,
          initialMatchField: field,
          initialMatchOffset: offset,
          embedded: true,
          onSaved: () {
            setState(() => _selectedNoteResultIndex = null);
            _loadTradeNotes();
            if (_noteSearchController.text.trim().isNotEmpty) {
              _searchSavedNotes(_noteSearchController.text);
            }
          },
        ),
      ],
    );
  }

  Widget _buildNoteSearchSection() {
    return _buildSection(
      title: 'جست‌وجوی یادداشت‌ها',
      icon: Icons.search,
      children: [
        TextField(
          controller: _noteSearchController,
          textDirection: TextDirection.rtl,
          onChanged: _searchSavedNotes,
          decoration: InputDecoration(
            hintText: 'جست‌وجو در عنوان، متن، موضوع، برچسب و دارایی',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'پاک‌کردن جست‌وجو',
              onPressed: () {
                _noteSearchController.clear();
                _searchSavedNotes('');
              },
              icon: const Icon(Icons.clear),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_noteSearchLoading) const LinearProgressIndicator(),
        if (_noteSearchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _noteSearchError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!_noteSearchLoading &&
            _noteSearchError == null &&
            _noteSearchController.text.trim().isNotEmpty &&
            _noteSearchResults.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('نتیجه‌ای پیدا نشد.'),
          ),
        ..._noteSearchResults.map((result) {
          final note = Map<String, dynamic>.from(result['note'] as Map);
          final title = note['title']?.toString() ?? 'بدون عنوان';
          final fieldLabel = result['field_label']?.toString() ?? 'یادداشت';
          final matchedText = result['matched_text']?.toString() ?? '';
          final startValue = result['match_start'];
          final endValue = result['match_end'];
          final start = startValue is num ? startValue.toInt() : 0;
          final end = endValue is num ? endValue.toInt() : 0;

          final safeStart = start.clamp(0, matchedText.length).toInt();
          final safeEnd = end.clamp(safeStart, matchedText.length).toInt();
          final prefixStart =
              (safeStart - 35).clamp(0, matchedText.length).toInt();
          final suffixEnd = (safeEnd + 55).clamp(0, matchedText.length).toInt();

          final prefix = matchedText.substring(prefixStart, safeStart);
          final match = matchedText.substring(safeStart, safeEnd);
          final suffix = matchedText.substring(safeEnd, suffixEnd);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('محل تطبیق: $fieldLabel'),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (prefixStart > 0) const TextSpan(text: '…'),
                        TextSpan(text: prefix),
                        TextSpan(
                          text: match,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                          ),
                        ),
                        TextSpan(text: suffix),
                        if (suffixEnd < matchedText.length)
                          const TextSpan(text: '…'),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openNoteSearchResult(result),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTradeNotesSection() {
    return _buildSection(
      title: 'یادداشت‌ها',
      icon: Icons.library_books_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loadTradeNotes,
              icon: const Icon(Icons.refresh),
              label: const Text('به‌روزرسانی فهرست'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute<void>(
                        builder: (_) => const notes_manager.TradeNotesPage(),
                      ),
                    )
                    .then((_) => _loadTradeNotes());
              },
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('مدیریت کامل یادداشت‌ها'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showNewNoteSection = true),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('یادداشت جدید'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_tradeNotesLoading)
          const Center(child: CircularProgressIndicator())
        else if (_tradeNotesError != null)
          Text(
            _tradeNotesError!,
            style: const TextStyle(color: Colors.red),
          )
        else if (_tradeNotes.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('هنوز یادداشتی ذخیره نشده است.'),
            ),
          )
        else
          ..._tradeNotes.map((note) {
            final title = note['title']?.toString().trim().isNotEmpty == true
                ? note['title'].toString()
                : 'بدون عنوان';

            final content = note['content']?.toString() ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(title),
                subtitle: content.trim().isEmpty
                    ? null
                    : Text(
                        content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                isThreeLine: content.trim().isNotEmpty,
                trailing: const Icon(Icons.notes_outlined),
              ),
            );
          }),
      ],
    );
  }

  // ============================================================
  // وضعیت لحظه‌ای
  // ============================================================

  Widget _buildMetricsSection() {
    return _buildSection(
      title: 'وضعیت لحظه‌ای (Live Metrics)',
      icon: Icons.analytics_outlined,
      children: [
        _metricRow(
          'تغییر قیمت نسبت به ورود',
          '${_formatPercent(_priceChangePercent)}%',
          englishTitle: 'Price Change vs Entry',
        ),
        _metricRow(
          'اثر روی مارجین',
          '${_formatMoney(_marginEffectDollar)}  |  '
              '${_formatPercent(_marginEffectPercent)}%',
          englishTitle: 'Margin Effect',
        ),
        _metricRow(
          'سود و زیان',
          _formatMoney(_livePnl),
          englishTitle: 'PnL',
        ),
        _metricRow(
          'بازده سرمایه',
          '${_formatPercent(_liveRoiPercent)}%  |  '
              '${_formatMoney(_liveRoiDollar)}',
          englishTitle: 'ROI',
        ),
        _metricRow(
          'ریسک تا حد ضرر',
          '${_formatMoney(_liveRiskDollar)}  |  '
              '${_formatPercent(_liveRiskPercent)}%',
          englishTitle: 'Risk to Stop Loss',
        ),
        _metricRow(
          'نسبت ریسک به ریوارد لحظه‌ای',
          _liveRiskReward > 0 ? '1 : ${_formatNumber(_liveRiskReward)}' : '-',
          englishTitle: 'Live R:R',
        ),
        _metricRow(
          'مدت معامله',
          _formatDuration(
            _durationSeconds,
          ),
          englishTitle: 'Trade Duration',
        ),
      ],
    );
  }

  // ============================================================
  // موقعیت قیمت
  // ============================================================

  Widget _buildProgressSection() {
    final entry =
        _entryPreciseValue ?? _toDoubleNullable(_entryController.text);
    final stop = _stopPreciseValue ?? _toDoubleNullable(_stopController.text);
    final target =
        _targetPreciseValue ?? _toDoubleNullable(_targetController.text);

    final current = _livePrice;

    if (entry == null || stop == null || target == null || current == null) {
      return const SizedBox.shrink();
    }

    double progress;

    if (_direction == TradeDirection.long) {
      final total = target - stop;

      progress = total > 0 ? (current - stop) / total : 0;
    } else {
      final total = stop - target;

      progress = total > 0 ? (stop - current) / total : 0;
    }

    progress = progress
        .clamp(
          0.0,
          1.0,
        )
        .toDouble();

    return _buildSection(
      title: 'موقعیت قیمت (Price Position)',
      icon: Icons.linear_scale,
      children: [
        Row(
          children: [
            Text(
              'حد ضرر (Stop Loss)',
              style: TextStyle(
                color: AppColors.stop,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              'ورود (Entry)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.entry,
              ),
            ),
            const Spacer(),
            Text(
              'حد سود (Take Profit)',
              style: TextStyle(
                color: AppColors.target,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 8,
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(
            10,
          ),
          child: LinearProgressIndicator(
            minHeight: 14,
            value: progress,
            backgroundColor: AppColors.boxBackground,
            color: _direction == TradeDirection.long
                ? AppColors.long
                : AppColors.short,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Center(
          child: Text(
            'قیمت فعلی (Current Price): '
            '${_formatAssetPrice(current)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Drawdown
  // ============================================================

  Widget _buildDrawdownSection() {
    return _buildSection(
      title: 'افت سرمایه (Drawdown)',
      icon: Icons.warning_amber_outlined,
      children: [
        _metricRow(
          'بیشترین افت قیمت',
          '${_formatPercent(_maxDrawdownPricePercent)}%',
          englishTitle: 'Maximum Price Drawdown',
        ),
        _metricRow(
          'افت دلاری',
          _formatMoney(
            _maxDrawdownDollar,
          ),
          englishTitle: 'Dollar Drawdown',
        ),
        _metricRow(
          'افت نسبت به مارجین',
          '${_formatPercent(_maxDrawdownMarginPercent)}%',
          englishTitle: 'Drawdown / Margin',
        ),
      ],
    );
  }

  void _updateDrawdown({
    bool updateUi = true,
  }) {
    final entry =
        _entryPreciseValue ?? _toDoubleNullable(_entryController.text);

    if (entry == null || entry <= 0 || _livePrice == null) {
      return;
    }

    final current = _livePrice!;

    double adversePercent;

    if (_direction == TradeDirection.long) {
      adversePercent = ((entry - current) / entry) * 100;
    } else {
      adversePercent = ((current - entry) / entry) * 100;
    }

    if (adversePercent < 0) {
      adversePercent = 0;
    }

    final margin = _toDouble(
      _marginController.text,
    );

    final drawdownDollar = _volume * adversePercent / 100;

    final marginPercent = margin > 0 ? drawdownDollar / margin * 100 : 0;

    if (adversePercent > _maxDrawdownPricePercent) {
      _maxDrawdownPricePercent = adversePercent;

      _maxDrawdownDollar = drawdownDollar;

      _maxDrawdownMarginPercent = marginPercent.toDouble();

      if (updateUi && mounted) {
        setState(() {});
      }
    }
  }

  // ============================================================
  // اطلاعات معامله
  // ============================================================

  Widget _buildGeneralSection() {
    return _buildSection(
      title: 'اطلاعات معامله (Trade Information)',
      icon: Icons.info_outline,
      children: [
        _buildDirectionSelector(),
        const SizedBox(height: 10),
        _buildMarginModeSelector(),
      ],
    );
  }

  // ============================================================
  // زمان ثبت معامله
  // ============================================================

  Widget _buildTradeTimeSection() {
    return _buildSection(
      title: 'زمان ثبت معامله (Trade Time)',
      icon: Icons.schedule_outlined,
      children: [
        InkWell(
          onTap: _selectEntryDateTime,
          borderRadius: BorderRadius.circular(
            12,
          ),
          child: InputDecorator(
            decoration: _inputDecoration(
              label: 'زمان ثبت معامله',
              englishLabel: 'Trade Time',
              suffixIcon: const Icon(
                Icons.calendar_today,
              ),
            ),
            child: Text(
              _formatEntryDate(),
            ),
          ),
        ),
        const SizedBox(
          height: 7,
        ),
        Text(
          'تقویم نمایش: شمسی (Jalali)',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // تصاویر
  // ============================================================

  Widget _buildImagesSection() {
    return _buildSection(
      title: 'تصاویر (Images)',
      icon: Icons.image_outlined,
      children: [
        OutlinedButton.icon(
          onPressed: _pickImages,
          icon: const Icon(
            Icons.add_photo_alternate_outlined,
          ),
          label: const Text(
            'افزودن تصویر',
          ),
        ),
        if (_imagePaths.isNotEmpty) ...[
          const SizedBox(
            height: 12,
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (context, index) => const SizedBox(
                width: 8,
              ),
              itemBuilder: (context, index) {
                final path = _imagePaths[index];

                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                              child: InteractiveViewer(
                                  child: Image.file(File(path),
                                      fit: BoxFit.contain)))),
                      onLongPress: () => _replaceImage(index),
                      child: Container(
                        width: 110,
                        height: 110,
                        alignment: Alignment.center,
                        child: Image.file(
                          File(path),
                          width: 110,
                          height: 110,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: InkWell(
                        onTap: () {
                          _removeImage(
                            index,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.imageDeleteBackground,
                          ),
                          padding: const EdgeInsets.all(
                            4,
                          ),
                          child: Icon(
                            Icons.close,
                            color: AppColors.imageDeleteIcon,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // ثبت معامله
  // ============================================================
  Widget _buildTopActionRow() {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 18,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveTrade,
                icon: _saving
                    ? SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.buttonText,
                        ),
                      )
                    : const Icon(
                        Icons.save_outlined,
                      ),
                label: Text(
                  _saving ? 'در حال ذخیره...' : 'ثبت معامله',
                ),
              ),
            ),
          ),
          const SizedBox(
            width: 6,
          ),
          Expanded(
            child: _buildAlertButtonWithLabel(
              title: 'حد ضرر',
              enabled: _stopAlertEnabled,
              onPressed: _toggleStopAlert,
            ),
          ),
          const SizedBox(
            width: 6,
          ),
          Expanded(
            child: _buildAlertButtonWithLabel(
              title: 'حد سود',
              enabled: _targetAlertEnabled,
              onPressed: _toggleTargetAlert,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Section
  // ============================================================
// ============================================================
// بخش عمومی صفحه
// ============================================================
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final bool hasTitle = title.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTitle) ...[
            Row(
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: AppColors.button,
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
          ],
          ...children,
        ],
      ),
    );
  }
// ============================================================
// استایل ورودی
// ============================================================

  InputDecoration _inputDecoration({
    required String label,
    String? englishLabel,
    String? hint,
    String? suffixText,
    String? helperText,
    Widget? suffixIcon,
  }) {
    final Widget? bilingualLabel = englishLabel == null
        ? null
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: const TextStyle(
                    fontSize: 14,
                  ),
                ),
                TextSpan(
                  text: '($englishLabel)',
                  style: const TextStyle(
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          );

    return InputDecoration(
      labelText: englishLabel == null ? label : null,
      label: bilingualLabel,
      hintText: hint,
      suffixText: suffixText,
      helperText: helperText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.inputBackground,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: AppColors.inputFocusedBorder,
          width: 2,
        ),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: AppColors.inputErrorBorder,
          width: 1,
        ),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: AppColors.inputErrorBorder,
          width: 2,
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String englishLabel,
    String? suffixText,
  }) {
    return TextField(
      controller: controller,
      onChanged: (value) => _onPriceChanged(controller, value),
      onEditingComplete: () {
        final exact = _exactPriceFor(controller);
        if (exact != null) {
          final formatted = _formatAssetPrice(exact);
          controller.value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
        FocusScope.of(context).unfocus();
      },
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      decoration: _inputDecoration(
        label: label,
        englishLabel: englishLabel,
        suffixText: suffixText,
      ),
    );
  }

  // ============================================================
  // نمایش متریک
  // ============================================================

  Widget _metricRow(
    String title,
    String value, {
    String? englishTitle,
  }) {
    final parsed = double.tryParse(
      numbers.normalizeNumberInput(value).replaceAll(
            RegExp(r'[^0-9.\-]'),
            '',
          ),
    );

    Color valueColor = AppColors.text;

    if (parsed != null) {
      if (parsed > 0) {
        valueColor = AppColors.profit;
      } else if (parsed < 0) {
        valueColor = AppColors.loss;
      }
    }

    final Widget titleWidget = englishTitle == null
        ? Text(
            title,
            style: TextStyle(
              color: AppColors.secondaryText,
            ),
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title ',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                  ),
                ),
                TextSpan(
                  text: '($englishTitle)',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 9,
      ),
      child: Row(
        children: [
          Expanded(
            child: titleWidget,
          ),
          const SizedBox(
            width: 8,
          ),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ابزارهای محاسباتی
  // ============================================================

  double _toDouble(
    String value,
  ) {
    return double.tryParse(
          numbers.normalizeNumberInput(value).replaceAll(',', '').trim(),
        ) ??
        0;
  }

  double? _toDoubleNullable(
    String value,
  ) {
    return double.tryParse(
      numbers.normalizeNumberInput(value).replaceAll(',', '').trim(),
    );
  }

  String _formatNumber(
    double value,
  ) {
    return numbers.formatNumber(value, decimals: 4);
  }

  String _formatMoney(
    double value,
  ) {
    return numbers.formatNumber(value, decimals: 2, trimTrailingZeros: false);
  }

  String _formatPercent(
    double value,
  ) {
    return numbers.formatNumber(value, decimals: 2, trimTrailingZeros: false);
  }

  String formatPercentValue(
    double value,
    double base,
  ) {
    if (base <= 0) {
      return '0.00';
    }

    return _formatPercent(
      (value / base) * 100,
    );
  }

  String _formatDuration(
    int seconds,
  ) {
    final hours = seconds ~/ 3600;

    final minutes = (seconds % 3600) ~/ 60;

    final secs = seconds % 60;

    return numbers.formatDigits('${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}');
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.button,
          ),
        ),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_noteFontSize / 14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            fontFamily: _customNoteFontPath == null ? null : _customNoteFontFamily,
          ),
          primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
            fontFamily: _customNoteFontPath == null ? null : _customNoteFontFamily,
          ),
        ),
        child: Scaffold(
      appBar: AppBar(
        title: const Text('معامله جدید'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              14,
              14,
              14,
              30,
            ),
            children: [
              // ردیف بالایی: ثبت معامله + هشدارها
              _buildTopActionRow(),

              // خلاصه سه ردیفی
              _buildTopSummarySection(),

              // قیمت‌ها و مدیریت معامله
              _buildPriceSection(),

              // سرمایه، حجم و اهرم
              _buildCapitalSection(),

              // وضعیت لحظه‌ای و افت سرمایه در صفحه جزئیات معامله نمایش داده می‌شوند.

              // موقعیت قیمت
              _buildProgressSection(),

              _buildOptionalSectionToggles(),

              // بخش‌های اختیاری بلافاصله بعد از کلیدهای نمایش قرار می‌گیرند
              // تا کاربر مجبور نباشد برای پیدا کردن آن‌ها تا انتهای فرم برود.
              if (_showWebsitesSection) _buildQuickWebsitesSection(),

              // سوالات و چک‌لیست‌ها با نمایش مستقل
              _buildPreTradeSection(),

              // تصاویر
              _buildImagesSection(),

              // فیلدهای سفارشی
              _buildCustomFieldsSection(),

              // زمان ثبت معامله
              _buildTradeTimeSection(),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _tickerSubscription?.cancel();

    _uiTimer?.cancel();

    _lbankService.dispose();
    _noteSearchController.dispose();

    _symbolController.dispose();
    _symbolFocusNode.dispose();
    _marginController.dispose();
    _dollarRateController.dispose();
    _volumeController.dispose();
    _leverageController.dispose();
    _entryController.dispose();
    _stopController.dispose();
    _targetController.dispose();
    _feeController.dispose();
    _rrController.dispose();

    for (final controller in _customTextControllers.values) {
      controller.dispose();
    }

    for (final controller in _preTradeControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }
}
