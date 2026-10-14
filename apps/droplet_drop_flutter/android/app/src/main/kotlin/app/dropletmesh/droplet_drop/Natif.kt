package app.dropletmesh.droplet_drop

import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.concurrent.thread

/**
 * Ce qu'Android seul sait faire, pour Droplet Drop.
 *
 *  • LE POINT D'ACCÈS LOCAL. Pour envoyer sans box ni Internet (comme
 *    Xender) : le destinataire ouvre un petit réseau Wi‑Fi local
 *    (`startLocalOnlyHotspot`, Android 8+), son nom et son mot de passe vont
 *    dans le QR code ; l'expéditeur le rejoint (`WifiNetworkSpecifier`,
 *    Android 10+ ; l'ancienne méthode avant) et y attache TOUTES les
 *    connexions de l'app (`bindProcessToNetwork`), celles du moteur Rust
 *    comprises.
 *  • LES APPLICATIONS INSTALLÉES, pour les partager : leur nom, leur icône,
 *    et leurs fichiers APK (plusieurs quand l'app est découpée).
 *  • OUVRIR un fichier reçu dans l'app qui convient, et INSTALLER une app
 *    reçue (un ou plusieurs APK, par une session d'installation).
 */
class Natif(private val activite: Activity) : MethodChannel.MethodCallHandler {
    private val ctx: Context = activite.applicationContext
    private val principal = Handler(Looper.getMainLooper())
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var rappelReseau: ConnectivityManager.NetworkCallback? = null

    private val wifi get() = ctx.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivite get() = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "versionAndroid" -> result.success(Build.VERSION.SDK_INT)
                "ouvrirPointAcces" -> ouvrirPointAcces(result)
                "fermerPointAcces" -> { fermerPointAcces(); result.success(null) }
                "rejoindrePointAcces" -> rejoindre(call.argument<String>("ssid")!!, call.argument<String>("mdp") ?: "", call.argument<Int>("securite") ?: 1, result)
                "quitterPointAcces" -> { quitter(); result.success(null) }
                "applications" -> thread { val l = applications(); principal.post { result.success(l) } }
                "installer" -> installer(call.argument<List<String>>("chemins")!!, result)
                "ouvrir" -> ouvrir(call.argument<String>("chemin")!!, result)
                "dossierPublic" -> result.success(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Droplet Drop").path)
                "localisationActive" -> result.success(localisationActive())
                "ouvrirReglagesLocalisation" -> { activite.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("erreur", e.message, null)
        }
    }

    fun liberer() {
        fermerPointAcces()
        quitter()
    }

    // ══ LE POINT D'ACCÈS ═════════════════════════════════════════════════

    private fun localisationActive(): Boolean {
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        return if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
        else lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
    }

