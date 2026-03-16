import 'package:flutter/widgets.dart'; // Importação para WidgetsBindingObserver
import 'package:flutter/foundation.dart';
import 'package:smssecurity/core/services/global_intelligence_service.dart';
import 'package:smssecurity/core/services/threat_analysis_service.dart';
import 'package:smssecurity/features/threat_analysis/domain/entities/threat_alert.dart';

class ThreatProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ThreatAnalysisService threatAnalysisService;
  List<ThreatAlert> _alerts = [];
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = false;

  ThreatProvider({required this.threatAnalysisService}) {
    _listenToThreats();
    
    // Registra observador de ciclo de vida
    WidgetsBinding.instance.addObserver(this);
    
    // Carga inicial
    loadHistory();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("🔄 App Resumed: Recarregando histórico de ameaças...");
      loadHistory();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<ThreatAlert> get alerts => _alerts;
  List<Map<String, dynamic>> get history => _history;
  bool get isLoading => _isLoading;

  void _listenToThreats() {
    threatAnalysisService.threatAlertStream.listen((alert) {
      // Verifica se já existe um alerta com o mesmo ID
      final index = _alerts.indexWhere((a) => a.id == alert.id);
      
      if (index != -1) {
        // Atualiza o alerta existente
        _alerts[index] = alert;
      } else {
        // Insere novo alerta no topo
        _alerts.insert(0, alert);
      }
      notifyListeners();
    });
  }

  Future<void> loadHistory({int limit = 50, DateTime? startDate, DateTime? endDate}) async {
    _isLoading = true;
    notifyListeners();
    try {
       _history = await threatAnalysisService.vectorDataSource.getHistory(limit: limit, startDate: startDate, endDate: endDate);
    } catch (e) {
       print("Erro ao carregar histórico: $e");
    } finally {
       _isLoading = false;
       notifyListeners();
    }
  }

  Future<void> deleteHistoryItems(List<int> ids) async {
    try {
      await threatAnalysisService.vectorDataSource.deleteHistoryItems(ids);
      // Remove localmente para refletir na UI instantaneamente
      _history.removeWhere((item) => ids.contains(item['id']));
      notifyListeners();
    } catch (e) {
      print("Erro ao excluir itens do histórico: $e");
    }
  }

  void clearAlerts() {
    _alerts.clear();
    notifyListeners();
  }

  /// Marca um alerta como fraude confirmada pelo usuário
  Future<void> confirmFraud(int id, String sender, String body, String category) async {
    try {
      // 1. Atualiza no Banco Local (Isolate)
      await threatAnalysisService.vectorDataSource.updateRiskScore(id, 1.0);
      
      // 2. Reporta para a Inteligência Global (Forçando envio)
      // Usamos um serviço auxiliar ou injetamos GlobalIntelligenceService aqui.
      // Como ThreatAnalysisService tem acesso ao Global, mas não expõe, 
      // podemos usar uma instância nova aqui (não ideal) ou adicionar método no ThreatAnalysisService.
      // Melhor adicionar um método helper no ThreatAnalysisService ou acessar o global service se ele fosse público.
      // O ThreatAnalysisService tem _globalIntelligenceService privado.
      // Vou criar uma instância aqui por simplicidade e urgência, já que é stateless HTTP.
      final globalService = GlobalIntelligenceService();
      await globalService.reportScam(
        text: body,
        sender: sender,
        category: category,
        riskScore: 1.0,
        force: true
      );

      // 3. Atualiza lista localmente para refletir na UI sem reload completo
      final index = _history.indexWhere((item) => item['id'] == id);
      if (index != -1) {
        _history[index]['riskScore'] = 1.0;
        _history[index]['category'] = category == "Desconhecido" ? "Fraude Confirmada" : category;
        notifyListeners();
      }
      
      print("✅ Fraude confirmada manualmente para ID $id");
    } catch (e) {
      print("Erro ao confirmar fraude: $e");
    }
  }

  /// Marca um alerta como falso positivo / seguro
  Future<void> markAsSafe(ThreatAlert alert) async {
    try {
      // 1. Adiciona à Whitelist
      await threatAnalysisService.vectorDataSource.addToWhitelist(alert.sender);
      
      // 2. Remove do Histórico de Ameaças (Aprendizado Corretivo)
      await threatAnalysisService.vectorDataSource.deleteFromHistory(alert.sender, alert.originalBody);
      
      // 3. Remove da lista atual de alertas visíveis
      _alerts.removeWhere((a) => a.id == alert.id);
      
      // 4. Recarrega histórico para refletir mudanças na UI
      await loadHistory();
      
      print("✅ Alerta marcado como seguro e removido do histórico.");
    } catch (e) {
      print("Erro ao marcar como seguro: $e");
    }
  }
}
