import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

enum LogLevel {
  debug,
  info,
  warn,
  error,
}

class LogUtils {
  static File? _logFile;
  static bool _initialized = false;

  /// 当前日志文件对应的日期（yyyy-MM-dd），用于跨天自动切换文件
  static String? _logFileDateStr;

  /// logs 目录路径，跨天切换文件时复用
  static String? _logDir;
  
  // 私有构造函数，防止实例化
  LogUtils._();

  /// 初始化日志工具
  /// 建议在 main() 中调用
  static Future<void> init() async {
    if (_initialized) return;

    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final String logDir = '${dir.path}/logs';
      final Directory logDirectory = Directory(logDir);
      
      if (!await logDirectory.exists()) {
        await logDirectory.create(recursive: true);
      }

      // 按日期生成日志文件
      final String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _logDir = logDir;
      _logFileDateStr = dateStr;
      _logFile = File('$logDir/log_$dateStr.txt');
      
      _initialized = true;
      i('LogUtils', 'LogUtils initialized. Log file: ${_logFile?.path}');
    } catch (e) {
      print('LogUtils init failed: $e');
    }
  }

  /// 获取当前日志文件路径
  static Future<String?> getLogFilePath() async {
    if (!_initialized) await init();
    // 确保返回的是当天对应的日志文件
    _ensureLogFileForDate();
    return _logFile?.path;
  }

  /// 跨天自动切换日志文件：
  /// 应用长期驻留不退出时，若当前日期与日志文件日期不一致，
  /// 则将 _logFile 切换到当天的新文件，避免所有日志写进同一个文件。
  static void _ensureLogFileForDate() {
    if (!_initialized || _logDir == null) return;
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_logFileDateStr == todayStr) return;

    try {
      final String oldDate = _logFileDateStr ?? 'unknown';
      _logFileDateStr = todayStr;
      _logFile = File('$_logDir/log_$todayStr.txt');
      // 走 i() 记录切换事件，此时 _logFileDateStr 已更新，不会递归触发切换
      i('LogUtils', 'Date changed ($oldDate -> $todayStr), switching log file to ${_logFile?.path}');
    } catch (e) {
      print('LogUtils switch log file failed: $e');
    }
  }

  /// 获取所有日志文件列表
  static Future<List<File>> getLogFiles() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final String logDir = '${dir.path}/logs';
      final Directory logDirectory = Directory(logDir);
      
      if (await logDirectory.exists()) {
        return logDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.txt'))
            .toList();
      }
    } catch (e) {
      print('Get log files failed: $e');
    }
    return [];
  }

  static void d(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  static void i(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  static void w(String tag, String message) {
    _log(LogLevel.warn, tag, message);
  }

  static void e(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    String msg = message;
    if (error != null) {
      msg += '\nError: $error';
    }
    if (stackTrace != null) {
      msg += '\nStackTrace: $stackTrace';
    }
    _log(LogLevel.error, tag, msg);
  }

  static void _log(LogLevel level, String tag, String message) {
    final DateTime now = DateTime.now();
    final String timeStr = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(now);
    final String levelStr = _getLevelString(level);
    final String logContent = '$timeStr $levelStr/$tag: $message';

    // 1. 输出到控制台 (所有日志)
    // 使用 debugPrint 可以避免长日志被截断
    debugPrint(logContent);

    // 2. 输出到文件
    _writeToFile(level, logContent);
  }

  static String _getLevelString(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return 'D';
      case LogLevel.info:  return 'I';
      case LogLevel.warn:  return 'W';
      case LogLevel.error: return 'E';
    }
  }

  static void _writeToFile(LogLevel level, String content) {
    if (!_initialized || _logFile == null) return;

    // 写入前校验日期，跨天时自动切换到当天的新日志文件
    _ensureLogFileForDate();
    if (_logFile == null) return;

    // 判断是否需要写入文件
    bool shouldWrite = false;
    
    if (kDebugMode) {
      // Debug 环境：所有日志都写入
      shouldWrite = true;
    } else {
      // Release 环境：只有 Warning 和 Error 写入
      if (level == LogLevel.warn || level == LogLevel.error) {
        shouldWrite = true;
      }
    }

    if (shouldWrite) {
      // 异步写入文件，避免阻塞 UI
      _logFile!.writeAsString('$content\n', mode: FileMode.append).catchError((e) {
        print('Write log failed: $e');
      });
    }
  }
}
