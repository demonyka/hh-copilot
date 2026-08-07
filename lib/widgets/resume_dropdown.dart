import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hh_profile.dart';
import '../state/app_state.dart';
import '../theme/hh_theme.dart';

/// Красивый дропдаун выбора резюме для шапки. От выбора зависят аналитика и чаты.
class ResumeDropdown extends StatelessWidget {
  const ResumeDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final resumes = appState.resumes;
    final selected = appState.selectedResume;

    if (resumes.isEmpty) {
      return _pill(
        context,
        title: 'Нет резюме',
        subtitle: null,
        enabled: false,
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Выбрать резюме',
      offset: const Offset(0, 52),
      color: HhColors.surface,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HhColors.border),
      ),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
      onSelected: (hash) {
        final resume = resumes.firstWhere((r) => r.hash == hash,
            orElse: () => resumes.first);
        appState.selectResume(resume);
      },
      itemBuilder: (context) => [
        for (final r in resumes)
          PopupMenuItem<String>(
            value: r.hash,
            child: _MenuRow(
              resume: r,
              selected: r.hash == selected?.hash,
            ),
          ),
      ],
      child: _pill(
        context,
        title: selected?.title.isNotEmpty == true
            ? selected!.title
            : 'Выберите резюме',
        subtitle: selected == null
            ? null
            : [
                if (selected.area.isNotEmpty) selected.area,
                if (selected.hasSalary) selected.salaryLabel,
              ].join(' · '),
        enabled: true,
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required String title,
    required String? subtitle,
    required bool enabled,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: HhColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: HhColors.red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description_outlined,
                size: 17, color: HhColors.red),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: enabled ? HhColors.textPrimary : HhColors.textMuted,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: HhColors.textSecondary),
                  ),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 6),
            const Icon(Icons.expand_more,
                size: 20, color: HhColors.textSecondary),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.resume, required this.selected});

  final HhResume resume;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resume.title.isEmpty ? 'Без названия' : resume.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: HhColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (resume.area.isNotEmpty) resume.area,
                  resume.salaryLabel,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: HhColors.textSecondary),
              ),
            ],
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 10),
          const Icon(Icons.check, size: 18, color: HhColors.red),
        ],
      ],
    );
  }
}
