import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smssecurity/core/services/global_intelligence_service.dart';
import 'package:smssecurity/core/services/google_search_service.dart';
import 'package:smssecurity/core/services/notification_service.dart';
import 'package:smssecurity/core/services/virustotal_service.dart';
import 'package:smssecurity/core/utils/bait_extractor.dart';
import 'package:smssecurity/core/utils/privacy_filter.dart';
import 'package:smssecurity/features/threat_analysis/data/datasources/local_vector_datasource.dart';
import 'package:smssecurity/features/threat_analysis/domain/entities/threat_alert.dart';
import 'package:smssecurity/features/threat_analysis/domain/usecases/analyze_sms_usecase.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class ThreatAnalysisService {
  static const platform = MethodChannel('com.escudo.sms/interceptor');
  
  final AnalyzeSmsUseCase analyzeSmsUseCase;
  final LocalVectorDataSource vectorDataSource; 
  final VirusTotalService _virusTotalService = VirusTotalService();
  final NotificationService _notificationService = NotificationService();
  final GoogleCustomSearchService _googleSearchService = GoogleCustomSearchService();
  final GlobalIntelligenceService _globalIntelligenceService = GlobalIntelligenceService();
  
  String? _cachedDeviceId;

  // Lista básica de Short Codes Oficiais (Exemplos: Bancos, Operadoras, Serviços)
  // Idealmente, isso seria alimentado por uma API ou config remota.
  static const List<String> _officialShortCodes = [
    '4004', '4003', '3003', // Bancos Gerais
    '27800', '25500', // Exemplos de 2FA
    '111', '1052', // Operadoras
  ];

  final _threatAlertController = StreamController<ThreatAlert>.broadcast();

  Stream<ThreatAlert> get threatAlertStream => _threatAlertController.stream;

  ThreatAnalysisService({
    required this.analyzeSmsUseCase,
    required this.vectorDataSource,
  }) {
    _initializeMethodChannel();
    _getDeviceId().then((id) => _cachedDeviceId = id);
  }

  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? "unknown_ios";
      }
    } catch (e) {
      print("Erro ao obter Device ID: $e");
    }
    return "unknown_device";
  }

  /// Método público para análise direta (chamado via Headless Engine ou UI)
  Future<void> analyzeDirectly(String sender, String body, {bool isHeadless = false}) async {
    await _processIncomingSms(sender, body, isHeadless: isHeadless);
  }

  void _initializeMethodChannel() {
    print("Iniciando escuta do MethodChannel: com.escudo.sms/interceptor");
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onSmsReceived') {
        final String sender = call.arguments['sender'] ?? 'Unknown';
        final String body = call.arguments['body'] ?? '';
        
        print("📥 Dart recebeu via MethodChannel: $body");
        
        await _processIncomingSms(sender, body);
      }
    });
  }

  Future<void> _processIncomingSms(String sender, String body, {bool isHeadless = false}) async {
    try {
      print('Processando SMS de $sender: $body (Headless: $isHeadless)');
      
      // Higieniza o texto para o "motor" interno (LGPD)
      String sanitizedBody;
      try {
        sanitizedBody = PrivacyFilter.sanitizeSms(body);
        print('Texto higienizado (Motor IA/Logs): $sanitizedBody');
      } catch (e) {
        print("⚠️ Erro na higienização LGPD: $e. Usando texto original para não interromper fluxo.");
        sanitizedBody = body;
      }
      
      String deviceId = "unknown_device";
      try {
        deviceId = await _getDeviceId();
      } catch (e) {
        print("⚠️ Erro ao obter DeviceID em background: $e");
      }

      // 0. Whitelist Check (Prioridade Absoluta)
      if (await _isSenderSafe(sender, isHeadless: isHeadless)) {
         print("✅ Remetente $sender está na Whitelist/Contatos. Ignorando análise.");
         final safeAlert = ThreatAlert(
           id: DateTime.now().millisecondsSinceEpoch.toString(),
           sender: sender,
           originalBody: body,
           riskScore: 0.0,
           threatCategory: "Remetente Confiável",
           reasoning: "Este remetente está na sua lista de confiáveis ou contatos.",
           timestamp: DateTime.now(),
           isExternalConfirmed: false,
           isVerifying: false,
           deviceId: deviceId,
         );
         
         // Silent Mining: Salva mesmo sendo seguro para Telemetria
         await vectorDataSource.saveHistory(
           sender,
           sanitizedBody,
           0.0,
           "Seguro (Whitelist)",
           false,
           source: 'whitelist',
           deviceId: deviceId
         );
         
         _threatAlertController.add(safeAlert);
         return;
      }

      // 1. Extração de Iscas (URLs e Telefones) - Usa o original para não quebrar links
      final baits = BaitExtractor.extractAllBaits(body);
      bool baitConfirmed = false;
      String baitReasoning = "";

      // 1.5. Consulta Inteligência Global (RAG Remoto) - Prioridade sobre APIs pagas
      if (!baitConfirmed) {
         final globalMatch = await _globalIntelligenceService.checkGlobalThreat(sanitizedBody);
         if (globalMatch != null) {
            print("🌍 Ameaça Global Confirmada! Similaridade: ${globalMatch['similarity']}");
            baitConfirmed = true;
            baitReasoning = "🚨 ALERTA GLOBAL: Este golpe já foi reportado pela comunidade (Categoria: ${globalMatch['category']}).";
         }
      }

      // 2. Consulta Google Search (Reclame Aqui) se houver iscas e não for confirmado globalmente
      // DESABILITADO TEMPORARIAMENTE: Evitar logs de erro 403 por falta de cota/chave
      /*
      if (baits.isNotEmpty && !baitConfirmed) {
        print("🎣 Iscas encontradas: $baits");
        
        for (final bait in baits) {
          try {
            // Check Cache
            int? complaints = await vectorDataSource.checkBaitCache(bait);
            
            if (complaints == null) {
               // Consulta API Real com Tratamento de Erro Silencioso
               try {
                 // Passa o texto original (ou higienizado, dependendo da estratégia de vacina)
                 // Como a vacina é global, idealmente enviamos o higienizado para não vazar dados PII para o servidor global,
                 // ou enviamos o original se o servidor for confiável e precisar do contexto exato.
                 // Vamos enviar o higienizado por segurança.
                 complaints = await _googleSearchService.checkReclameAqui(bait, smsText: sanitizedBody);
               } catch (e) {
                 print("⚠️ Erro silencioso ao consultar Google Search: $e");
                 complaints = 0; // Fallback seguro
               }
               // Salva no Cache (mesmo que 0, para evitar flood na API em caso de erro persistente ou ausência real)// Salva no Cache
               await vectorDataSource.cacheBaitCheck(bait, complaints);
            }
            
            if (complaints > 0) {
              baitConfirmed = true;
              baitReasoning = "⚠️ Isca '$bait' possui $complaints reclamações no Reclame Aqui!";
              break; // Basta uma isca confirmada
            }
          } catch (e) {
             print("Erro ao processar isca $bait: $e");
          }
        }
      }
      */

      ThreatAlert alert;

      // 3. Decisão Baseada em Iscas (Prioridade Máxima)
      if (baitConfirmed) {
         print("🚨 ALERTA MÁXIMO: Golpe confirmado pelo Reclame Aqui!");
         alert = ThreatAlert(
           id: DateTime.now().millisecondsSinceEpoch.toString(),
           sender: sender,
           originalBody: body,
           riskScore: 1.0, 
           threatCategory: "Golpe Relatado (Reclame Aqui)",
           reasoning: baitReasoning,
           timestamp: DateTime.now(),
           isExternalConfirmed: true,
           isVerifying: false, // Já confirmamos, não precisa de mais checks
           deviceId: deviceId,
         );
         
         // Envia alerta imediatamente
         _threatAlertController.add(alert);
      } else {
         // 4. Fallback: Análise de IA Local (Se não houve confirmação por isca)
         // Usa o texto higienizado para a IA
         alert = await analyzeSmsUseCase(sender, sanitizedBody);
         // Mas para a UI, mostramos o original
         alert = alert.copyWith(originalBody: body, deviceId: deviceId);
         _threatAlertController.add(alert.copyWith(isVerifying: true));

         // 5. Verificação Externa Complementar (VirusTotal) para URLs não pegas pelo Reclame Aqui
         // (Apenas se já não foi confirmado como golpe)
         bool externalConfirmed = false;
         final urls = _virusTotalService.extractUrls(body);
         
         if (urls.isNotEmpty) {
            print("🔎 Verificando ${urls.length} URLs no VirusTotal...");
            for (final url in urls) {
               try {
                 bool? isMalicious = await vectorDataSource.checkUrlCache(url);
                 if (isMalicious == null) {
                    isMalicious = await _virusTotalService.checkUrl(url, smsText: sanitizedBody);
                    await vectorDataSource.cacheUrlCheck(url, isMalicious);
                 }
                 if (isMalicious) {
                    externalConfirmed = true;
                    break;
                 }
               } catch (e) {
                 print("Erro silencioso VirusTotal: $e");
               }
            }
         }

         if (externalConfirmed) {
            print("🚨 ALERTA MÁXIMO: Link malicioso confirmado por VirusTotal!");
            alert = alert.copyWith(
              riskScore: 1.0,
              threatCategory: "Link Malicioso (VirusTotal)",
              reasoning: "URL detectada como maliciosa por múltiplos motores de segurança.\n${alert.reasoning}",
              isExternalConfirmed: true,
              isVerifying: false,
            );
         } else {
            alert = alert.copyWith(isVerifying: false);
         }
      }

      // 6. Salva no Histórico - Usa o texto higienizado no banco/logs
      await vectorDataSource.saveHistory(
        alert.sender,
        sanitizedBody,
        alert.riskScore,
        alert.threatCategory,
        alert.riskScore > 0.5, // Bloqueia/Alerta se risco > 50%
        source: alert.isExternalConfirmed ? (baitConfirmed ? 'reclame_aqui' : 'virustotal') : 'local_ai',
        deviceId: alert.deviceId
      );
      
      // 7. Auto-Aprendizado (Auto-RAG) e Notificação (Thresholds Calibrados)
      // Score > 75%: Fraude Confirmada (Vermelho)
      // Score 60% - 75%: Atenção: Possível Golpe (Amarelo)
      // Score 50% - 60%: Mensagem Suspeita (Cinza/Amarelo)
      
      if (alert.riskScore > 0.75) {
         // Auto-Aprendizado para alta confiança
         if (alert.riskScore > 0.85) {
            print("🧠 Auto-Aprendizado (Autônomo): Incorporando nova ameaça ao RAG...");
            vectorDataSource.learnThreat(sanitizedBody, alert.threatCategory);
            
            // Tenta reportar globalmente (O serviço filtra se < 0.85, mas aqui já garantimos > 0.85)
            _globalIntelligenceService.reportScam(
              text: sanitizedBody, 
              sender: alert.sender, 
              category: alert.threatCategory, 
              riskScore: alert.riskScore
            );
         }
         
         _notificationService.showThreatNotification(
           id: alert.timestamp.millisecondsSinceEpoch ~/ 1000,
           title: "🚨 FRAUDE CONFIRMADA!",
           body: "Bloqueado: ${alert.sender} - ${alert.threatCategory}",
           payload: alert.id,
         );
      } else if (alert.riskScore >= 0.60) {
         _notificationService.showThreatNotification(
           id: alert.timestamp.millisecondsSinceEpoch ~/ 1000,
           title: "⚠️ ATENÇÃO: POSSÍVEL GOLPE",
           body: "Análise de risco detectou padrões suspeitos em ${alert.sender}",
           payload: alert.id,
         );
      } else if (alert.riskScore >= 0.50) {
         _notificationService.showThreatNotification(
           id: alert.timestamp.millisecondsSinceEpoch ~/ 1000,
           title: "Mensagem Suspeita",
           body: "Analise com cuidado: ${alert.sender}",
           payload: alert.id,
         );
      }
      
      // Notifica a UI final (com o texto original para o usuário)
      _threatAlertController.add(alert);
      
    } catch (e) {
      print("Erro ao processar SMS: $e");
    }
  }

  /// Verifica se o remetente é seguro (Whitelist, Contatos ou Short Code Oficial)
  Future<bool> _isSenderSafe(String sender, {bool isHeadless = false}) async {
    // 1. Whitelist do Usuário (DB)
    try {
      // PROTEÇÃO CONTRA NULL CHECK OPERATOR (Erro Crítico em Headless)
      // Se vectorDataSource ou seu DB interno não estiverem prontos, retornamos false
      // em vez de quebrar a aplicação.
      if (vectorDataSource == null) {
         print("⚠️ Whitelist: vectorDataSource é nulo. Pulando verificação.");
         return false; 
      }
      
      final isWhitelisted = await vectorDataSource.isWhitelisted(sender);
      if (isWhitelisted) return true;
      
    } catch (e) {
      print("⚠️ Erro ao verificar whitelist local (Safe Fallback): $e");
      // Fallback seguro: Assume que não está na whitelist se der erro no banco
      return false;
    }

    // 2. Short Codes Oficiais (Lista Estática)
    // Remove caracteres não numéricos para comparar
    final cleanSender = sender.replaceAll(RegExp(r'\D'), '');
    if (_officialShortCodes.contains(cleanSender)) return true;
    
    // 3. Contatos do Dispositivo (CRÍTICO: Evitar em Headless)
    if (isHeadless) {
      print("👻 [Headless] Pulando verificação de contatos para evitar crash de Activity/Context.");
      return false; // Assume não seguro e processa
    }

    // Requer permissão. Se não tiver, ignora silenciosamente.
    try {
      if (await Permission.contacts.isGranted) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        // Verifica se algum contato possui este número
        // Normalização básica: verificar se o número do remetente está contido no número do contato ou vice-versa
        // Isso é complexo devido a formatos (+55, 0xx, etc).
        // Simplificação: contains
        for (final contact in contacts) {
           for (final phone in contact.phones) {
              final cleanPhone = phone.number.replaceAll(RegExp(r'\D'), '');
              if (cleanPhone.isNotEmpty && (cleanPhone == cleanSender || cleanPhone.endsWith(cleanSender) || cleanSender.endsWith(cleanPhone))) {
                 return true;
              }
           }
        }
      }
    } catch (e) {
      print("Erro ao verificar contatos: $e");
    }
    
    return false;
  }


  void dispose() {
    _threatAlertController.close();
  }
}
