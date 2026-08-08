import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/autoresponder_controller.dart';
import '../theme/hh_theme.dart';
import '../widgets/bot_ai_section.dart';
import '../widgets/bot_widgets.dart';

/// Раздел «Автоотклики»: два процесса (отклики и ответы в чатах) в одном
/// экране, с общими настройками и единой кнопкой Старт/Стоп.
class AutoresponsesScreen extends StatelessWidget {
  const AutoresponsesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AutoresponderController>();
    if (!controller.loaded) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }
    return const _Body();
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final TextEditingController _query;
  late final TextEditingController _searchUrl;
  late final TextEditingController _limit;
  late final TextEditingController _maxResponses;
  late final TextEditingController _interval;
  late final TextEditingController _loopInterval;
  late final TextEditingController _letterPrompt;
  late final TextEditingController _chatPrompt;
  late final TextEditingController _contacts;

  AutoresponderController get _c => context.read<AutoresponderController>();

  @override
  void initState() {
    super.initState();
    final cfg = _c.config;
    _query = TextEditingController(text: cfg.query);
    _searchUrl = TextEditingController(text: cfg.searchUrl);
    _limit = TextEditingController(text: cfg.limit.toString());
    _maxResponses = TextEditingController(text: cfg.maxResponses.toString());
    _interval = TextEditingController(text: cfg.intervalSec.toString());
    _loopInterval = TextEditingController(text: cfg.loopIntervalMin.toString());
    _letterPrompt = TextEditingController(text: cfg.letterPrompt);
    _chatPrompt = TextEditingController(text: cfg.chatPrompt);
    _contacts = TextEditingController(text: cfg.contacts);
  }

  @override
  void dispose() {
    for (final c in [
      _query,
      _searchUrl,
      _limit,
      _maxResponses,
      _interval,
      _loopInterval,
      _letterPrompt,
      _chatPrompt,
      _contacts,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _update(dynamic cfg) => _c.updateConfig(cfg);
  int _int(String s, int fallback) => int.tryParse(s.trim()) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AutoresponderController>();
    final cfg = controller.config;
    // Поля блокируем, только пока идёт соответствующий процесс.
    final vacRunning = controller.vacRunning;
    final chatRunning = controller.chatRunning;
    final anyRunning = controller.anyRunning;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CombinedStatusCard(controller: controller),
                const SizedBox(height: 16),
                BotSection(
                  title: 'Что делает бот',
                  children: [
                    BotSwitch(
                      label: 'Откликаться на вакансии',
                      value: cfg.applyVacancies,
                      enabled: !vacRunning,
                      onChanged: (v) =>
                          _update(cfg.copyWith(applyVacancies: v)),
                    ),
                    BotSwitch(
                      label: 'Отвечать в чатах с работодателями',
                      value: cfg.answerChats,
                      enabled: !chatRunning,
                      onChanged: (v) => _update(cfg.copyWith(answerChats: v)),
                    ),
                    BotSwitch(
                      label: 'Выходить из отказных чатов (очистка)',
                      value: cfg.leaveDiscardChats,
                      enabled: !chatRunning,
                      onChanged: (v) =>
                          _update(cfg.copyWith(leaveDiscardChats: v)),
                    ),
                    BotSwitch(
                      label: 'Поднимать резюме в выдаче',
                      value: cfg.raiseResume,
                      enabled: !anyRunning,
                      onChanged: (v) => _update(cfg.copyWith(raiseResume: v)),
                    ),
                    const Divider(height: 20),
                    BotSwitch(
                      label: 'Фоновый цикл — повторять по кругу',
                      value: cfg.loopEnabled,
                      enabled: !anyRunning,
                      onChanged: (v) => _update(cfg.copyWith(loopEnabled: v)),
                    ),
                    if (cfg.loopEnabled)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: 220,
                          child: BotTextField(
                            controller: _loopInterval,
                            label: 'Интервал цикла, мин',
                            number: true,
                            enabled: !anyRunning,
                            onChanged: (v) => _update(cfg.copyWith(
                                loopIntervalMin: _int(v, cfg.loopIntervalMin))),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                BotSection(
                  title: 'Резюме и поиск',
                  children: [
                    BotResumeField(enabled: !anyRunning),
                    const SizedBox(height: 14),
                    BotTextField(
                      controller: _query,
                      label: 'Ключевые слова',
                      hint: 'Пусто — подходящие вакансии для резюме',
                      enabled: !vacRunning,
                      onChanged: (v) => _update(cfg.copyWith(query: v)),
                    ),
                    const SizedBox(height: 14),
                    BotTextField(
                      controller: _searchUrl,
                      label: 'Ссылка поиска hh.ru (необязательно)',
                      hint: 'https://hh.ru/search/vacancy?...',
                      enabled: !vacRunning,
                      onChanged: (v) => _update(cfg.copyWith(searchUrl: v)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: BotTextField(
                            controller: _limit,
                            label: 'Максимум откликов',
                            number: true,
                            enabled: !vacRunning,
                            onChanged: (v) =>
                                _update(cfg.copyWith(limit: _int(v, cfg.limit))),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: BotTextField(
                            controller: _maxResponses,
                            label: 'Пропуск, если откликов >',
                            number: true,
                            enabled: !vacRunning,
                            onChanged: (v) => _update(cfg.copyWith(
                                maxResponses: _int(v, cfg.maxResponses))),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: BotTextField(
                            controller: _interval,
                            label: 'Пауза, сек',
                            number: true,
                            enabled: !anyRunning,
                            onChanged: (v) => _update(cfg.copyWith(
                                intervalSec: _int(v, cfg.intervalSec))),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    BotSwitch(
                      label: 'Всегда писать сопроводительное',
                      value: cfg.forceLetter,
                      enabled: !vacRunning,
                      onChanged: (v) => _update(cfg.copyWith(forceLetter: v)),
                    ),
                    BotSwitch(
                      label: 'Тестовый режим — ничего не отправлять',
                      value: cfg.dryRun,
                      enabled: !anyRunning,
                      onChanged: (v) => _update(cfg.copyWith(dryRun: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                BotAiSection(enabled: !anyRunning),
                const SizedBox(height: 16),
                BotSection(
                  title: 'Промпты',
                  subtitle:
                      'Плейсхолдеры: {name} {title} {salary} {skills} {experience}.',
                  children: [
                    BotTextField(
                      controller: _letterPrompt,
                      label: 'Промпт сопроводительного письма',
                      maxLines: 7,
                      enabled: !vacRunning,
                      onChanged: (v) => _update(cfg.copyWith(letterPrompt: v)),
                    ),
                    const SizedBox(height: 14),
                    BotTextField(
                      controller: _chatPrompt,
                      label: 'Промпт ответов в чатах',
                      maxLines: 7,
                      enabled: !chatRunning,
                      onChanged: (v) => _update(cfg.copyWith(chatPrompt: v)),
                    ),
                    const SizedBox(height: 14),
                    BotTextField(
                      controller: _contacts,
                      label: 'Контакты для письма/чата (необязательно)',
                      hint: 'Telegram, телефон, e-mail…',
                      enabled: !anyRunning,
                      onChanged: (v) => _update(cfg.copyWith(contacts: v)),
                    ),
                  ],
                ),
                if (cfg.applyVacancies) ...[
                  const SizedBox(height: 16),
                  BotLogCard(
                      title: 'Журнал откликов', log: controller.vacLog),
                ],
                if (cfg.answerChats) ...[
                  const SizedBox(height: 16),
                  BotLogCard(title: 'Журнал чатов', log: controller.chatLog),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка статуса обоих процессов + единая кнопка Старт/Стоп.
class _CombinedStatusCard extends StatelessWidget {
  const _CombinedStatusCard({required this.controller});

  final AutoresponderController controller;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    final anyRunning = controller.anyRunning;
    final canStart = cfg.applyVacancies || cfg.answerChats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HhColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HhColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (anyRunning)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                const Icon(Icons.smart_toy_outlined,
                    size: 22, color: HhColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: anyRunning
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cfg.applyVacancies)
                            _line('Отклики', controller.vacStatus),
                          if (cfg.answerChats)
                            _line('Ответы', controller.chatStatus),
                        ],
                      )
                    : const Text('Готов к запуску',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: HhColors.textPrimary)),
              ),
              if (cfg.dryRun)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: HhColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Тестовый режим',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9A6B00))),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (cfg.applyVacancies) ...[
                _stat('Отклики', controller.applied, HhColors.green),
                const SizedBox(width: 20),
                _stat('Пропущено', controller.skipped, HhColors.textSecondary),
                const SizedBox(width: 20),
                _stat('Ошибки', controller.vacErrors, HhColors.red),
                const SizedBox(width: 20),
              ],
              if (cfg.answerChats) ...[
                _stat('Ответы', controller.replied, HhColors.blue),
                const SizedBox(width: 20),
              ],
              const Spacer(),
              if (anyRunning)
                OutlinedButton.icon(
                  onPressed: controller.stopBoth,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Стоп'),
                )
              else
                ElevatedButton.icon(
                  onPressed: canStart ? controller.startBoth : null,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Старт'),
                ),
            ],
          ),
          if (!canStart)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Включите отклики и/или ответы в чатах.',
                  style: TextStyle(fontSize: 12, color: HhColors.textMuted)),
            ),
        ],
      ),
    );
  }

  Widget _line(String label, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: HhColors.textPrimary),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: status),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: HhColors.textSecondary)),
      ],
    );
  }
}
