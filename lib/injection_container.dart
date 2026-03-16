import 'package:get_it/get_it.dart';
import 'package:smssecurity/core/services/threat_analysis_service.dart';
import 'package:smssecurity/core/services/threat_isolate_manager.dart';
import 'package:smssecurity/features/threat_analysis/data/datasources/local_llm_datasource.dart';
import 'package:smssecurity/features/threat_analysis/data/datasources/local_vector_datasource.dart';
import 'package:smssecurity/features/threat_analysis/data/repositories/threat_repository_impl.dart';
import 'package:smssecurity/features/threat_analysis/domain/repositories/threat_repository.dart';
import 'package:smssecurity/features/threat_analysis/domain/usecases/analyze_sms_usecase.dart';
import 'package:smssecurity/features/threat_analysis/presentation/providers/threat_provider.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // --- Core ---
  // O VectorDbService e BertLocalService agora são geridos pelo IsolateManager
  // Não precisamos registrá-los como Singleton na Main Thread, pois rodam isolados.
  
  final isolateManager = ThreatIsolateManager();
  // init() será chamado pelo LocalVectorDataSource com o path correto
  sl.registerSingleton<ThreatIsolateManager>(isolateManager);

  // --- Data Sources ---
  sl.registerLazySingleton<LocalVectorDataSource>(
    () => LocalVectorDataSourceImpl(
      isolateManager: sl(),
    ),
  );
  sl.registerLazySingleton<LocalLlmDataSource>(
    () => LocalLlmDataSourceImpl(),
  );

  // --- Repository ---
  sl.registerLazySingleton<ThreatRepository>(
    () => ThreatRepositoryImpl(
      vectorDataSource: sl(),
      llmDataSource: sl(),
    ),
  );

  // --- Use Cases ---
  sl.registerLazySingleton(() => AnalyzeSmsUseCase(sl()));

  // --- Services ---
  // Inicializa o serviço que escuta o MethodChannel nativo
  sl.registerSingleton<ThreatAnalysisService>(
    ThreatAnalysisService(
      analyzeSmsUseCase: sl(),
      vectorDataSource: sl(),
    ),
  );

  // --- Providers (Presentation) ---
  sl.registerFactory(
    () => ThreatProvider(threatAnalysisService: sl()),
  );
}
