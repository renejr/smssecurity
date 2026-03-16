import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:smssecurity/core/services/admob_service.dart';
import 'package:smssecurity/core/services/log_service.dart'; // Import do LogService
import 'package:smssecurity/features/settings/presentation/controllers/trial_controller.dart';

class CustomBannerAd extends StatefulWidget {
  const CustomBannerAd({super.key});

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    // Inicia carregamento se necessário (será checado no didChangeDependencies também)
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Garante que o anúncio seja verificado ao iniciar ou mudar dependências
    _checkAndLoadAd();
  }

  @override
  void didUpdateWidget(CustomBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reage a reconstruções do widget pai (Tarefa 2)
    _checkAndLoadAd();
  }

  void _checkAndLoadAd() {
    // Obtém o controller sem ouvir mudanças automáticas aqui (o Consumer no build ou o pai cuidam da reconstrução se necessário)
    // Para garantir reatividade total, o ideal é que o pai reconstrua este widget quando o estado mudar.
    final trial = Provider.of<TrialController>(context, listen: false);
    
    // Regra de Exibição:
    // 1. NÃO é Premium (se for premium, nunca mostra).
    // 2. E (Trial Expirado OU Force Expired).
    bool shouldShowAds = (!trial.isPremium && (trial.status == 'trial_expired' || trial.daysRemaining <= 0)) || trial.isForceExpired;

    if (shouldShowAds) {
       // Tarefa 3: Log de Diagnóstico Exato
       LogService().log("BannerAd: Decidiu exibir anúncio (Trial Expirado). _isAdLoaded: $_isAdLoaded, _bannerAd: ${_bannerAd != null}");
    }

    if (shouldShowAds && !_isAdLoaded && _bannerAd == null) {
      _loadAd();
    } else if (!shouldShowAds && _bannerAd != null) {
      // Se virou Premium ou renovou, remove o anúncio imediatamente
      LogService().log("BannerAd: Removendo Ads pois usuário agora é Premium ou Trial Ativo");
      _disposeAd();
    }
  }

  void _loadAd() {
    LogService().log("BannerAd: Iniciando carregamento do AdUnit: ${AdmobService.bannerAdUnitId}");
    _bannerAd = BannerAd(
      adUnitId: AdmobService.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isAdLoaded = true;
          });
          LogService().log("BannerAd: 🟢 CARREGADO COM SUCESSO!");
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          LogService().log("BannerAd: 🔴 FALHA AO CARREGAR: código ${error.code}, msg: ${error.message}, domain: ${error.domain}");
        },
      ),
    );
    _bannerAd!.load();
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    if (mounted) {
      setState(() {
        _isAdLoaded = false;
      });
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Consumer para reagir a mudanças de estado do Trial
    return Consumer<TrialController>(
      builder: (context, trial, child) {
        // Regra de Exibição Refinada
        // 1. Se Premium, não exibe.
        // 2. Se forçada expiração (debug), exibe.
        // 3. Se status for trial_expired, exibe.
        // 4. Se dias restantes <= 0, exibe.
        bool shouldShowAds = (!trial.isPremium && (trial.status == 'trial_expired' || trial.daysRemaining <= 0)) || trial.isForceExpired;

        // Se o estado mudou e o anúncio não está carregado, tenta carregar
        if (shouldShowAds && _bannerAd == null) {
           WidgetsBinding.instance.addPostFrameCallback((_) => _loadAd());
        } else if (!shouldShowAds && _bannerAd != null) {
           WidgetsBinding.instance.addPostFrameCallback((_) => _disposeAd());
        }

        if (!shouldShowAds) return const SizedBox.shrink();

        if (_bannerAd != null && _isAdLoaded) {
          return Container(
            alignment: Alignment.center,
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          );
        }
        
        // Placeholder enquanto carrega
        return const SizedBox(height: 50); 
      },
    );
  }
}
