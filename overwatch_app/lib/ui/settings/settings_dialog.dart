import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/role_manager.dart';
import '../../services/connection_service.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _passcodeController;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final rm = Provider.of<RoleManager>(context, listen: false);
    _hostController = TextEditingController(text: rm.serverHost);
    _portController = TextEditingController(text: rm.serverPort.toString());
    _passcodeController = TextEditingController(text: rm.passcode);
    _nameController = TextEditingController(text: rm.deviceName);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passcodeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rm = Provider.of<RoleManager>(context, listen: false);

    return Dialog(
      backgroundColor: AppConstants.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppConstants.cardBorderColor, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⚙️ Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppConstants.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: AppConstants.cardBorderColor),
              const SizedBox(height: 12),

              // Device Name
              _buildTextField(
                controller: _nameController,
                label: 'Device Label / Employee Name',
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 12),

              // Server Host & Port
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTextField(
                      controller: _hostController,
                      label: 'Master Server IP',
                      icon: Icons.lan_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _portController,
                      label: 'Port',
                      icon: Icons.numbers_outlined,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Passcode
              _buildTextField(
                controller: _passcodeController,
                label: 'Access Passcode',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 24),

              // Switch Role Action
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.backgroundDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppConstants.cardBorderColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: AppConstants.accentOrange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Active Mode',
                            style: TextStyle(fontSize: 11, color: AppConstants.textMuted),
                          ),
                          Text(
                            rm.currentRole == AppRole.manager
                                ? '🎛️ Manager Mode'
                                : '💻 Client Mode',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: AppConstants.accentOrange,
                        side: const BorderSide(color: AppConstants.accentOrange),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        rm.resetRole();
                      },
                      child: const Text('Switch Role'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Save Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppConstants.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.accentOrange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      final port = int.tryParse(_portController.text.trim()) ?? 8765;
                      final newHost = _hostController.text.trim();
                      final newPasscode = _passcodeController.text.trim();
                      final newDeviceName = _nameController.text.trim();

                      rm.updateNetworkSettings(
                        host: newHost,
                        port: port,
                        passcode: newPasscode,
                        deviceName: newDeviceName,
                      );

                      final conn = Provider.of<ConnectionService>(context, listen: false);
                      conn.disconnect();
                      conn.connect(
                        host: newHost,
                        port: port,
                        clientName: rm.currentRole == AppRole.manager
                            ? 'Manager-$newDeviceName'
                            : newDeviceName,
                        passcode: newPasscode,
                      );

                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Save Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppConstants.textMuted, fontSize: 12),
        prefixIcon: Icon(icon, color: AppConstants.textMuted, size: 20),
        filled: true,
        fillColor: AppConstants.backgroundDark,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppConstants.cardBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppConstants.accentOrange),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}
