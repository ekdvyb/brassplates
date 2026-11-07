import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../features/vault/vault_screen.dart';
import '../widgets/common.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class BrassPlatesApp extends ConsumerStatefulWidget {
  const BrassPlatesApp({super.key});

  @override
  ConsumerState<BrassPlatesApp> createState() => _BrassPlatesAppState();
}

class _BrassPlatesAppState extends ConsumerState<BrassPlatesApp>
    with WidgetsBindingObserver {
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(appSettingsProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (settings.autoLockMinutes > 0) {
        _lockTimer?.cancel();
        _lockTimer = Timer(Duration(minutes: settings.autoLockMinutes), () {
          if (mounted) {
            ref.read(vaultProvider.notifier).lock();
          }
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _lockTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final vault = ref.watch(vaultProvider);
    final router = ref.watch(routerProvider);

    final light = AppTheme.light(fontScale: settings.fontScale);
    final dark = AppTheme.dark(fontScale: settings.fontScale);

    if (vault.checking) {
      return MaterialApp(
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: settings.themeMode,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 52),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 14),
                Text(
                  'Opening your workspace…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!vault.initialized || !vault.unlocked) {
      return MaterialApp(
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: settings.themeMode,
        home: const VaultScreen(),
      );
    }

    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(settings.fontScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
