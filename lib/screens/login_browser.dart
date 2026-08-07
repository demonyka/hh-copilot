import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/hh_theme.dart';

/// Долгоживущий встроенный браузер hh.ru.
///
/// Он всегда присутствует в дереве в одной и той же позиции (даже когда сверху
/// показан список резюме), чтобы держать живую hh.ru-сессию и выполнять `fetch`
/// от имени пользователя. Виден только на этапе входа — в остальное время его
/// перекрывает непрозрачный экран поверх.
///
/// На экране входа никакого хедбара нет — только красная плашка с подсказкой
/// и сама форма hh.ru.
class LoginBrowser extends StatefulWidget {
  const LoginBrowser({super.key});

  @override
  State<LoginBrowser> createState() => _LoginBrowserState();
}

class _LoginBrowserState extends State<LoginBrowser> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    // ВАЖНО: сам InAppWebView всегда на одной и той же позиции в дереве,
    // иначе Flutter пересоздаст нативный веб-вью и hh.ru-сессия сбросится.
    final webView = InAppWebView(
      key: const ValueKey('hh-session-webview'),
      initialUrlRequest: URLRequest(url: WebUri(AppState.resumesUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        supportZoom: false,
        thirdPartyCookiesEnabled: true,
        clearCache: false,
        cacheEnabled: true,
        isInspectable: true,
      ),
      onWebViewCreated: appState.attachController,
      onLoadStart: (controller, url) {
        // Как только уходим с формы входа — прячем браузер (см. AppState),
        // чтобы страница hh.ru не мелькнула перед списком резюме.
        appState.onNavigationStart(url?.toString());
      },
      onLoadStop: (controller, url) {
        appState.onPageEvent(url?.toString());
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        appState.onPageEvent(url?.toString());
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? true) {
          appState.reportLoadError(error.description);
        }
      },
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() => _progress = progress / 100);
      },
    );

    return Scaffold(
      backgroundColor: HhColors.surface,
      body: Column(
        children: [
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2.5,
              backgroundColor: HhColors.surfaceMuted,
            )
          else
            const SizedBox(height: 2.5),
          const _LoginHint(),
          Expanded(
            child: ClipRect(child: webView),
          ),
        ],
      ),
    );
  }
}

/// Красная плашка над формой входа: единственная «обвязка» на экране входа.
class _LoginHint extends StatelessWidget {
  const _LoginHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFFFFF4F5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: HhColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Вход в аккаунт hh.ru',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: HhColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Войдите как соискатель — сразу после входа мы покажем ваши резюме. '
                  'Сессия hh.ru остаётся только на этом устройстве.',
                  style: TextStyle(
                    fontSize: 13,
                    color: HhColors.textPrimary.withValues(alpha: 0.8),
                    height: 1.35,
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
