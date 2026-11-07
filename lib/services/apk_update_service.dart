import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks the public update manifest, downloads a newer APK and launches
/// Android's package installer. Android always controls final consent.
class ApkUpdateService {
  ApkUpdateService._();

  static final ApkUpdateService instance = ApkUpdateService._();

  static const String manifestUrl =
      'https://raw.githubusercontent.com/mhasanzare82-crypto/portfolio-app2/main/latest.json';

  bool _checkInProgress = false;

  Future<void> checkAndPrompt(BuildContext context) async {
    if (_checkInProgress) return;
    _checkInProgress = true;

    try {
      final response = await http
          .get(Uri.parse(manifestUrl), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return;

      final remoteCode = data['versionCode'];
      final remoteName = data['versionName'];
      final apkUrl = data['apkUrl'];

      if (remoteCode is! int ||
          remoteName is! String ||
          apkUrl is! String ||
          remoteCode <= 0 ||
          !apkUrl.startsWith('https://')) return;

      final current = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(current.buildNumber) ?? 0;
      if (remoteCode <= currentCode || !context.mounted) return;

      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('نسخه جدید در دسترس است'),
          content: Text(
            'نسخه ' + current.version + ' روی دستگاه نصب است. ' +
            'نسخه ' + remoteName + ' آماده دریافت است.\n\n' +
            'پس از دانلود، نصب‌کننده اندروید باز می‌شود. ' +
            'برای تکمیل به‌روزرسانی باید نصب را تأیید کنید.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('بعداً'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('دریافت و نصب'),
            ),
          ],
        ),
      );

      if (shouldUpdate == true && context.mounted) {
        await _downloadAndInstall(context, apkUrl, remoteName);
      }
    } catch (_) {
      // Update checks are best-effort and must never block app startup.
    } finally {
      _checkInProgress = false;
    }
  }

  Future<void> _downloadAndInstall(
    BuildContext context,
    String apkUrl,
    String versionName,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('در حال دریافت نسخه جدید...')),
          ],
        ),
      ),
    );

    try {
      final response = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.length < 1024) {
        throw const HttpException('دانلود فایل APK ناموفق بود.');
      }

      final directory = await getTemporaryDirectory();
      final apkFile = File(
        directory.path + '/lbank-gold-' + versionName + '-update.apk',
      );
      await apkFile.writeAsBytes(response.bodyBytes, flush: true);

      if (context.mounted) Navigator.of(context).pop();

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فایل دریافت شد، اما نصب‌کننده باز نشد: ' + result.message,
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('به‌روزرسانی انجام نشد: ' + error.toString())),
        );
      }
    }
  }
}