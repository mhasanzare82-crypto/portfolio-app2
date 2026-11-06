import 'dart:io';

import 'package:docx_dart/docx_dart.dart' as docx;
import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/trade.dart';

class TradeExportService {
  // =========================================================
  // خروجی Excel
  // =========================================================

  static Future<String> exportToExcel(
    Trade trade,
  ) async {
    final excel = Excel.createExcel();

    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.delete(defaultSheet);
    }

    final sheet = excel['معامله'];

    final rows = _buildRows(trade);

    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];

      for (int columnIndex = 0; columnIndex < row.length; columnIndex++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: columnIndex,
            rowIndex: rowIndex,
          ),
        );

        final value = row[columnIndex];

        if (value is double) {
          cell.value = DoubleCellValue(value);
        } else if (value is int) {
          cell.value = IntCellValue(value);
        } else {
          cell.value = TextCellValue(
            value?.toString() ?? '',
          );
        }
      }
    }

    final bytes = excel.save();

    if (bytes == null) {
      throw Exception(
        'ساخت فایل Excel با خطا مواجه شد.',
      );
    }

    final directory = await getApplicationDocumentsDirectory();

    final fileName = 'trade_${_safeFileName(trade.tradeId)}.xlsx';

    final filePath = path.join(
      directory.path,
      fileName,
    );

    final file = File(filePath);

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return filePath;
  }

  // =========================================================
  // خروجی Word
  // =========================================================

  static Future<String> exportToWord(
    Trade trade,
  ) async {
    final document = docx.loadDocxDocument();

    document.addHeading(
      text: 'گزارش معامله',
      level: 1,
    );

    document.addParagraph(
      text: 'شناسه معامله: ${trade.tradeId}',
    );

    final table = document.addTable(
      1,
      2,
      style: 'Table Grid',
    );

    table.cell(0, 0).text = 'مورد';
    table.cell(0, 1).text = 'مقدار';

    final rows = _buildRows(trade);

    for (final row in rows) {
      if (row.length < 2) {
        continue;
      }

      final tableRow = table.addRow();

      tableRow.cells[0].text = row[0]?.toString() ?? '';

      tableRow.cells[1].text = row[1]?.toString() ?? '';
    }

    document.addParagraph(
      text: '',
    );

    document.addHeading(
      text: 'تصاویر معامله',
      level: 2,
    );

    if (trade.imagePaths.isEmpty) {
      document.addParagraph(
        text: 'تصویری برای این معامله ثبت نشده است.',
      );
    } else {
      document.addParagraph(
        text: 'تعداد تصاویر ثبت‌شده: ${trade.imagePaths.length}',
      );

      for (int i = 0; i < trade.imagePaths.length; i++) {
        document.addParagraph(
          text: '${i + 1}. ${trade.imagePaths[i]}',
        );
      }
    }

    final directory = await getApplicationDocumentsDirectory();

    final fileName = 'trade_${_safeFileName(trade.tradeId)}.docx';

    final filePath = path.join(
      directory.path,
      fileName,
    );

    document.save(filePath);

    return filePath;
  }

  // =========================================================
  // اطلاعات معامله
  // =========================================================

  static List<List<dynamic>> _buildRows(
    Trade trade,
  ) {
    return [
      [
        'شناسه معامله',
        trade.tradeId,
      ],
      [
        'دارایی',
        trade.assetSymbol,
      ],
      [
        'جهت معامله',
        trade.tradeDirection == TradeDirection.long ? 'لانگ' : 'شورت',
      ],
      [
        'نوع معامله',
        trade.tradeType == TradeType.scalp ? 'اسکالپ' : 'روزانه',
      ],
      [
        'وضعیت',
        trade.tradeStatus == TradeStatus.open ? 'باز' : 'بسته',
      ],
      [
        'حالت مارجین',
        trade.marginMode == 'cross' ? 'کراس' : 'ایزوله',
      ],
      [
        'تایم‌فریم',
        trade.tradeTimeframe,
      ],

      // -------------------------------------------------------
      // سرمایه و حجم
      // -------------------------------------------------------

      [
        'مقدار مارجین',
        trade.marginAmount,
      ],
      [
        'اهرم',
        trade.leverageValue,
      ],
      [
        'حجم معامله',
        trade.volumeAmount,
      ],
      [
        'کارمزد به ازای هر 100',
        trade.feePerHundred,
      ],
      [
        'کارمزد معامله',
        trade.tradeFee,
      ],

      // -------------------------------------------------------
      // قیمت‌ها
      // -------------------------------------------------------

      [
        'قیمت ورود',
        trade.entryPrice,
      ],
      [
        'قیمت خروج',
        trade.exitPrice,
      ],
      [
        'قیمت حد ضرر',
        trade.stopPrice,
      ],
      [
        'قیمت هدف',
        trade.targetPrice,
      ],

      // -------------------------------------------------------
      // زمان
      // -------------------------------------------------------

      [
        'زمان ورود',
        _formatDateTime(trade.entryTime),
      ],
      [
        'زمان خروج',
        trade.exitTime == null ? '-' : _formatDateTime(trade.exitTime!),
      ],
      [
        'مدت معامله',
        _formatDuration(
          trade.durationSeconds,
        ),
      ],

      // -------------------------------------------------------
      // ریسک و بازده
      // -------------------------------------------------------

      [
        'فاصله ریسک',
        trade.riskDistance,
      ],
      [
        'فاصله بازده',
        trade.rewardDistance,
      ],
      [
        'ارزش ریسک',
        trade.riskValue,
      ],
      [
        'ارزش بازده',
        trade.rewardValue,
      ],
      [
        'نسبت ریسک به بازده',
        trade.tradeRiskReward,
      ],

      // -------------------------------------------------------
      // نتیجه نهایی
      // -------------------------------------------------------

      [
        'سود و زیان نهایی',
        trade.finalPnl,
      ],
      [
        'ROI نهایی درصدی',
        trade.finalRoiPercent,
      ],
      [
        'ROI نهایی دلاری',
        trade.finalRoiDollar,
      ],
      [
        'R:R نهایی',
        trade.finalRiskReward,
      ],

      // -------------------------------------------------------
      // Drawdown
      // -------------------------------------------------------

      [
        'حداکثر Drawdown قیمت درصدی',
        trade.maxDrawdownPricePercent,
      ],
      [
        'حداکثر Drawdown دلاری',
        trade.maxDrawdownDollar,
      ],
      [
        'حداکثر Drawdown مارجین درصدی',
        trade.maxDrawdownMarginPercent,
      ],

      // -------------------------------------------------------
      // اطلاعات ورود
      // -------------------------------------------------------

      [
        'ستاپ ورود',
        trade.entrySetup,
      ],
      [
        'دلیل ورود',
        trade.entryReason,
      ],
      [
        'انگیزه ورود',
        trade.entryMotivation,
      ],
      [
        'سناریوی مورد انتظار',
        trade.expectedScenario,
      ],

      // -------------------------------------------------------
      // تصاویر
      // -------------------------------------------------------

      [
        'تعداد تصاویر',
        trade.imagePaths.length,
      ],
    ];
  }

  // =========================================================
  // فرمت تاریخ
  // =========================================================

  static String _formatDateTime(
    DateTime dateTime,
  ) {
    String twoDigits(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${dateTime.year}/'
        '${twoDigits(dateTime.month)}/'
        '${twoDigits(dateTime.day)} '
        '${twoDigits(dateTime.hour)}:'
        '${twoDigits(dateTime.minute)}:'
        '${twoDigits(dateTime.second)}';
  }

  // =========================================================
  // فرمت مدت معامله
  // =========================================================

  static String _formatDuration(
    int seconds,
  ) {
    if (seconds <= 0) {
      return '0 ثانیه';
    }

    final duration = Duration(
      seconds: seconds,
    );

    final days = duration.inDays;

    final hours = duration.inHours.remainder(24);

    final minutes = duration.inMinutes.remainder(60);

    final secs = duration.inSeconds.remainder(60);

    final parts = <String>[];

    if (days > 0) {
      parts.add('$days روز');
    }

    if (hours > 0) {
      parts.add('$hours ساعت');
    }

    if (minutes > 0) {
      parts.add('$minutes دقیقه');
    }

    if (secs > 0) {
      parts.add('$secs ثانیه');
    }

    return parts.join(' و ');
  }

  // =========================================================
  // نام فایل امن
  // =========================================================

  static String _safeFileName(
    String value,
  ) {
    final cleaned = value.replaceAll(
      RegExp(r'[\\/:*?"<>| ]'),
      '_',
    );

    if (cleaned.isEmpty) {
      return 'unknown';
    }

    return cleaned;
  }
}
