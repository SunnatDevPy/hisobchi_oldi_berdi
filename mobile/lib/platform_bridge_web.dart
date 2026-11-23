import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'platform_bridge_types.dart';

@JS('HisobchiWebBridge.init')
external void _jsInit();

@JS('HisobchiWebBridge.getInitData')
external JSString _jsGetInitData();

@JS('HisobchiWebBridge.getColorScheme')
external JSString _jsGetColorScheme();

@JS('HisobchiWebBridge.syncChromeColors')
external void _jsSyncChromeColors(JSBoolean isDark);

@JS('HisobchiWebBridge.tryTelegramDownload')
external JSBoolean _jsTryTelegramDownload(JSString url, JSString filename);

@JS('HisobchiWebBridge.downloadBlob')
external void _jsDownloadBlob(JSUint8Array bytes, JSString filename);

@JS('HisobchiWebBridge.pickFile')
external JSPromise<JSObject?> _jsPickFile(JSString accept);

@JS('HisobchiWebBridge.openTelegramLink')
external JSBoolean _jsOpenTelegramLink(JSString url);

extension type _JsPickedFile(JSObject _) implements JSObject {
  external JSString get name;
  external JSUint8Array get bytes;
}

String resolveDefaultApiBaseUrl() {
  try {
    final origin = Uri.base.origin;
    if (origin.startsWith('https://') || origin.startsWith('http://')) {
      return origin;
    }
  } catch (_) {}
  return 'https://hisobchi.okaposai.uz';
}

void initTelegramWebApp() {
  try {
    _jsInit();
  } catch (_) {}
}

String? getTelegramWebAppInitData() {
  try {
    final val = _jsGetInitData().toDart.trim();
    return val.isEmpty ? null : val;
  } catch (_) {
    return null;
  }
}

String? getTelegramColorScheme() {
  try {
    final val = _jsGetColorScheme().toDart.trim();
    return val.isEmpty ? null : val;
  } catch (_) {
    return null;
  }
}

void syncTelegramChromeColors({required bool isDark}) {
  try {
    _jsSyncChromeColors(isDark.toJS);
  } catch (_) {}
}

Future<void> saveAndShareExcel({
  required Future<Uint8List> Function() fetchBytes,
  required String filename,
  required String authenticatedDownloadUrl,
}) async {
  try {
    if (_jsTryTelegramDownload(
      authenticatedDownloadUrl.toJS,
      filename.toJS,
    ).toDart) {
      return;
    }
  } catch (_) {}
  final bytes = await fetchBytes();
  _jsDownloadBlob(bytes.toJS, filename.toJS);
}

Future<PickedBytesFile?> pickYesPosDocument() async {
  final raw = await _jsPickFile('.xlsx,.xls,.csv'.toJS).toDart;
  if (raw == null) return null;
  final picked = _JsPickedFile(raw);
  final name = picked.name.toDart.trim();
  return PickedBytesFile(
    bytes: picked.bytes.toDart,
    filename: name.isNotEmpty ? name : 'yespos_report.xlsx',
  );
}

Future<bool> openExternalTelegramUrl(String url) async {
  try {
    return _jsOpenTelegramLink(url.toJS).toDart;
  } catch (_) {
    return false;
  }
}

Future<void> showInAppApkUpdateDialog({
  required BuildContext context,
  required Uri downloadUri,
  required String version,
  required int sizeBytes,
}) async {}
