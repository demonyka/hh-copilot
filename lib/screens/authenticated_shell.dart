import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/autoresponder_controller.dart';
import '../theme/hh_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/resume_dropdown.dart';
import 'autoresponses_screen.dart';
import 'chats_screen.dart';
import 'interviews_screen.dart';
import 'resume_analytics_screen.dart';
import 'settings_screen.dart';

/// Каркас авторизованной части: узкий сайдбар слева, сверху шапка, ниже —
/// контент раздела.
class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: HhColors.pageBackground,
      body: Row(
        children: [
          const AppSidebar(),
          Expanded(
            child: Column(
              children: [
                _ShellHeader(section: appState.section),
                Expanded(
                  child: IndexedStack(
                    index: appState.section.index,
                    children: const [
                      ResumeAnalyticsScreen(),
                      ChatsScreen(),
                      AutoresponsesScreen(),
                      InterviewsScreen(),
                      SettingsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.section});

  final AppSection section;

  String get _title {
    switch (section) {
      case AppSection.analytics:
        return 'Аналитика';
      case AppSection.chats:
        return 'Чаты';
      case AppSection.autoresponses:
        return 'Автоотклики';
      case AppSection.interviews:
        return 'Собеседования';
      case AppSection.settings:
        return 'Настройки';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final showResume = section == AppSection.analytics;
    final showRefresh =
        section == AppSection.analytics || section == AppSection.chats;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: HhColors.surface,
        border: Border(bottom: BorderSide(color: HhColors.border)),
      ),
      child: Row(
        children: [
          Text(
            _title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: HhColors.textPrimary,
            ),
          ),
          const _BotStatusBar(),
          const Spacer(),
          if (showResume) ...[
            const ResumeDropdown(),
            const SizedBox(width: 12),
          ],
          if (showRefresh)
            IconButton(
              tooltip: 'Обновить',
              onPressed: () {
                if (section == AppSection.analytics) {
                  appState.refreshAnalytics();
                } else {
                  appState.reloadChats();
                }
              },
              icon: const Icon(Icons.refresh, color: HhColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Компактные индикаторы работающих процессов бота в шапке (на всех разделах).
class _BotStatusBar extends StatelessWidget {
  const _BotStatusBar();

  @override
  Widget build(BuildContext context) {
    final bot = context.watch<AutoresponderController>();
    if (!bot.anyRunning) return const SizedBox.shrink();
    final appState = context.read<AppState>();

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bot.vacRunning)
            _ProcChip(
              label: 'Отклики',
              tooltip: bot.vacStatus,
              stopping: bot.vacState == RunState.stopping,
              onOpen: () => appState.selectSection(AppSection.autoresponses),
              onStop: bot.stopVacancies,
            ),
          if (bot.vacRunning && bot.chatRunning) const SizedBox(width: 8),
          if (bot.chatRunning)
            _ProcChip(
              label: 'Ответы',
              tooltip: bot.chatStatus,
              stopping: bot.chatState == RunState.stopping,
              onOpen: () => appState.selectSection(AppSection.autoresponses),
              onStop: bot.stopChats,
            ),
        ],
      ),
    );
  }
}

class _ProcChip extends StatelessWidget {
  const _ProcChip({
    required this.label,
    required this.tooltip,
    required this.stopping,
    required this.onOpen,
    required this.onStop,
  });

  final String label;
  final String tooltip;
  final bool stopping;
  final VoidCallback onOpen;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Container(
            padding:
                const EdgeInsets.only(left: 12, right: 4, top: 5, bottom: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HhColors.red.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HhColors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Остановить',
                  visualDensity: VisualDensity.compact,
                  onPressed: stopping ? null : onStop,
                  icon: const Icon(Icons.stop_circle_outlined,
                      size: 18, color: HhColors.red),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
