import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/hh_profile.dart';
import '../models/resume_analytics.dart';
import '../services/hh_analytics_parser.dart';
import '../services/hh_profile_parser.dart';

enum AppStatus {
  /// Первичная загрузка: проверяем, есть ли живая hh.ru-сессия.
  initializing,

  /// Нужен вход: показываем встроенный браузер с формой hh.ru.
  needLogin,

  /// Непрозрачный экран поверх браузера с подписью [AppState.busyMessage].
  /// Используется, пока идёт вход/выход, чтобы страница hh.ru не мелькала.
  busy,

  /// Сессия подтверждена, профиль и резюме загружены.
  authenticated,

  /// Непредвиденная ошибка.
  error,
}

/// Разделы левого сайдбара в авторизованной части приложения.
enum AppSection { analytics, chats, autoresponses, interviews, settings }

/// Ответ hh.ru на запрос через встроенный браузер.
class HhResponse {
  const HhResponse(this.status, this.body);
  final int status;
  final String body;
  bool get ok => status == 200;
}

/// Централизованное состояние приложения. Владеет ссылкой на контроллер
/// встроенного браузера hh.ru и превращает его в источник данных о профиле.
class AppState extends ChangeNotifier {
  static const String baseUrl = 'https://hh.ru';
  static const String resumesUrl = 'https://hh.ru/applicant/resumes';
  static const String loginUrl =
      'https://hh.ru/account/login?backurl=%2Fapplicant%2Fresumes&role=applicant';

  AppStatus _status = AppStatus.initializing;
  AppStatus get status => _status;

  String _busyMessage = 'Подключение к hh.ru…';
  String get busyMessage => _busyMessage;

  HhAccount? _account;
  HhAccount? get account => _account;

  List<HhResume> _resumes = const [];
  List<HhResume> get resumes => _resumes;

  // --- Навигация внутри авторизованной части ---
  AppSection _section = AppSection.analytics;
  AppSection get section => _section;

  /// Выбранное резюме, для которого открыта аналитика (null — показываем список).
  HhResume? _selectedResume;
  HhResume? get selectedResume => _selectedResume;

  void selectSection(AppSection section) {
    if (_section == section) return;
    _section = section;
    notifyListeners();
  }

  /// Выбрать резюме (из дропдауна в шапке). От него зависят аналитика и чаты.
  void selectResume(HhResume resume) {
    if (_selectedResume?.hash == resume.hash) return;
    _selectedResume = resume;
    notifyListeners();
    loadAnalytics(resume);
  }

  // Перезагрузка встроенного чата (кнопка «обновить» в разделе «Чаты»).
  int _chatsReloadCounter = 0;
  int get chatsReloadCounter => _chatsReloadCounter;
  void reloadChats() {
    _chatsReloadCounter++;
    notifyListeners();
  }

  // --- Аналитика по резюме ---
  final Map<String, ResumeAnalytics> _analytics = {};
  bool _analyticsLoading = false;
  String? _analyticsError;

  ResumeAnalytics? analyticsFor(String hash) => _analytics[hash];
  bool get analyticsLoading => _analyticsLoading;
  String? get analyticsError => _analyticsError;

  /// Максимум страниц откликов (по 20 на странице), чтобы ограничить нагрузку.
  static const int _maxNegotiationPages = 20;

