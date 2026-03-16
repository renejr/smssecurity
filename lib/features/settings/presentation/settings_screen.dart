import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:provider/provider.dart';
import 'package:smssecurity/features/settings/presentation/controllers/trial_controller.dart';
import 'package:smssecurity/features/settings/presentation/telemetry_screen.dart'; // Import da Telemetria

import 'package:smssecurity/core/services/background_service.dart';

import 'package:smssecurity/core/services/admob_service.dart'; // Import AdMob
import 'package:smssecurity/features/settings/presentation/screens/log_viewer_screen.dart'; // Import da tela de logs
import 'package:smssecurity/features/settings/presentation/widgets/paywall_bottom_sheet.dart'; // Import do Paywall

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    // Tenta pré-carregar um anúncio ao entrar na tela de configurações
    // Mas só exibe se for o momento certo.
    // Melhor: AdmobService gerencia o estado interno.
    final trial = Provider.of<TrialController>(context, listen: false);
    if (!trial.isPremium && trial.status == 'trial_expired') {
       AdmobService.loadInterstitial();
    }
  }

  Future<void> _contactSupport() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'renebmjr@gmail.com',
      query: 'subject=Suporte Escudo SMS',
    );

    if (!await launchUrl(emailLaunchUri)) {
      debugPrint('Could not launch $emailLaunchUri');
    }
  }

  void _handleVersionTap(TrialController controller) {
    setState(() {
      _versionTapCount++;
    });

    if (_versionTapCount == 5) {
      if (controller.status == 'premium_override') {
        controller.resetDevPremium();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🔒 Modo Desenvolvedor Desativado.")),
        );
      } else {
        controller.activateDevPremium();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🛠️ Modo Desenvolvedor Ativado: Premium Liberado."),
            duration: Duration(seconds: 3),
          ),
        );
      }
      _versionTapCount = 0;
    }
  }

  void _showTutorial(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Como usar o Escudo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 20),
              _buildTutorialItem(
                context,
                icon: Icons.check_circle,
                color: Colors.green,
                text: 'Mensagem segura ou de contato conhecido.',
              ),
              const SizedBox(height: 12),
              _buildTutorialItem(
                context,
                icon: Icons.warning,
                color: Colors.orange,
                text: 'Link ou palavras suspeitas, tenha cautela.',
              ),
              const SizedBox(height: 12),
              _buildTutorialItem(
                context,
                icon: Icons.error,
                color: Colors.red,
                text: 'Golpe detectado! A IA bloqueou a ameaça.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendi'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sua Privacidade em 1º Lugar',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 20),
              _buildTutorialItem(
                context,
                icon: Icons.phone_android,
                color: Colors.blue,
                text: '1. Processamento Local: A maior parte da análise ocorre direto no seu celular.',
              ),
              const SizedBox(height: 12),
              _buildTutorialItem(
                context,
                icon: Icons.visibility_off,
                color: Colors.purple,
                text: '2. Anonimização: Ocultamos automaticamente códigos de banco (OTP), CPFs e valores antes de qualquer análise externa.',
              ),
              const SizedBox(height: 12),
              _buildTutorialItem(
                context,
                icon: Icons.security,
                color: Colors.green,
                text: '3. Proteção Coletiva: Apenas links perigosos e números de golpistas são mapeados para proteger outros usuários.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendi'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTutorialItem(BuildContext context,
      {required IconData icon, required Color color, required String text}) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  void _confirmStopProtection(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ Desativar Proteção?"),
        content: const Text(
            "Deseja desativar a proteção em tempo real? Seu dispositivo ficará vulnerável a SMS maliciosos."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Manter Proteção"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              BackgroundService.stopService();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Proteção em segundo plano desativada.")),
              );
            },
            child: const Text("Desativar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trialController = context.watch<TrialController>();
    
    // Define cor e texto do status
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (trialController.isPremium) {
      statusColor = Colors.amber;
      statusIcon = Icons.verified;
      if (trialController.status == 'premium_override') {
        statusText = "Premium (Developer)";
      } else {
        statusText = "Trial Premium: ${trialController.daysRemaining} dias";
      }
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.access_time;
      statusText = "Versão Gratuita";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre / Configurações'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Opção de Debug - Simular Expiração do Trial
              if (trialController.isPremium) ...[ // Só mostra se for Premium/Trial
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text("Simular Trial Expirado", style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text("Debug: Ativa Ads e Paywall", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: trialController.isForceExpired,
                  activeColor: Colors.redAccent,
                  onChanged: (bool val) {
                    trialController.toggleForceExpired(val);
                  },
                  tileColor: Colors.grey.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.red.withOpacity(0.5), width: 0.5),
                  ),
                ),
              ],
            
              // Opção de Resetar Mock Premium (Aparece se for premium_purchased mas via mock)
              if (trialController.isPremium) ...[
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.redAccent),
                  title: const Text('Resetar Premium (Debug Mock)', style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('Volta para Free/Trial para testar Paywall', style: TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.redAccent),
                  onTap: () async {
                     await trialController.resetPurchaseMock();
                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text("🔄 Status resetado para Gratuito/Trial.")),
                       );
                     }
                  },
                  tileColor: Colors.grey.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.redAccent, width: 0.5),
                  ),
                ),
              ],

              const SizedBox(height: 40), // Substitui Spacer() por espaço fixo
              // Branding
            Icon(
              Icons.shield,
              size: 64,
              color: statusColor, // Cor dinâmica
            ),
            const SizedBox(height: 16),
            const Text(
              'Escudo SMS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Status Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Botão "SEJA PREMIUM" (Se for Free)
            if (!trialController.isPremium) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                     showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => const PaywallBottomSheet(),
                     );
                  },
                  icon: const Icon(Icons.star, size: 28),
                  label: const Text(
                    "SEJA PREMIUM AGORA",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],

            GestureDetector(
              onTap: () => _handleVersionTap(trialController),
              child: const Text(
                'Versão 1.0.0',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 32),

            // Botões de Ação
            ListTile(
              leading: const Icon(Icons.help_outline, color: Colors.white),
              title: const Text('Como usar o Escudo', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
              onTap: () => _showTutorial(context),
              tileColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.email_outlined, color: Colors.white),
              title: const Text('Falar com o Suporte', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
              onTap: _contactSupport,
              tileColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Colors.white),
              title: const Text('Política de Privacidade', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
              onTap: () => _showPrivacyPolicy(context),
              tileColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Opção de Telemetria (Apenas Dev/Premium)
            if (trialController.isPremium) ...[
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.analytics, color: Colors.amber),
                title: const Text('Telemetria Avançada (Dev)', style: TextStyle(color: Colors.amber)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.amber),
                onTap: () {
                  // Gatilho do Interstitial Ad
                  // Só exibe se Trial Expirado
                  if (!trialController.isPremium && trialController.status == 'trial_expired') {
                     print("📺 Exibindo Interstitial Ad...");
                     AdmobService.showInterstitial();
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TelemetryScreen()),
                  );
                },
                tileColor: Colors.grey.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.amber, width: 0.5),
                ),
              ),
            ],

            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.greenAccent),
              title: const Text('Logs de Debug do AdMob', style: TextStyle(color: Colors.greenAccent)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.greenAccent),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LogViewerScreen()),
                );
              },
              tileColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.greenAccent, width: 0.5),
              ),
            ),

            // Opção de Desativar Proteção (Perigo) - OCULTADO POR SEGURANÇA (Solicitação do Usuário)
            /*
            ListTile(
              leading: const Icon(Icons.power_settings_new, color: Colors.red),
              title: const Text('Desativar Proteção em 2º Plano', style: TextStyle(color: Colors.red)),
              onTap: () => _confirmStopProtection(context),
              tileColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.red, width: 0.5),
              ),
            ),
            */
            
            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Desenvolvido por MDXHQ Desenvolvimento ©',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
