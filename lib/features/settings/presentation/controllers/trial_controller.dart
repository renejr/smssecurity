import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smssecurity/core/constants/api_constants.dart';
import 'package:smssecurity/core/services/payment_service.dart';
import 'package:smssecurity/core/services/admob_service.dart'; // Adicionar Import

class TrialController extends ChangeNotifier {
  bool _isPremium = false;
  int _daysRemaining = 0;
  String _status = "checking"; // checking, active, expired, premium_override, premium_purchased
  String _deviceId = "";
  bool _isForceExpired = false; // Feature Toggle para Debug

  bool get isPremium => _isPremium;
  int get daysRemaining => _daysRemaining;
  String get status => _status;
  String get deviceId => _deviceId; // Getter público para acessar o ID em outros lugares
  // Método para acionar o Mock de Compra e atualizar a UI
  Future<void> simulatePurchaseSuccess() async {
    await PaymentService().activateMockPremium();
    await checkTrialStatus(); // Revalida e atualiza UI
  }

  // Método para Resetar o Mock (Voltar a ser Free)
  Future<void> resetPurchaseMock() async {
    await PaymentService().deactivateMockPremium();
    // Limpa estado local
    _isPremium = false;
    _status = "checking";
    notifyListeners();
    await checkTrialStatus(); // Revalida
  }

  bool get isForceExpired => _isForceExpired;

  /// Alterna o modo de Expiração Forçada para testes de UI (Paywall/Ads)
  void toggleForceExpired(bool value) {
    _isForceExpired = value;
    if (_isForceExpired) {
      _isPremium = false;
      _daysRemaining = 0;
      _status = "trial_expired";
      notifyListeners();
      // Recarrega anúncios imediatamente ao forçar expiração
      AdmobService.refreshAds(_isPremium, true, _isForceExpired);
      print("🛑 DEBUG: Trial expirado forçadamente.");
    } else {
      print("🔄 DEBUG: Restaurando estado real do Trial...");
      checkTrialStatus(); // Consulta o servidor novamente para restaurar o estado real
    }
  }

  Future<void> checkTrialStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 0. Inicializa e Checa Assinatura Real (RevenueCat ou Mock)
      // Se tiver assinatura ativa, ela SOBRESCREVE qualquer trial ou expiração.
      final paymentService = PaymentService();
      await paymentService.init();
      final isRealPremium = await paymentService.checkPremiumStatus();

      if (isRealPremium) {
        _isPremium = true;
        _status = "premium_purchased";
        _daysRemaining = 999;
        notifyListeners();
        // Recarrega anúncios (para sumir com eles)
        AdmobService.refreshAds(_isPremium, false, false);
        print("💎 Assinatura Premium Ativa (RevenueCat/Mock)!");
        return;
      }

      // 1. Check Dev Override (Secret 5 Taps)
      final devOverride = prefs.getBool('dev_premium_override') ?? false;
      if (devOverride) {
        _isPremium = true;
        _status = "premium_override";
        _daysRemaining = 999;
        notifyListeners();
        print("🔓 Premium ativado via Dev Override!");
        return;
      }

      // 2. Get Device ID
      _deviceId = await _getDeviceId();
      if (_deviceId.isEmpty) {
        // Fallback para não bloquear em erro de device id
        _isPremium = false;
        _status = "error_device_id";
        notifyListeners();
        return;
      }

      // 3. Consult Server
      final uri = Uri.parse(ApiConstants.trialStatusEndpoint);
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"device_id": _deviceId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isValid = data['is_valid'] as bool;
        final days = data['days_remaining'] as int;
        
        _isPremium = isValid; // Trial válido = Premium temporário
        _daysRemaining = days;
        _status = isValid ? "trial_active" : "trial_expired";
        
        notifyListeners();
        
        // Dispara recarga de anúncios se expirou
        if (_status == "trial_expired") {
           AdmobService.refreshAds(_isPremium, true, _isForceExpired);
        }
        
        print("📅 Trial Status: $_status ($days dias restantes)");
      } else {
        print("⚠️ Erro servidor trial: ${response.statusCode}");
        // Em caso de erro de servidor, mantém estado anterior ou bloqueia?
        // Política de Fail-Open: Se servidor cair, libera acesso básico, mas não premium.
        // Como o app é de segurança, funcionalidades core não devem ser bloqueadas.
        // O Premium aqui seria para features extras.
      }

    } catch (e) {
      print("Erro ao verificar trial: $e");
    }
  }

  Future<void> activateDevPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_premium_override', true);
    await checkTrialStatus(); // Recarrega estado
  }

  Future<void> resetDevPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dev_premium_override');
    await checkTrialStatus();
  }

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id; // ANDROID_ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? "unknown_ios";
      }
    } catch (e) {
      print("Erro ao obter Device ID: $e");
    }
    return "unknown_device";
  }
}
