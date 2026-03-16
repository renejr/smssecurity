import 'package:flutter/services.dart' show rootBundle;

abstract class LocalLlmDataSource {
  /// Inicializa recursos do LLM (carrega assets, vocabulários, etc) de forma lazy.
  Future<void> initialize();

  /// Executa a inferência do LLM local para analisar a ameaça.
  /// [smsBody]: O conteúdo do SMS.
  /// [similarThreats]: Lista de ameaças similares encontradas no RAG.
  /// Retorna um Map com {score: double, reasoning: String, category: String}
  Future<Map<String, dynamic>> analyzeWithContext(String smsBody, List<Map<String, dynamic>> similarThreats);
}

class LocalLlmDataSourceImpl implements LocalLlmDataSource {
  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    print("🧠 Inicializando LocalLlmDataSource (Lazy Loading)...");
    
    // Simula carga de assets pesados (vocab, modelos .tflite, .bin)
    try {
      // Esta chamada deve ser feita após ensureInitialized(), o que já garantimos no main/background.
      // Em um cenário real com BERT, faríamos:
      // final vocabString = await rootBundle.loadString('assets/models/vocab.txt');
      // _tokenizer = BertTokenizer.fromString(vocabString);
    } catch (e) {
      print("⚠️ Erro ao carregar assets do LLM: $e");
    }

    await Future.delayed(Duration(milliseconds: 100));
    
    _isInitialized = true;
    print("🧠 LocalLlmDataSource pronto.");
  }

  @override
  Future<Map<String, dynamic>> analyzeWithContext(String smsBody, List<Map<String, dynamic>> similarThreats) async {
    if (!_isInitialized) await initialize(); // Garante inicialização sob demanda se necessário
    
    // 1. Constrói o Prompt com RAG
    _buildPrompt(smsBody, similarThreats);
    
    // 2. Envia para o modelo local (Simulação por enquanto)
    // Em produção: await methodChannel.invokeMethod('analyzeSMS', {'prompt': prompt});
    // Ou via FFI binding direto com llama.cpp
    
    // Simula processamento assíncrono do modelo
    await Future.delayed(Duration(milliseconds: 500));
    
    // Lógica simples baseada no RAG para simular a resposta do LLM
    double maxSimilarity = 0.0;
    String bestMatchCategory = "Safe";
    
    if (similarThreats.isNotEmpty) {
      maxSimilarity = similarThreats.first['similarity'] as double;
      bestMatchCategory = similarThreats.first['category'] as String;
    }

    // Heurística simples de fallback se o modelo não responder bem
    // Se a similaridade for alta (> 0.8), confia no RAG.
    // Se não, o LLM analisaria o texto semanticamente.
    
    double riskScore = maxSimilarity; // Simplificação
    String reasoning = "Análise baseada em ${similarThreats.length} padrões similares encontrados.";
    
    if (smsBody.toLowerCase().contains("pix") || smsBody.toLowerCase().contains("bloqueio")) {
      riskScore = 0.95;
      bestMatchCategory = "Phishing Bancário";
      reasoning = "Palavras-chave de alta periculosidade detectadas (PIX/Bloqueio).";
    }

    return {
      'score': riskScore,
      'reasoning': reasoning,
      'category': riskScore > 0.5 ? bestMatchCategory : "Safe",
    };
  }

  String _buildPrompt(String smsBody, List<Map<String, dynamic>> context) {
    final sb = StringBuffer();
    sb.writeln("Analise o seguinte SMS e determine se é um golpe (Phishing/Fraud) ou legítimo.");
    sb.writeln("Responda com JSON: {risk_score: 0-1, category: string, reasoning: string}");
    sb.writeln("\nContexto (Casos similares conhecidos):");
    for (final threat in context) {
      sb.writeln("- [${threat['category']}] ${threat['text']} (Similaridade: ${threat['similarity']})");
    }
    sb.writeln("\nSMS para análise: \"$smsBody\"");
    return sb.toString();
  }
}
