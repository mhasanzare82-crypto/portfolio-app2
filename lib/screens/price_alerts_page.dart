import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/price_alert.dart';
import '../repositories/price_alert_repository.dart';
import '../services/notification_service.dart';
import 'color_settings_page.dart';
import '../utils/number_formatter.dart' as numbers;

class PriceAlertsPage extends StatefulWidget {
  const PriceAlertsPage({
    super.key,
  });

  @override
  State<PriceAlertsPage> createState() => _PriceAlertsPageState();
}

class _PriceAlertsPageState extends State<PriceAlertsPage> {
  final PriceAlertRepository _repository = PriceAlertRepository.instance;

  final List<PriceAlert> _alerts = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final alerts = await _repository.getAllAlerts();

      if (!mounted) return;

      setState(() {
        _alerts
          ..clear()
          ..addAll(alerts);

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage(
        'خطا در دریافت هشدارها: $e',
      );
    }
  }

  Future<void> _testNotification() async {
    try {
      await NotificationService.instance.showTestNotification();

      if (!mounted) return;

      _showMessage(
        'اعلان آزمایشی ارسال شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'ارسال اعلان ناموفق بود: $e',
      );
    }
  }

  Future<void> _showAddAlertDialog() async {
    final result = await showDialog<PriceAlert>(
      context: context,
      builder: (_) => const _AlertEditorDialog(),
    );

    if (result == null) {
      return;
    }

    try {
      await _repository.insertAlert(
        result,
      );

      await _loadAlerts();

      if (!mounted) return;

      _showMessage(
        'هشدار با موفقیت ایجاد شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'ایجاد هشدار ناموفق بود: $e',
      );
    }
  }

  Future<void> _showAddMultiStageDialog() async {
    final result = await showDialog<List<PriceAlert>>(
      context: context,
      builder: (_) => const _MultiStageEditorDialog(),
    );

    if (result == null || result.isEmpty) {
      return;
    }

    try {
      for (final alert in result) {
        await _repository.insertAlert(
          alert,
        );
      }

      await _loadAlerts();

      if (!mounted) return;

      _showMessage(
        '${numbers.formatInteger(result.length)} مرحله هشدار ایجاد شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'ایجاد هشدار مرحله‌ای ناموفق بود: $e',
      );
    }
  }

  Future<void> _showEditAlertDialog(
    PriceAlert alert,
  ) async {
    if (alert.type == PriceAlertType.multiStage &&
        alert.multiStageGroupId != null) {
      await _showEditMultiStageDialog(
        alert,
      );

      return;
    }

    final result = await showDialog<PriceAlert>(
      context: context,
      builder: (_) => _AlertEditorDialog(
        initialAlert: alert,
      ),
    );

    if (result == null) {
      return;
    }

    try {
      await _repository.updateAlert(
        result,
      );

      await _loadAlerts();

      if (!mounted) return;

      _showMessage(
        'هشدار ویرایش شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'ویرایش هشدار ناموفق بود: $e',
      );
    }
  }

  Future<void> _showEditMultiStageDialog(
    PriceAlert alert,
  ) async {
    final groupId = alert.multiStageGroupId;

    if (groupId == null || groupId.trim().isEmpty) {
      return;
    }

    final group = await _repository.getAlertsByGroupId(
      groupId,
    );

    if (!mounted) return;

    if (group.isEmpty) {
      _showMessage(
        'مراحل این گروه پیدا نشد.',
      );
      return;
    }

    final result = await showDialog<List<PriceAlert>>(
      context: context,
      builder: (_) => _MultiStageEditorDialog(
        initialAlerts: group,
      ),
    );

    if (result == null || result.isEmpty) {
      return;
    }

    try {
      for (final oldAlert in group) {
        final exists = result.any(
          (item) => item.id == oldAlert.id,
        );

        if (!exists) {
          await _repository.deleteAlert(
            oldAlert.id,
          );
        }
      }

      for (final item in result) {
        final existed = group.any(
          (old) => old.id == item.id,
        );

        if (existed) {
          await _repository.updateAlert(
            item,
          );
        } else {
          await _repository.insertAlert(
            item,
          );
        }
      }

      await _loadAlerts();

      if (!mounted) return;

      _showMessage(
        'هشدار مرحله‌ای ویرایش شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'ویرایش هشدار مرحله‌ای ناموفق بود: $e',
      );
    }
  }

