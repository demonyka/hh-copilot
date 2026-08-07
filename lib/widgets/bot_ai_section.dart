import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ai_client.dart';
import '../state/autoresponder_controller.dart';
import '../theme/hh_theme.dart';
import 'bot_widgets.dart';

/// Настройки модели ИИ (общие для обоих процессов). Правки сохраняются в общий
/// конфиг; при открытии раздела поля читаются из него.
class BotAiSection extends StatefulWidget {
  const BotAiSection({super.key, required this.enabled});

  final bool enabled;

  @override
  State<BotAiSection> createState() => _BotAiSectionState();
}

class _BotAiSectionState extends State<BotAiSection> {
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _key;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AutoresponderController>().config;
    _base = TextEditingController(text: cfg.aiBaseUrl);
    _model = TextEditingController(text: cfg.aiModel);
    _key = TextEditingController(text: cfg.aiApiKey);
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AutoresponderController>();
    void update() => controller.updateConfig(controller.config.copyWith(
          aiBaseUrl: _base.text,
          aiModel: _model.text,
          aiApiKey: _key.text,
        ));

    return BotSection(
      title: 'Модель ИИ',
      subtitle:
          'Любой OpenAI-совместимый сервер: OpenAI, DeepSeek, локальный Ollama/LM Studio. Общая для обоих процессов.',
      children: [
        BotTextField(
          controller: _base,
          label: 'Адрес сервера',
          hint: 'http://localhost:11434',
          enabled: widget.enabled,
          onChanged: (_) => update(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: BotTextField(
                controller: _model,
                label: 'Модель',
                hint: 'gpt-4o-mini / deepseek-chat / llama3',
                enabled: widget.enabled,
                onChanged: (_) => update(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: BotTextField(
                controller: _key,
                label: 'API-ключ (если нужен)',
                obscure: true,
                enabled: widget.enabled,
                onChanged: (_) => update(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: _effortValues.contains(controller.config.aiReasoningEffort)
                    ? controller.config.aiReasoningEffort
                    : '',
                isExpanded: true,
                decoration: botInputDecoration('Reasoning (для reasoning-моделей)', null),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Не отправлять')),
                  DropdownMenuItem(value: 'none', child: Text('Отключить (none)')),
                  DropdownMenuItem(value: 'low', child: Text('Низкий (low)')),
                  DropdownMenuItem(value: 'medium', child: Text('Средний (medium)')),
                  DropdownMenuItem(value: 'high', child: Text('Высокий (high)')),
                ],
                onChanged: widget.enabled
                    ? (v) => controller.updateConfig(
                        controller.config.copyWith(aiReasoningEffort: v ?? ''))
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Если модель «думает» и возвращает пустой ответ — поставьте «Отключить (none)» '
                'или «Низкий». Обычным chat-моделям обычно нужно «Не отправлять».',
                style: TextStyle(fontSize: 12, color: HhColors.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.enabled ? _ping : null,
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Проверить ИИ'),
          ),
        ),
      ],
    );
  }

  static const _effortValues = ['', 'none', 'low', 'medium', 'high'];

  Future<void> _ping() async {
    final messenger = ScaffoldMessenger.of(context);
    final effort = context.read<AutoresponderController>().config.aiReasoningEffort;
    messenger.showSnackBar(
        const SnackBar(content: Text('Проверяю подключение к ИИ…')));
    try {
      await AiClient(
        baseUrl: _base.text,
        model: _model.text,
        apiKey: _key.text,
        reasoningEffort: effort,
      ).ping();
      messenger.showSnackBar(const SnackBar(
          backgroundColor: HhColors.green,
          content: Text('ИИ отвечает — всё в порядке')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: HhColors.red, content: Text('Ошибка ИИ: $e')));
    }
  }
}
