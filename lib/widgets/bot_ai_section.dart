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
    final controller = context.read<AutoresponderController>();
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

  Future<void> _ping() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Проверяю подключение к ИИ…')));
    try {
      await AiClient(
              baseUrl: _base.text, model: _model.text, apiKey: _key.text)
          .ping();
      messenger.showSnackBar(const SnackBar(
          backgroundColor: HhColors.green,
          content: Text('ИИ отвечает — всё в порядке')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: HhColors.red, content: Text('Ошибка ИИ: $e')));
    }
  }
}
