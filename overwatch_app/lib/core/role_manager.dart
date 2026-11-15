import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

enum AppRole {
  unselected,
  manager,
  client,
}

class RoleManager extends ChangeNotifier {
  static const String _keyRole = 'overwatch_app_role';
  static const String _keyServerHost = 'overwatch_server_host';
  static const String _keyServerPort = 'overwatch_server_port';
  static const String _keyPasscode = 'overwatch_passcode';
  static const String _keyDeviceName = 'overwatch_device_name';

  AppRole _currentRole = AppRole.unselected;
  String _serverHost = AppConstants.defaultHost;
  int _serverPort = AppConstants.defaultPort;
  String _passcode = AppConstants.defaultAuthToken;
  String _deviceName = 'Android-Device';
  bool _isInitialized = false;

  AppRole get currentRole => _currentRole;
  String get serverHost => _serverHost;
  int get serverPort => _serverPort;
  String get passcode => _passcode;
  String get deviceName => _deviceName;
  bool get isInitialized => _isInitialized;

  RoleManager() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoleStr = prefs.getString(_keyRole);

    if (savedRoleStr == 'manager') {
      _currentRole = AppRole.manager;
    } else if (savedRoleStr == 'client') {
      _currentRole = AppRole.client;
    } else {
      _currentRole = AppRole.unselected;
    }

    _serverHost = prefs.getString(_keyServerHost) ?? AppConstants.defaultHost;
    if (_serverHost == '192.168.1.100' || _serverHost == '192.168.1.74') {
      _serverHost = AppConstants.defaultHost;
      await prefs.setString(_keyServerHost, _serverHost);
    }

    _serverPort = prefs.getInt(_keyServerPort) ?? AppConstants.defaultPort;

    _passcode = prefs.getString(_keyPasscode) ?? AppConstants.defaultAuthToken;
    if (_passcode == '1234') {
      _passcode = AppConstants.defaultAuthToken;
      await prefs.setString(_keyPasscode, _passcode);
    }
    _deviceName = prefs.getString(_keyDeviceName) ?? 'Android-Device';

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setRole(AppRole role) async {
    _currentRole = role;
    final prefs = await SharedPreferences.getInstance();
    if (role == AppRole.manager) {
      await prefs.setString(_keyRole, 'manager');
    } else if (role == AppRole.client) {
      await prefs.setString(_keyRole, 'client');
    } else {
      await prefs.remove(_keyRole);
    }
    notifyListeners();
  }

  Future<void> updateNetworkSettings({
    String? host,
    int? port,
    String? passcode,
    String? deviceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (host != null) {
      _serverHost = host;
      await prefs.setString(_keyServerHost, host);
    }
    if (port != null) {
      _serverPort = port;
      await prefs.setInt(_keyServerPort, port);
    }
    if (passcode != null) {
      _passcode = passcode;
      await prefs.setString(_keyPasscode, passcode);
    }
    if (deviceName != null) {
      _deviceName = deviceName;
      await prefs.setString(_keyDeviceName, deviceName);
    }
    notifyListeners();
  }

  Future<void> resetRole() async {
    await setRole(AppRole.unselected);
  }
}
