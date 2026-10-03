import 'dart:async';

import 'package:flutter/services.dart';

/// قناة الاتصال بمحرك UCI. فصلها عن [EngineService] يسمح باختبار
/// منطق الجلسات (stale bestmove، stop/start...) بمحرك وهمي بدون
/// جهاز Android.
abstract class EngineTransport {
  /// أسطر المخرجات الواردة من المحرك (بترتيب وصولها).
  Stream<String> get output;

  /// يشغّل المحرك. يعيد false عند الفشل.
  Future<bool> start();

  /// يرسل أمر UCI واحدًا.
  Future<void> send(String command);

  Future<void> dispose();
}

/// التنفيذ الحقيقي: جسر Android (MethodChannel + EventChannel).
class PlatformEngineTransport implements EngineTransport {
  static const MethodChannel _methodChannel =
      MethodChannel('chess_analyzer/stockfish');

  static const EventChannel _eventChannel =
      EventChannel('chess_analyzer/stockfish/output');

  @override
  Stream<String> get output => _eventChannel
      .receiveBroadcastStream()
      .where((dynamic v) => v != null)
      .map((dynamic v) => v.toString());

  @override
  Future<bool> start() async =>
      await _methodChannel.invokeMethod<bool>('start') ?? false;

  @override
  Future<void> send(String command) async {
    await _methodChannel.invokeMethod<void>(
      'send',
      <String, dynamic>{'command': command},
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await _methodChannel.invokeMethod<void>('dispose');
    } catch (_) {}
  }
}