  Future<void> _toggleAlert(
    PriceAlert alert,
  ) async {
    try {
      await _repository.setActive(
        alert.id,
        !alert.isActive,
      );

      await _loadAlerts();
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'تغییر وضعیت هشدار ناموفق بود: $e',
      );
    }
  }

  Future<void> _resetAlert(
    PriceAlert alert,
  ) async {
    try {
      await _repository.resetAlert(
        alert.id,
      );

      await _loadAlerts();

      if (!mounted) return;

      _showMessage(
        'هشدار دوباره فعال شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'بازنشانی هشدار ناموفق بود: $e',
      );
    }
  }

  Future<void> _deleteAlert(
    PriceAlert alert,
  ) async {
    final isGroup = alert.type == PriceAlertType.multiStage &&
        alert.multiStageGroupId != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          isGroup ? 'حذف هشدار مرحله‌ای' : 'حذف هشدار',
        ),
        content: Text(
          isGroup
              ? 'آیا تمام مراحل «${alert.title}» حذف شوند؟'
              : 'آیا هشدار «${alert.title}» حذف شود؟',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                context,
                false,
              );
            },
            child: const Text(
              'انصراف',
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                true,
              );
            },
            child: const Text(
              'حذف',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      if (isGroup) {
        await _repository.deleteGroup(
          alert.multiStageGroupId!,
        );
      } else {
        await _repository.deleteAlert(
          alert.id,
        );
      }

      await _loadAlerts();

      if (!mounted) return;

      _showMessage(
        isGroup ? 'هشدار مرحله‌ای حذف شد.' : 'هشدار حذف شد.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'حذف هشدار ناموفق بود: $e',
      );
    }
  }

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  String _typeTitle(
    PriceAlertType type,
  ) {
    switch (type) {
      case PriceAlertType.target:
        return 'قیمت هدف';

      case PriceAlertType.crossing:
        return 'عبور قیمت';

      case PriceAlertType.rangeExit:
        return 'خروج از محدوده';

      case PriceAlertType.tradeTarget:
        return 'Target معامله';

      case PriceAlertType.tradeStopLoss:
        return 'Stop Loss معامله';

      case PriceAlertType.multiStage:
        return 'هشدار مرحله‌ای';
    }
  }

  String _repeatTitle(
    PriceAlertRepeatMode mode,
  ) {
    switch (mode) {
      case PriceAlertRepeatMode.once:
        return 'یک‌بار';

      case PriceAlertRepeatMode.everyCrossing:
        return 'هر بار عبور';

      case PriceAlertRepeatMode.periodic:
        return 'دوره‌ای';
    }
  }

  String _formatPrice(
    double? value,
  ) {
    if (value == null) {
      return '-';
    }

    if (value == value.roundToDouble()) {
      return numbers.formatNumber(value, decimals: 0, trimTrailingZeros: false);
    }

    return numbers.formatNumber(value, decimals: 4);
  }

  Widget _buildAlertCard(
    PriceAlert alert,
  ) {
    final isStage = alert.type == PriceAlertType.multiStage;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    alert.title.isEmpty ? 'هشدار قیمت' : alert.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Icon(
                  alert.isActive
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  color: alert.isActive
                      ? AppColors.alertActive
                      : AppColors.alertInactive,
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'نوع: ${_typeTitle(alert.type)}',
            ),
            const SizedBox(
              height: 4,
            ),
            if (isStage)
              Text(
                'مرحله: ${(alert.stageIndex ?? 0) + 1}',
              ),
            if (alert.targetPrice != null)
              Text(
                'قیمت هدف: ${_formatPrice(alert.targetPrice)}',
              ),
            if (alert.lowerPrice != null && alert.upperPrice != null)
              Text(
                'محدوده: '
                '${_formatPrice(alert.lowerPrice)}'
                ' تا '
                '${_formatPrice(alert.upperPrice)}',
              ),
            const SizedBox(
              height: 4,
            ),
            Text(
              'جهت: '
              '${alert.triggerOnRise ? 'صعودی' : 'نزولی'}',
            ),
            const SizedBox(
              height: 4,
            ),
            Text(
              'تکرار: '
              '${_repeatTitle(alert.repeatMode)}',
            ),
            if (alert.repeatMode == PriceAlertRepeatMode.periodic &&
                alert.repeatIntervalMinutes != null)
              Text(
                'فاصله: '
                '${alert.repeatIntervalMinutes} دقیقه',
              ),
            if (alert.note.trim().isNotEmpty) ...[
              const SizedBox(
                height: 6,
              ),
              Text(
                alert.note,
              ),
            ],
            if (alert.soundPath != null &&
                alert.soundPath!.trim().isNotEmpty) ...[
              const SizedBox(
                height: 6,
              ),
              const Row(
                children: [
                  Icon(
                    Icons.volume_up,
                    size: 18,
                  ),
                  SizedBox(
                    width: 5,
                  ),
                  Text(
                    'صدای اختصاصی فعال است',
                  ),
                ],
              ),
            ],
            const SizedBox(
              height: 8,
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                IconButton(
                  tooltip: 'ویرایش',
                  onPressed: () => _showEditAlertDialog(
                    alert,
                  ),
                  icon: const Icon(
                    Icons.edit,
                  ),
                ),
                IconButton(
                  tooltip: alert.isActive ? 'غیرفعال کردن' : 'فعال کردن',
                  onPressed: () => _toggleAlert(
                    alert,
                  ),
                  icon: Icon(
                    alert.isActive ? Icons.pause_circle : Icons.play_circle,
                  ),
                ),
                if (alert.isTriggered)
                  IconButton(
                    tooltip: 'بازنشانی',
                    onPressed: () => _resetAlert(
                      alert,
                    ),
                    icon: const Icon(
                      Icons.restart_alt,
                    ),
                  ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => _deleteAlert(
                    alert,
                  ),
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final grouped = <String, List<PriceAlert>>{};

    for (final alert in _alerts) {
      final symbol = alert.symbol.trim().toUpperCase();

      grouped
          .putIfAbsent(
            symbol.isEmpty ? 'بدون نماد' : symbol,
            () => [],
          )
          .add(alert);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'هشدارهای قیمت',
        ),
        actions: [
          IconButton(
            tooltip: 'تست اعلان',
            icon: const Icon(
              Icons.notifications_active,
            ),
            onPressed: _testNotification,
          ),
        ],
      ),
      floatingActionButton: PopupMenuButton<String>(
        tooltip: 'افزودن هشدار',
        icon: const Icon(
          Icons.add_alert,
        ),
        onSelected: (value) {
          if (value == 'normal') {
            _showAddAlertDialog();
          } else if (value == 'multi') {
            _showAddMultiStageDialog();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'normal',
            child: Text(
              'هشدار معمولی',
            ),
          ),
          PopupMenuItem(
            value: 'multi',
            child: Text(
              'هشدار چندمرحله‌ای',
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_none,
                        size: 60,
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      const Text(
                        'هنوز هشداری ایجاد نشده است.',
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      FilledButton.icon(
                        onPressed: _showAddAlertDialog,
                        icon: const Icon(
                          Icons.add_alert,
                        ),
                        label: const Text(
                          'ایجاد هشدار',
                        ),
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      OutlinedButton.icon(
                        onPressed: _showAddMultiStageDialog,
                        icon: const Icon(
                          Icons.linear_scale,
                        ),
                        label: const Text(
                          'ایجاد هشدار مرحله‌ای',
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAlerts,
                  child: ListView(
                    padding: const EdgeInsets.all(
                      12,
                    ),
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 8,
                            bottom: 8,
                          ),
                          child: Text(
                            entry.key,
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        for (final alert in entry.value)
                          _buildAlertCard(
                            alert,
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ============================================================================
// NORMAL ALERT EDITOR
// ============================================================================

class _AlertEditorDialog extends StatefulWidget {
  final PriceAlert? initialAlert;

  const _AlertEditorDialog({
    this.initialAlert,
  });

  @override
  State<_AlertEditorDialog> createState() => _AlertEditorDialogState();
}

class _AlertEditorDialogState extends State<_AlertEditorDialog> {
  late final TextEditingController _symbolController;

  late final TextEditingController _titleController;

  late final TextEditingController _noteController;

  late final TextEditingController _targetController;

  late final TextEditingController _lowerController;

  late final TextEditingController _upperController;

  late final TextEditingController _intervalController;

  PriceAlertType _type = PriceAlertType.target;

  PriceAlertRepeatMode _repeatMode = PriceAlertRepeatMode.once;

  bool _triggerOnRise = true;

  String? _soundPath;

  bool get _editing => widget.initialAlert != null;

  @override
  void initState() {
    super.initState();

    final alert = widget.initialAlert;

    _symbolController = TextEditingController(
      text: alert?.symbol ?? 'GOLDUSDT',
    );

    _titleController = TextEditingController(
      text: alert?.title ?? '',
    );

    _noteController = TextEditingController(
      text: alert?.note ?? '',
    );

    _targetController = TextEditingController(
      text: alert?.targetPrice?.toString() ?? '',
    );

    _lowerController = TextEditingController(
      text: alert?.lowerPrice?.toString() ?? '',
    );

    _upperController = TextEditingController(
      text: alert?.upperPrice?.toString() ?? '',
    );

    _intervalController = TextEditingController(
      text: alert?.repeatIntervalMinutes?.toString() ?? '5',
    );

    if (alert != null) {
      _type = alert.type;
      _repeatMode = alert.repeatMode;
      _triggerOnRise = alert.triggerOnRise;
      _soundPath = alert.soundPath;
    }
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _titleController.dispose();
    _noteController.dispose();
    _targetController.dispose();
    _lowerController.dispose();
    _upperController.dispose();
    _intervalController.dispose();

    super.dispose();
  }

  Future<void> _pickSound() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final path = result.files.single.path;

      if (path == null || path.trim().isEmpty) {
        return;
      }

      setState(() {
        _soundPath = path;
      });
    } catch (e) {
      if (!mounted) return;

      _showError(
        'انتخاب صدا ناموفق بود: $e',
      );
    }
  }

  double? _parseDouble(
    String value,
  ) {
    final normalized =
        numbers.normalizeNumberInput(value).trim().replaceAll(',', '');

    if (normalized.isEmpty) {
      return null;
    }

    return double.tryParse(
      normalized,
    );
  }

  int? _parseInt(
    String value,
  ) {
    return int.tryParse(
      numbers.normalizeNumberInput(value).trim().replaceAll(',', ''),
    );
  }

  void _save() {
    final symbol = _symbolController.text.trim().toUpperCase();

    final title = _titleController.text.trim();

    final note = _noteController.text.trim();

    if (symbol.isEmpty) {
      _showError(
        'نماد دارایی را وارد کنید.',
      );
      return;
    }

    if (title.isEmpty) {
      _showError(
        'عنوان هشدار را وارد کنید.',
      );
      return;
    }

    final target = _parseDouble(
      _targetController.text,
    );

    final lower = _parseDouble(
      _lowerController.text,
    );

    final upper = _parseDouble(
      _upperController.text,
    );

    int? interval;

    if (_repeatMode == PriceAlertRepeatMode.periodic) {
      interval = _parseInt(
        _intervalController.text,
      );

      if (interval == null || interval <= 0) {
        _showError(
          'فاصله تکرار باید بیشتر از صفر باشد.',
        );
        return;
      }
    }

    if (_type == PriceAlertType.rangeExit &&
        (lower == null || upper == null || lower <= 0 || upper <= 0)) {
      _showError(
        'برای خروج از محدوده، هر دو قیمت محدوده را وارد کنید.',
      );
      return;
    }

    if (_type != PriceAlertType.rangeExit &&
        (_type != PriceAlertType.multiStage &&
            (target == null || target <= 0))) {
      _showError(
        'قیمت هدف معتبر وارد کنید.',
      );
      return;
    }

    if (_type == PriceAlertType.multiStage) {
      _showError(
        'برای هشدار چندمرحله‌ای از گزینه «هشدار چندمرحله‌ای» استفاده کنید.',
      );
      return;
    }

    final old = widget.initialAlert;

    final alert = PriceAlert(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      symbol: symbol,
      title: title,
      note: note,
      type: _type,
      targetPrice: _type == PriceAlertType.rangeExit ? null : target,
      lowerPrice: _type == PriceAlertType.rangeExit ? lower : null,
      upperPrice: _type == PriceAlertType.rangeExit ? upper : null,
      triggerOnRise: _triggerOnRise,
      repeatMode: _repeatMode,
      repeatIntervalMinutes: interval,
      isActive: old?.isActive ?? true,
      isTriggered: old?.isTriggered ?? false,
      soundPath: _soundPath,
      tradeId: old?.tradeId,
      tradePriceType: old?.tradePriceType,
      multiStageGroupId: old?.multiStageGroupId,
      stageIndex: old?.stageIndex,
      createdAt: old?.createdAt ?? DateTime.now(),
      lastTriggeredAt: old?.lastTriggeredAt,
      triggeredAt: old?.triggeredAt,
    );

    Navigator.pop(
      context,
      alert,
    );
  }

  void _showError(
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  String _typeLabel(
    PriceAlertType type,
  ) {
    switch (type) {
      case PriceAlertType.target:
        return 'قیمت هدف';

      case PriceAlertType.crossing:
        return 'عبور قیمت';

      case PriceAlertType.rangeExit:
        return 'خروج از محدوده';

      case PriceAlertType.tradeTarget:
        return 'Target معامله';

      case PriceAlertType.tradeStopLoss:
        return 'Stop Loss معامله';

      case PriceAlertType.multiStage:
        return 'هشدار مرحله‌ای';
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final isRange = _type == PriceAlertType.rangeExit;

    return AlertDialog(
      title: Text(
        _editing ? 'ویرایش هشدار' : 'هشدار جدید',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _symbolController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'نماد',
                  hintText: 'GOLDUSDT',
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان هشدار',
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'متن / توضیح کوتاه',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              DropdownButtonFormField<PriceAlertType>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'نوع هشدار',
                ),
                items: PriceAlertType.values
                    .where(
                      (type) => type != PriceAlertType.multiStage,
                    )
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          _typeLabel(
                            type,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _type = value;
                  });
                },
              ),
              const SizedBox(
                height: 10,
              ),
              if (isRange) ...[
                TextField(
                  controller: _lowerController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'حد پایین',
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                TextField(
                  controller: _upperController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'حد بالا',
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _targetController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'قیمت هدف',
                  ),
                ),
              ],
              const SizedBox(
                height: 10,
              ),
              DropdownButtonFormField<PriceAlertRepeatMode>(
                value: _repeatMode,
                decoration: const InputDecoration(
                  labelText: 'نوع تکرار',
                ),
                items: PriceAlertRepeatMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(
                          _repeatLabel(
                            mode,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _repeatMode = value;
                  });
                },
              ),
              if (_repeatMode == PriceAlertRepeatMode.periodic) ...[
                const SizedBox(
                  height: 10,
                ),
                TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'فاصله تکرار به دقیقه',
                  ),
                ),
              ],
              const SizedBox(
                height: 10,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'جهت صعودی',
                ),
                subtitle: Text(
                  _triggerOnRise
                      ? 'رسیدن قیمت از پایین به بالا'
                      : 'رسیدن قیمت از بالا به پایین',
                ),
                value: _triggerOnRise,
                onChanged: (value) {
                  setState(() {
                    _triggerOnRise = value;
                  });
                },
              ),
              const SizedBox(
                height: 8,
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickSound,
                      icon: const Icon(
                        Icons.audio_file,
                      ),
                      label: const Text(
                        'انتخاب صدای هشدار',
                      ),
                    ),
                  ),
                  if (_soundPath != null && _soundPath!.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'حذف صدا',
                      onPressed: () {
                        setState(
                          () {
                            _soundPath = null;
                          },
                        );
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                    ),
                ],
              ),
              if (_soundPath != null && _soundPath!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 6,
                  ),
                  child: Text(
                    _soundPath!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
            );
          },
          child: const Text(
            'انصراف',
          ),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            _editing ? 'ذخیره تغییرات' : 'ایجاد هشدار',
          ),
        ),
      ],
    );
  }

  String _repeatLabel(
    PriceAlertRepeatMode mode,
  ) {
    switch (mode) {
      case PriceAlertRepeatMode.once:
        return 'یک‌بار';

      case PriceAlertRepeatMode.everyCrossing:
        return 'هر بار عبور';

      case PriceAlertRepeatMode.periodic:
        return 'دوره‌ای';
    }
  }
}

