class PrivacyFilter {
  /// Remove dados sensíveis (PII) do texto do SMS para garantir anonimidade
  /// antes de processamento externo ou armazenamento em logs.
  static String sanitizeSms(String text) {
    String sanitized = text;

    // 1. Ocultar CPF (Formato 000.000.000-00 ou 11 dígitos seguidos)
    // Regex para CPF com pontuação
    sanitized = sanitized.replaceAll(
      RegExp(r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b'), 
      '[CPF OCULTO]'
    );

    // 2. Ocultar Valores Monetários (R$ 1.500,00 ou BRL 50,00)
    // Corrigido: Removido (?i) e usando caseSensitive: false
    sanitized = sanitized.replaceAll(
      RegExp(r'(R\$|BRL)\s?\d{1,3}(\.\d{3})*(,\d{2})?', caseSensitive: false), 
      '[VALOR OCULTO]'
    );

    // 3. Ocultar Códigos OTP / Tokens (4 a 8 dígitos isolados)
    sanitized = sanitized.replaceAll(
      RegExp(r'\b\d{4,8}\b'), 
      '[CÓDIGO OCULTO]'
    );

    // 4. Cartões de Crédito (13 a 16 dígitos)
    sanitized = sanitized.replaceAll(
      RegExp(r'\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{1,4}\b'), 
      '[CARTÃO OCULTO]'
    );

    return sanitized;
  }
}
