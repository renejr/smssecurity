import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:smssecurity/core/constants/api_constants.dart';

class GlobalIntelligenceService {
  /// Consulta a Inteligência Global (Backend) para verificar se o SMS é um golpe conhecido.
  /// Retorna um Map com o resultado ou null se não houver match.
  Future<Map<String, dynamic>?> checkGlobalThreat(String text) async {
    try {
      final uri = Uri.parse(ApiConstants.analyzeGlobalEndpoint);
      
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"text": text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'CONFIRMED_SCAM') {
          return data;
        }
      }
      return null;
    } catch (e) {
      print('Erro ao consultar Inteligência Global: $e');
      return null;
    }
  }

  /// Envia um reporte de golpe para a base global.
  /// Retorna true se enviado com sucesso.
  /// 
  /// [force] = true ignora o filtro de confiança mínima (para reportes manuais).
  Future<bool> reportScam({
    required String text, 
    required String sender, 
    required String category, 
    required double riskScore,
    bool force = false,
  }) async {
    // Filtro de Confiança (Regra de Negócio)
    // Apenas envia automaticamente se score >= 0.85
    if (!force && riskScore < 0.85) {
      print("[GlobalSync] Bloqueado: Confiança insuficiente ($riskScore < 0.85) para envio automático.");
      return false;
    }

    try {
      final uri = Uri.parse(ApiConstants.reportThreatEndpoint);
      
      final body = {
        "text": text,
        "sender": sender,
        "category": category,
        "risk_score": riskScore,
        "manual_confirmation": force,
        "timestamp": DateTime.now().toIso8601String(),
      };

      print("📤 Enviando reporte global (Force: $force, Score: $riskScore)...");

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ Reporte global enviado com sucesso!");
        return true;
      } else {
        print("❌ Falha no envio global: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      print("⚠️ Erro de conexão ao reportar: $e");
      return false;
    }
  }

  /// Obtém estatísticas globais da comunidade (Total de golpes, bloqueios, usuários)
  Future<Map<String, dynamic>?> getCommunityStats() async {
    try {
      final uri = Uri.parse(ApiConstants.statsSummaryEndpoint);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Erro ao buscar stats globais: $e');
      return null;
    }
  }
}
