package io.github.avasync.ava_sync_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Push.registrarCanal(flutterEngine, applicationContext)
    }

    override fun onResume() {
        super.onResume()
        Push.emPrimeiroPlano = true
    }

    override fun onPause() {
        Push.emPrimeiroPlano = false
        super.onPause()
    }
}
