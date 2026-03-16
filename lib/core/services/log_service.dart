import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  File? _logFile;

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/app_debug_logs.txt');
    
    // Log inicial de sessão
    log("=== Nova Sessão Iniciada ===");
  }

  Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final formattedMessage = '[$timestamp] $message\n';
    
    // Mantém o print no console para desenvolvimento
    print("📝 LOG: $message");

    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(formattedMessage, mode: FileMode.append);
      } catch (e) {
        print("Erro ao escrever no arquivo de log: $e");
      }
    }
  }

  Future<String> readLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      return await _logFile!.readAsString();
    }
    return "Nenhum log encontrado.";
  }

  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString("=== Logs Limpos ===\n");
    }
  }

  Future<File?> getLogFile() async {
    return _logFile;
  }
}
