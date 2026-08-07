import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/interview_lead.dart';
import '../state/app_state.dart';
import '../state/autoresponder_controller.dart';
import '../state/interviews_controller.dart';
import '../state/settings_controller.dart';
import '../theme/hh_theme.dart';

/// Раздел «Собеседования»: список обнаруженных приглашений + мониторинг.
class InterviewsScreen extends StatelessWidget {
  const InterviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InterviewsController>();
    if (!controller.loaded) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }

    final leads = controller.leads;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StatusCard(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('Приглашения',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: HhColors.textPrimary)),
                    const SizedBox(width: 10),
                    if (leads.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: HhColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${leads.length}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: HhColors.textSecondary)),
                      ),
                    const Spacer(),
                    if (leads.isNotEmpty)
                      TextButton(
                        onPressed: controller.clearLeads,
                        child: const Text('Очистить'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (leads.isEmpty)
                  const _EmptyState()
                else
                  ...leads.map((l) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LeadCard(lead: l),
                      )),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final interviews = context.watch<InterviewsController>();
    final bot = context.watch<AutoresponderController>();
    final settings = context.watch<SettingsController>().settings;
    final appState = context.read<AppState>();
    final active = bot.chatRunning;

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
              if (active)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                const Icon(Icons.notifications_active_outlined,
                    size: 22, color: HhColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  active
                      ? 'Слежу за чатами — процесс «Ответы в чатах» работает'
                      : 'Детект неактивен',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: HhColors.textPrimary),
                ),
              ),
              if (!active)
                ElevatedButton.icon(
                  onPressed: () =>
                      appState.selectSection(AppSection.autoresponses),
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: const Text('К автооткликам'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Приглашения определяются тем же проходом по чатам, что и авто-ответы: '
            'запустите «Ответы в чатах» в «Автооткликах». Определяем по смыслу '
            'сообщения работодателя (звонок, встреча, просьба написать/прислать '
            'контакты, оффер). '
            '${interviews.hasAi ? 'Используется ваш ИИ.' : 'ИИ не настроен — работает эвристика; для точности задайте модель в «Автооткликах».'} '
            'Чтобы только получать уведомления (без реальных ответов) — включите '
            'тестовый режим.',
            style: const TextStyle(
                fontSize: 13, color: HhColors.textSecondary, height: 1.4),
          ),
          if (!settings.telegramConfigured) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: HhColors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Telegram не настроен — уведомления не будут приходить. '
                    'Настройте в разделе «Настройки».',
                    style: TextStyle(fontSize: 12, color: HhColors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead});

  final InterviewLead lead;

  @override
  Widget build(BuildContext context) {
    final when = lead.messageAt ?? lead.detectedAt;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HhColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HhColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  lead.vacancy.isEmpty ? 'Вакансия' : lead.vacancy,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: HhColors.textPrimary),
                ),
              ),
              if (lead.kind.isNotEmpty) _KindChip(kind: lead.kind),
            ],
          ),
          if (lead.company.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lead.company,
                style: const TextStyle(
                    fontSize: 14, color: HhColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HhColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              lead.message,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: HhColors.textPrimary, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.schedule,
                  size: 15, color: HhColors.textMuted),
              const SizedBox(width: 6),
              Text(_formatDate(when),
                  style: const TextStyle(
                      fontSize: 12, color: HhColors.textMuted)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(lead.chatUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Открыть чат'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: HhColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        kind,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF08823F)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: HhColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HhColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_available_outlined,
              size: 44, color: HhColors.textMuted),
          SizedBox(height: 14),
          Text('Пока нет приглашений',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: HhColors.textPrimary)),
          SizedBox(height: 6),
          Text('Нажмите «Следить», и приглашения из чатов появятся здесь.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: HhColors.textSecondary)),
        ],
      ),
    );
  }
}
