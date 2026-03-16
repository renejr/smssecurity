import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smssecurity/features/threat_analysis/presentation/providers/threat_provider.dart';

class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({super.key});

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  DateTimeRange? _selectedDateRange;
  
  @override
  void initState() {
    super.initState();
    // Carrega histórico inicial (últimos 7 dias por padrão ou tudo)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final provider = context.read<ThreatProvider>();
    provider.loadHistory(
      limit: 500, // Limite maior para telemetria
      startDate: _selectedDateRange?.start,
      endDate: _selectedDateRange?.end,
    );
  }

  Future<void> _selectDateRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: now,
      initialDateRange: _selectedDateRange ?? DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _loadData();
    }
  }

  Future<void> _exportTelemetry() async {
    final provider = context.read<ThreatProvider>();
    final logs = provider.history;

    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nenhum dado para exportar.")),
      );
      return;
    }

    // Formata JSON conforme especificação
    final List<Map<String, dynamic>> exportData = logs.map((log) {
      final score = log['riskScore'] as double;
      // Candidato a RAG se score entre 0.4 e 0.6 (incerteza) ou alto risco não confirmado
      final isRagCandidate = (score > 0.4 && score < 0.6) || (score > 0.8);
      
      return {
        "timestamp": DateTime.fromMillisecondsSinceEpoch(log['timestamp']).toIso8601String(),
        "sender": log['sender'],
        "text": log['body'], // Texto higienizado
        "classification": score > 0.5 ? "spam" : "ham",
        "confidence_score": score,
        "device_id": log['deviceId'] ?? "unknown",
        "is_rag_candidate": isRagCandidate,
        "source": log['source']
      };
    }).toList();

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

    // Salva arquivo temporário
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/telemetry_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonString);

    // Compartilha
    await Share.shareXFiles([XFile(file.path)], text: 'Exportação de Telemetria MDXHQ');
  }

  Future<void> _exportSentinelLog() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/headless_log.txt');
      
      if (!await file.exists()) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("Log Sentinela não encontrado (o modo headless ainda não rodou?)")),
           );
        }
        return;
      }
      
      // Compartilha
      await Share.shareXFiles([XFile(file.path)], text: 'Log Sentinela (Headless Debug) - MDXHQ');
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Erro ao exportar log: $e")),
         );
      }
    }
  }

  void _showLogDetails(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Detalhes do Log"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("Remetente:", log['sender']),
              _detailRow("Score:", "${(log['riskScore'] * 100).toStringAsFixed(1)}%"),
              _detailRow("Fonte:", log['source']),
              _detailRow("Device ID:", log['deviceId'] ?? "N/A"),
              const SizedBox(height: 10),
              const Text("Conteúdo (Higienizado):", style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                child: Text(log['body'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar")),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThreatProvider>();
    final logs = provider.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Telemetria Avançada"),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: "Exportar Log Sentinela",
            onPressed: _exportSentinelLog,
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: "Filtrar por Data",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportTelemetry,
        icon: const Icon(Icons.download),
        label: const Text("Exportar JSON"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          if (_selectedDateRange != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.deepPurple.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Filtro: ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() => _selectedDateRange = null);
                      _loadData();
                    },
                  )
                ],
              ),
            ),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : logs.isEmpty
                    ? const Center(child: Text("Nenhum registro encontrado."))
                    : ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final score = log['riskScore'] as double;
                          
                          // Destaque para incerteza (Candidato RAG)
                          final isUncertain = score > 0.4 && score < 0.6;
                          final isHighRisk = score > 0.8;
                          
                          Color scoreColor = Colors.green;
                          if (isHighRisk) scoreColor = Colors.red;
                          else if (score > 0.5) scoreColor = Colors.orange;
                          
                          if (isUncertain) scoreColor = Colors.amber; // Laranja destaque

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scoreColor.withOpacity(0.2),
                              child: Text(
                                "${(score * 100).toStringAsFixed(0)}",
                                style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            title: Text(log['sender'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log['body'], 
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  DateFormat('dd/MM HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(log['timestamp'])),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                            trailing: isUncertain 
                              ? const Tooltip(message: "Candidato RAG (Incerteza)", child: Icon(Icons.science, color: Colors.amber))
                              : null,
                            onTap: () => _showLogDetails(log),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
