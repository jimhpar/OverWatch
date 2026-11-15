import 'dart:convert';
import 'dart:typed_data';

class PacketType {
  // Client -> Server
  static const String authReq = "AUTH_REQ";
  static const String frameData = "FRAME_DATA";
  static const String heartbeat = "HEARTBEAT";
  static const String shareStreamInput = "SHARE_STREAM_INPUT";
  static const String peerShareReq = "PEER_SHARE_REQ";
  static const String peerPromptResp = "PEER_PROMPT_RESP";

  // Server -> Client
  static const String authResp = "AUTH_RESP";
  static const String remoteInput = "REMOTE_INPUT";
  static const String qualityUpdate = "QUALITY_UPDATE";
  static const String disconnectCmd = "DISCONNECT_CMD";
  static const String alert = "ALERT";
  static const String shareStreamStart = "SHARE_STREAM_START";
  static const String shareStreamFrame = "SHARE_STREAM_FRAME";
  static const String shareStreamStop = "SHARE_STREAM_STOP";
  static const String clientListUpdate = "CLIENT_LIST_UPDATE";
  static const String cursorUpdate = "CURSOR_UPDATE";
}

class FramePacket {
  final String clientId;
  final Uint8List imageBytes;
  final double fps;
  final int width;
  final int height;
  final bool isStatic;
  final Map<String, dynamic>? cursor;
  final double timestamp;

  FramePacket({
    required this.clientId,
    required this.imageBytes,
    required this.fps,
    required this.width,
    required this.height,
    this.isStatic = false,
    this.cursor,
    required this.timestamp,
  });

  factory FramePacket.fromJson(Map<String, dynamic> json) {
    final b64 = json['frame'] as String? ?? '';
    final bytes = base64Decode(b64);
    return FramePacket(
      clientId: json['client_id']?.toString() ?? '',
      imageBytes: bytes,
      fps: (json['fps'] is num) ? (json['fps'] as num).toDouble() : 0.0,
      width: (json['width'] is num) ? (json['width'] as num).toInt() : 0,
      height: (json['height'] is num) ? (json['height'] as num).toInt() : 0,
      isStatic: json['is_static'] == true,
      cursor: json['cursor'] as Map<String, dynamic>?,
      timestamp: (json['timestamp'] is num) ? (json['timestamp'] as num).toDouble() : 0.0,
    );
  }
}

class ClientInfo {
  final String clientId;
  final String name;
  final String hostname;
  final String ipAddress;
  double fps;
  Uint8List? latestFrame;
  int width;
  int height;
  DateTime lastSeen;

  ClientInfo({
    required this.clientId,
    required this.name,
    required this.hostname,
    required this.ipAddress,
    this.fps = 0.0,
    this.latestFrame,
    this.width = 1920,
    this.height = 1080,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory ClientInfo.fromJson(Map<String, dynamic> json) {
    return ClientInfo(
      clientId: json['client_id']?.toString() ?? '',
      name: json['client_name']?.toString() ?? 'Workstation',
      hostname: json['hostname']?.toString() ?? 'Host',
      ipAddress: json['ip_address']?.toString() ?? '127.0.0.1',
    );
  }
}

class ProtocolHelper {
  static String createAuthRequest({
    required String clientName,
    required String hostname,
    required String ipAddress,
    required String passcode,
  }) {
    return jsonEncode({
      "type": PacketType.authReq,
      "client_name": clientName,
      "hostname": hostname,
      "ip_address": ipAddress,
      "passcode": passcode,
      "timestamp": DateTime.now().millisecondsSinceEpoch / 1000.0,
    });
  }

  static String createHeartbeat(String clientId) {
    return jsonEncode({
      "type": PacketType.heartbeat,
      "client_id": clientId,
      "timestamp": DateTime.now().millisecondsSinceEpoch / 1000.0,
    });
  }

  static String createRemoteInput({
    required String eventType,
    required Map<String, dynamic> params,
    String? targetClientId,
  }) {
    final payload = {
      "type": PacketType.remoteInput,
      "event_type": eventType,
      "params": params,
      "timestamp": DateTime.now().millisecondsSinceEpoch / 1000.0,
    };
    if (targetClientId != null) {
      payload["target_client_id"] = targetClientId;
    }
    return jsonEncode(payload);
  }

  static String createAlertPacket({String? imageB64}) {
    final payload = {
      "type": PacketType.alert,
      "timestamp": DateTime.now().millisecondsSinceEpoch / 1000.0,
    };
    if (imageB64 != null) {
      payload["image_b64"] = imageB64;
    }
    return jsonEncode(payload);
  }

  static String createFramePacket({
    required String clientId,
    required Uint8List frameBytes,
    required double fps,
    required int width,
    required int height,
    bool isStatic = false,
  }) {
    final b64 = base64Encode(frameBytes);
    return jsonEncode({
      "type": PacketType.frameData,
      "client_id": clientId,
      "frame": b64,
      "fps": double.parse(fps.toStringAsFixed(1)),
      "width": width,
      "height": height,
      "is_static": isStatic,
      "timestamp": DateTime.now().millisecondsSinceEpoch / 1000.0,
    });
  }
}
