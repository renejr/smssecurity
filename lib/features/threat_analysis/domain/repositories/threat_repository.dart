import 'package:smssecurity/features/threat_analysis/domain/entities/threat_alert.dart';

abstract class ThreatRepository {
  /// Analisa um SMS recebido e retorna um alerta de ameaça detalhado.
  /// 
  /// [sender]: Número ou identificador do remetente.
  /// [body]: Conteúdo da mensagem SMS.
  Future<ThreatAlert> analyzeSms(String sender, String body);

  /// Salva um novo padrão de golpe conhecido (feedback loop do usuário ou do sistema).
  Future<void> learnThreatPattern(String body, String category);
}
