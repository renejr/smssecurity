import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smssecurity/core/services/log_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _logs = "Carregando logs...";

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await LogService().readLogs();
    setState(() {
      _logs = logs;
    });
  }

  Future<void> _exportLogs() async {
    final file = await LogService().getLogFile();
    if (file != null && await file.exists()) {
      await Share.shareXFiles([XFile(file.path)], text: 'Logs de Debug - Escudo SMS');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo de log não encontrado.')),
        );
      }
    }
  }

  Future<void> _clearLogs() async {
    await LogService().clearLogs();
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs de Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearLogs,
            tooltip: 'Limpar Logs',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportLogs,
            tooltip: 'Exportar (TXT)',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _logs,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
