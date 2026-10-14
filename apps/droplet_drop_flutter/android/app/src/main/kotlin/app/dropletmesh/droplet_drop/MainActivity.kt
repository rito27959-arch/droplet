package app.dropletmesh.droplet_drop

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android filtre le multicast par défaut pour économiser la batterie : sans
 * ce verrou, les annonces mDNS des autres appareils n'arrivent jamais et la
 * liste « Appareils à proximité » reste vide. On le prend tant que
 * l'application est ouverte, et on le rend en la quittant.
 *
 * Le canal « droplet_drop/natif » donne à Flutter ce qu'Android seul sait
 * faire : le point d'accès local, les applications installées, ouvrir et
 * installer un fichier reçu (voir Natif.kt).
 *
 * Il apporte aussi les liens d'invitation ouverts depuis une autre app
 * (WhatsApp, SMS…) : celui qui a lancé l'app (« lienInitial ») et ceux qui
 * arrivent pendant qu'elle tourne (« lien », envoyé à Flutter).
 */
class MainActivity : FlutterActivity() {
    private var verrou: WifiManager.MulticastLock? = null
    private var natif: Natif? = null
    private var canal: MethodChannel? = null
    private var lienInitial: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        lienInitial = lien(intent)
        super.onCreate(savedInstanceState)
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        verrou = wifi?.createMulticastLock("droplet-drop")?.apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val n = Natif(this)
        natif = n
        val c = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "droplet_drop/natif")
        canal = c
        c.setMethodCallHandler { call, result ->
            if (call.method == "lienInitial") {
                result.success(lienInitial)
                lienInitial = null
            } else {
                n.onMethodCall(call, result)
            }
        }
    }

    /** Un lien d'invitation ouvert pendant que l'app tourne. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        lien(intent)?.let { canal?.invokeMethod("lien", it) }
    }

    private fun lien(intent: Intent?): String? =
        intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString?.takeIf { it.contains("rejoindre") }

    override fun onDestroy() {
        natif?.liberer()
        verrou?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
