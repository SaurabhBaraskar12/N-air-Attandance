package org.svsgroup.attendance_log_app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

/**
 * Custom Application. Its onCreate runs before ANY component in the process
 * (Activity, BootReceiver, or the background Service), so we create the
 * foreground-service notification channel here.
 *
 * flutter_background_service does NOT create this channel automatically; if the
 * channel is missing, startForeground() throws
 * CannotPostForegroundServiceNotificationException ("Bad notification for
 * startForeground") and the app crashes on launch. Creating it up front fixes
 * that crash for every start path (app open, boot, package-replaced).
 */
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            if (mgr != null && mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Attendance location",
                    NotificationManager.IMPORTANCE_LOW,
                )
                channel.description =
                    "Active only during the 9:00-9:30 AM and 8:30-9:00 PM tracking windows"
                mgr.createNotificationChannel(channel)
            }
        }
    }

    companion object {
        // must match _notifChannelId in lib/location_service.dart
        private const val CHANNEL_ID = "attendance_location"
    }
}
