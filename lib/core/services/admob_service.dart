import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdmobService {
  static String get bannerAdUnitId {
    // TODO: Inserir IDs reais de produção antes do lançamento na loja
    // Por enquanto, forçamos os IDs de Teste mesmo em Release para validação no dispositivo físico
    if (Platform.isAndroid) {
      return 'ca-app-pub-9817704085866532/4298614567'; // Test ID Android
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // Test ID iOS
    }
    return 'ca-app-pub-9817704085866532/4298614567'; // Fallback
  }

  static String get interstitialAdUnitId {
    // TODO: Inserir IDs reais de produção antes do lançamento na loja
    if (Platform.isAndroid) {
      return 'ca-app-pub-9817704085866532/4362193743'; // Test ID Android
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // Test ID iOS
    }
    return 'ca-app-pub-9817704085866532/4362193743'; // Fallback
  }

  // Variável para armazenar o Interstitial carregado
  static InterstitialAd? _interstitialAd;
  static bool _isInterstitialLoading = false;

  /// Carrega um Interstitial Ad antecipadamente
  static void loadInterstitial() {
    if (_isInterstitialLoading || _interstitialAd != null) return;
    
    _isInterstitialLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          print('✅ AdMob: Interstitial carregado.');
          _interstitialAd = ad;
          _isInterstitialLoading = false;
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('❌ AdMob: Falha ao carregar Interstitial: $error');
          _isInterstitialLoading = false;
        },
      ),
    );
  }

  /// Exibe o Interstitial se estiver carregado e recarrega o próximo
  static void showInterstitial() {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          print('👋 AdMob: Interstitial fechado.');
          ad.dispose();
          _interstitialAd = null;
          loadInterstitial(); // Preload do próximo
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          print('❌ AdMob: Falha ao exibir Interstitial: $error');
          ad.dispose();
          _interstitialAd = null;
          loadInterstitial();
        },
      );
      
      _interstitialAd!.show();
      _interstitialAd = null; // Limpa referência para evitar reuso indevido
    } else {
      print('⚠️ AdMob: Interstitial não estava pronto. Tentando carregar para a próxima...');
      loadInterstitial();
    }
  }

  /// Recarrega anúncios se o status do usuário mudar para expirado
  static void refreshAds(bool isPremium, bool isTrialExpired, bool isForceExpired) {
    if ((!isPremium && isTrialExpired) || isForceExpired) {
      print("🔄 AdMobService: Status Trial Expirado detectado. Recarregando Interstitial...");
      loadInterstitial();
    }
  }
}
