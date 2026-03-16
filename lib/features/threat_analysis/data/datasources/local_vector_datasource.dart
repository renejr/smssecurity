import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smssecurity/core/services/threat_isolate_manager.dart';

abstract class LocalVectorDataSource {
  Future<List<Map<String, dynamic>>> findSimilarThreats(String smsBody, {int limit = 3});
  Future<void> saveThreatPattern(String smsBody, String category, List<double> embedding);
  Future<void> initializeData();
  
  // Novos métodos de Histórico
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50, DateTime? startDate, DateTime? endDate});
  Future<void> saveHistory(String sender, String body, double riskScore, String category, bool isBlocked, {String source = 'local', String? deviceId});
  
  // Cache de URL
  Future<bool?> checkUrlCache(String url);
  Future<void> cacheUrlCheck(String url, bool isMalicious);
  // Auto-Aprendizado (Auto-RAG)
  Future<void> learnThreat(String body, String category);
  
  // Cache de Isca (Reclame Aqui)
  Future<int?> checkBaitCache(String bait);
  Future<void> cacheBaitCheck(String bait, int complaintCount);
  
  // Whitelist e Feedback
  Future<void> addToWhitelist(String sender);
  Future<bool> isWhitelisted(String sender);
  Future<void> deleteFromHistory(String sender, String body);
  Future<void> deleteHistoryItems(List<int> ids);
  Future<void> updateRiskScore(int id, double newScore);
}

class LocalVectorDataSourceImpl implements LocalVectorDataSource {
  final ThreatIsolateManager isolateManager;

  LocalVectorDataSourceImpl({
    required this.isolateManager,
  });
  
  @override
  Future<void> updateRiskScore(int id, double newScore) async {
    await isolateManager.updateRiskScore(id, newScore);
  }

  @override
  Future<int?> checkBaitCache(String bait) async {
    return await isolateManager.checkBaitCache(bait);
  }

  @override
  Future<void> cacheBaitCheck(String bait, int complaintCount) async {
    await isolateManager.cacheBaitCheck(bait, complaintCount);
  }

  @override
  Future<void> addToWhitelist(String sender) async {
    await isolateManager.addToWhitelist(sender);
  }

  @override
  Future<bool> isWhitelisted(String sender) async {
    return await isolateManager.isWhitelisted(sender);
  }

  @override
  Future<void> deleteFromHistory(String sender, String body) async {
    await isolateManager.deleteFromHistory(sender, body);
  }

  @override
  Future<void> deleteHistoryItems(List<int> ids) async {
    await isolateManager.deleteHistoryItems(ids);
  }

  @override
  Future<void> learnThreat(String body, String category) async {
    await isolateManager.learnThreat(body, category);
  }

  @override
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50, DateTime? startDate, DateTime? endDate}) async {
    return await isolateManager.getHistory(limit: limit, startDate: startDate, endDate: endDate);
  }

  @override
  Future<void> saveHistory(String sender, String body, double riskScore, String category, bool isBlocked, {String source = 'local', String? deviceId}) async {
    await isolateManager.saveHistory(sender, body, riskScore, category, isBlocked, source: source, deviceId: deviceId);
  }
  
  @override
  Future<bool?> checkUrlCache(String url) async {
    return await isolateManager.checkUrlCache(url);
  }

  @override
  Future<void> cacheUrlCheck(String url, bool isMalicious) async {
    await isolateManager.cacheUrlCheck(url, isMalicious);
  }

  @override
  Future<List<Map<String, dynamic>>> findSimilarThreats(String smsBody, {int limit = 3}) async {
    // Delega para o Isolate
    return await isolateManager.analyzeSms(smsBody);
  }

  @override
  Future<void> saveThreatPattern(String smsBody, String category, List<double> embedding) async {
    // Por enquanto, não expusemos "inserção manual" via isolate além da carga inicial.
    // Como a carga inicial cobre 99% dos casos, e o aprendizado incremental é futuro,
    // deixamos vazio ou logamos aviso.
    print("Aviso: Inserção manual não implementada via Isolate neste MVP.");
  }

  @override
  Future<void> initializeData() async {
    // 1. Inicializa o Isolate Manager passando o caminho do DB
    final docDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docDir.path, 'sms_shield_rag.db');
    
    // Copiar modelo para arquivo local para evitar problemas de assets no Isolate
    final modelPath = join(docDir.path, 'bert_tiny.tflite');
    try {
       // Sobrescreve sempre para garantir atualização se asset mudar
       final data = await rootBundle.load('assets/models/bert_tiny.tflite');
       final bytes = data.buffer.asUint8List();
       await File(modelPath).writeAsBytes(bytes, flush: true);
       print("Modelo copiado com sucesso para $modelPath");
    } catch(e) {
       print("Erro ao copiar modelo TFLite: $e");
    }
    
    // Passa o caminho do modelo para o Isolate
    await isolateManager.init(dbPath, modelPath: modelPath);

    // 2. Carrega conteudos dos assets (Main Thread)
    try {
      final threatsJson = await rootBundle.loadString('assets/data/threats.json');
      final vocabContent = await rootBundle.loadString('assets/models/vocab.txt');
      
      // 3. Envia para o Isolate processar
      await isolateManager.initializeData(threatsJson, vocabContent);
      
    } catch (e, stackTrace) {
      print("Erro ao carregar assets para inicialização: $e\n$stackTrace");
    }
  }
}
