import 'dart:convert';

import '../models/autoresponder_config.dart';
import '../state/app_state.dart';
import 'ai_client.dart';
import 'hh_profile_parser.dart';
import 'hh_resume.dart';
import 'json_scan.dart';

/// Вакансия из выдачи поиска hh.ru.
class _Vacancy {
  _Vacancy({
    required this.id,
    required this.name,
    required this.companyName,
    required this.desktopLink,
    required this.letterRequired,
    required this.testPresent,
    required this.archived,
    required this.hasUserLabels,
    required this.alreadyResponded,
    required this.totalResponses,
  });

  final int id;
  final String name;
  final String companyName;
  final String desktopLink;
  final bool letterRequired;
  final bool testPresent;
  final bool archived;
  final bool hasUserLabels;
  final bool alreadyResponded;
  final int totalResponses;
}

/// Итог запуска.
class AutoresponderResult {
  const AutoresponderResult({
    required this.applied,
    required this.skipped,
    required this.errors,
    required this.stoppedByUser,
    required this.reason,
  });

  final int applied;
  final int skipped;
  final int errors;
  final bool stoppedByUser;
  final String reason;
}

/// Движок автооткликов. Портирован с Go-референса (`ApplyVacancies`), но ходит
/// на hh.ru через встроенный браузер (cookies пользователя + обход анти-бота),
/// а письма пишет через OpenAI-совместимый ИИ пользователя.
class Autoresponder {
  Autoresponder({
    required this.appState,
    required this.ai,
    required this.config,
    required this.fullName,
    required this.resumeTitle,
    required this.resumeSalary,
    required this.resumeSkills,
    required this.experience,
    required this.onStatus,
    required this.onLog,
    required this.onCounters,
  });

  final AppState appState;
  final AiClient ai;
  final AutoresponderConfig config;
  final String fullName;
  final String resumeTitle;
  final String resumeSalary;
  final String resumeSkills;
  final String experience;

  final void Function(String status) onStatus;
  final void Function(String message, {bool error}) onLog;
  final void Function(int applied, int skipped, int errors) onCounters;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  int _applied = 0;
  int _skipped = 0;
  int _errors = 0;

  Future<AutoresponderResult> run() async {
    if (config.resumeHash.isEmpty) {
      return _result('Не выбрано резюме');
    }
    String reason = 'Готово';
    outer:
    for (int page = 0; !_cancelled; page++) {
      onStatus('Ищу вакансии (страница ${page + 1})…');
      final vacancies = await _fetchVacancyPage(page);
      if (vacancies == null) {
        onLog('Не удалось загрузить вакансии', error: true);
        reason = 'Ошибка загрузки вакансий';
        break;
      }
      if (vacancies.isEmpty) {
        reason = 'Вакансии закончились';
        break;
      }

      for (final v in vacancies) {
        if (_cancelled) break outer;

        if (v.archived || v.hasUserLabels || v.alreadyResponded) {
          _skipped++;
          _emit();
          continue;
        }
        if (config.maxResponses > 0 && v.totalResponses > config.maxResponses) {
          _skipped++;
          _emit();
          continue;
        }
        if (v.testPresent && !ai.isConfigured) {
          _skipped++;
          onLog('Пропуск «${v.name}» — тест, а ИИ не настроен');
          _emit();
          continue;
        }
        if (v.desktopLink.isEmpty) {
          _skipped++;
          _emit();
          continue;
        }

        String letter = '';
        if (v.letterRequired || config.forceLetter) {
          if (!ai.isConfigured) {
            _skipped++;
            onLog('Пропуск «${v.name}» — нужно письмо, а ИИ не настроен');
            _emit();
            continue;
          }
          onStatus('Пишу письмо для «${v.name}»…');
          final description = await _vacancyDescription(v.id);
          if (description.isEmpty) {
            _skipped++;
            onLog('Пропуск «${v.name}» — нет описания');
            _emit();
            continue;
          }
          try {
            letter = await _generateLetter(v, description);
          } catch (e) {
            _errors++;
            onLog('Ошибка ИИ для «${v.name}»: $e', error: true);
            _emit();
            await _wait();
            continue;
          }
          if (letter.trim().isEmpty) {
            _skipped++;
            onLog('Пропуск «${v.name}» — пустое письмо');
            _emit();
            continue;
          }
        }

        if (config.dryRun) {
          _applied++;
          final testNote = v.testPresent ? ' (решил бы тест)' : '';
          onLog('[тест] откликнулся бы: ${v.name} — ${v.companyName}$testNote');
          _emit();
          if (_limitReached()) {
            reason = 'Достигнут лимит откликов';
            break outer;
          }
          await _wait();
          continue;
        }

        onStatus(v.testPresent
            ? 'Решаю тест и откликаюсь на «${v.name}»…'
            : 'Откликаюсь на «${v.name}»…');
        final res = v.testPresent
            ? await _applyWithTest(v, letter)
            : await _apply(v, letter);
        switch (res) {
          case 'ok':
            _applied++;
            onLog('Отклик отправлен: ${v.name} — ${v.companyName}');
            _emit();
            if (_limitReached()) {
              reason = 'Достигнут лимит откликов';
              break outer;
            }
            break;
          case 'limit':
            onLog('Лимит откликов hh.ru исчерпан', error: true);
            reason = 'Лимит откликов hh.ru';
            break outer;
          default:
            _errors++;
            onLog('Не удалось откликнуться на «${v.name}»: $res', error: true);
            _emit();
        }
        await _wait();
      }
    }

    return _result(_cancelled ? 'Остановлено' : reason);
  }

