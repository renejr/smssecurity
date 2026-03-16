import 'package:flutter/material.dart';
import 'package:smssecurity/core/services/log_service.dart'; // Importação do LogService
import 'package:permission_handler/permission_handler.dart'; // Importação necessária
import 'package:provider/provider.dart';
import 'package:smssecurity/core/services/notification_service.dart'; // Importação
import 'package:smssecurity/core/services/threat_analysis_service.dart';
import 'package:smssecurity/features/threat_analysis/data/datasources/local_vector_datasource.dart';
import 'package:smssecurity/features/threat_analysis/data/datasources/local_llm_datasource.dart';
import 'package:smssecurity/features/threat_analysis/domain/entities/threat_alert.dart';
import 'package:smssecurity/features/threat_analysis/presentation/providers/threat_provider.dart';
import 'package:smssecurity/features/radar/presentation/radar_screen.dart'; // Import da nova tela Radar
import 'package:smssecurity/features/threat_analysis/presentation/screens/threat_history_screen.dart'; // Import da nova tela
import 'package:smssecurity/features/settings/presentation/settings_screen.dart';
import 'package:smssecurity/features/settings/presentation/widgets/paywall_bottom_sheet.dart'; // Import do Paywall
import 'package:smssecurity/features/settings/presentation/controllers/trial_controller.dart'; // Import Controller
import 'package:smssecurity/core/services/background_service.dart'; // Import Background Service
import 'package:smssecurity/injection_container.dart' as di;
import 'package:share_plus/share_plus.dart';

import 'dart:io'; // Para log local
import 'dart:ui'; // Para DartPluginRegistrant
import 'package:flutter/services.dart'; // Para rootBundle
import 'package:path_provider/path_provider.dart';

import 'package:smssecurity/core/widgets/custom_banner_ad.dart'; // Import CustomBannerAd
import 'package:google_mobile_ads/google_mobile_ads.dart'; // Import AdMob

// Entry point para processamento em background (Headless)
@pragma('vm:entry-point')
void processSmsInBackground(List<String> args) async {
  // Garante binding e plugins ANTES de qualquer coisa
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  // Função auxiliar local para log (para não depender de nada externo ainda)
  Future<void> logHeadless(String msg) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/headless_log.txt');
      final timestamp = DateTime.now().toIso8601String();
      final logMsg = '[$timestamp] $msg\n';
      await file.writeAsString(logMsg, mode: FileMode.append);
      print("👻 HEADLESS_LOG: $msg"); // Também joga no Logcat
    } catch (e) {
      print("❌ Erro ao escrever log headless: $e");
    }
  }

  await logHeadless("Isolate Iniciado. Args: $args");

  // PREPARAÇÃO DE ARQUIVOS (Vocab)
  // Como rootBundle é instável no background, usamos a cópia local feita pela UI principal.
  // Se não existir, tentamos ler (mas pode falhar).
  
  // Inicializa dependências críticas
  // CUIDADO: di.init() pode tentar inicializar coisas que precisam de UI ou Activity
  try {
    await logHeadless("Iniciando Injeção de Dependência (di.init)...");
    await di.init();
    
    // CRÍTICO: Inicializar o Banco de Dados Vectorial no Isolate Headless!
    // Sem isso, a whitelist falha e o app quebra por Null Check Operator.
    await logHeadless("Inicializando LocalVectorDataSource (SQLite)...");
    final dataSource = di.sl<LocalVectorDataSource>();
    await dataSource.initializeData();
    
    // Inicializa IA Lazy Load
    await logHeadless("Inicializando LocalLlmDataSource (BERT/LLM)...");
    try {
      final llmSource = di.sl<LocalLlmDataSource>();
      await llmSource.initialize();
    } catch (e) {
      await logHeadless("⚠️ Aviso: Falha ao inicializar LLM no headless (pode ser esperado se usar MethodChannel): $e");
    }
    
    await logHeadless("di.init e DB concluídos com sucesso.");
  } catch (e) {
    await logHeadless("CRITICAL ERROR: di.init falhou: $e");
    return;
  }
  
  try {
    await logHeadless("Recuperando ThreatAnalysisService...");
    final service = di.sl<ThreatAnalysisService>();
    
    // O Kotlin passará os argumentos como lista: [sender, body]
    if (args.length >= 2) {
      final sender = args[0];
      final body = args[1];
      
      await logHeadless("Iniciando análise direta para: $sender");
      // Passa flag isHeadless: true para evitar chamadas de UI/Activity
      await service.analyzeDirectly(sender, body, isHeadless: true);
      
      await logHeadless("Análise concluída.");
    } else {
      await logHeadless("Argumentos inválidos recebidos: $args");
    }
  } catch (e, stack) {
    await logHeadless("CRITICAL ERROR durante análise: $e\nStack: $stack");
  }
}

