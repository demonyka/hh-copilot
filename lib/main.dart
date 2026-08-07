import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/authenticated_shell.dart';
import 'screens/login_browser.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'state/autoresponder_controller.dart';
import 'state/interviews_controller.dart';
import 'state/settings_controller.dart';
import 'state/update_controller.dart';
import 'theme/hh_theme.dart';
import 'widgets/hh_logo.dart';
import 'widgets/update_banner.dart';

void main() {
  runApp(const HhCopilotApp());
}

class HhCopilotApp extends StatelessWidget {
  const HhCopilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => UpdateController()),
        ChangeNotifierProvider(
            create: (ctx) => AutoresponderController(ctx.read<AppState>())),
        // lazy:false — контроллер должен существовать сразу, чтобы движок
        // чатов сразу отдавал ему сообщения работодателей для детекта.
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) => InterviewsController(
            bot: ctx.read<AutoresponderController>(),
            settings: ctx.read<SettingsController>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'hh·copilot',
        debugShowCheckedModeBanner: false,
        theme: HhTheme.light(),
        home: const HomeShell(),
      ),
    );
  }
}

/// Корневой каркас. Встроенный браузер hh.ru всегда живёт в основании стека;
/// поверх него по состоянию показываем сплэш, список резюме или экран ошибки.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final status = appState.status;

    return Column(
      children: [
        const UpdateBanner(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Основание: живой hh.ru-браузер (виден только при needLogin).
              const LoginBrowser(),

              // Непрозрачные экраны поверх браузера.
              if (status == AppStatus.initializing)
                const Positioned.fill(child: SplashScreen()),
              if (status == AppStatus.busy)
                Positioned.fill(
                    child: SplashScreen(message: appState.busyMessage)),
              if (status == AppStatus.authenticated)
                const Positioned.fill(child: AuthenticatedShell()),
              if (status == AppStatus.error)
                const Positioned.fill(child: _ErrorScreen()),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Scaffold(
      backgroundColor: HhColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HhLogoMark(size: 56),
              const SizedBox(height: 24),
              const Text(
                'Что-то пошло не так',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: HhColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appState.errorMessage ??
                    'Не удалось связаться с hh.ru. Проверьте соединение и попробуйте снова.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: HhColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: appState.retry,
                child: const Text('Попробовать снова'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