  AutoresponderResult _result(String reason) => AutoresponderResult(
        applied: _applied,
        skipped: _skipped,
        errors: _errors,
        stoppedByUser: _cancelled,
        reason: reason,
      );

  bool _limitReached() => config.limit > 0 && _applied >= config.limit;

  void _emit() => onCounters(_applied, _skipped, _errors);

  Future<void> _wait() async {
    var remaining = config.intervalSec;
    while (remaining > 0 && !_cancelled) {
      onStatus('Жду $remaining сек…');
      await Future<void>.delayed(const Duration(seconds: 1));
      remaining--;
    }
  }

  // --- hh.ru ---

  Future<List<_Vacancy>?> _fetchVacancyPage(int page) async {
    final params = _searchParams();
    params['page'] = '$page';
    final url = '${AppState.baseUrl}/search/vacancy?${_encodeQuery(params)}';
    final resp = await appState.hhRequest(method: 'GET', url: url);
    if (resp == null || !resp.ok) return null;
    final text = HhProfileParser.htmlUnescape(resp.body);
    final list = _extractVacancies(text);
    return list;
  }

  Map<String, String> _searchParams() {
    final raw = config.searchUrl.trim();
    if (raw.isNotEmpty) {
      final uri = Uri.tryParse(raw);
      if (uri != null) {
        final p = Map<String, String>.from(uri.queryParameters);
        p.remove('page');
        if (p.isNotEmpty) return p;
      }
    }
    final p = <String, String>{};
    if (config.query.trim().isNotEmpty) {
      p['text'] = config.query.trim();
    } else {
      p['resume'] = config.resumeHash;
    }
    return p;
  }

  List<_Vacancy> _extractVacancies(String text) {
    // Ищем массив "vacancies", у элементов которого есть vacancyId.
    for (final key in const ['"vacancies":']) {
      int from = 0;
      while (true) {
        final list = JsonScan.arrayAfterKey(text, key, from: from);
        final k = text.indexOf(key, from);
        if (k < 0) break;
        from = k + key.length;
        if (list == null) continue;
        if (list.isNotEmpty &&
            list.first is Map &&
            (list.first as Map).containsKey('vacancyId')) {
          return list.whereType<Map>().map(_mapVacancy).toList();
        }
      }
    }
    return const [];
  }

