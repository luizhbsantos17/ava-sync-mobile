package io.github.avasync.ava_sync_mobile

import android.app.Application

/**
 * Liga o Firebase (push do Social) assim que o processo sobe, antes de qualquer aviso
 * chegar. Sem a configuração do push no build, não faz nada.
 */
class AvaSyncApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Push.iniciar(this)
    }
}
