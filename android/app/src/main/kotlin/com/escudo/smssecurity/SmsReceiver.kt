package com.escudo.smssecurity

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Telephony
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.FlutterInjector
import io.flutter.plugins.GeneratedPluginRegistrant

class SmsReceiver : BroadcastReceiver() {
    private val TAG = "MDXHQ_NATIVE"

    override fun onReceive(context: Context, intent: Intent) {
        if (Telephony.Sms.Intents.SMS_RECEIVED_ACTION != intent.action) return

        Log.d(TAG, "📡 [Receiver] SMS Recebido. Iniciando processamento.")

        // Adquire WakeLock imediatamente
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MDXHQ::SmsProcessingWakeLock")
        wakeLock.acquire(30 * 1000L) // 30s timeout

        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages == null || messages.isEmpty()) {
                Log.w(TAG, "⚠️ [Receiver] Mensagens nulas ou vazias.")
                return
            }

            val sender = messages[0].originatingAddress ?: "Unknown"
            val body = StringBuilder()
            for (message in messages) body.append(message.messageBody)
            val fullBody = body.toString()

            Log.d(TAG, "📨 [Receiver] De: $sender")

            // ROTEAMENTO INTELIGENTE
            if (MainActivity.isFlutterUiAlive && MainActivity.methodChannel != null) {
                Log.d(TAG, "🟢 [Receiver] UI Detectada VIVA. Tentando MethodChannel...")
                
                // Tenta enviar via UI. Se falhar no callback, ativa fallback.
                val channel = MainActivity.methodChannel
                if (channel != null) {
                     Handler(Looper.getMainLooper()).post {
                        try {
                            channel.invokeMethod("onSmsReceived", 
                                mapOf("sender" to sender, "body" to fullBody),
                                object : io.flutter.plugin.common.MethodChannel.Result {
                                    override fun success(result: Any?) {
                                        Log.d(TAG, "✅ [Receiver] Sucesso via MethodChannel.")
                                    }

                                    override fun error(code: String, msg: String?, details: Any?) {
                                        Log.e(TAG, "❌ [Receiver] Erro no MethodChannel: $msg. Ativando Fallback Headless.")
                                        startHeadlessEngine(context, sender, fullBody)
                                    }

                                    override fun notImplemented() {
                                        Log.e(TAG, "❌ [Receiver] MethodChannel não implementado. Ativando Fallback Headless.")
                                        startHeadlessEngine(context, sender, fullBody)
                                    }
                                }
                            )
                        } catch (e: Exception) {
                            Log.e(TAG, "🔥 [Receiver] Exceção ao invocar MethodChannel: ${e.message}. Fallback!")
                            startHeadlessEngine(context, sender, fullBody)
                        }
                    }
                } else {
                    Log.w(TAG, "⚠️ [Receiver] MethodChannel nulo apesar da flag. Fallback!")
                    startHeadlessEngine(context, sender, fullBody)
                }
            } else {
                Log.d(TAG, "⚫ [Receiver] UI Morta ou Detached. Iniciando Headless Engine DIRETAMENTE.")
                startHeadlessEngine(context, sender, fullBody)
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ [Receiver] Erro Fatal: ${e.message}")
            e.printStackTrace()
        } finally {
            if (wakeLock.isHeld) {
                wakeLock.release()
                Log.d(TAG, "💤 [Receiver] WakeLock liberado.")
            }
        }
    }

    private fun startHeadlessEngine(context: Context, sender: String, body: String) {
        Log.d(TAG, "🚀 [Headless] Iniciando Engine Silenciosa...")
        
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationComplete(context, null)

            // Cria uma nova engine isolada
            val engine = FlutterEngine(context.applicationContext)
            
            // Registra plugins (Vital para path_provider, etc)
            GeneratedPluginRegistrant.registerWith(engine)
            Log.d(TAG, "🔌 [Headless] Plugins registrados.")

            // Define o ponto de entrada Dart
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "processSmsInBackground"
            )

            // Executa
            engine.dartExecutor.executeDartEntrypoint(entrypoint, listOf(sender, body))
            Log.d(TAG, "▶️ [Headless] Dart Entrypoint executado.")
            
            // A engine será coletada pelo GC eventualmente, mas esperamos que o Dart termine seu trabalho antes.
            // Para garantir, poderíamos manter uma referência estática temporária, mas o WakeLock ajuda.
            
        } catch (e: Exception) {
            Log.e(TAG, "🔥 [Headless] Falha Crítica: ${e.message}")
            e.printStackTrace()
        }
    }
}
