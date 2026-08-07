import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/update_service.dart';

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
}