// ============================================================================
// MULTI STAGE EDITOR
// ============================================================================

class _MultiStageEditorDialog extends StatefulWidget {
  final List<PriceAlert>? initialAlerts;

  const _MultiStageEditorDialog({
    this.initialAlerts,
  });

  @override
  State<_MultiStageEditorDialog> createState() =>
      _MultiStageEditorDialogState();
}

class _MultiStageEditorDialogState extends State<_MultiStageEditorDialog> {
  late final TextEditingController _symbolController;

  late final TextEditingController _groupTitleController;

  late final List<_StageDraft> _stages;

  bool get _editing =>
      widget.initialAlerts != null && widget.initialAlerts!.isNotEmpty;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialAlerts;

    final first = initial?.first;

    _symbolController = TextEditingController(
      text: first?.symbol ?? 'GOLDUSDT',
    );

    _groupTitleController = TextEditingController(
      text: first?.title ?? 'هشدار مرحله‌ای',
    );

    _stages = [];

    if (initial != null && initial.isNotEmpty) {
      final sorted = List<PriceAlert>.from(
        initial,
      )..sort(
          (a, b) => (a.stageIndex ?? 0).compareTo(
            b.stageIndex ?? 0,
          ),
        );

      for (final alert in sorted) {
        _stages.add(
          _StageDraft.fromAlert(
            alert,
          ),
        );
      }
    }

