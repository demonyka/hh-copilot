import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Информация о доступном обновлении.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.pageUrl,
    required this.notes,
    this.assetUrl,
  });

  /// Версия из релиза (например, «v1.1.0»).
  final String version;

  /// Текущая версия приложения.
  final String currentVersion;

  /// Ссылка на страницу релиза.
  final String pageUrl;

  /// Описание релиза (changelog).
  final String notes;

  /// Прямая ссылка на артефакт под текущую ОС (если найдена).
  final String? assetUrl;

  /// Что открывать по кнопке «Обновить».
  String get downloadUrl => assetUrl ?? pageUrl;
}

/// Проверка обновлений через GitHub Releases.
class UpdateService {
  const UpdateService();

  static const String repo = 'demonyka/hh-copilot';

  Future<UpdateInfo?> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version; // напр. «1.0.0»

    final resp = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null; // 404 — релизов ещё нет

    final data = jsonDecode(resp.body);
    if (data is! Map) return null;
    if (data['draft'] == true || data['prerelease'] == true) return null;

    final tag = (data['tag_name'] ?? '').toString();
    if (tag.isEmpty) return null;
    if (!_isNewer(tag, current)) return null;

    String? asset;
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] ?? '').toString().toLowerCase();
        final url = a['browser_download_url']?.toString();
        if (url == null) continue;
        final isMac = Platform.isMacOS &&
            (name.endsWith('.dmg') ||
                name.endsWith('.zip') ||
                name.contains('macos') ||
                name.contains('mac'));
        final isWin = Platform.isWindows &&
            (name.endsWith('.exe') ||
                name.endsWith('.msix') ||
                name.endsWith('.zip') ||
                name.contains('win'));
        if (isMac || isWin) {
          asset = url;
          break;
        }
      }
    }

    return UpdateInfo(
      version: tag,
      currentVersion: current,
      pageUrl: (data['html_url'] ?? 'https://github.com/$repo/releases')
          .toString(),
      notes: (data['body'] ?? '').toString(),
      assetUrl: asset,
    );
  }

  /// true, если [tag] новее [current]. Понимает форматы вида «v1.2.3» / «1.2».
  static bool _isNewer(String tag, String current) {
    final a = _parse(tag);
    final b = _parse(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parse(String v) {
    var s = v.trim().toLowerCase();
    if (s.startsWith('v')) s = s.substring(1);
    final dash = s.indexOf('-'); // отбрасываем pre-release суффикс
    if (dash >= 0) s = s.substring(0, dash);
    final plus = s.indexOf('+'); // и build-метку
    if (plus >= 0) s = s.substring(0, plus);
    return s
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}
