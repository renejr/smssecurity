package com.escudo.smssecurity

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity: FlutterActivity() {
    companion object {
        const val CHANNEL = "com.escudo.sms/interceptor"
        
        // Flag volátil para rastrear o estado real da UI
        @Volatile
        var isFlutterUiAlive = false
        
        var methodChannel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        Log.d("MDXHQ_NATIVE", "✅ [MainActivity] Engine Configurada. Canal criado.")
    }

    override fun onResume() {
        super.onResume()
        isFlutterUiAlive = true
        Log.d("MDXHQ_NATIVE", "🟢 [MainActivity] onResume: UI Viva.")
    }

    override fun onPause() {
        super.onPause()
        // Não marcamos como false no onPause pois o app pode estar apenas em segundo plano mas vivo
        // Mas se o onDetached for chamado, aí sim.
        Log.d("MDXHQ_NATIVE", "🟡 [MainActivity] onPause.")
    }

    override fun onDestroy() {
        isFlutterUiAlive = false
        methodChannel = null
        Log.d("MDXHQ_NATIVE", "🔴 [MainActivity] onDestroy: UI Morta. Canal limpo.")
        super.onDestroy()
    }
}
