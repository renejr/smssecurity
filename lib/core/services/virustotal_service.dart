import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:smssecurity/core/constants/api_constants.dart';

class VirusTotalService {
  /// Extrai URLs do corpo da mensagem
  List<String> extractUrls(String text) {
    // Regex simples para URLs (http/https/www)
    final urlRegExp = RegExp(
      r'((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&//=]*)?',
      caseSensitive: false,
    );
    
    return urlRegExp.allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
  }

  /// Verifica se uma URL é maliciosa consultando o Backend
  Future<bool> checkUrl(String urlToCheck, {String? smsText}) async {
    try {
      final uri = Uri.parse(ApiConstants.scanUrlEndpoint);
      
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "url": urlToCheck,
          "sms_text": smsText
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // O backend retorna {"malicious": bool, ...}
        return data['malicious'] as bool? ?? false;
      } else {
         print('Erro backend VirusTotal: ${response.statusCode} ${response.body}');
         return false;
      }
    } catch (e) {
      print('Erro de conexão ao consultar VirusTotal via Backend: $e');
      return false;
    }
  }
}
