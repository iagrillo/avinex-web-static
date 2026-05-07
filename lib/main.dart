import 'package:flutter/widgets.dart';
import 'session_timeout_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'services/notification_service.dart';
import 'core/config/supabase_keys.dart';
import 'core/theme/theme_controller.dart';
import 'dart:js' as js;

// Use a top-level navigatorKey so it persists across app restarts/logouts
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.init();
  // DEBUG: Print env values to browser console
  print('SUPABASE_URL: [32m${SupabaseKeys.url}[0m');
  print('SUPABASE_ANON_KEY: [32m${SupabaseKeys.anonKey}[0m');
  // JS interop for browser console
  js.context.callMethod('console.log', ['SUPABASE_URL (JS): ${SupabaseKeys.url}']);
  js.context.callMethod('console.log', ['SUPABASE_ANON_KEY (JS): ${SupabaseKeys.anonKey}']);
  await Supabase.initialize(
    url: SupabaseKeys.url,
    anonKey: SupabaseKeys.anonKey,
  );

  await NotificationService.initialize(navigatorKey);
  await NotificationService.clearAllNotifications();
  NotificationService.configureSelectNotificationHandler(navigatorKey);

  runApp(
    SessionTimeoutManager(
      timeout: Duration(minutes: 5),
      warningDuration: Duration(seconds: 30),
      navigatorKey: navigatorKey,
      onTimeout: () async {
        await Supabase.instance.client.auth.signOut();
        NotificationService.configureSelectNotificationHandler(navigatorKey);
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
      },
      child: AvinexEscrowApp(navigatorKey: navigatorKey),
    ),
  );
}
