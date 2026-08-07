import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/autoresponder_config.dart';
import '../models/hh_profile.dart';
import '../services/ai_client.dart';
import '../services/autoresponder.dart';
import '../services/chat_responder.dart';
import '../services/hh_resume.dart';
import 'app_state.dart';

enum RunState { idle, running, stopping }

class AutoLogEntry {
  AutoLogEntry(this.message, this.error, this.time);
  final String message;
  final bool error;
  final DateTime time;
}

/// Владеет общими настройками и ДВУМЯ независимыми процессами:
/// откликами на вакансии и ответами в чатах. Их можно запускать и
/// останавливать по отдельности; они работают параллельно.
class AutoresponderController extends ChangeNotifier {
  AutoresponderController(this._appState) {
    _load();
  }

  static const _prefsKey = 'autoresponder_config_v1';

  final AppState _appState;

  AutoresponderConfig _config = const AutoresponderConfig();
  AutoresponderConfig get config => _config;

  /// Куда отдавать сообщения работодателей для детекта собеседований
  /// (устанавливает InterviewsController). Тем же проходом по чатам.
  void Function(EmployerMessage msg)? employerMessageSink;

  bool _loaded = false;
  bool get loaded => _loaded;

  // ---- общие настройки ----

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _config = AutoresponderConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_config.toJson()));
    } catch (_) {}
  }

  void updateConfig(AutoresponderConfig config) {
    _config = config;
    notifyListeners();
    _save();
  }

  /// Резюме, выбранное для бота (из конфига или глобальное по умолчанию).
  HhResume? get resume {
    final hash = _config.resumeHash.isNotEmpty
        ? _config.resumeHash
        : _appState.selectedResume?.hash;
    if (hash == null) return _appState.selectedResume;
    for (final r in _appState.resumes) {
      if (r.hash == hash) return r;
    }
    return _appState.selectedResume;
  }

  void selectResume(HhResume resume) {
    updateConfig(_config.copyWith(resumeHash: resume.hash));
  }

  bool get anyRunning => vacRunning || chatRunning;

  /// Запустить включённые процессы (отклики и/или ответы) одной кнопкой.
  Future<void> startBoth() async {
    final tasks = <Future<void>>[];
    if (_config.applyVacancies && !vacRunning) tasks.add(startVacancies());
    if (_config.answerChats && !chatRunning) tasks.add(startChats());
    await Future.wait(tasks);
  }

  /// Остановить оба процесса.
  void stopBoth() {
    stopVacancies();
    stopChats();
  }

  // =========================================================================
  // Процесс 1: отклики на вакансии
  // =========================================================================

  RunState _vacState = RunState.idle;
  RunState get vacState => _vacState;
  bool get vacRunning => _vacState != RunState.idle;

  String _vacStatus = 'Готов к запуску';
  String get vacStatus => _vacStatus;

  int _applied = 0;
  int _skipped = 0;
  int _vacErrors = 0;
  int get applied => _applied;
  int get skipped => _skipped;
  int get vacErrors => _vacErrors;

  final List<AutoLogEntry> _vacLog = [];
  List<AutoLogEntry> get vacLog => List.unmodifiable(_vacLog);

  Autoresponder? _vacEngine;

  Future<void> startVacancies() async {
    if (vacRunning) return;
    final resume = this.resume;
    if (resume == null) {
      _setVacStatus('Нет резюме');
      return;
    }
    if (_config.forceLetter && _config.aiModel.trim().isEmpty) {
      _setVacStatus('Укажите модель ИИ или выключите «Всегда писать письмо»');
      return;
    }

    _applied = 0;
    _skipped = 0;
    _vacErrors = 0;
    _vacLog.clear();
    _vacState = RunState.running;
    _setVacStatus('Запуск…');

    final ai = _buildAi();
    final runConfig = _config.copyWith(resumeHash: resume.hash);
    final ctx = _ResumeContext.of(_appState, resume);

    void log(String m, {bool error = false}) => _appendLog(_vacLog, m, error);
    void status(String s) {
      _vacStatus = s;
      notifyListeners();
    }

    try {
      status('Готовлю запуск…');
      final experience = await loadResumeExperience(_appState, resume.hash);
      final loop = _config.loopEnabled;
      var cycle = 0;

      while (_vacState == RunState.running) {
        cycle++;
        if (loop) log('— Цикл $cycle —');
        _applied = 0;
        _skipped = 0;
        _vacErrors = 0;
        notifyListeners();

        final engine = Autoresponder(
          appState: _appState,
          ai: ai,
          config: runConfig,
          fullName: ctx.fullName,
          resumeTitle: ctx.title,
          resumeSalary: ctx.salary,
          resumeSkills: ctx.skills,
          experience: experience,
          onStatus: status,
          onLog: log,
          onCounters: (a, s, e) {
            _applied = a;
            _skipped = s;
            _vacErrors = e;
            notifyListeners();
          },
        );
        _vacEngine = engine;
        await engine.run();
        _vacEngine = null;

        if (!loop || _vacState != RunState.running) break;
        await _waitCycle(() => _vacState, status);
      }

      _setVacStatus(_finalStatus(_vacState, 'откликов $_applied'));
    } catch (e) {
      _setVacStatus('Ошибка: $e');
    } finally {
      _vacEngine = null;
      _vacState = RunState.idle;
      notifyListeners();
    }
  }

  void stopVacancies() {
    if (_vacState != RunState.running) return;
    _vacState = RunState.stopping;
    _vacEngine?.cancel();
    _setVacStatus('Останавливаю…');
  }

  void _setVacStatus(String s) {
    _vacStatus = s;
    notifyListeners();
  }

  // =========================================================================
  // Процесс 2: ответы в чатах
  // =========================================================================

  RunState _chatState = RunState.idle;
  RunState get chatState => _chatState;
  bool get chatRunning => _chatState != RunState.idle;

  String _chatStatus = 'Готов к запуску';
  String get chatStatus => _chatStatus;

  int _replied = 0;
  int get replied => _replied;

  final List<AutoLogEntry> _chatLog = [];
  List<AutoLogEntry> get chatLog => List.unmodifiable(_chatLog);

  ChatResponder? _chatEngine;

  Future<void> startChats() async {
    if (chatRunning) return;
    final resume = this.resume;
    if (resume == null) {
      _setChatStatus('Нет резюме');
      return;
    }
    if (_config.aiModel.trim().isEmpty) {
      _setChatStatus('Укажите модель ИИ в настройках');
      return;
    }

    _replied = 0;
    _chatLog.clear();
    _chatState = RunState.running;
    _setChatStatus('Запуск…');

    final ai = _buildAi();
    final runConfig = _config.copyWith(resumeHash: resume.hash);
    final ctx = _ResumeContext.of(_appState, resume);

    void log(String m, {bool error = false}) => _appendLog(_chatLog, m, error);
    void status(String s) {
      _chatStatus = s;
      notifyListeners();
    }

    try {
      status('Готовлю запуск…');
      final experience = await loadResumeExperience(_appState, resume.hash);
      final loop = _config.loopEnabled;
      var cycle = 0;

      while (_chatState == RunState.running) {
        cycle++;
        if (loop) log('— Цикл $cycle —');
        _replied = 0;
        notifyListeners();

        final chat = ChatResponder(
          appState: _appState,
          ai: ai,
          config: runConfig,
          userId: _appState.account?.userId ?? 0,
          resumeId: resume.id,
          fullName: ctx.fullName,
          resumeTitle: ctx.title,
          resumeSalary: ctx.salary,
          resumeSkills: ctx.skills,
          experience: experience,
          onStatus: status,
          onLog: log,
          onReplied: (n) {
            _replied = n;
            notifyListeners();
          },
          onEmployerMessage: (msg) => employerMessageSink?.call(msg),
        );
        _chatEngine = chat;
        await chat.run();
        _chatEngine = null;

        if (!loop || _chatState != RunState.running) break;
        await _waitCycle(() => _chatState, status);
      }

      _setChatStatus(_finalStatus(_chatState, 'ответов $_replied'));
    } catch (e) {
      _setChatStatus('Ошибка: $e');
    } finally {
      _chatEngine = null;
      _chatState = RunState.idle;
      notifyListeners();
    }
  }

  void stopChats() {
    if (_chatState != RunState.running) return;
    _chatState = RunState.stopping;
    _chatEngine?.cancel();
    _setChatStatus('Останавливаю…');
  }

  void _setChatStatus(String s) {
    _chatStatus = s;
    notifyListeners();
  }

  // ---- общие помощники ----

  AiClient _buildAi() => AiClient(
        baseUrl: _config.aiBaseUrl,
        model: _config.aiModel,
        apiKey: _config.aiApiKey,
        reasoningEffort: _config.aiReasoningEffort,
      );

  void _appendLog(List<AutoLogEntry> log, String m, bool error) {
    log.insert(0, AutoLogEntry(m, error, DateTime.now()));
    if (log.length > 200) log.removeRange(200, log.length);
    notifyListeners();
  }

  String _finalStatus(RunState state, String counts) {
    final tail = _config.dryRun ? ' · тестовый режим' : '';
    final stopped = state == RunState.stopping;
    return '${stopped ? 'Остановлено' : 'Готово'}: $counts$tail';
  }

  Future<void> _waitCycle(
      RunState Function() getState, void Function(String) status) async {
    var remaining = (_config.loopIntervalMin * 60).clamp(1, 24 * 3600);
    while (remaining > 0 && getState() == RunState.running) {
      final mm = (remaining ~/ 60).toString().padLeft(2, '0');
      final ss = (remaining % 60).toString().padLeft(2, '0');
      status('Следующий цикл через $mm:$ss');
      await Future<void>.delayed(const Duration(seconds: 1));
      remaining--;
    }
  }
}

/// Данные резюме для промптов.
class _ResumeContext {
  _ResumeContext(this.fullName, this.title, this.salary, this.skills);
  final String fullName;
  final String title;
  final String salary;
  final String skills;

  factory _ResumeContext.of(AppState appState, HhResume resume) {
    return _ResumeContext(
      appState.account?.fullName ?? '',
      resume.title,
      resume.hasSalary ? resume.salaryLabel : 'по договорённости',
      resume.skills.join(', '),
    );
  }
}
