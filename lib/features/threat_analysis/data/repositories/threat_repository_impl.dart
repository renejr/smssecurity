import 'package:smssecurity/features/threat_analysis/data/datasources/local_llm_datasource.dart';
import 'package:smssecurity/features/threat_analysis/data/datasources/local_vector_datasource.dart';
import 'package:smssecurity/features/threat_analysis/domain/entities/threat_alert.dart';
import 'package:smssecurity/features/threat_analysis/domain/repositories/threat_repository.dart';
import 'package:uuid/uuid.dart';

class ThreatRepositoryImpl implements ThreatRepository {
  final LocalVectorDataSource vectorDataSource;
  final LocalLlmDataSource llmDataSource;
  final _uuid = const Uuid();

  ThreatRepositoryImpl({required this.vectorDataSource, required this.llmDataSource});

  @override
  Future<ThreatAlert> analyzeSms(String sender, String body) async {
    // 1. Busca similaridade no RAG local
    final similarThreats = await vectorDataSource.findSimilarThreats(body);

    // 2. Consulta o LLM Local com contexto
    final analysisResult = await llmDataSource.analyzeWithContext(body, similarThreats);

    // 3. Constrói a entidade de domínio
    return ThreatAlert(
      id: _uuid.v4(),
      sender: sender,
      originalBody: body,
      riskScore: analysisResult['score'] as double,
      threatCategory: analysisResult['category'] as String,
      reasoning: analysisResult['reasoning'] as String,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<void> learnThreatPattern(String body, String category) async {
    // Simula a adição ao banco vetorial.
    // Em um sistema real, o embedding deve ser calculado aqui ou no servidor.
    // Vamos usar um placeholder para o embedding.
    final embedding = List.generate(512, (index) => 0.5); // Ajustado para 512 (BERT Mobile)
    await vectorDataSource.saveThreatPattern(body, category, embedding);
  }
}
