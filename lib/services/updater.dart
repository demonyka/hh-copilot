import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'update_service.dart';

/// Ставит обновление «на месте»: скачивает архив релиза, безопасно заменяет
/// бандл приложения и перезапускает — без ручной переустановки.
///
/// Работает для незасендбоксенного приложения (мы раздаёмся вне App Store).
class Updater {
  const Updater();

  bool get supported => Platform.isMacOS;

  /// Выполняет обновление. На успехе macOS-приложение завершится и
  /// перезапустится само. Бросает исключение, если обновиться на месте нельзя
  /// (тогда вызывающий откроет страницу релиза).
  Future<void> apply(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Авто-установка поддержана только на macOS');
    }
    final assetUrl = info.assetUrl;
    if (assetUrl == null) {
      throw Exception('Нет прямой ссылки на артефакт релиза');
    }

    final appPath = _currentAppBundlePath();

    final tmp = await Directory.systemTemp.createTemp('hhcopilot_update');
    final zipPath = p.join(tmp.path, 'update.zip');
    final extractDir = p.join(tmp.path, 'extracted');
    await Directory(extractDir).create(recursive: true);

    onStage?.call('Скачивание…');
    await _download(assetUrl, zipPath, onProgress);

    onStage?.call('Распаковка…');
    final res = await Process.run(
        '/usr/bin/ditto', ['-x', '-k', zipPath, extractDir]);
    if (res.exitCode != 0) {
      throw Exception('Распаковка не удалась: ${res.stderr}');
    }
    final newApp = _findApp(extractDir);
    if (newApp == null) {
      throw Exception('В архиве не найден .app');
    }

    onStage?.call('Установка…');
    final script = await _writeSwapScript(tmp.path);
    await Process.start(
      '/bin/bash',
      [script, appPath, newApp],
      mode: ProcessStartMode.detached,
    );

    // Даём скрипту стартовать и выходим — он дождётся выхода, заменит и запустит.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  String _currentAppBundlePath() {
    final exe = Platform.resolvedExecutable;
    if (exe.contains('/AppTranslocation/')) {
      throw Exception(
          'Приложение запущено из карантина. Переместите его в «Программы» '
          '(или снимите карантин) и попробуйте снова.');
    }
    // .../hh_copilot.app/Contents/MacOS/hh_copilot
    final appDir = p.dirname(p.dirname(p.dirname(exe)));
    if (!appDir.endsWith('.app')) {
      throw Exception('Не удалось определить бандл приложения');
    }
    return appDir;
  }

  String? _findApp(String dir) {
    for (final e in Directory(dir).listSync()) {
      if (e is Directory && e.path.endsWith('.app')) return e.path;
    }
    return null;
  }

  Future<void> _download(
      String url, String dest, void Function(double)? onProgress) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..followRedirects = true;
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw Exception('Загрузка не удалась: HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? 0;
      final sink = File(dest).openWrite();
      var got = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<String> _writeSwapScript(String dir) async {
    final path = p.join(dir, 'apply_update.sh');
    // Пути передаются аргументами ($1/$2), чтобы не мучиться с экранированием.
    const script = r'''#!/bin/bash
APP="$1"
NEW="$2"
# Ждём завершения текущего приложения.
sleep 2
BAK="${APP}.old-$$"
rm -rf "$BAK"
mv "$APP" "$BAK" 2>/dev/null
if [ -e "$APP" ]; then
  # старый бандл не удалось убрать — просто запускаем как было
  open "$APP"
  exit 0
fi
if mv "$NEW" "$APP" 2>/dev/null; then
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null
  rm -rf "$BAK"
else
  # не удалось установить новый — откатываемся
  mv "$BAK" "$APP" 2>/dev/null
fi
open "$APP"
''';
    final file = File(path);
    await file.writeAsString(script);
    await Process.run('/bin/chmod', ['+x', path]);
    return path;
  }
}
