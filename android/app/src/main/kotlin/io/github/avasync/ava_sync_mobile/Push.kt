package io.github.avasync.ava_sync_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Push do Social (Firebase Cloud Messaging), sem os pacotes Flutter do Firebase: assim o
 * app de computador não carrega o SDK do Firebase. O Firebase é configurado por código com
 * os valores de `R.string.fcm_*` (vindos do build); sem eles, o push fica desligado.
 */
object Push {
    const val CANAL = "avasync/push"

    /** O app está na tela? Então a escuta em tempo real do Dart já cuida das mensagens. */
    @Volatile
    var emPrimeiroPlano = false

    private fun valor(ctx: Context, id: Int) = ctx.getString(id).trim()

    /** Liga o Firebase. Devolve false se este build não tem a configuração do push. */
    fun iniciar(ctx: Context): Boolean {
        if (FirebaseApp.getApps(ctx).isNotEmpty()) return true
        val appId = valor(ctx, R.string.fcm_app_id)
        val apiKey = valor(ctx, R.string.fcm_api_key)
        val projeto = valor(ctx, R.string.fcm_project_id)
        val remetente = valor(ctx, R.string.fcm_sender_id)
        if (appId.isEmpty() || apiKey.isEmpty() || projeto.isEmpty() || remetente.isEmpty()) return false
        return try {
            FirebaseApp.initializeApp(
                ctx,
                FirebaseOptions.Builder()
                    .setApplicationId(appId)
                    .setApiKey(apiKey)
                    .setProjectId(projeto)
                    .setGcmSenderId(remetente)
                    .build(),
            )
            true
        } catch (e: Exception) {
            Log.w("AvaSyncPush", "Firebase não iniciou", e)
            false
        }
    }

    /** Canal com o Dart da tela: `token` devolve o token do FCM (ou null sem push). */
    fun registrarCanal(engine: FlutterEngine, ctx: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { call, result ->
            when (call.method) {
                "token" -> {
                    if (!iniciar(ctx)) {
                        result.success(null)
                    } else {
                        FirebaseMessaging.getInstance().token
                            .addOnSuccessListener { result.success(it) }
                            .addOnFailureListener { result.success(null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

/**
 * Recebe o aviso do servidor ("tem mensagem nova na conversa X") com o app fechado.
 * Sobe um Flutter sem tela, roda `aoReceberPush` (lib/social/push.dart), que busca as
 * mensagens, decifra e mostra a notificação com nome e texto, e espera ele terminar.
 */
class PushService : FirebaseMessagingService() {
    override fun onCreate() {
        super.onCreate()
        Push.iniciar(applicationContext)
    }

    override fun onNewToken(token: String) {
        // o Dart registra o token novo na próxima vez que o app abrir (ou no próximo push)
        getSharedPreferences("avasync_push", MODE_PRIVATE).edit().putBoolean("token_novo", true).apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["tipo"] != "social" || Push.emPrimeiroPlano) return
        val terminou = CountDownLatch(1)
        val principal = Handler(Looper.getMainLooper())
        var engine: FlutterEngine? = null
        principal.post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val e = FlutterEngine(applicationContext) // registra os plugins sozinho
                engine = e
                MethodChannel(e.dartExecutor.binaryMessenger, Push.CANAL).setMethodCallHandler { call, result ->
                    if (call.method == "pronto") terminou.countDown()
                    result.success(null)
                }
                e.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:ava_sync_mobile/social/push.dart",
                        "aoReceberPush",
                    ),
                )
            } catch (ex: Exception) {
                Log.w("AvaSyncPush", "não consegui acordar o app", ex)
                terminou.countDown()
            }
        }
        // o Android dá ~20 s para tratar um push de prioridade alta
        terminou.await(18, TimeUnit.SECONDS)
        principal.post { engine?.destroy() }
    }
}
