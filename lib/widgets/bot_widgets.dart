import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/autoresponder_controller.dart';
import '../theme/hh_theme.dart';

InputDecoration botInputDecoration(String label, String? hint) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: HhColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HhColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HhColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HhColors.red, width: 1.5),
      ),
    );

class BotTextField extends StatelessWidget {
  const BotTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.obscure = false,
    this.enabled = true,
    this.number = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final bool obscure;
  final bool enabled;
  final bool number;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      obscureText: obscure,
      keyboardType: number ? TextInputType.number : null,
      inputFormatters:
          number ? [FilteringTextInputFormatter.digitsOnly] : null,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: botInputDecoration(label, hint),
    );
  }
}

class BotSwitch extends StatelessWidget {
  const BotSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      activeThumbColor: HhColors.red,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class BotSection extends StatelessWidget {
  const BotSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: HhColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: const TextStyle(
                    fontSize: 13, color: HhColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Выпадающий список выбора резюме для бота.
class BotResumeField extends StatelessWidget {
  const BotResumeField({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final controller = context.read<AutoresponderController>();
    final resumes = appState.resumes;
    final current = controller.resume?.hash;

    return DropdownButtonFormField<String>(
      initialValue: resumes.any((r) => r.hash == current) ? current : null,
      isExpanded: true,
      decoration: botInputDecoration('Резюме', null),
      items: [
        for (final r in resumes)
          DropdownMenuItem(
            value: r.hash,
            child: Text(r.title.isEmpty ? 'Без названия' : r.title,
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled
          ? (hash) {
              if (hash == null) return;
              controller.selectResume(resumes.firstWhere((r) => r.hash == hash));
            }
          : null,
    );
  }
}

/// Карточка статуса процесса со счётчиками и кнопками Старт/Стоп.
class BotStatusCard extends StatelessWidget {
  const BotStatusCard({
    super.key,
    required this.title,
    required this.status,
    required this.running,
    required this.stopping,
    required this.dryRun,
    required this.stats,
    required this.onStart,
    required this.onStop,
  });

  final String title;
  final String status;
  final bool running;
  final bool stopping;
  final bool dryRun;
  final List<(String, int, Color)> stats;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
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
              if (running)
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
                child: Text(status,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: HhColors.textPrimary)),
              ),
              if (dryRun)
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
              for (final s in stats) ...[
                _stat(s.$1, s.$2, s.$3),
                const SizedBox(width: 20),
              ],
              const Spacer(),
              if (running)
                OutlinedButton.icon(
                  onPressed: stopping ? null : onStop,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Стоп'),
                )
              else
                ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Старт'),
                ),
            ],
          ),
        ],
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

class BotLogCard extends StatelessWidget {
  const BotLogCard({super.key, required this.log, this.title = 'Журнал'});

  final List<AutoLogEntry> log;
  final String title;

  @override
  Widget build(BuildContext context) {
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
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: HhColors.textPrimary)),
          const SizedBox(height: 12),
          if (log.isEmpty)
            const Text('Здесь появятся действия движка.',
                style: TextStyle(fontSize: 13, color: HhColors.textMuted))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: log.length,
                separatorBuilder: (_, _) => const Divider(height: 12),
                itemBuilder: (context, i) {
                  final e = log[i];
                  final t =
                      '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}:${e.time.second.toString().padLeft(2, '0')}';
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t,
                          style: const TextStyle(
                              fontSize: 12, color: HhColors.textMuted)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.message,
                            style: TextStyle(
                                fontSize: 13,
                                color: e.error
                                    ? HhColors.red
                                    : HhColors.textPrimary)),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
