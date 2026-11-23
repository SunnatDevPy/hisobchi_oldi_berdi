import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'platform_bridge_types.dart';
import 'theme.dart';

const MethodChannel _installerChannel =
    MethodChannel('uz.hisobchi.hisobchi_app/installer');

String resolveDefaultApiBaseUrl() => 'https://hisobchi.okaposai.uz';

void initTelegramWebApp() {}

String? getTelegramWebAppInitData() => null;

String? getTelegramColorScheme() => null;

void syncTelegramChromeColors({required bool isDark}) {}

Future<void> saveAndShareExcel({
  required Future<Uint8List> Function() fetchBytes,
  required String filename,
  required String authenticatedDownloadUrl,
}) async {
  final bytes = await fetchBytes();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Hisobchi Excel hisobot: $filename',
  );
}

Future<PickedBytesFile?> pickYesPosDocument() async {
  final picked = await _installerChannel.invokeMethod<dynamic>('pickDocument');
  if (picked == null || picked is! Map) {
    return null;
  }
  final path = (picked['path'] ?? '').toString();
  if (path.isEmpty) {
    return null;
  }
  final bytes = await File(path).readAsBytes();
  final rawName = (picked['name'] ?? '').toString().trim();
  final filename = rawName.isNotEmpty
      ? rawName
      : path.split(Platform.pathSeparator).last;
  return PickedBytesFile(bytes: bytes, filename: filename);
}

Future<bool> openExternalTelegramUrl(String url) async {
  try {
    final res = await _installerChannel.invokeMethod<bool>(
      'openExternalUrl',
      {'url': url},
    );
    return res == true;
  } catch (_) {
    return false;
  }
}

Future<void> showInAppApkUpdateDialog({
  required BuildContext context,
  required Uri downloadUri,
  required String version,
  required int sizeBytes,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InAppUpdateProgressDialog(
      downloadUri: downloadUri,
      version: version,
      sizeBytes: sizeBytes,
    ),
  );
}

class _InAppUpdateProgressDialog extends StatefulWidget {
  final Uri downloadUri;
  final String version;
  final int sizeBytes;

  const _InAppUpdateProgressDialog({
    required this.downloadUri,
    required this.version,
    required this.sizeBytes,
  });

  @override
  State<_InAppUpdateProgressDialog> createState() =>
      _InAppUpdateProgressDialogState();
}

class _InAppUpdateProgressDialogState
    extends State<_InAppUpdateProgressDialog> {
  int _receivedBytes = 0;
  int _totalBytes = 0;
  bool _downloading = true;
  File? _downloadedFile;
  String? _statusMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.sizeBytes;
    _startDownloadAndInstall();
  }

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _downloading = true;
      _error = null;
      _statusMessage = 'Yangi versiya yuklab olinmoqda...';
    });
    final client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final target = File('${dir.path}/Hisobchi_v${widget.version}.apk');
      if (await target.exists()) {
        await target.delete();
      }
      final req = http.Request('GET', widget.downloadUri);
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 180));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw ApiException(
          'APK yuklab olishda xatolik (HTTP ${streamed.statusCode})',
          statusCode: streamed.statusCode,
        );
      }
      final total =
          (streamed.contentLength != null && streamed.contentLength! > 0)
              ? streamed.contentLength!
              : widget.sizeBytes;
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in streamed.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted) {
            setState(() {
              _receivedBytes = received;
              if (total > 0) _totalBytes = total;
            });
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received < 100 * 1024) {
        throw const ApiException("Yuklangan APK fayl to'liq emas");
      }
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedFile = target;
        _statusMessage = "Yuklab olindi! O'rnatish oynasi ochilmoqda...";
      });
      await _triggerNativeInstall(target);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = e.toString();
        });
      }
    } finally {
      client.close();
    }
  }

  Future<void> _triggerNativeInstall(File file) async {
    try {
      final res = await _installerChannel.invokeMethod<String>(
        'installApk',
        {'path': file.path},
      );
      if (!mounted) return;
      if (res == 'PERMISSION_REQUESTED') {
        setState(() {
          _statusMessage =
              "⚙️ Telefon sozlamalarida «Hisobchi» ilovasiga o'rnatish ruxsatini yoqing — qaytishingiz bilan o'rnatish avtomatik boshlanadi.";
        });
      } else {
        setState(() {
          _statusMessage =
              "✅ Android o'rnatish oynasida «Yangilash (Update)» tugmasini bosing.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = "O'rnatish oynasini ochishda xatolik: $e");
      }
    }
  }

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final ratio = _totalBytes > 0
        ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0)
        : null;
    final pct = ratio != null ? (ratio * 100).round() : 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTokens.aiGradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.system_update_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hisobchi v${widget.version}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_downloading) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Yuklanmoqda: $pct%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppTokens.brand,
                    fontFeatures: AppTokens.tabularNums,
                  ),
                ),
                Text(
                  _totalBytes > 0
                      ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)} MB'
                      : '${_formatMb(_receivedBytes)} MB',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: textSecondaryOf(context),
                    fontFeatures: AppTokens.tabularNums,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: AppTokens.brand.withValues(alpha: 0.14),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTokens.brand),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusMessage ?? '',
              style: TextStyle(
                fontSize: 12.5,
                color: textSecondaryOf(context),
              ),
            ),
          ] else if (_error != null) ...[
            Text(
              '⚠️ $_error',
              style: const TextStyle(
                color: AppTokens.dangerRed,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ] else ...[
            Text(
              _statusMessage ?? '✅ Yuklab olindi!',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_downloading && _downloadedFile != null)
          FilledButton.icon(
            onPressed: () => _triggerNativeInstall(_downloadedFile!),
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: const Text("O'rnatish (Yangilash)"),
          ),
        if (!_downloading && _error != null)
          FilledButton.icon(
            onPressed: _startDownloadAndInstall,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Qayta urinish'),
          ),
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish'),
          ),
      ],
    );
  }
}
