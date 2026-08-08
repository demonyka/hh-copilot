import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../services/updater.dart';

/// Проверяет обновления при старте и по кнопке. Хранит результат для баннера.
class UpdateController extends ChangeNotifier {
  UpdateController() {
    _init();
  }

  final _service = const UpdateService();

  UpdateInfo? _info;
  bool _dismissed = false;

  /// Доступное обновление (или null, если нет / скрыто пользователем).
  UpdateInfo? get available => _dismissed ? null : _info;

  bool _checking = false;
  bool get checking => _checking;

  String _currentVersion = '';
  String get currentVersion => _currentVersion;

  /// Итог последней ручной проверки (для раздела «Настройки»).
  String? _lastCheckMessage;
  String? get lastCheckMessage => _lastCheckMessage;

  Future<void> _init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      notifyListeners();
    } catch (_) {}
    await check();
  }

  Future<void> check({bool manual = false}) async {
    if (_checking) return;
    _checking = true;
    if (manual) _lastCheckMessage = null;
    notifyListeners();
    try {
      final info = await _service.check();
      _info = info;
      if (info != null) _dismissed = false;
      _lastCheckMessage = info != null
          ? 'Доступна новая версия ${info.version}'
          : 'У вас последняя версия';
    } catch (e) {
      _lastCheckMessage = 'Не удалось проверить обновления';
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  // --- Установка обновления «на месте» ---
  final _updater = const Updater();

  bool _installing = false;
  bool get installing => _installing;

  double _installProgress = 0;
  double get installProgress => _installProgress;

  String _installStage = '';
  String get installStage => _installStage;

  String? _installError;
  String? get installError => _installError;

  bool get canInstall => _updater.supported && _info?.assetUrl != null;

  /// Скачать и установить обновление. На macOS приложение само перезапустится.
  /// Если авто-установка невозможна — открываем страницу релиза.
  Future<void> installUpdate() async {
    final info = _info;
    if (info == null || _installing) return;

    if (!canInstall) {
      await _openPage(info);
      return;
    }

    _installing = true;
    _installProgress = 0;
    _installStage = 'Подготовка…';
    _installError = null;
    notifyListeners();
    try {
      await _updater.apply(
        info,
        onProgress: (p) {
          _installProgress = p;
          notifyListeners();
        },
        onStage: (s) {
          _installStage = s;
          notifyListeners();
        },
      );
      // При успехе приложение завершится и перезапустится (сюда не вернёмся).
    } catch (e) {
      _installError = '$e';
      _installing = false;
      notifyListeners();
      await _openPage(info); // запасной путь — ручное скачивание
    }
  }

  Future<void> _openPage(UpdateInfo info) async {
    try {
      await launchUrl(Uri.parse(info.downloadUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
