class BaitExtractor {
  /// Extrai URLs do texto
  static List<String> extractUrls(String text) {
    final urlRegExp = RegExp(
      r'((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?',
      caseSensitive: false,
    );
    return urlRegExp.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// Extrai números de telefone (celular, fixo, 0800, 4004, 3003)
  static List<String> extractPhoneNumbers(String text) {
    // Simplificação para capturar sequências numéricas que parecem telefones no contexto de SMS
    // Muitas vezes golpistas usam formatos variados. Vamos focar nos padrões de centrais de atendimento e celulares.
    final simplePhoneRegex = RegExp(
      r'\b(?:0800|4004|3003)[- ]?\d{3,4}(?:[- ]?\d{4})?\b|\b(?:\(?\d{2}\)?\s?)?9?\d{4}[- ]?\d{4}\b',
    );

    return simplePhoneRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// Extrai todas as iscas (URLs e Telefones)
  static List<String> extractAllBaits(String text) {
    final urls = extractUrls(text);
    final phones = extractPhoneNumbers(text);
    return [...urls, ...phones].toSet().toList(); // Remove duplicatas
  }
}