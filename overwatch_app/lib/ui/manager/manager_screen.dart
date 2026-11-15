import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/role_manager.dart';
import '../../protocol/packets.dart';
import '../../services/connection_service.dart';
import '../settings/settings_dialog.dart';
import '../widgets/glass_card.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initConnection();
    });
  }

  void _initConnection() {
    final roleManager = Provider.of<RoleManager>(context, listen: false);
    final connectionService = Provider.of<ConnectionService>(context, listen: false);

    connectionService.connect(
      host: roleManager.serverHost,
      port: roleManager.serverPort,
      clientName: 'Manager-${roleManager.deviceName}',
      passcode: roleManager.passcode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = Provider.of<ConnectionService>(context);
    final screenWidth = MediaQuery.of(context).size.width;

    int crossAxisCount = 1;
    if (screenWidth >= 1200) {
      crossAxisCount = 3;
    } else if (screenWidth >= 650) {
      crossAxisCount = 2;
    }

    final clientsList = conn.clients.values.toList();

    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceDark,
        elevation: 0,
        title: Row(
          children: [
            const Text('🛡️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            const Text(
              'Overwatch Manager',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            _buildStatusPill(conn.status),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Broadcast Emergency Alert',
            icon: const Icon(Icons.warning_amber_rounded, color: AppConstants.accentOrange),
            onPressed: () {
              conn.sendEmergencyAlert();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚨 Emergency alert sent to all workstations!'),
                  backgroundColor: AppConstants.accentOrange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
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
      body: clientsList.isEmpty
          ? _buildEmptyState(conn)
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.45,
              ),
              itemCount: clientsList.length,
              itemBuilder: (context, index) {
                final client = clientsList[index];
                return _buildClientCard(context, client, conn);
              },
            ),
    );
  }

  Widget _buildStatusPill(ConnectionStatus status) {
    Color color = AppConstants.accentRed;
    String label = 'Offline';

    if (status == ConnectionStatus.authenticated) {
      color = AppConstants.accentGreen;
      label = 'Live';
    } else if (status == ConnectionStatus.connecting) {
      color = AppConstants.accentOrange;
      label = 'Connecting...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ConnectionService conn) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_outlined,
              size: 64,
              color: AppConstants.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              conn.status == ConnectionStatus.authenticated
                  ? 'Waiting for employee workstations to connect...'
                  : 'Connecting to Master WebSocket Server...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppConstants.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Server: ${Provider.of<RoleManager>(context, listen: false).serverHost}:${Provider.of<RoleManager>(context, listen: false).serverPort}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, color: AppConstants.accentOrange),
              label: const Text('Retry Connection', style: TextStyle(color: AppConstants.accentOrange)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppConstants.accentOrange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _initConnection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientCard(BuildContext context, ClientInfo client, ConnectionService conn) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      borderRadius: 12,
      onTap: () => _openExpandedViewer(context, client, conn),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stream Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  client.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${client.fps.toStringAsFixed(1)} FPS',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Stream Frame Box
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: client.latestFrame != null
                    ? Image.memory(
                        client.latestFrame!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      )
                    : const Center(
                        child: Text(
                          'No Signal',
                          style: TextStyle(color: AppConstants.textMuted, fontSize: 12),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openExpandedViewer(BuildContext context, ClientInfo client, ConnectionService conn) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpandedViewerScreen(client: client, conn: conn),
      ),
    );
  }
}

class ExpandedViewerScreen extends StatefulWidget {
  final ClientInfo client;
  final ConnectionService conn;

  const ExpandedViewerScreen({
    super.key,
    required this.client,
    required this.conn,
  });

  @override
  State<ExpandedViewerScreen> createState() => _ExpandedViewerScreenState();
}

class _ExpandedViewerScreenState extends State<ExpandedViewerScreen> {
  final GlobalKey _imageKey = GlobalKey();

  void _sendNormalizedClick(Offset globalPos, String button) {
    final renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPos = renderBox.globalToLocal(globalPos);
    final size = renderBox.size;

    if (localPos.dx < 0 || localPos.dy < 0 || localPos.dx > size.width || localPos.dy > size.height) {
      return;
    }

    final normX = localPos.dx / size.width;
    final normY = localPos.dy / size.height;

    widget.conn.sendRemoteInput(
      eventType: 'mouse_click',
      params: {
        'x': normX,
        'y': normY,
        'button': button,
      },
      targetClientId: widget.client.clientId,
    );
  }

  void _sendNormalizedMove(Offset globalPos) {
    final renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPos = renderBox.globalToLocal(globalPos);
    final size = renderBox.size;

    final normX = (localPos.dx / size.width).clamp(0.0, 1.0);
    final normY = (localPos.dy / size.height).clamp(0.0, 1.0);

    widget.conn.sendRemoteInput(
      eventType: 'mouse_move',
      params: {
        'x': normX,
        'y': normY,
      },
      targetClientId: widget.client.clientId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          widget.client.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                '${widget.client.fps.toStringAsFixed(1)} FPS • ${widget.client.width}x${widget.client.height}',
                style: const TextStyle(fontSize: 12, color: AppConstants.accentGreen),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onTapDown: (details) => _sendNormalizedClick(details.globalPosition, 'left'),
          onLongPressStart: (details) => _sendNormalizedClick(details.globalPosition, 'right'),
          onPanUpdate: (details) => _sendNormalizedMove(details.globalPosition),
          child: widget.client.latestFrame != null
              ? Image.memory(
                  widget.client.latestFrame!,
                  key: _imageKey,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                )
              : const Center(
                  child: Text(
                    'Waiting for stream...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
        ),
      ),
    );
  }
}
