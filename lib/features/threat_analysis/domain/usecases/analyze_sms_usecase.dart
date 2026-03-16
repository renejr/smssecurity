import 'package:smssecurity/features/threat_analysis/domain/entities/threat_alert.dart';
import 'package:smssecurity/features/threat_analysis/domain/repositories/threat_repository.dart';

class AnalyzeSmsUseCase {
  final ThreatRepository repository;

  AnalyzeSmsUseCase(this.repository);

  Future<ThreatAlert> call(String sender, String body) {
    return repository.analyzeSms(sender, body);
  }
}
