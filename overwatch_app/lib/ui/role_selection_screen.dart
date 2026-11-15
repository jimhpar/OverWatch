import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/role_manager.dart';
import 'widgets/glass_card.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roleManager = Provider.of<RoleManager>(context, listen: false);
    final isWide = MediaQuery.of(context).size.width >= 650;

    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // App Logo / Icon Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.surfaceDark,
                    border: Border.all(
                      color: AppConstants.accentOrange.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.accentOrange.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Text(
                    '🛡️',
                    style: TextStyle(fontSize: 48),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: AppConstants.accentOrange,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose your installation mode',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppConstants.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'by ${AppConstants.publisher} • v${AppConstants.appVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 36),

                // Cards: Manager Mode & Client Mode
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: isWide
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _buildRoleCard(
                                context: context,
                                icon: '🎛️',
                                title: 'Manager Mode',
                                subtitle: 'Master Dashboard',
                                description:
                                    'Monitor live screens in real-time, control remote PCs, send emergency alerts, and broadcast presentations.',
                                accentColor: AppConstants.accentOrange,
                                autofocus: true,
                                onSelect: () => roleManager.setRole(AppRole.manager),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildRoleCard(
                                context: context,
                                icon: '💻',
                                title: 'Client Mode',
                                subtitle: 'Employee Client',
                                description:
                                    'Stream this screen to the manager, receive technical support, and view presentations securely on LAN.',
                                accentColor: AppConstants.accentBlue,
                                autofocus: false,
                                onSelect: () => roleManager.setRole(AppRole.client),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildRoleCard(
                              context: context,
                              icon: '🎛️',
                              title: 'Manager Mode',
                              subtitle: 'Master Dashboard',
                              description:
                                    'Monitor live screens in real-time, control remote PCs, send emergency alerts, and broadcast presentations.',
                              accentColor: AppConstants.accentOrange,
                              autofocus: true,
                              onSelect: () => roleManager.setRole(AppRole.manager),
                            ),
                            const SizedBox(height: 20),
                            _buildRoleCard(
                              context: context,
                              icon: '💻',
                              title: 'Client Mode',
                              subtitle: 'Employee Client',
                              description:
                                    'Stream this screen to the manager, receive technical support, and view presentations securely on LAN.',
                              accentColor: AppConstants.accentBlue,
                              autofocus: false,
                              onSelect: () => roleManager.setRole(AppRole.client),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 32),
                const Text(
                  '💡 You can switch modes anytime later from in-app settings.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String icon,
    required String title,
    required String subtitle,
    required String description,
    required Color accentColor,
    required bool autofocus,
    required VoidCallback onSelect,
  }) {
    return GlassCard(
      autofocus: autofocus,
      focusedBorderColor: accentColor,
      borderColor: accentColor.withValues(alpha: 0.3),
      onTap: onSelect,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppConstants.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFCBD5E1),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: onSelect,
              child: Text(
                'Select $title',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
