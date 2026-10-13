package app.dropletmesh.droplet_drop

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Android filtre le multicast par défaut pour économiser la batterie : sans
 * ce verrou, les annonces mDNS des autres appareils n'arrivent jamais et la
 * liste « Appareils à proximité » reste vide. On le prend tant que
 * l'application est ouverte, et on le rend en la quittant.
 */
class MainActivity : FlutterActivity() {
    private var verrou: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        verrou = wifi?.createMulticastLock("droplet-drop")?.apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onDestroy() {
        verrou?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
