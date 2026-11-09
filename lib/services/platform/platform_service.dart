import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_auth/local_auth.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/legacy.dart' as legacy;

import '../../core/constants.dart';

class SharedContent {
  const SharedContent({this.text = '', this.filePaths = const []});
  final String text;
  final List<String> filePaths;
}

class PlatformService with TrayListener, legacy.WindowListener {
  PlatformService._();
  static final PlatformService instance = PlatformService._();

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  final _localAuth = LocalAuthentication();
  final _notifications = FlutterLocalNotificationsPlugin();

  /// When true the window close button hides to the tray instead of quitting.
  bool minimizeToTray = false;

  Future<void> initDesktop({
    VoidCallback? onOpen,
    VoidCallback? onQuit,
    VoidCallback? onQuickNote,
  }) async {
    if (!isDesktop) return;
    try {
      await legacy.windowManager.ensureInitialized();
      final options = legacy.WindowOptions(
        size: const Size(1280, 820),
        minimumSize: const Size(900, 600),
        center: true,
        title: AppInfo.name,
      );
      await legacy.windowManager.waitUntilReadyToShow(options, () async {
        await legacy.windowManager.show();
        await legacy.windowManager.setPreventClose(true);
      });
      legacy.windowManager.addListener(this);
      trayManager.addListener(this);
      await _setupTray(onOpen, onQuit, onQuickNote);
      LaunchAtStartup.instance.setup(
        appName: AppInfo.name,
        appPath: Platform.resolvedExecutable,
      );
      try {
        final hotKey = HotKey(
          identifier: 'brassplates-open',
          key: LogicalKeyboardKey.keyB,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
          scope: HotKeyScope.system,
        );
        await HotKeyManager.instance.register(
          hotKey,
          keyDownHandler: (_) => onOpen?.call(),
        );
      } catch (_) {
        // Global hotkeys are not available on every Linux compositor.
      }
    } catch (_) {
      // Desktop shell features are best-effort; never block startup.
    }
  }

  Future<void> _setupTray(
    VoidCallback? onOpen,
    VoidCallback? onQuit,
    VoidCallback? onQuickNote,
  ) async {
    try {
      final icon = Platform.isWindows
          ? 'assets/icons/tray_icon.ico'
          : 'assets/icons/tray_icon.png';
      await trayManager.setIcon(icon);
      await trayManager.setToolTip(AppInfo.name);
      final menu = Menu(
        items: [
          MenuItem(key: 'open', label: 'Show ${AppInfo.name}'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      );
      await trayManager.setContextMenu(menu);
      _trayActions = {
        'open': onOpen,
        'quit': onQuit,
      };
    } catch (_) {}
  }

  Map<String, VoidCallback?> _trayActions = {};

  Future<void> showWindow() async {
    await legacy.windowManager.show();
    await legacy.windowManager.focus();
  }

  Future<void> toggleWindow() async {
    if (await legacy.windowManager.isVisible()) {
      await legacy.windowManager.hide();
    } else {
      await showWindow();
    }
  }

  Future<void> quit() async {
    try {
      await HotKeyManager.instance.unregisterAll();
    } catch (_) {}
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (_) {}
    try {
      await legacy.windowManager.setPreventClose(false);
      await legacy.windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  @override
  void onWindowClose() {
    if (minimizeToTray) {
      legacy.windowManager.hide();
    } else {
      quit();
    }
  }

  @override
  void onTrayIconMouseDown() {
    toggleWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final action = _trayActions[menuItem.key];
    if (menuItem.key == 'quit') {
      action?.call();
      return;
    }
    await showWindow();
    action?.call();
  }

  Future<void> disposeDesktop() async {
    if (!isDesktop) return;
    trayManager.removeListener(this);
    try {
      await HotKeyManager.instance.unregisterAll();
    } catch (_) {}
  }

  Future<void> setStartup(bool enabled) async {
    if (!isDesktop || Platform.isLinux) return;
    try {
      if (enabled) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
    } catch (_) {}
  }

  Future<bool> biometricsAvailable() async {
    if (!isAndroid && !Platform.isMacOS && !Platform.isWindows) return false;
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> initNotifications() async {
    if (!isAndroid) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notifications.initialize(
        settings: const InitializationSettings(android: android),
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> showNotification(String title, String body) async {
    if (!isAndroid) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'brassplates_reminders',
          'Reminders',
          channelDescription: 'Task and sync reminders from BRASSPLATES',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      await _notifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  Future<SharedContent?> consumeInitialShare() async {
    if (!isAndroid) return null;
    try {
      final items = await ReceiveSharingIntent.instance.getInitialMedia();
      if (items.isEmpty) return null;
      await ReceiveSharingIntent.instance.reset();
      return _toContent(items);
    } catch (_) {
      return null;
    }
  }

  Stream<SharedContent> shareStream() {
    if (!isAndroid) return const Stream.empty();
    return ReceiveSharingIntent.instance
        .getMediaStream()
        .map(_toContent)
        .where(
          (content) => content.text.isNotEmpty || content.filePaths.isNotEmpty,
        );
  }

  SharedContent _toContent(List<SharedMediaFile> items) {
    final text = items
        .where(
          (f) =>
              f.type == SharedMediaType.text || f.type == SharedMediaType.url,
        )
        .map((f) => f.path)
        .join('\n');
    final files = items
        .where(
          (f) =>
              f.type == SharedMediaType.image || f.type == SharedMediaType.file,
        )
        .map((f) => f.path)
        .toList();
    return SharedContent(text: text, filePaths: files);
  }

  Future<void> enableScreenProtection(bool enabled) async {
    if (!isAndroid) return;
    try {
      const channel = MethodChannel('com.zerobug.brassplates/protection');
      await channel.invokeMethod('setSecure', {'enabled': enabled});
    } catch (_) {}
  }
}