    if (_stages.isEmpty) {
      _stages.add(
        _StageDraft(),
      );
      _stages.add(
        _StageDraft(),
      );
      _stages.add(
        _StageDraft(),
      );
    }
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _groupTitleController.dispose();

    for (final stage in _stages) {
      stage.dispose();
    }

    super.dispose();
  }

  void _addStage() {
    if (_stages.length >= 20) {
      _showError(
        'حداکثر ۲۰ مرحله قابل ایجاد است.',
      );
      return;
    }

    setState(() {
      _stages.add(
        _StageDraft(),
      );
    });
  }

  void _removeStage(
    int index,
  ) {
    if (_stages.length <= 1) {
      _showError(
        'حداقل یک مرحله باید وجود داشته باشد.',
      );
      return;
    }

    setState(() {
      final stage = _stages.removeAt(
        index,
      );

      stage.dispose();
    });
  }

  void _save() {
    final symbol = _symbolController.text.trim().toUpperCase();

    final groupTitle = _groupTitleController.text.trim();

    if (symbol.isEmpty) {
      _showError(
        'نماد دارایی را وارد کنید.',
      );
      return;
    }

    if (groupTitle.isEmpty) {
      _showError(
        'عنوان گروه را وارد کنید.',
      );
      return;
    }

    if (_stages.isEmpty) {
      _showError(
        'حداقل یک مرحله لازم است.',
      );
      return;
    }

    for (var i = 0; i < _stages.length; i++) {
      final target = _stages[i].target;

      if (target == null || target <= 0) {
        _showError(
          'قیمت مرحله ${i + 1} معتبر نیست.',
        );
        return;
      }
    }

    final oldGroup = widget.initialAlerts;

    final groupId = oldGroup?.first.multiStageGroupId ??
        DateTime.now().microsecondsSinceEpoch.toString();

    final now = DateTime.now();

    final oldByIndex = <int, PriceAlert>{};

    if (oldGroup != null) {
      for (final old in oldGroup) {
        oldByIndex[old.stageIndex ?? 0] = old;
      }
    }

    final result = <PriceAlert>[];

    for (var i = 0; i < _stages.length; i++) {
      final draft = _stages[i];

      final old = oldByIndex[i];

      final isFirst = i == 0;

      final isActive = old != null ? old.isActive : isFirst;

      final alert = PriceAlert(
        id: old?.id ?? '${DateTime.now().microsecondsSinceEpoch}_$i',
        symbol: symbol,
        title: draft.title.trim().isEmpty ? groupTitle : draft.title.trim(),
        note: draft.note.trim(),
        type: PriceAlertType.multiStage,
        targetPrice: draft.target,
        lowerPrice: null,
        upperPrice: null,
        triggerOnRise: draft.triggerOnRise,
        repeatMode: PriceAlertRepeatMode.once,
        repeatIntervalMinutes: null,
        isActive: isActive,
        isTriggered: old?.isTriggered ?? false,
        soundPath: draft.soundPath,
        tradeId: old?.tradeId,
        tradePriceType: old?.tradePriceType,
        multiStageGroupId: groupId,
        stageIndex: i,
        createdAt: old?.createdAt ?? now,
        lastTriggeredAt: old?.lastTriggeredAt,
        triggeredAt: old?.triggeredAt,
      );

      result.add(
        alert,
      );
    }

    Navigator.pop(
      context,
      result,
    );
  }

  void _showError(
    String message,
  ) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AlertDialog(
      title: Text(
        _editing ? 'ویرایش هشدار مرحله‌ای' : 'هشدار مرحله‌ای جدید',
      ),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _symbolController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'نماد',
                  hintText: 'GOLDUSDT',
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              TextField(
                controller: _groupTitleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان گروه',
                  hintText: 'اهداف صعودی طلا',
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'مراحل',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addStage,
                    icon: const Icon(
                      Icons.add,
                    ),
                    label: const Text(
                      'مرحله',
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 6,
              ),
              ...List.generate(
                _stages.length,
                (index) {
                  return _buildStage(
                    index,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
          ),
          child: const Text(
            'انصراف',
          ),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            _editing ? 'ذخیره تغییرات' : 'ایجاد مراحل',
          ),
        ),
      ],
    );
  }

  Widget _buildStage(
    int index,
  ) {
    final stage = _stages[index];

    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          10,
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(
                    '${index + 1}',
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Text(
                    'مرحله ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_stages.length > 1)
                  IconButton(
                    tooltip: 'حذف مرحله',
                    onPressed: () => _removeStage(
                      index,
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            TextField(
              controller: stage.targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'قیمت مرحله',
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            TextField(
              controller: stage.titleController,
              decoration: const InputDecoration(
                labelText: 'عنوان مرحله',
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            TextField(
              controller: stage.noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'توضیح مرحله',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'جهت صعودی',
              ),
              subtitle: Text(
                stage.triggerOnRise
                    ? 'قیمت باید به سمت بالا به این مرحله برسد.'
                    : 'قیمت باید به سمت پایین به این مرحله برسد.',
              ),
              value: stage.triggerOnRise,
              onChanged: (value) {
                setState(() {
                  stage.triggerOnRise = value;
                });
              },
            ),
            const SizedBox(
              height: 4,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickStageSound(
                      stage,
                    ),
                    icon: const Icon(
                      Icons.audio_file,
                    ),
                    label: Text(
                      stage.soundPath == null || stage.soundPath!.trim().isEmpty
                          ? 'صدای مرحله'
                          : 'تغییر صدا',
                    ),
                  ),
                ),
                if (stage.soundPath != null &&
                    stage.soundPath!.trim().isNotEmpty)
                  IconButton(
                    tooltip: 'حذف صدا',
                    onPressed: () {
                      setState(() {
                        stage.soundPath = null;
                      });
                    },
                    icon: const Icon(
                      Icons.clear,
                    ),
                  ),
              ],
            ),
            if (stage.soundPath != null && stage.soundPath!.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  stage.soundPath!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStageSound(
    _StageDraft stage,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final path = result.files.single.path;

      if (path == null || path.trim().isEmpty) {
        return;
      }

      setState(() {
        stage.soundPath = path;
      });
    } catch (e) {
      if (!mounted) return;

      _showError(
        'انتخاب صدا ناموفق بود: $e',
      );
    }
  }
}

// ============================================================================
// STAGE DRAFT
// ============================================================================

class _StageDraft {
  late final TextEditingController targetController;

  late final TextEditingController titleController;

  late final TextEditingController noteController;

  bool triggerOnRise = true;

  String? soundPath;

  _StageDraft({
    double? target,
    String title = '',
    String note = '',
    bool triggerOnRise = true,
    String? soundPath,
  }) {
    targetController = TextEditingController(
      text: target?.toString() ?? '',
    );

    titleController = TextEditingController(
      text: title,
    );

    noteController = TextEditingController(
      text: note,
    );

    this.triggerOnRise = triggerOnRise;

    this.soundPath = soundPath;
  }

  factory _StageDraft.fromAlert(
    PriceAlert alert,
  ) {
    return _StageDraft(
      target: alert.targetPrice,
      title: alert.title,
      note: alert.note,
      triggerOnRise: alert.triggerOnRise,
      soundPath: alert.soundPath,
    );
  }

  double? get target {
    final value = numbers
        .normalizeNumberInput(targetController.text)
        .trim()
        .replaceAll(',', '');

    if (value.isEmpty) {
      return null;
    }

    return double.tryParse(
      value,
    );
  }

  String get title => titleController.text;

  String get note => noteController.text;

  void dispose() {
    targetController.dispose();

    titleController.dispose();

    noteController.dispose();
  }
}
