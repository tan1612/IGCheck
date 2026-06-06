import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/pairing/pairing_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/ig_request/create_ig_request_screen.dart';
import 'screens/ig_request/ig_request_detail_screen.dart';
import 'screens/ig_request/edit_ig_request_screen.dart';
import 'screens/ig_request/fullscreen_image_screen.dart';

class IGCheckApp extends StatelessWidget {
  const IGCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => FirestoreService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        title: 'IGCheck / PairIG Review',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/pairing': (context) => const PairingScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/create_ig_request': (context) => const CreateIGRequestScreen(),
          '/ig_request_detail': (context) => const IGRequestDetailScreen(),
          '/edit_ig_request': (context) => const EditIGRequestScreen(),
          '/fullscreen_image': (context) => const FullscreenImageScreen(),
        },
      ),
    );
  }
}
