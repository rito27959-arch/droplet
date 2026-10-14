package app.dropletmesh.droplet_drop

import android.content.Context
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
 */
class MainActivity : FlutterActivity() {
    private var verrou: WifiManager.MulticastLock? = null
    private var natif: Natif? = null

    override fun onCreate(savedInstanceState: Bundle?) {
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "droplet_drop/natif").setMethodCallHandler(n)
    }

    override fun onDestroy() {
        natif?.liberer()
        verrou?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