void main() async {
  // CRÍTICO: Inicialização do Binding deve ser a PRIMEIRA coisa
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o serviço de log
  await LogService().init();
  await LogService().log("App Iniciado. Preparando AdMob...");
  
  // Inicializa AdMob (Bloqueante para garantir que esteja pronto antes da UI)
  // Removido Lazy Loading de 3s que causava falha em dispositivos reais
  print("📱 Inicializando AdMob SDK...");
  try {
    await MobileAds.instance.initialize();
    await LogService().log("AdMob inicializado com sucesso.");
  } catch (e) {
    await LogService().log("Erro Crítico na inicialização do AdMob: $e");
  }
  
  // Configuração de Dispositivos de Teste (Segurança contra cliques inválidos)
  // Adicione o ID do seu dispositivo real aqui se necessário (aparece no Logcat)
  /*
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ['SEU_DEVICE_ID_AQUI']),
  );
  */

  DartPluginRegistrant.ensureInitialized(); // Garantia extra para plugins
  
  // Inicializa Background Service (Monitoramento Persistente)
  await BackgroundService.initialize();
  
  // COPIA VOCABULÁRIO PARA FILESYSTEM (Bypass rootBundle no Background)
  try {
    final dir = await getApplicationDocumentsDirectory();
    final vocabFile = File('${dir.path}/vocab.txt');
    if (!await vocabFile.exists()) {
      print("📦 Copiando vocab.txt para armazenamento local...");
      // Tenta carregar do asset. Se falhar aqui (UI thread), algo está muito errado com o projeto.
      try {
        final vocabData = await rootBundle.loadString('assets/models/vocab.txt');
        await vocabFile.writeAsString(vocabData);
        print("✅ Vocab copiado com sucesso para: ${vocabFile.path}");
      } catch (e) {
        print("⚠️ Aviso: assets/models/vocab.txt não encontrado. O BERT usará fallback.");
      }
    }
  } catch (e) {
    print("Erro ao preparar arquivos para background: $e");
  }
  
  // Inicializa Notificações
  await NotificationService().init();
  
  // Inicializa Injeção de Dependência
  await di.init();
  
  // ALTERAÇÃO: Forçamos a inicialização do serviço de escuta do MethodChannel
  // Isso liga o "rádio" para ouvir o Kotlin
  di.sl<ThreatAnalysisService>();
  
  // Popula o banco de dados com dados iniciais (se necessário)
  final dataSource = di.sl<LocalVectorDataSource>();
  await dataSource.initializeData();

  // Inicializa IA Lazy Load (Evita erro de Binding na main thread)
  print("🧠 Inicializando LLM/BERT na Main Thread...");
  try {
    final llmSource = di.sl<LocalLlmDataSource>();
    await llmSource.initialize();
  } catch (e) {
    print("⚠️ Falha não crítica na inicialização do LLM: $e");
  }

  // Inicializa Trial Controller
  final trialController = TrialController();
  await trialController.checkTrialStatus(); // Check inicial

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => di.sl<ThreatProvider>()),
        ChangeNotifierProvider(create: (_) => trialController), // Injeta TrialController
      ],
      child: const EscudoApp(),
    ),
  );
}

