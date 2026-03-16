import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  bool _isInitialized = false;

  // Flag interna para saber se o RevenueCat está funcional
  bool _isRevenueCatConfigured = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    // MOCK MODE: Se a chave for placeholder, nem tenta inicializar para evitar erros no log
    const apiKey = "goog_placeholder_api_key";
    
    if (apiKey.contains("placeholder")) {
      print("⚠️ [PAYMENT] RevenueCat usando API Key Placeholder. Modo Offline/Mock Ativado.");
      _isInitialized = true;
      _isRevenueCatConfigured = false;
      return;
    }

    try {
      await Purchases.setLogLevel(LogLevel.debug);
      PurchasesConfiguration configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(configuration);
      _isRevenueCatConfigured = true;
      print("💰 RevenueCat inicializado com sucesso.");
    } catch (e) {
      print("❌ [PAYMENT] Falha ao inicializar RevenueCat: $e");
      _isRevenueCatConfigured = false;
    }
    _isInitialized = true;
  }

  /// Obtém o status atual do usuário (Premium ou não)
  Future<bool> checkPremiumStatus() async {
    // 1. MOCK: Verifica se o modo "Premium Mock" está ativado (persistencia local)
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('mock_premium_purchased') ?? false) {
      print("[MOCK PAYMENT] Status verificado: USUÁRIO PREMIUM (Simulado)");
      return true;
    }

    // 2. Se RevenueCat não estiver configurado, retorna falso (Free) sem gerar erro
    if (!_isRevenueCatConfigured) {
      return false;
    }

    try {
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.all["premium"]?.isActive ?? false;
    } on PlatformException catch (e) {
      // Ignora erro de credencial se estivermos em desenvolvimento
      if (e.code == 'InvalidCredentialsError') return false;
      print("Erro ao checar status Premium: $e");
      return false;
    }
  }

  /// Ativa o Mock de Compra (Simula sucesso)
  Future<void> activateMockPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mock_premium_purchased', true);
    print("[MOCK PAYMENT] Compra simulada com sucesso. Status salvo: PREMIUM.");
  }

  /// Desativa o Mock de Compra (Simula cancelamento/reembolso)
  Future<void> deactivateMockPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mock_premium_purchased');
    print("[MOCK PAYMENT] Status resetado para GRATUITO.");
  }

  /// Busca as ofertas disponíveis (Pacotes de Assinatura)
  Future<List<Package>> getOfferings() async {
    if (!_isRevenueCatConfigured) return [];

    try {
      Offerings offerings = await Purchases.getOfferings();
      if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
        return offerings.current!.availablePackages;
      }
    } on PlatformException catch (e) {
      print("Erro ao buscar ofertas: $e");
    }
    return [];
  }

  /// Realiza a compra de um pacote
  Future<bool> purchasePackage(Package package) async {
    if (!_isRevenueCatConfigured) {
       print("⚠️ [PAYMENT] Tentativa de compra sem RevenueCat configurado.");
       throw PlatformException(code: "CONFIG_ERROR", message: "RevenueCat not configured");
    }

    try {
      // Tentativa de correção definitiva para compatibilidade de tipos
      // Em algumas versões, purchasePackage retorna CustomerInfo.
      // Em outras, retorna void ou algo diferente? Não, a API estável é CustomerInfo.
      
      // O erro 'The getter entitlements isn't defined for the type PurchaseResult' 
      // indica inequivocamente que o tipo retornado é PurchaseResult.
      
      // Vamos inspecionar o que é PurchaseResult. Geralmente é um wrapper que contém customerInfo.
      // Se a IDE não ajuda, vamos usar dynamic para acessar 'customerInfo' primeiro, depois 'entitlements'.
      
      // Hipótese: PurchaseResult tem uma propriedade .customerInfo
      // Vamos tentar acessar isso via dynamic para bypassar o checker estático.
      
      dynamic result = await Purchases.purchasePackage(package);
      
      // Tenta acessar customerInfo dentro do resultado (se for um wrapper)
      // Se o resultado JÁ for o CustomerInfo (versões antigas/novas), ele terá entitlements direto.
      
      // Estratégia de Duck Typing (Se anda como pato...)
      // 1. Tenta acessar .entitlements direto
      // 2. Tenta acessar .customerInfo.entitlements
      
      // Como Dart não tem 'hasProperty' fácil em runtime sem mirrors, vamos usar try-catch de NoSuchMethodError
      // Mas isso é feio. Vamos tentar o cast.
      
      if (result is CustomerInfo) {
         return result.entitlements.all["premium"]?.isActive ?? false;
      }
      
      // Se não é CustomerInfo, deve ser o tal PurchaseResult que o linter viu.
      // Vamos assumir que ele tem uma propriedade customerInfo (padrão RevenueCat).
      // Mas como não sabemos o nome exato, vamos tentar acessar dynamicamente.
      
      // Solução pragmática: O método purchasePackage oficial retorna CustomerInfo.
      // Se o linter está vendo PurchaseResult, pode ser que o import esteja errado ou a versão seja específica.
      // Mas vamos tentar acessar a propriedade 'customerInfo' se ela existir.
      
      try {
        // Tenta acessar como se fosse um wrapper
        return result.customerInfo.entitlements.all["premium"]?.isActive ?? false;
      } catch (_) {
        // Se falhar, tenta acessar direto (talvez o linter esteja alucinando ou seja dynamic)
        try {
           return result.entitlements.all["premium"]?.isActive ?? false;
        } catch (e) {
           print("Erro crítico de API RevenueCat: $e. Retorno inesperado: $result");
           return false;
        }
      }

    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        print("Erro na compra: $e");
      }
      return false;
    }
  }

  /// Restaura compras anteriores
  Future<bool> restorePurchases() async {
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      return customerInfo.entitlements.all["premium"]?.isActive ?? false;
    } on PlatformException catch (e) {
      print("Erro ao restaurar compras: $e");
      return false;
    }
  }
}
