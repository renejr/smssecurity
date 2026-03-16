import 'package:equatable/equatable.dart';

class ThreatAlert extends Equatable {
  final String id;
  final String sender;
  final String originalBody;
  final double riskScore; // 0.0 a 1.0 (ou 0-100)
  final String threatCategory; // ex: "Phishing", "Bank Fraud", "Safe"
  final String reasoning; // Explicação do LLM
  final DateTime timestamp;
  final bool isVerifying; // Estado de carregamento da verificação externa
  final bool isExternalConfirmed; // Se foi confirmado por fonte externa (VirusTotal)
  final String? deviceId; // ID do dispositivo para Telemetria

  const ThreatAlert({
    required this.id,
    required this.sender,
    required this.originalBody,
    required this.riskScore,
    required this.threatCategory,
    required this.reasoning,
    required this.timestamp,
    this.isVerifying = false,
    this.isExternalConfirmed = false,
    this.deviceId,
  });

  @override
  List<Object?> get props => [id, sender, originalBody, riskScore, threatCategory, reasoning, timestamp, isVerifying, isExternalConfirmed, deviceId];

  ThreatAlert copyWith({
    String? id,
    String? sender,
    String? originalBody,
    double? riskScore,
    String? threatCategory,
    String? reasoning,
    DateTime? timestamp,
    bool? isVerifying,
    bool? isExternalConfirmed,
    String? deviceId,
  }) {
    return ThreatAlert(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      originalBody: originalBody ?? this.originalBody,
      riskScore: riskScore ?? this.riskScore,
      threatCategory: threatCategory ?? this.threatCategory,
      reasoning: reasoning ?? this.reasoning,
      timestamp: timestamp ?? this.timestamp,
      isVerifying: isVerifying ?? this.isVerifying,
      isExternalConfirmed: isExternalConfirmed ?? this.isExternalConfirmed,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
