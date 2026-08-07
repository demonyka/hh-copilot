import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/hh_theme.dart';

/// Раздел «Чаты» — встроенный мессенджер hh.ru (chatik).
///
/// Переиспользуем реальный виджет переписок hh (список всех чатов + ответы в
/// реальном времени через его же вебсокеты). Веб-вью авторизован теми же
/// cookies `.hh.ru`, что и основная сессия.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  /// Мессенджер hh (тот же адрес, что hh встраивает в iframe чата).
  static const String chatUrl = 'https://chatik.hh.ru/?platform=xhh&dest=iframe';

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Column(
      children: [
        if (_progress > 0 && _progress < 1)
          LinearProgressIndicator(
            value: _progress,
            minHeight: 2.5,
            backgroundColor: HhColors.surfaceMuted,
          )
        else
          const SizedBox(height: 2.5),
        Expanded(
          child: InAppWebView(
            key: ValueKey('chats-${appState.chatsReloadCounter}'),
            initialUrlRequest:
                URLRequest(url: WebUri(ChatsScreen.chatUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              supportZoom: false,
              thirdPartyCookiesEnabled: true,
              cacheEnabled: true,
              isInspectable: true,
            ),
            onWebViewCreated: appState.attachChatController,
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() => _progress = progress / 100);
            },
          ),
        ),
      ],
    );
  }
}
