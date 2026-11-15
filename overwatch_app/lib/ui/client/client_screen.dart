import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/role_manager.dart';
import '../../services/connection_service.dart';
import '../../services/native_screen_capture.dart';
import '../settings/settings_dialog.dart';
import '../widgets/glass_card.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  bool _isStreaming = false;
  StreamSubscription? _frameSubscription;
  bool _hasAutoStarted = false;
  int _sentFrameCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initConnection();
      _listenToNativeFrames();
    });
  }

  void _initConnection() {
    final roleManager = Provider.of<RoleManager>(context, listen: false);
    final connectionService = Provider.of<ConnectionService>(context, listen: false);

    connectionService.connect(
      host: roleManager.serverHost,
      port: roleManager.serverPort,
      clientName: roleManager.deviceName,
      passcode: roleManager.passcode,
    );
  }

  void _listenToNativeFrames() {
    _frameSubscription?.cancel();
    _frameSubscription = NativeScreenCapture.frameStream.listen(
      (data) {
        final frameBytes = data['frame'] as Uint8List?;
        final width = data['width'] as int? ?? 720;
        final height = data['height'] as int? ?? 1280;

        if (frameBytes != null && mounted) {
          final conn = Provider.of<ConnectionService>(context, listen: false);
          final rm = Provider.of<RoleManager>(context, listen: false);

          if (conn.status == ConnectionStatus.authenticated) {
            conn.sendFrameData(
              frameBytes: frameBytes,
              fps: 11.0,
              width: width,
              height: height,
              clientId: rm.deviceName,
            );
            setState(() {
              _sentFrameCount++;
              _isStreaming = true;
            });
          }
        }
      },
      onError: (err) {
        debugPrint('[ClientScreen] Frame stream error: $err');
      },
    );
  }

  Future<void> _startBroadcasting() async {
    final success = await NativeScreenCapture.startCapture();
    if (success && mounted) {
      setState(() {
        _isStreaming = true;
      });
      // Also request battery exemption so the app never gets killed in background
      await NativeScreenCapture.requestBatteryExemption();
    }
  }

  Future<void> _stopBroadcasting() async {
    await NativeScreenCapture.stopCapture();
    if (mounted) {
      setState(() {
        _isStreaming = false;
      });
    }
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleManager = Provider.of<RoleManager>(context);
    final conn = Provider.of<ConnectionService>(context);

    // Auto-start screen capture once authenticated with master server
    if (conn.status == ConnectionStatus.authenticated && !_hasAutoStarted && !_isStreaming) {
      _hasAutoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startBroadcasting();
      });
    }

    final isAlertActive = conn.activeAlertMessage != null;

    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceDark,
        elevation: 0,
        title: const Row(
          children: [
            Text('💻', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Overwatch Client',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings & Switch Role',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const SettingsDialog(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Connection Status Card
                    GlassCard(
                      borderColor: _getStatusColor(conn.status).withValues(alpha: 0.4),
                      focusedBorderColor: _getStatusColor(conn.status),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getStatusColor(conn.status).withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              _getStatusIcon(conn.status),
                              color: _getStatusColor(conn.status),
                              size: 42,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getStatusTitle(conn.status),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(conn.status),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            conn.status == ConnectionStatus.authenticated
                                ? (_isStreaming
                                    ? 'Live Screen Streaming Active ($_sentFrameCount frames sent)'
                                    : 'Connected to Master at ${roleManager.serverHost}:${roleManager.serverPort}')
                                : (conn.errorMessage.isNotEmpty
                                    ? conn.errorMessage
                                    : 'Searching for Master Server...'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: conn.status == ConnectionStatus.error
                                  ? AppConstants.accentRed
                                  : AppConstants.textMuted,
                            ),
                          ),
                          if (conn.status != ConnectionStatus.authenticated) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Retry Now'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppConstants.accentOrange,
                                  ),
                                  onPressed: () {
                                    conn.connect(
                                      host: roleManager.serverHost,
                                      port: roleManager.serverPort,
                                      clientName: roleManager.deviceName,
                                      passcode: roleManager.passcode,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Edit IP & Passcode'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppConstants.accentBlue,
                                  ),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => const SettingsDialog(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Device Info Details
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            'Device Label',
                            roleManager.deviceName,
                            Icons.devices,
                          ),
                          const Divider(color: AppConstants.cardBorderColor, height: 24),
                          _buildDetailRow(
                            'Master Server IP',
                            '${roleManager.serverHost}:${roleManager.serverPort}',
                            Icons.dns_outlined,
                          ),
                          const Divider(color: AppConstants.cardBorderColor, height: 24),
                          _buildDetailRow(
                            'Screen Status',
                            _isStreaming ? '🟢 Live Screen Broadcasting' : '⚪ Standby',
                            Icons.screen_share_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Battery / Background Persistence Action Card
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      borderColor: AppConstants.accentOrange.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          const Icon(Icons.battery_saver, color: AppConstants.accentOrange, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Background Persistence',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Prevent OS from killing screen stream in background',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppConstants.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppConstants.accentOrange,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () async {
                              await NativeScreenCapture.requestBatteryExemption();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Battery optimization exemption requested'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            child: const Text('Enable', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Toggle Screen Broadcast Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isStreaming ? AppConstants.accentRed : AppConstants.accentGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_isStreaming ? Icons.stop_circle_outlined : Icons.screen_share_outlined),
                      label: Text(
                        _isStreaming ? 'Stop Screen Broadcast' : 'Start Screen Broadcast',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: conn.status == ConnectionStatus.authenticated
                          ? () {
                              if (_isStreaming) {
                                _stopBroadcasting();
                              } else {
                                _startBroadcasting();
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Switch Role shortcut
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppConstants.cardBorderColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.swap_horiz, color: AppConstants.accentOrange),
                      label: const Text(
                        'Switch to Manager Mode',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        _stopBroadcasting();
                        conn.disconnect();
                        roleManager.resetRole();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Neon Alert Border if emergency alert triggered
          if (isAlertActive)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppConstants.accentRed,
                      width: 12,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppConstants.accentRed, width: 2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppConstants.accentRed, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            conn.activeAlertMessage ?? 'EMERGENCY ALERT',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.authenticated:
        return AppConstants.accentGreen;
      case ConnectionStatus.connecting:
        return AppConstants.accentOrange;
      default:
        return AppConstants.accentRed;
    }
  }

  IconData _getStatusIcon(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.authenticated:
        return Icons.check_circle_outline;
      case ConnectionStatus.connecting:
        return Icons.sync;
      default:
        return Icons.error_outline;
    }
  }

  String _getStatusTitle(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.authenticated:
        return 'Online & Connected';
      case ConnectionStatus.connecting:
        return 'Connecting to Master...';
      default:
        return 'Disconnected';
    }
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppConstants.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppConstants.textMuted),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
