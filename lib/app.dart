import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'state/settings_controller.dart';
import 'ui/shell/app_shell.dart';

/// 应用根组件：主题、本地化与外壳。
class EchoScorerApp extends StatelessWidget {
  const EchoScorerApp({this.windowCloseGuard = false, super.key});

  /// Windows 桌面上是否拦截窗口关闭以提示保存未保存的改动。
  final bool windowCloseGuard;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.seedColor),
      darkTheme: AppTheme.dark(settings.seedColor),
      themeMode: settings.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: const Locale('zh', 'CN'),
      home: AppShell(windowCloseGuard: windowCloseGuard),
    );
  }
}
