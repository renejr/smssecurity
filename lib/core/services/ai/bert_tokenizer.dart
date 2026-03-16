import 'package:flutter/services.dart';

class BertTokenizer {
  Map<String, int> vocab = {};
  final int maxLen;
  final bool doLowerCase = true;

  BertTokenizer._({
    required this.vocab,
    this.maxLen = 128,
  });

  /// Carrega o vocabulário de um asset
  static Future<BertTokenizer> fromAsset(String assetPath, {int maxLen = 128}) async {
    try {
      final vocabString = await rootBundle.loadString(assetPath);
      return fromString(vocabString, maxLen: maxLen);
    } catch (e) {
      print('Erro ao carregar vocab: $e');
      // Fallback para vocab vazio em caso de erro, evitando crash
      return BertTokenizer._(vocab: {});
    }
  }

  /// Carrega o vocabulário de uma String direta (útil para Isolates)
  static BertTokenizer fromString(String vocabContent, {int maxLen = 128}) {
    final lines = vocabContent.split('\n');
    final Map<String, int> vocabMap = {};
    
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        vocabMap[token] = i;
      }
    }
    return BertTokenizer._(vocab: vocabMap, maxLen: maxLen);
  }

  /// Tokeniza o texto e retorna os IDs para o modelo BERT
  /// Retorna um List<int> com tamanho fixo [maxLen] (padded)
  List<int> tokenize(String text) {
    if (vocab.isEmpty) return List.filled(maxLen, 0);

    String processedText = text;
    if (doLowerCase) {
      processedText = processedText.toLowerCase();
    }

    // Normalização básica: remove acentos e caracteres especiais
    // Em produção, usar pacote 'diacritic' ou similar
    processedText = processedText
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^\w\s]'), ' '); // Remove pontuação
    
    final words = processedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    
    // IDs especiais (padrão BERT)
    final int clsId = vocab['[CLS]'] ?? 101;
    final int sepId = vocab['[SEP]'] ?? 102;
    final int unkId = vocab['[UNK]'] ?? 100;
    final int padId = vocab['[PAD]'] ?? 0;

    final List<int> ids = [];

    // [CLS] no início
    ids.add(clsId);

    for (final word in words) {
      if (ids.length >= maxLen - 1) break; // Reserva espaço para [SEP]

      if (vocab.containsKey(word)) {
        ids.add(vocab[word]!);
      } else {
        // Fallback simples para UNK
        // O ideal seria WordPiece (ex: "correndo" -> "corren" + "##do")
        // Mas requer lógica complexa de prefixo. 
        // Para MVP, se a palavra exata não existe, é UNK.
        ids.add(unkId);
      }
    }

    // [SEP] no final
    if (ids.length < maxLen) {
      ids.add(sepId);
    } else {
      // Se estourou, substitui o último por SEP
      ids[maxLen - 1] = sepId;
    }

    // Padding [PAD] até completar maxLen
    while (ids.length < maxLen) {
      ids.add(padId);
    }

    return ids;
  }
}