class EscudoApp extends StatelessWidget {
  const EscudoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Escudo SMS',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
        brightness: Brightness.dark,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    print("🚩 [MainScreen] BUILD CALLED - Nova Estrutura Global Ativa");
    return Scaffold(
      body: Column(
        children: [
          // Banner de Trial Global (Implacável e Reativo)
          Consumer<TrialController>(
            builder: (context, trial, child) {
              print("🔥 [CONSUMER] Estado Recebido: isPremium=${trial.isPremium}, days=${trial.daysRemaining}, status=${trial.status}");
              
              // Lógica de Exibição do Banner:
              // 1. Se NÃO for Premium, exibe (Freemium/Expirado).
              // 2. Se FOR Premium, exibe APENAS se estiver em período de Trial (trial_active).
              // 3. Se FOR Premium Assinante (não trial), não exibe.
              
              bool shouldShow = !trial.isPremium || trial.status == 'trial_active';
              
              if (!shouldShow) {
                print("🚫 [CONSUMER] Bloqueado: Usuário Premium Assinante.");
                return const SizedBox.shrink();
              }

              // Lógica de Cores e Texto
              final isExpired = trial.daysRemaining <= 0; // Se expirado, é freemium. Se > 0, é trial.
              // Correção: Se isPremium e trial_active, não é expirado, mesmo que a contagem bugue.
              // Mas aqui daysRemaining vem do backend e é confiável.
              
              final Color bgColor = isExpired ? Colors.red.shade900 : Colors.orangeAccent;
              final IconData icon = isExpired ? Icons.lock : Icons.hourglass_empty;
              final String message = isExpired 
                  ? "⚠️ Proteção limitada. Faça o upgrade." 
                  : "⏳ Faltam ${trial.daysRemaining} dias de proteção gratuita.";

              return Container(
                width: double.infinity,
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 12, left: 16, right: 16),
                color: bgColor,
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold,
                          fontSize: 14
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: bgColor,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        );
                      },
                      child: const Text("UPGRADE", style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              );
            },
          ),
          const Expanded(
            child: SmsMonitorScreen(),
          ),
          // Banner AdMob no Rodapé (Condicional Interna)
          const CustomBannerAd(),
        ],
      ),
    );
  }
}

class SmsMonitorScreen extends StatefulWidget {
  const SmsMonitorScreen({super.key});

  @override
  State<SmsMonitorScreen> createState() => _SmsMonitorScreenState();
}

class _SmsMonitorScreenState extends State<SmsMonitorScreen> {
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    print("🔒 Solicitando permissões...");
    