  _Vacancy _mapVacancy(Map v) {
    final links = v['links'];
    String desktop = '';
    if (links is Map && links['desktop'] != null) {
      desktop = links['desktop'].toString();
    }
    final company = v['company'];
    final companyName =
        company is Map ? (company['name']?.toString() ?? '') : '';
    final labels = v['userLabels'];
    return _Vacancy(
      id: JsonScan.asInt(v['vacancyId']),
      name: v['name']?.toString() ?? '',
      companyName: companyName,
      desktopLink: desktop,
      letterRequired: v['@responseLetterRequired'] == true,
      testPresent: v['userTestPresent'] == true,
      archived: v['archived'] == true,
      hasUserLabels: labels is List && labels.isNotEmpty,
      alreadyResponded: (v['response_url']?.toString() ?? '').isNotEmpty,
      totalResponses: JsonScan.asInt(v['totalResponsesCount']),
    );
  }

  Future<String> _vacancyDescription(int id) async {
    final resp = await appState.hhRequest(
      method: 'GET',
      url: '${AppState.baseUrl}/vacancy/$id?hhtmFrom=negotiation_list',
    );
    if (resp == null || !resp.ok) return '';
    final text = HhProfileParser.htmlUnescape(resp.body);
    final root = redirectConfigRoot(text);
    final view = root?['vacancyView'];
    final desc = view is Map ? view['description']?.toString() : null;
    if (desc == null || desc.isEmpty) return '';
    return _cleanVacancyText(desc);
  }

  Future<String> _apply(_Vacancy v, String letter) async {
    final xsrf = await appState.xsrfToken();
    if (xsrf.isEmpty) return 'нет xsrf-токена';
    final form = <String, String>{
      '_xsrf': xsrf,
      'vacancy_id': '${v.id}',
      'resume_hash': config.resumeHash,
      'letter': letter,
      'ignore_postponed': 'true',
    };
    return _sendResponse(form, xsrf, v.desktopLink);
  }

  /// Отклик на вакансию с тестом: тянет задания, решает их через ИИ и отправляет
  /// вместе с письмом (порт `ApplyVacancyWithTest`).
  Future<String> _applyWithTest(_Vacancy v, String letter) async {
    final xsrf = await appState.xsrfToken();
    if (xsrf.isEmpty) return 'нет xsrf-токена';

    final responseUrl =
        '${AppState.baseUrl}/applicant/vacancy_response?vacancyId=${v.id}&startedWithQuestion=false&hhtmFrom=vacancy';
    final testsResp =
        await appState.hhRequest(method: 'GET', url: responseUrl);
    if (testsResp == null || !testsResp.ok) return 'не загрузил тест';
    final text = HhProfileParser.htmlUnescape(testsResp.body);
    final testsObj = JsonScan.objectAfterKey(text, ',"vacancyTests":') ??
        JsonScan.objectAfterKey(text, '"vacancyTests":');
    final test = testsObj?['${v.id}'];
    if (test is! Map) return 'нет данных теста';
    final tasksRaw = test['tasks'];
    if (tasksRaw is! List || tasksRaw.isEmpty) return 'нет заданий теста';

    // Упрощаем задачи для ИИ.
    final trimmed = <Map<String, dynamic>>[];
    for (final t in tasksRaw) {
      if (t is! Map) continue;
      final candidates = <Map<String, dynamic>>[];
      final cs = t['candidateSolutions'];
      if (cs is List) {
        for (final c in cs) {
          if (c is Map) {
            candidates.add({
              'id': c['id'],
              'text': c['text'],
              'title': c['title'],
              'value': c['value'],
            });
          }
        }
      }
      trimmed.add({
        'id': t['id'],
        'description': t['description'],
        'candidateSolutions': candidates,
      });
    }

    final Map<int, TestSolution> solutions;
    try {
      solutions = await ai.solveTests(trimmed, contacts: config.contacts);
    } catch (e) {
      return 'ошибка ИИ (тест): $e';
    }
    if (solutions.length != tasksRaw.length) return 'неполные ответы теста';

    final form = <String, String>{
      '_xsrf': xsrf,
      'uidPk': test['uidPk']?.toString() ?? '',
      'guid': test['guid']?.toString() ?? '',
      'startTime': test['startTime']?.toString() ?? '',
      'testRequired': test['required']?.toString() ?? '',
      'vacancy_id': '${v.id}',
      'resume_hash': config.resumeHash,
      'ignore_postponed': 'true',
      'incomplete': 'false',
      'lux': 'true',
      'withoutTest': 'no',
      'letter': letter,
      'mark_applicant_visible_in_vacancy_country': 'false',
      'country_ids': '[]',
    };
    for (final t in tasksRaw) {
      if (t is! Map) continue;
      final taskId = JsonScan.asInt(t['id']);
      final ans = solutions[taskId];
      if (ans == null) return 'нет ответа на задание $taskId';
      if (ans.hasChoice) {
        form['task_$taskId'] = '${ans.solutionId}';
      } else {
        form['task_${taskId}_text'] = ans.textSolution;
      }
    }

    return _sendResponse(form, xsrf, responseUrl);
  }

