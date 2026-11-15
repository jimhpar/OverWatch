import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/packets.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  authenticated,
  error,
}

class ConnectionService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _connectTimeoutTimer;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _errorMessage = '';
  final Map<String, ClientInfo> _clients = {};
  String? _activeAlertMessage;

  ConnectionStatus get status => _status;
  String get errorMessage => _errorMessage;
  Map<String, ClientInfo> get clients => _clients;
  String? get activeAlertMessage => _activeAlertMessage;

  void connect({
    required String host,
    required int port,
    required String clientName,
    required String passcode,
  }) {
    if (_status == ConnectionStatus.authenticated) {
      return;
    }

    _cleanupSocket();
    _reconnectTimer?.cancel();
    _status = ConnectionStatus.connecting;
    _errorMessage = 'Attempting connection to ws://$host:$port...';
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);

      // Connect timeout check
      _connectTimeoutTimer?.cancel();
      _connectTimeoutTimer = Timer(const Duration(seconds: 8), () {
        if (_status == ConnectionStatus.connecting) {
          _handleError(
            'Connection timed out. Could not reach $host:$port. Ensure master server is running and both devices are on the same Wi-Fi.',
            host,
            port,
            clientName,
            passcode,
            autoReconnect: true,
          );
        }
      });

      _channelSubscription = _channel!.stream.listen(
        (data) {
          _connectTimeoutTimer?.cancel();
          _handleIncomingData(data);
        },
        onError: (err) {
          _connectTimeoutTimer?.cancel();
          _handleError(
            'Connection error ($err). Check if IP $host:$port is reachable.',
            host,
            port,
            clientName,
            passcode,
            autoReconnect: true,
          );
        },
        onDone: () {
          _connectTimeoutTimer?.cancel();
          _handleDone(host, port, clientName, passcode);
        },
      );

      // Send initial authentication request
      final authPacket = ProtocolHelper.createAuthRequest(
        clientName: clientName,
        hostname: 'Android-Device',
        ipAddress: '127.0.0.1',
        passcode: passcode,
      );
      _channel!.sink.add(authPacket);

      // Start periodic heartbeat
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_status == ConnectionStatus.authenticated) {
          _channel?.sink.add(ProtocolHelper.createHeartbeat(clientName));
        }
      });
    } catch (e) {
      _connectTimeoutTimer?.cancel();
      _handleError(
        'Failed to connect: $e',
        host,
        port,
        clientName,
        passcode,
        autoReconnect: true,
      );
    }
  }

  void _handleIncomingData(dynamic rawData) {
    try {
      final json = jsonDecode(rawData as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == PacketType.authResp) {
        final success = json['success'] == true;
        if (success) {
          _status = ConnectionStatus.authenticated;
          _errorMessage = '';
        } else {
          _status = ConnectionStatus.error;
          final msg = json['message']?.toString() ?? 'Passcode mismatch';
          _errorMessage = 'Authentication Rejected: $msg. Please verify Passcode in settings.';
          _cleanupSocket();
        }
        notifyListeners();
      } else if (type == PacketType.frameData) {
        final frame = FramePacket.fromJson(json);
        if (!_clients.containsKey(frame.clientId)) {
          _clients[frame.clientId] = ClientInfo(
            clientId: frame.clientId,
            name: frame.clientId,
            hostname: 'Workstation',
            ipAddress: 'LAN',
          );
        }
        final client = _clients[frame.clientId]!;
        client.latestFrame = frame.imageBytes;
        client.fps = frame.fps;
        client.width = frame.width;
        client.height = frame.height;
        client.lastSeen = DateTime.now();
        notifyListeners();
      } else if (type == PacketType.clientListUpdate) {
        final list = json['clients'] as List<dynamic>? ?? [];
        final updatedIds = <String>{};
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final info = ClientInfo.fromJson(item);
            updatedIds.add(info.clientId);
            if (!_clients.containsKey(info.clientId)) {
              _clients[info.clientId] = info;
            } else {
              _clients[info.clientId]!.fps = info.fps;
            }
          }
        }
        _clients.removeWhere((id, _) => !updatedIds.contains(id));
        notifyListeners();
      } else if (type == PacketType.alert) {
        _activeAlertMessage = 'Emergency Admin Alert Triggered!';
        notifyListeners();
        Future.delayed(const Duration(seconds: 4), () {
          _activeAlertMessage = null;
          notifyListeners();
        });
      }
    } catch (e) {
      debugPrint('[ConnectionService] Error parsing packet: $e');
    }
  }

  void sendRemoteInput({
    required String eventType,
    required Map<String, dynamic> params,
    String? targetClientId,
  }) {
    if (_status == ConnectionStatus.authenticated && _channel != null) {
      final packet = ProtocolHelper.createRemoteInput(
        eventType: eventType,
        params: params,
        targetClientId: targetClientId,
      );
      _channel!.sink.add(packet);
    }
  }

  void sendEmergencyAlert() {
    if (_status == ConnectionStatus.authenticated && _channel != null) {
      final packet = ProtocolHelper.createAlertPacket();
      _channel!.sink.add(packet);
    }
  }

  void sendFrameData({
    required Uint8List frameBytes,
    required double fps,
    required int width,
    required int height,
    required String clientId,
  }) {
    if (_status == ConnectionStatus.authenticated && _channel != null) {
      final packet = ProtocolHelper.createFramePacket(
        clientId: clientId,
        frameBytes: frameBytes,
        fps: fps,
        width: width,
        height: height,
      );
      _channel!.sink.add(packet);
    }
  }

  void _handleError(
    String err,
    String host,
    int port,
    String clientName,
    String passcode, {
    bool autoReconnect = true,
  }) {
    _status = ConnectionStatus.error;
    _errorMessage = err;
    _cleanupSocket();
    notifyListeners();
    if (autoReconnect) {
      _scheduleReconnect(host, port, clientName, passcode);
    }
  }

  void _handleDone(String host, int port, String clientName, String passcode) {
    if (_status == ConnectionStatus.authenticated) {
      _status = ConnectionStatus.disconnected;
      _errorMessage = 'Server disconnected.';
      _cleanupSocket();
      notifyListeners();
      _scheduleReconnect(host, port, clientName, passcode);
    }
  }

  void _scheduleReconnect(String host, int port, String clientName, String passcode) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_status != ConnectionStatus.authenticated) {
        debugPrint('[ConnectionService] Attempting automatic reconnection...');
        connect(
          host: host,
          port: port,
          clientName: clientName,
          passcode: passcode,
        );
      }
    });
  }

  void disconnect() {
    _connectTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _status = ConnectionStatus.disconnected;
    _errorMessage = '';
    _cleanupSocket();
    notifyListeners();
  }

  void _cleanupSocket() {
    _connectTimeoutTimer?.cancel();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  void dispose() {
    _connectTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _cleanupSocket();
    super.dispose();
  }
}
