import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/update_controller.dart';
import '../theme/hh_theme.dart';

/// Тонкая полоса вверху приложения, когда доступно обновление.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<UpdateController>();
    final info = controller.available;
    if (info == null) return const SizedBox.shrink();

    return Material(
      color: HhColors.red,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Доступна новая версия ${info.version} '
                  '(у вас ${info.currentVersion})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(info.pageUrl),
                    mode: LaunchMode.externalApplication),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Что нового'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => launchUrl(Uri.parse(info.downloadUrl),
                    mode: LaunchMode.externalApplication),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: HhColors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 30),
                ),
                child: const Text('Обновить'),
              ),
              IconButton(
                tooltip: 'Скрыть',
                onPressed: controller.dismiss,
                icon: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