    @SuppressLint("MissingPermission")
    private fun ouvrirPointAcces(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 26) {
            result.error("non_supporte", "Android 8 requis", null)
            return
        }
        fermerPointAcces()
        var repondu = false
        fun repondre(f: () -> Unit) { if (!repondu) { repondu = true; f() } }
        wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
            override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                reservation = r
                var ssid: String? = null
                var mdp: String? = null
                var securite = 1
                if (Build.VERSION.SDK_INT >= 30) {
                    val c = r.softApConfiguration
                    ssid = if (Build.VERSION.SDK_INT >= 33) c.wifiSsid?.toString()?.removeSurrounding("\"") else @Suppress("DEPRECATION") c.ssid
                    mdp = c.passphrase
                    securite = c.securityType
                } else {
                    @Suppress("DEPRECATION") val c = r.wifiConfiguration
                    @Suppress("DEPRECATION")
                    ssid = c?.SSID?.removeSurrounding("\"")
                    @Suppress("DEPRECATION")
                    mdp = c?.preSharedKey?.removeSurrounding("\"")
                }
                repondre { result.success(mapOf("ssid" to ssid, "mdp" to mdp, "securite" to securite)) }
            }

            override fun onFailed(reason: Int) {
                // 1 = pas de canal, 2 = conflit (partage de connexion déjà actif), 3 = mode incompatible
                repondre { result.error("echec", reason.toString(), null) }
            }

            override fun onStopped() {
                reservation = null
            }
        }, principal)
    }

    private fun fermerPointAcces() {
        reservation?.close()
        reservation = null
    }

    @SuppressLint("MissingPermission")
    private fun rejoindre(ssid: String, mdp: String, securite: Int, result: MethodChannel.Result) {
        quitter()
        var repondu = false
        fun repondre(f: () -> Unit) { principal.post { if (!repondu) { repondu = true; f() } } }
        if (Build.VERSION.SDK_INT >= 29) {
            val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
                when {
                    mdp.isEmpty() -> {}
                    securite == 3 && Build.VERSION.SDK_INT >= 29 -> setWpa3Passphrase(mdp)
                    else -> setWpa2Passphrase(mdp)
                }
            }.build()
            val requete = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(spec)
                .build()
            val rappel = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    connectivite.bindProcessToNetwork(network)
                    repondre { result.success(true) }
                }

                override fun onUnavailable() {
                    repondre { result.error("refuse", "indisponible", null) }
                }

                override fun onLost(network: Network) {
                    connectivite.bindProcessToNetwork(null)
                }
            }
            rappelReseau = rappel
            connectivite.requestNetwork(requete, rappel, 60_000)
        } else {
            // Android 7 à 9 : l'ancienne méthode, puis on attend d'y être.
            @Suppress("DEPRECATION")
            val conf = WifiConfiguration().apply {
                SSID = "\"$ssid\""
                if (mdp.isEmpty()) allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE) else preSharedKey = "\"$mdp\""
            }
            thread {
                @Suppress("DEPRECATION")
                val w = wifi
                if (!w.isWifiEnabled) @Suppress("DEPRECATION") w.setWifiEnabled(true)
                @Suppress("DEPRECATION") val id = w.addNetwork(conf)
                @Suppress("DEPRECATION") w.disconnect()
                @Suppress("DEPRECATION") w.enableNetwork(id, true)
                @Suppress("DEPRECATION") w.reconnect()
                val fin = System.currentTimeMillis() + 25_000
                while (System.currentTimeMillis() < fin) {
                    @Suppress("DEPRECATION")
                    val actuel = w.connectionInfo?.ssid?.removeSurrounding("\"")
                    @Suppress("DEPRECATION")
                    val reseau = connectivite.allNetworks.firstOrNull { connectivite.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
                    if (actuel == ssid && reseau != null) {
                        connectivite.bindProcessToNetwork(reseau)
                        Thread.sleep(800) // l'adresse IP arrive juste après
                        repondre { result.success(true) }
                        return@thread
                    }
                    Thread.sleep(400)
                }
                repondre { result.error("delai", "délai dépassé", null) }
            }
        }
    }

    private fun quitter() {
        connectivite.bindProcessToNetwork(null)
        rappelReseau?.let { runCatching { connectivite.unregisterNetworkCallback(it) } }
        rappelReseau = null
    }

    // ══ LES APPLICATIONS INSTALLÉES ══════════════════════════════════════

    private fun applications(): List<Map<String, Any?>> {
        val pm = ctx.packageManager
        val lanceur = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val activites = pm.queryIntentActivities(lanceur, 0)
        val vus = HashSet<String>()
        val liste = ArrayList<Map<String, Any?>>()
        for (ri in activites) {
            val pkg = ri.activityInfo.packageName
            if (pkg == ctx.packageName || !vus.add(pkg)) continue
            val ai: ApplicationInfo = try { pm.getApplicationInfo(pkg, 0) } catch (_: Exception) { continue }
            val systeme = ai.flags and ApplicationInfo.FLAG_SYSTEM != 0 && ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP == 0
            if (systeme) continue
            val apk = listOf(ai.sourceDir) + (ai.splitSourceDirs?.toList() ?: emptyList())
            val taille = apk.sumOf { File(it).length() }
            @Suppress("DEPRECATION")
            val version = try { pm.getPackageInfo(pkg, 0).versionName } catch (_: Exception) { null }
            liste.add(
                mapOf(
                    "paquet" to pkg,
                    "nom" to (ai.loadLabel(pm)?.toString() ?: pkg),
                    "version" to version,
                    "apk" to apk,
                    "taille" to taille,
                    "icone" to icone(ai, pm),
                )
            )
        }
        return liste.sortedBy { (it["nom"] as String).lowercase() }
    }

    private fun icone(ai: ApplicationInfo, pm: PackageManager): ByteArray? = try {
        val d = ai.loadIcon(pm)
        val taille = 96
        val b = Bitmap.createBitmap(taille, taille, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        d.setBounds(0, 0, taille, taille)
        d.draw(c)
        val sortie = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.PNG, 100, sortie)
        sortie.toByteArray()
    } catch (_: Exception) {
        null
    }

    // ══ INSTALLER, OUVRIR ════════════════════════════════════════════════

    private fun installer(chemins: List<String>, result: MethodChannel.Result) {
        val pm = ctx.packageManager
        if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
            // Android demande d'abord d'autoriser Droplet Drop à installer.
            activite.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")))
            result.success("autorisation")
            return
        }
        thread {
            try {
                val installeur = pm.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                val id = installeur.createSession(params)
                installeur.openSession(id).use { s ->
                    chemins.forEachIndexed { i, chemin ->
                        val f = File(chemin)
                        f.inputStream().use { entree ->
                            s.openWrite("apk$i.apk", 0, f.length()).use { sortie ->
                                entree.copyTo(sortie, 1 shl 16)
                                s.fsync(sortie)
                            }
                        }
                    }
                    val drapeaux = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
                    val pi = PendingIntent.getBroadcast(ctx, id, Intent(ctx, RecepteurInstallation::class.java), drapeaux)
                    s.commit(pi.intentSender)
                }
                principal.post { result.success("lancee") }
            } catch (e: Exception) {
                principal.post { result.error("installation", e.message, null) }
            }
        }
    }

    private fun ouvrir(chemin: String, result: MethodChannel.Result) {
        val f = File(chemin)
        if (f.isDirectory) {
            // Une app découpée (plusieurs APK) : on l'installe d'un coup.
            val apk = f.listFiles { x -> x.name.endsWith(".apk", true) }?.map { it.path }.orEmpty()
            if (apk.isNotEmpty()) return installer(apk, result)
            result.error("dossier", "dossier", null)
            return
        }
        val ext = f.extension.lowercase()
        if (ext == "apk") return installer(listOf(chemin), result)
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fichiers", f)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activite.startActivity(i)
            result.success("ouvert")
        } catch (_: Exception) {
            result.error("aucune_app", mime, null)
        }
    }
}

/** La fin d'une installation : Android demande la confirmation à l'utilisateur. */
class RecepteurInstallation : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirmer = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                confirmer.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(confirmer)
            }
        }
    }
}
