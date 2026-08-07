import 'package:flutter/material.dart';

import '../theme/hh_theme.dart';
import '../widgets/hh_logo.dart';

/// Стартовый экран: пока проверяем, есть ли живая hh.ru-сессия.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.message = 'Подключение к hh.ru…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HhColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HhLogoMark(size: 64),
            const SizedBox(height: 28),
            const HhWordmark(markSize: 26),
            const SizedBox(height: 36),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: HhColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
