package com.otclient

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.Toast

class AndroidInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmationIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirmationIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                confirmationIntent?.let(context::startActivity)
            }

            PackageInstaller.STATUS_SUCCESS -> showMessage(context, "Atualização do Elemental instalada.")

            else -> {
                val details = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                val message = details?.takeIf(String::isNotBlank)
                    ?: "O Android não conseguiu instalar a atualização."
                showMessage(context, message)
            }
        }
    }

    private fun showMessage(context: Context, message: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, message, Toast.LENGTH_LONG).show()
        }
    }
}
