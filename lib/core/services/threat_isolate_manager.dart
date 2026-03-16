import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:smssecurity/core/database/vector_db_service.dart';
import 'package:smssecurity/core/services/ai/bert_local_service.dart';

/// Classe que gerencia o Isolate de Análise de Ameaças.
/// Encapsula toda a lógica de background para não travar a UI.
class ThreatIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  
  Completer<void>? _initCompleter;

  Future<void> init(String dbPath, {String? modelPath}) async {
    if (_isolate != null) return;
    
    _initCompleter = Completer<void>();
    
    // Obtém o token do Isolate Raiz (Main Thread)
    // Isso é necessário para que o Isolate filho possa usar serviços de plataforma
    // como assets e method channels via BackgroundIsolateBinaryMessenger.
    RootIsolateToken rootToken = RootIsolateToken.instance!;

    // Spawna o Isolate passando o RootToken junto com a SendPort
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      [rootToken, _receivePort.sendPort], // Passamos uma lista de argumentos
    );

    // Aguarda o handshake inicial (SendPort do Isolate)
    final firstMessage = await _receivePort.first;
    if (firstMessage is SendPort) {
      _sendPort = firstMessage;
      // Envia configuração inicial (caminho do DB e modelo)
      _sendPort!.send({
        'command': 'config', 
        'dbPath': dbPath,
        'modelPath': modelPath,
      });
      _initCompleter!.complete();
    } else {
      _initCompleter!.completeError("Falha ao inicializar Isolate");
    }
  }

  /// Envia um comando de inicialização de dados (Carga de JSON)
  Future<void> initializeData(String threatsJsonContent, String vocabContent) async {
    await _initCompleter!.future;
    _sendPort!.send({
      'command': 'initData',
      'threatsJson': threatsJsonContent,
      'vocabContent': vocabContent, 
    });
  }

  /// Envia um SMS para análise
  Future<List<Map<String, dynamic>>> analyzeSms(String smsBody) async {
    await _initCompleter!.future;
    
    final responsePort = ReceivePort();
    _sendPort!.send({
      'command': 'analyze',
      'smsBody': smsBody,
      'replyTo': responsePort.sendPort,
    });

    final result = await responsePort.first;
    if (result is List) {
      return List<Map<String, dynamic>>.from(result);
    }
    return [];
  }

  /// Recupera o histórico de SMS com filtros opcionais
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50, DateTime? startDate, DateTime? endDate}) async {
    await _initCompleter!.future;
    
    final responsePort = ReceivePort();
    _sendPort!.send({
      'command': 'getHistory',
      'limit': limit,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'replyTo': responsePort.sendPort,
    });

    final result = await responsePort.first;
    if (result is List) {
      return List<Map<String, dynamic>>.from(result);
    }
    return [];
  }
  
  /// Salva um SMS analisado no histórico
  Future<void> saveHistory(String sender, String body, double riskScore, String category, bool isBlocked, {String source = 'local', String? deviceId}) async {
    await _initCompleter!.future;
    
    _sendPort!.send({
      'command': 'saveHistory',
      'sender': sender,
      'body': body,
      'riskScore': riskScore,
      'category': category,
      'isBlocked': isBlocked,
      'source': source,
      'deviceId': deviceId,
    });
  }

  /// Atualiza o Risk Score de um item (Confirmação Manual)
  Future<void> updateRiskScore(int id, double newScore) async {
    await _initCompleter!.future;
    _sendPort!.send({
      'command': 'updateRiskScore',
      'id': id,
      'newScore': newScore,
    });
  }

  /// Verifica cache de URL
  Future<bool?> checkUrlCache(String url) async {
    await _initCompleter!.future;
    
    final responsePort = ReceivePort();
    _sendPort!.send({
      'command': 'checkUrlCache',
      'url': url,
      'replyTo': responsePort.sendPort,
    });

    final result = await responsePort.first;
    return result as bool?;
  }

  /// Salva cache de URL
  Future<void> cacheUrlCheck(String url, bool isMalicious) async {
    await _initCompleter!.future;
    
    _sendPort!.send({
      'command': 'cacheUrlCheck',
      'url': url,
      'isMalicious': isMalicious,
    });
  }
  
  /// Verifica cache de Isca (Reclame Aqui)
  Future<int?> checkBaitCache(String bait) async {
    await _initCompleter!.future;
    
    final responsePort = ReceivePort();
    _sendPort!.send({
      'command': 'checkBaitCache',
      'bait': bait,
      'replyTo': responsePort.sendPort,
    });

    final result = await responsePort.first;
    return result as int?;
  }

  /// Salva cache de Isca (Reclame Aqui)
  Future<void> cacheBaitCheck(String bait, int complaintCount) async {
    await _initCompleter!.future;
    
    _sendPort!.send({
      'command': 'cacheBaitCheck',
      'bait': bait,
      'complaintCount': complaintCount,
    });
  }

  /// Aprende uma nova ameaça (Auto-RAG)
  Future<void> learnThreat(String body, String category) async {
    await _initCompleter!.future;
    
    _sendPort!.send({
      'command': 'learnThreat',
      'body': body,
      'category': category,
    });
  }

  /// Adiciona remetente à whitelist
  Future<void> addToWhitelist(String sender) async {
    await _initCompleter!.future;
    _sendPort!.send({
      'command': 'addToWhitelist',
      'sender': sender,
    });
  }

  /// Verifica se está na whitelist
  Future<bool> isWhitelisted(String sender) async {
    await _initCompleter!.future;
    final responsePort = ReceivePort();
    _sendPort!.send({
      'command': 'isWhitelisted',
      'sender': sender,
      'replyTo': responsePort.sendPort,
    });
    return (await responsePort.first) as bool;
  }

  /// Remove do histórico
  Future<void> deleteFromHistory(String sender, String body) async {
    await _initCompleter!.future;
    _sendPort!.send({
      'command': 'deleteFromHistory',
      'sender': sender,
      'body': body,
    });
  }

  /// Remove múltiplos itens do histórico por ID
  Future<void> deleteHistoryItems(List<int> ids) async {
    await _initCompleter!.future;
    _sendPort!.send({
      'command': 'deleteHistoryItems',
      'ids': ids,
    });
  }

  void dispose() {
    _sendPort?.send({'command': 'close'});
    _isolate?.kill();
    _isolate = null;
  }

  /// Ponto de entrada do Isolate (Static ou Top-Level)
  /// args[0] = RootIsolateToken
  /// args[1] = SendPort da Main Thread
  static void _isolateEntryPoint(List<dynamic> args) async {
    final RootIsolateToken rootToken = args[0];
    final SendPort mainSendPort = args[1];

    // Inicializa o binding para Isolates em background usando o token da raiz
    // Isso permite usar MethodChannels e Assets sem tentar subir a UI
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
     
    // Cria a porta de recebimento deste Isolate
    final isolateReceivePort = ReceivePort();
    
    // Envia a porta de envio para a Main Thread (Handshake)
    mainSendPort.send(isolateReceivePort.sendPort);

    // Inicializa serviços dentro do Isolate
    final vectorDb = VectorDbService();
    final bertService = BertLocalService(); 
    
    // Loop de mensagens
    await for (final message in isolateReceivePort) {
      if (message is Map) {
        final command = message['command'];

        if (command == 'config') {
          final dbPath = message['dbPath'] as String;
          final modelPath = message['modelPath'] as String?;
          
          await vectorDb.init(customPath: dbPath);
          
          // Se tivermos um caminho de modelo, pré-configuramos o BERT
          if (modelPath != null) {
             await bertService.init(modelPath: modelPath);
          }
        }
        else if (command == 'initData') {
           final threatsJson = message['threatsJson'] as String;
           final vocabContent = message['vocabContent'] as String;
           
           // Inicializa BERT (se não tiver sido inicializado via config)
           await bertService.init(vocabContent: vocabContent); 

           try {
             final List<dynamic> data = json.decode(threatsJson);
             // Verifica se já tem dados
             final existing = await vectorDb.searchSimilarThreats(List.filled(512, 0.0), limit: 1);
             if (existing.isEmpty) {
               print("[Isolate] Indexando ${data.length} ameaças...");
               int index = 0;
               for (final item in data) {
                 try {
                    // Blindagem contra campos nulos e tipos errados
                    final text = (item['text'] ?? '').toString();
                    
                    // Suporte a múltiplas chaves possíveis para categoria
                    String categoryVal = 'Desconhecido';
                    if (item['threatCategory'] != null) categoryVal = item['threatCategory'].toString();
                    else if (item['category'] != null) categoryVal = item['category'].toString();
                    
                    if (text.isEmpty) {
                       print("[Isolate] Aviso: Item $index com texto vazio. Pulando.");
                       continue;
                    }

                    final embedding = await bertService.getEmbedding(text);
                    vectorDb.insertThreat(text, categoryVal, embedding);
                 } catch (e) {
                    print("[Isolate] Erro ao indexar item $index: $e. Item: $item");
                 }
                 index++;
               }
               print("[Isolate] Indexação concluída.");
             }
           } catch (e) {
             print("[Isolate] Erro na indexação: $e");
           }
        } 
        else if (command == 'analyze') {
          final smsBody = message['smsBody'] as String;
          final replyTo = message['replyTo'] as SendPort;

          try {
            List<double> embedding;
            try {
               embedding = await bertService.getEmbedding(smsBody);
            } catch (e) {
               embedding = []; 
            }

            List<Map<String, dynamic>> results;
            
            results = await vectorDb.searchSimilarThreats(embedding);
            
            // Fallback por palavra-chave se similaridade baixa
            if (results.isEmpty || (results.first['similarity'] as double) < 0.2) {
               final keywordResults = await vectorDb.searchByKeywords(smsBody);
               if (keywordResults.isNotEmpty) {
                 results = keywordResults;
               }
            }

            replyTo.send(results);
            
          } catch (e) {
            print("[Isolate] Erro na análise: $e");
            replyTo.send([]);
          }
        }
        else if (command == 'getHistory') {
           final limit = message['limit'] as int;
           final startDateStr = message['startDate'] as String?;
           final endDateStr = message['endDate'] as String?;
           final replyTo = message['replyTo'] as SendPort;
           
           DateTime? startDate = startDateStr != null ? DateTime.parse(startDateStr) : null;
           DateTime? endDate = endDateStr != null ? DateTime.parse(endDateStr) : null;

           final history = vectorDb.getHistory(limit: limit, startDate: startDate, endDate: endDate);
           replyTo.send(history);
        }
        else if (command == 'saveHistory') {
           final sender = message['sender'] as String;
           final body = message['body'] as String;
           final riskScore = message['riskScore'] as double;
           final category = message['category'] as String;
           final isBlocked = message['isBlocked'] as bool;
           final source = message['source'] as String? ?? 'local';
           final deviceId = message['deviceId'] as String?;
           
           vectorDb.insertHistory(sender, body, riskScore, category, isBlocked, source: source, deviceId: deviceId);
        }
        else if (command == 'updateRiskScore') {
           final id = message['id'] as int;
           final newScore = message['newScore'] as double;
           vectorDb.updateRiskScore(id, newScore);
        }
        else if (command == 'checkUrlCache') {
           final url = message['url'] as String;
           final replyTo = message['replyTo'] as SendPort;
           final result = vectorDb.checkUrlCache(url);
           replyTo.send(result);
        }
        else if (command == 'cacheUrlCheck') {
           final url = message['url'] as String;
           final isMalicious = message['isMalicious'] as bool;
           vectorDb.cacheUrlCheck(url, isMalicious);
        }
        else if (command == 'checkBaitCache') {
           final bait = message['bait'] as String;
           final replyTo = message['replyTo'] as SendPort;
           final result = vectorDb.checkBaitCache(bait);
           replyTo.send(result);
        }
        else if (command == 'cacheBaitCheck') {
           final bait = message['bait'] as String;
           final complaintCount = message['complaintCount'] as int;
           vectorDb.cacheBaitCheck(bait, complaintCount);
        }
        else if (command == 'learnThreat') {
           final body = message['body'] as String;
           final category = message['category'] as String;
           
           try {
             // 1. Gera embedding
             final embedding = await bertService.getEmbedding(body);
             
             // 2. Insere na tabela de threats (RAG)
             vectorDb.insertThreat(body, category, embedding, metadata: 'auto_learned');
             print("[Isolate] Nova ameaça aprendida (Auto-RAG): $body");
           } catch (e) {
             print("[Isolate] Erro ao aprender nova ameaça: $e");
           }
        }
        else if (command == 'addToWhitelist') {
           final sender = message['sender'] as String;
           vectorDb.addToWhitelist(sender);
        }
        else if (command == 'isWhitelisted') {
            final sender = message['sender'] as String;
            final replyTo = message['replyTo'] as SendPort;
            final result = vectorDb.isWhitelisted(sender);
            replyTo.send(result);
         }
        else if (command == 'deleteFromHistory') {
           final sender = message['sender'] as String;
           final body = message['body'] as String;
           vectorDb.deleteFromHistory(sender, body);
        }
        else if (command == 'deleteHistoryItems') {
           final ids = (message['ids'] as List).cast<int>();
           vectorDb.deleteAlertsByIds(ids);
        }
      }
    }
  }
}
