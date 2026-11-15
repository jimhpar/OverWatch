import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'core/role_manager.dart';
import 'services/connection_service.dart';
import 'ui/client/client_screen.dart';
import 'ui/manager/manager_screen.dart';
import 'ui/role_selection_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverwatchApp());
}

class OverwatchApp extends StatelessWidget {
  const OverwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RoleManager()),
        ChangeNotifierProvider(create: (_) => ConnectionService()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppConstants.backgroundDark,
          primaryColor: AppConstants.accentOrange,
          colorScheme: const ColorScheme.dark(
            primary: AppConstants.accentOrange,
            secondary: AppConstants.accentBlue,
            surface: AppConstants.surfaceDark,
          ),
          fontFamily: 'Roboto',
        ),
        home: const AppRootRouter(),
      ),
    );
  }
}

class AppRootRouter extends StatelessWidget {
  const AppRootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final roleManager = Provider.of<RoleManager>(context);

    // If role manager is still loading saved preferences from disk
    if (!roleManager.isInitialized) {
      return const Scaffold(
        backgroundColor: AppConstants.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppConstants.accentOrange),
        ),
      );
    }

    // Role Router
    switch (roleManager.currentRole) {
      case AppRole.manager:
        return const ManagerScreen();
      case AppRole.client:
        return const ClientScreen();
      case AppRole.unselected:
        return const RoleSelectionScreen();
    }
  }
}