    // Solicita múltiplas permissões
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.contacts,
      Permission.notification,
      Permission.ignoreBatteryOptimizations, // Vital para background
    ].request();

    if (statuses[Permission.sms]!.isGranted) {
      print("✅ Permissão de SMS concedida!");
    } else {
      print("❌ Permissão de SMS negada.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ERRO CRÍTICO: Permissão de SMS necessária!")),
        );
      }
    }
    
    if (statuses[Permission.ignoreBatteryOptimizations]!.isGranted) {
       print("✅ Otimização de bateria desativada (Serviço Persistente OK)");
    } else {
       print("⚠️ Otimização de bateria ativa. O sistema pode matar o app.");
       // Opcional: Mostrar diálogo explicando
    }
    
    if (statuses[Permission.contacts]!.isGranted) {
      print("✅ Permissão de Contatos concedida (Whitelist ativa)!");
    } else {
      print("⚠️ Permissão de Contatos negada. Whitelist funcionará apenas com lista manual.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Escudo SMS - Radar IA"),
        actions: [
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Radar MDXHQ',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RadarScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Histórico de Ameaças',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ThreatHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurações e Sobre',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Removido (Elevado para EscudoApp)
          
          // Conteúdo Principal (Scrollável)
          Expanded(
            child: Consumer<ThreatProvider>(
              builder: (context, provider, child) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      // Card Premium (Banner Promocional dentro do Scroll)
                      Card(
                        margin: const EdgeInsets.all(16.0),
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: GestureDetector(
                          onTap: () {
                             Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SettingsScreen()),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Colors.purple, Colors.deepPurple],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            padding: const EdgeInsets.all(16.0),
                            child: const Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 32),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Seja Premium',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Zero Anúncios, Histórico Ilimitado e Whitelist Infinita',
                                        style: TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Lista de Ameaças
                      if (provider.alerts.isEmpty)
                         const Padding(
                           padding: EdgeInsets.all(32.0),
                           child: Column(
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
                               SizedBox(height: 16),
                               Text("Radar Ativo. Aguardando SMS...", style: TextStyle(color: Colors.grey)),
                             ],
                           ),
                         )
                      else
                         ListView.builder(
                            shrinkWrap: true, // Importante dentro de SingleChildScrollView
                            physics: const NeverScrollableScrollPhysics(), // Scroll gerenciado pelo pai
                            itemCount: provider.alerts.length,
                            itemBuilder: (context, index) {
                              // Inverte a ordem para mostrar o mais recente primeiro
                              final alert = provider.alerts[provider.alerts.length - 1 - index];
                              return ThreatCard(alert: alert);
                            },
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ThreatCard extends StatelessWidget {
  final ThreatAlert alert;

  const ThreatCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    // Novos Thresholds
    // Vermelho >= 85% | Amarelo 50-84% | Verde < 50%
    final Color riskColor;
    final IconData riskIcon;
    final String riskLabel;

    if (alert.riskScore >= 0.85) {
       riskColor = Colors.redAccent;
       riskIcon = Icons.dangerous;
       riskLabel = "PERIGO";
    } else if (alert.riskScore >= 0.50) {
       riskColor = Colors.orangeAccent;
       riskIcon = Icons.warning_amber_rounded;
       riskLabel = "SUSPEITO";
    } else {
       riskColor = Colors.greenAccent;
       riskIcon = Icons.verified_user;
       riskLabel = "SEGURO";
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: riskColor.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: riskColor.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(riskIcon, color: riskColor, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        riskLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: riskColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        alert.threatCategory,
                        style: const TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (alert.isExternalConfirmed)
                   const Tooltip(
                     message: "Confirmado por Fonte Externa",
                     child: Icon(Icons.cloud_done, color: Colors.blueAccent),
                   ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${(alert.riskScore * 100).toStringAsFixed(0)}%",
                    style: TextStyle(fontWeight: FontWeight.bold, color: riskColor),
                  ),
                ),
              ],
            ),
            if (alert.isVerifying)
               const Padding(
                 padding: EdgeInsets.symmetric(vertical: 8.0),
                 child: LinearProgressIndicator(minHeight: 2),
               ),
            const Divider(),
            Text("Remetente: ${alert.sender}", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(alert.originalBody),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.psychology, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.reasoning,
                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Botão de Feedback (Aprendizado Corretivo)
                // Só mostra se for considerado risco (Amarelo ou Vermelho)
                if (alert.riskScore >= 0.50)
                  TextButton.icon(
                    icon: const Icon(Icons.thumb_up_alt_outlined, color: Colors.green),
                    label: const Text("Não é Golpe", style: TextStyle(color: Colors.green)),
                    onPressed: () {
                       // Chama o Provider para marcar como seguro
                       context.read<ThreatProvider>().markAsSafe(alert);
                       
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(
                           content: Text("Obrigado! '${alert.sender}' foi adicionado aos confiáveis."),
                           backgroundColor: Colors.green,
                         ),
                       );
                    },
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: "Compartilhar Alerta",
                  onPressed: () {
                    Share.share(
                      "🛡️ *ESCUDO SMS - ALERTA DE GOLPE* 🛡️\n\n"
                      "O Escudo SMS detectou uma ameaça!\n\n"
                      "⚠️ *Categoria:* ${alert.threatCategory}\n"
                      "🛑 *Risco:* ${(alert.riskScore * 100).toStringAsFixed(0)}%\n"
                      "📩 *Mensagem:* \"${alert.originalBody}\"\n\n"
                      "#EscudoSMS #SegurançaDigital"
                    );
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
