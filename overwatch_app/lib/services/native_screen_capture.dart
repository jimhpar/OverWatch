import 'dart:async';
import 'package:flutter/services.dart';

class NativeScreenCapture {
  static const MethodChannel _methodChannel =
      MethodChannel('com.blackboxthc.overwatch/screen_capture');
  static const EventChannel _eventChannel =
      EventChannel('com.blackboxthc.overwatch/screen_frames');

  static Stream<Map<String, dynamic>>? _frameStream;

  static Future<bool> startCapture() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestScreenCapture');
      return res == true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> stopCapture() async {
    try {
      await _methodChannel.invokeMethod('stopScreenCapture');
    } catch (_) {}
  }

  static Future<bool> isCapturing() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isCapturing');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestBatteryExemption() async {
    try {
      await _methodChannel.invokeMethod('requestBatteryOptimization');
    } catch (_) {}
  }

  static Stream<Map<String, dynamic>> get frameStream {
    _frameStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => Map<String, dynamic>.from(event as Map));
    return _frameStream!;
  }
}
