import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/hh_theme.dart';
import 'hh_logo.dart';

/// Узкий левый сайдбар только с иконками (без подписей).
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: HhColors.surface,
        border: Border(right: BorderSide(color: HhColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const HhLogoMark(size: 34),
          const SizedBox(height: 24),
          _SidebarButton(
            icon: Icons.insights_rounded,
            tooltip: 'Аналитика',
            selected: appState.section == AppSection.analytics,
            onTap: () => appState.selectSection(AppSection.analytics),
          ),
          _SidebarButton(
            icon: Icons.forum_outlined,
            tooltip: 'Чаты',
            selected: appState.section == AppSection.chats,
            onTap: () => appState.selectSection(AppSection.chats),
          ),
          _SidebarButton(
            icon: Icons.smart_toy_outlined,
            tooltip: 'Автоотклики',
            selected: appState.section == AppSection.autoresponses,
            onTap: () => appState.selectSection(AppSection.autoresponses),
          ),
          _SidebarButton(
            icon: Icons.event_available_outlined,
            tooltip: 'Собеседования',
            selected: appState.section == AppSection.interviews,
            onTap: () => appState.selectSection(AppSection.interviews),
          ),
          const Spacer(),
          _SidebarButton(
            icon: Icons.settings_outlined,
            tooltip: 'Настройки',
            selected: appState.section == AppSection.settings,
            onTap: () => appState.selectSection(AppSection.settings),
          ),
          const SizedBox(height: 10),
          const Divider(
              height: 1, thickness: 1, indent: 14, endIndent: 14),
          const SizedBox(height: 10),
          const _SidebarAccount(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Аватар аккаунта внизу сайдбара с меню (профиль + выход).
class _SidebarAccount extends StatelessWidget {
  const _SidebarAccount();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final account = appState.account;
    final initials = account?.initials ?? '?';

    return PopupMenuButton<String>(
      tooltip: 'Аккаунт',
      offset: const Offset(56, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'logout') appState.logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (account?.fullName.isNotEmpty ?? false)
                    ? account!.fullName
                    : 'Аккаунт hh.ru',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: HhColors.textPrimary),
              ),
              if (account?.email.isNotEmpty ?? false)
                Text(account!.email,
                    style: const TextStyle(
                        fontSize: 12, color: HhColors.textSecondary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: HhColors.red),
              SizedBox(width: 10),
              Text('Выйти', style: TextStyle(color: HhColors.red)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: HhColors.red,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  const _SidebarButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final Color bg = selected
        ? const Color(0xFFFFECEE)
        : (_hovered ? HhColors.surfaceMuted : Colors.transparent);
    final Color fg = selected ? HhColors.red : HhColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, size: 24, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
