import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:smssecurity/core/constants/api_constants.dart';

class GoogleCustomSearchService {
  /// Consulta uma isca (telefone, link, etc.) no Backend (que consulta o Google)
  /// Retorna o número total de resultados encontrados.
  Future<int> checkReclameAqui(String bait, {String? smsText}) async {
    try {
      final uri = Uri.parse(ApiConstants.scanPhoneEndpoint);
      
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": bait,
          "sms_text": smsText // Envia o texto completo para vacina se necessário
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // O backend retorna {"complaints": int}
        return data['complaints'] as int? ?? 0;
      } else {
        print('Erro backend Google: ${response.statusCode} ${response.body}');
        return 0;
      }
    } catch (e) {
      print('Erro de conexão ao consultar Google via Backend: $e');
      return 0;
    }
  }
}