  Future<void> loadAnalytics(HhResume resume, {bool force = false}) async {
    if (_analyticsLoading) return;
    if (!force && _analytics.containsKey(resume.hash)) return;
    _analyticsLoading = true;
    _analyticsError = null;
    notifyListeners();

    try {
      // 1. Статистика резюме и общее число откликов — со страницы резюме.
      ResumeStatistics? stats;
      int total = 0;
      final resumesHtml = await _fetchHtml(resumesUrl);
      if (resumesHtml != null) {
        stats =
            HhAnalyticsParser.parseResumeStatistics(resumesHtml, resume.id);
        total = HhAnalyticsParser.parseTotalResponses(resumesHtml);
      }

      // 2. Отклики постранично. Первую страницу берём отдельно (из неё узнаём
      //    число страниц), остальные — параллельными пачками, чтобы не ждать.
      final negotiations = <Negotiation>[];
      final now = DateTime.now();
      String pageUrl(int p) =>
          '$baseUrl/applicant/negotiations?resume=${resume.hash}&page=$p';

      int pages = 0;
      bool capped = false;

      final firstHtml = await _fetchHtml(pageUrl(0));
      if (firstHtml != null) {
        negotiations.addAll(HhAnalyticsParser.parseNegotiationsPage(firstHtml));
        pages = 1;
        final totalPages =
            HhAnalyticsParser.parseNegotiationPageCount(firstHtml);
        final toFetch = totalPages.clamp(1, _maxNegotiationPages);
        capped = totalPages > _maxNegotiationPages;
        _log('analytics: $totalPages pages total, fetching $toFetch');

        const batchSize = 6;
        for (int start = 1; start < toFetch; start += batchSize) {
          final end = (start + batchSize).clamp(1, toFetch);
          final htmls = await Future.wait([
            for (int p = start; p < end; p++) _fetchHtml(pageUrl(p)),
          ]);
          for (final html in htmls) {
            if (html == null) continue;
            negotiations
                .addAll(HhAnalyticsParser.parseNegotiationsPage(html));
            pages++;
          }
          _log('analytics: fetched ${end - 1}/$toFetch pages, '
              '${negotiations.length} responses');
        }
      }

      // Если выгрузили все страницы — точное число откликов по резюме это их
      // количество. Если обрезали — берём account-wide счётчик как оценку.
      final totalResponses =
          (capped && total > negotiations.length) ? total : negotiations.length;

      _analytics[resume.hash] = ResumeAnalytics(
        resumeHash: resume.hash,
        stats: stats,
        negotiations: negotiations,
        totalResponsesAllTime: totalResponses,
        fetchedPages: pages,
        capped: capped,
        now: now,
      );
    } catch (e) {
      _analyticsError = 'Не удалось загрузить аналитику';
      _log('analytics error: $e');
    } finally {
      _analyticsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAnalytics() async {
    final resume = _selectedResume;
    if (resume != null) await loadAnalytics(resume, force: true);
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  InAppWebViewController? _controller;
  bool _redirectedToLogin = false;
  bool _checking = false;

  /// Пока true — браузер спрятан (busy), и мы ждём, когда форма входа hh.ru
  /// полностью загрузится, чтобы показать именно её, а не старую страницу.
  bool _revealLoginOnLoad = false;

  void attachController(InAppWebViewController controller) {
    _controller = controller;
    _log('webview controller attached');
  }

  /// Вызывается из веб-вью в момент НАЧАЛА навигации — самая ранняя точка,
  /// чтобы спрятать браузер, как только пользователь уходит с формы входа.
  void onNavigationStart([String? url]) => _coverIfLeftLogin(url);

  /// Вызывается из веб-вью после каждой завершённой навигации.
  Future<void> onPageEvent([String? url]) async {
    _log('page event: ${url ?? '(no url)'}');
    final uri = url == null ? null : Uri.tryParse(url);

    // Режим ожидания формы входа (после выхода или первого редиректа).
    // Здесь браузер НИКОГДА не раскрываем на чужую страницу — только на саму
    // форму hh.ru, иначе на секунду показалась бы страница профиля.
    if (_revealLoginOnLoad) {
      final isAuthForm =
          uri != null && uri.host.endsWith('hh.ru') && _isAuthPath(uri.path);
      if (isAuthForm) {
        _revealLoginOnLoad = false;
        _log('login form ready -> needLogin');
        _setStatus(AppStatus.needLogin);
        return;
      }
      // Не форма входа. Возможно, сессия ещё жива (cookies не удалились) —
      // тогда уходим в список; иначе продолжаем ждать форму, оставаясь busy.
      final profile = await _loadProfileOnce();
      if (profile != null && profile.isAuthenticated) {
        _revealLoginOnLoad = false;
        _applyProfile(profile);
        _onAuthenticated();
      }
      return;
    }

    // Подстраховка на случай серверных редиректов, когда onLoadStart для
    // конечного URL не сработал: прячем браузер до запроса профиля.
    _coverIfLeftLogin(url);
    await _recheckSession();
  }

  /// Если во время входа мы оказались на обычной странице hh.ru (не форме
  /// входа) — значит, вход прошёл; сразу закрываем браузер экраном «Входим…»,
  /// чтобы страница hh.ru не мелькнула перед списком резюме.
  void _coverIfLeftLogin(String? url) {
    if (_status != AppStatus.needLogin || url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // Внешние провайдеры входа (VK, Госуслуги и т.п.) — браузер нужен видимым.
    if (!uri.host.endsWith('hh.ru')) return;
    // Всё ещё внутри формы входа hh.ru — браузер нужен.
    if (_isAuthPath(uri.path)) return;
    _log('left login flow -> busy ($url)');
    _setBusy('Входим в hh.ru…');
  }

  /// Проверить, появилась ли авторизованная hh.ru-сессия.
  Future<void> _recheckSession() async {
    if (_checking || _status == AppStatus.authenticated) return;
    _checking = true;
    try {
      final profile = await _loadProfileOnce();
      if (profile != null && profile.isAuthenticated) {
        _log('authenticated as ${profile.account.fullName} '
            '(#${profile.account.userId}), resumes: ${profile.resumes.length}');
        _applyProfile(profile);
        _onAuthenticated();
        return;
      }
      _log('guest page (no hh.ru session yet)');
      if (_status == AppStatus.initializing && !_redirectedToLogin) {
        // Первая проверка — уводим на форму входа.
        await _goToLoginForm('Открываем вход в hh.ru…');
      } else if (_status == AppStatus.busy) {
        // Ложная тревога: ушли со страницы входа, но сессии нет — вернём браузер.
        _setStatus(AppStatus.needLogin);
      }
    } finally {
      _checking = false;
    }
  }

  static bool _isAuthPath(String path) =>
      path.startsWith('/account') ||
      path.startsWith('/auth') ||
      path.startsWith('/oauth') ||
      path.contains('/connect/');

  /// Обновить список резюме, оставаясь авторизованным.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final profile = await _loadProfileOnce();
      if (profile != null && profile.isAuthenticated) {
        _applyProfile(profile);
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Выйти из hh.ru-сессии: чистим cookies и возвращаемся к форме входа.
  /// Порядок важен: сперва прячем экран и включаем «ожидание формы входа»,
  /// затем чистим cookies и только потом уводим браузер на форму — так старая
  /// страница профиля hh.ru не показывается ни на мгновение.
  Future<void> logout() async {
    _redirectedToLogin = true;
    // Чистим cookies, пока список резюме ещё перекрывает браузер, — так
    // страница профиля hh.ru не может показаться, и нет гонки повторного входа.
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    _account = null;
    _resumes = const [];
    _revealLoginOnLoad = true; // до загрузки формы браузер не раскрываем
    _setBusy('Выходим из hh.ru…');
    await _navigate(loginUrl);
  }

  /// Повторить инициализацию после ошибки.
  Future<void> retry() async {
    _errorMessage = null;
    _redirectedToLogin = false;
    _revealLoginOnLoad = false;
    _setStatus(AppStatus.initializing);
    await _navigate(resumesUrl);
  }

  /// Ошибка первичной загрузки страницы веб-вью.
  void reportLoadError(String message) {
    if (_status == AppStatus.authenticated) return;
    if (_status == AppStatus.initializing) {
      // Не смогли даже открыть hh.ru — ведём на форму входа вручную.
      _goToLoginForm('Открываем вход в hh.ru…');
    }
  }

  /// Спрятать браузер и увести на форму входа; показать её, когда загрузится.
  Future<void> _goToLoginForm(String message) async {
    _redirectedToLogin = true;
    _revealLoginOnLoad = true;
    _setBusy(message);
    await _navigate(loginUrl);
  }

  Future<HhProfile?> _loadProfileOnce() async {
    final html = await _fetchHtml(resumesUrl);
    _log('fetched /applicant/resumes: ${html?.length ?? 0} bytes');
    if (html == null || html.isEmpty) return null;
    try {
      return HhProfileParser.parse(html);
    } catch (e) {
      _log('parse error: $e');
      return null;
    }
  }

  /// Загружает страницу через `fetch` внутри реального браузерного контекста —
  /// так запрос идёт с cookies пользователя и проходит анти-бот hh.ru.
  ///
  /// Сразу после `onLoadStop` контекст страницы иногда ещё не готов и `fetch`
  /// возвращает пусто — поэтому делаем несколько коротких повторов.
  Future<String?> _fetchHtml(String url) async {
    final controller = _controller;
    if (controller == null) return null;
    for (int attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      try {
        final result = await controller.callAsyncJavaScript(
          functionBody: '''
            const resp = await fetch(url, { credentials: 'include', redirect: 'follow', cache: 'no-store' });
            return await resp.text();
          ''',
          arguments: {'url': url},
        );
        if (result != null && result.error == null) {
          final value = result.value;
          final html = value is String ? value : value?.toString();
          if (html != null && html.isNotEmpty) return html;
        }
      } catch (_) {
        // повторим
      }
    }
    return null;
  }

  /// Контроллер веб-вью чатов (chatik.hh.ru) — для запросов к чат-API,
  /// которые кросс-доменны для hh.ru, но same-origin для chatik.
  InAppWebViewController? _chatController;
  void attachChatController(InAppWebViewController controller) {
    _chatController = controller;
  }

  /// Запрос к hh.ru через основной браузерный контекст (cookies + обход
  /// анти-бота). Используется движком автооткликов.
  Future<HhResponse?> hhRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) =>
      _requestVia(_controller,
          method: method, url: url, headers: headers, body: body);

  /// Запрос к чат-API chatik.hh.ru через веб-вью раздела «Чаты» (same-origin).
  Future<HhResponse?> chatikRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) =>
      _requestVia(_chatController,
          method: method, url: url, headers: headers, body: body);

  Future<HhResponse?> _requestVia(
    InAppWebViewController? controller, {
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) async {
    if (controller == null) return null;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          const opts = { method: method, credentials: 'include', redirect: 'follow', cache: 'no-store', headers: headers || {} };
          if (body !== null && body !== undefined) opts.body = body;
          const resp = await fetch(url, opts);
          const text = await resp.text();
          return { status: resp.status, body: text };
        ''',
        arguments: {
          'method': method,
          'url': url,
          'headers': headers ?? <String, String>{},
          'body': body,
        },
      );
      if (result == null || result.error != null) return null;
      final value = result.value;
      if (value is Map) {
        return HhResponse(
          ((value['status'] as num?)?.toInt()) ?? 0,
          value['body']?.toString() ?? '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// XSRF-токен hh.ru (cookie `_xsrf`) — нужен для POST-действий.
  Future<String> xsrfToken() async {
    final controller = _controller;
    if (controller == null) return '';
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody:
            r"return (document.cookie.match(/(?:^|; )_xsrf=([^;]+)/) || [])[1] || '';",
      );
      final value = result?.value;
      return value is String ? value : (value?.toString() ?? '');
    } catch (_) {
      return '';
    }
  }

  /// Поднять резюме в поисковой выдаче hh.ru (порт `TouchResume`).
  /// multipart-форма с полями resume + undirectable. hh даёт поднятие раз в ~4ч.
  Future<bool> touchResume(String resumeHash) async {
    if (resumeHash.isEmpty) return false;
    final xsrf = await xsrfToken();
    if (xsrf.isEmpty) return false;
    final boundary =
        '----hhcopilot${DateTime.now().microsecondsSinceEpoch}';
    final body = '--$boundary\r\n'
        'Content-Disposition: form-data; name="resume"\r\n\r\n$resumeHash\r\n'
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="undirectable"\r\n\r\ntrue\r\n'
        '--$boundary--\r\n';
    final resp = await hhRequest(
      method: 'POST',
      url: '$baseUrl/applicant/resumes/touch',
      headers: {
        'Content-Type': 'multipart/form-data; boundary=$boundary',
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Hhtmfrom': 'negotiation_list',
        'X-Hhtmsource': 'resume_list',
        'X-Xsrftoken': xsrf,
        'Referer': '$baseUrl/applicant/resumes',
      },
      body: body,
    );
    return resp != null && resp.ok;
  }

  Future<void> _navigate(String url) async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _applyProfile(HhProfile profile) {
    _account = profile.account;
    _resumes = profile.resumes;
    // Выбираем резюме по умолчанию (последнее/первое), сохраняя текущее,
    // если оно всё ещё есть в списке.
    final current = _selectedResume;
    if (current == null || !_resumes.any((r) => r.hash == current.hash)) {
      _selectedResume = _defaultResume(profile);
    }
  }

  HhResume? _defaultResume(HhProfile profile) {
    if (profile.resumes.isEmpty) return null;
    for (final r in profile.resumes) {
      if (r.hash == profile.latestResumeHash) return r;
    }
    return profile.resumes.first;
  }

  void _onAuthenticated() {
    _setStatus(AppStatus.authenticated);
    final resume = _selectedResume;
    if (resume != null) loadAnalytics(resume);
  }

  void _setBusy(String message) {
    final wasBusy = _status == AppStatus.busy;
    _busyMessage = message;
    if (wasBusy) {
      notifyListeners(); // статус тот же, обновилась только подпись
    } else {
      _setStatus(AppStatus.busy);
    }
  }

  void _setStatus(AppStatus status) {
    if (_status == status) return;
    _log('status: ${_status.name} -> ${status.name}');
    _status = status;
    notifyListeners();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[hh-copilot] $message');
  }
}
