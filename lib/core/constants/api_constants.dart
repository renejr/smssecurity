class ApiConstants {
  // ===========================================================================
  // CONFIGURAÇÃO DE REDE (VPS / LOCALHOST)
  // ===========================================================================
  // 
  // [DEV LOCAL] (Cloudflare Tunnel)
  // Use esta URL enquanto estiver desenvolvendo localmente e expondo via tunnel.
  static const String _devUrl = 'https://rest-cannon-geographic-trains.trycloudflare.com';
  
  // [PRODUÇÃO VPS] (Sua VPS Linux)
  // Quando fizer o deploy na VPS, descomente a linha abaixo e insira o IP/Domínio real.
  // static const String _prodUrl = 'https://api.escudosms.com.br'; 
  
  // SELETOR DE URL:
  // Alterne entre _devUrl e _prodUrl conforme o ambiente de build.
  static const String baseUrl = _devUrl; 
  
  // ===========================================================================
  // ENDPOINTS
  // ===========================================================================
  static const String scanUrlEndpoint = '$baseUrl/scan/url';
  static const String scanPhoneEndpoint = '$baseUrl/scan/phone';
  static const String analyzeGlobalEndpoint = '$baseUrl/analyze/global';
  static const String reportThreatEndpoint = '$baseUrl/report/threat';
  static const String statsSummaryEndpoint = '$baseUrl/stats/summary';
  static const String trialStatusEndpoint = '$baseUrl/trial/status';
}