  Future<String> _sendResponse(
      Map<String, String> form, String xsrf, String referer) async {
    final resp = await appState.hhRequest(
      method: 'POST',
      url: '${AppState.baseUrl}/applicant/vacancy_response/popup',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Xsrftoken': xsrf,
        'X-Hhtmfrom': 'vacancy',
        'X-Hhtmsource': 'vacancy_response',
        'Referer': referer,
      },
      body: _encodeQuery(form),
    );
    if (resp == null) return 'нет ответа';
    try {
      final data = jsonDecode(resp.body);
      if (data is Map) {
        final err = data['error'];
        if (err != null) {
          final e = err.toString();
          return e == 'negotiations-limit-exceeded' ? 'limit' : e;
        }
        if (data['success']?.toString() == 'true') return 'ok';
      }
      return 'неожиданный ответ';
    } catch (_) {
      return 'ответ не JSON (${resp.status})';
    }
  }

  // --- ИИ ---

  Future<String> _generateLetter(_Vacancy v, String description) async {
    final template =
        config.letterPrompt.trim().isEmpty ? kDefaultLetterPrompt : config.letterPrompt;
    var system = _renderPrompt(template, {
      '{name}': fullName,
      '{title}': resumeTitle,
      '{salary}': resumeSalary,
      '{skills}': resumeSkills,
      '{experience}': experience,
    });
    if (config.contacts.trim().isNotEmpty) {
      system += '\nКонтакты для указания в письме: ${config.contacts.trim()}';
    }
    final user =
        'Название вакансии: ${v.name}\nКомпания: ${v.companyName}\nОписание вакансии:\n$description';
    // Запас по токенам, чтобы reasoning-моделям хватило и на «размышления», и на ответ.
    return ai.chat(system, user, maxTokens: 1500, temperature: 0.8);
  }

  // --- helpers ---

  static String _renderPrompt(String tmpl, Map<String, String> vars) {
    var out = tmpl;
    vars.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  static String _encodeQuery(Map<String, String> params) =>
      Uri(queryParameters: params).query;

  static String _truncate(String s, int n) {
    if (s.length <= n) return s.trim();
    return '${s.substring(0, n).trim()}…';
  }

  static final RegExp _tagRe = RegExp(r'<[^>]+>', dotAll: true);
  static final RegExp _wsRe = RegExp(r'[ \t]*\n[ \t\n]*');
  static final RegExp _spacesRe = RegExp(r'[ \t]{2,}');

  static String _cleanVacancyText(String s) {
    s = s
        .replaceAll('</li>', '\n')
        .replaceAll('</p>', '\n')
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br />', '\n');
    s = s.replaceAll(_tagRe, '');
    s = s.replaceAll(_spacesRe, ' ');
    s = s.replaceAll(_wsRe, '\n');
    return _truncate(s.trim(), 1600);
  }
}
