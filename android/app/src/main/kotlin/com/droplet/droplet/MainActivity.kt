package com.droplet.droplet

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * CHANGER L'ICÔNE DE L'APPLICATION DEPUIS L'APPLICATION.
 *
 * Android ne permet pas de remplacer l'icône d'une app à l'exécution :
 * elle est figée dans le manifeste, lu à l'installation. La seule
 * méthode officielle consiste à déclarer PLUSIEURS points d'entrée vers
 * la même activité — des `activity-alias`, chacun avec sa propre icône —
 * puis à n'en laisser qu'UN seul activé à la fois.
 *
 * C'est exactement ce que font les applications qui proposent des icônes
 * alternatives. Le lanceur affiche l'icône de l'alias actif ; les autres
 * sont désactivés, donc invisibles.
 *
 * ⚠️ DEUX CONSÉQUENCES À CONNAÎTRE
 *
 * 1. Le changement ferme l'application sur la plupart des lanceurs.
 *    Désactiver le composant par lequel l'app a été lancée revient à
 *    couper la branche sur laquelle on est assis : Android termine le
 *    processus. C'est le comportement normal, y compris chez les grandes
 *    applications — l'interface prévient donc l'utilisateur avant.
 *
 * 2. L'ordre compte. On ACTIVE la nouvelle icône AVANT de désactiver
 *    l'ancienne : si l'on faisait l'inverse et que le processus était
 *    tué entre les deux, l'application n'aurait plus AUCUN point
 *    d'entrée activé et disparaîtrait complètement du lanceur, sans
 *    aucun moyen de la rouvrir.
 */
class MainActivity : FlutterActivity() {

    private val channel = "com.droplet.droplet/app_icon"
    private val mediaChannel = "com.droplet.droplet/media"

    /** Le nom de l'alias par défaut, celui déclaré dans le manifeste. */
    private val defaultAlias = "Default"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val alias = call.argument<String>("alias")
                        if (alias == null) {
                            result.error("ARG", "alias manquant", null)
                        } else {
                            try {
                                applyIcon(alias)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("FAIL", e.message, null)
                            }
                        }
                    }

                    "currentIcon" -> result.success(currentAlias())

                    else -> result.notImplemented()
                }
            }

        // Découpe de vidéo et enregistrement dans la galerie — deux
        // services qu'Android seul sait rendre (voir `MediaBridge.kt`).
        val media = MediaBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result -> media.handle(call, result) }
    }

    /** Tous les alias déclarés au manifeste. */
    private fun aliases(): List<String> =
        listOf(defaultAlias) + (1..12).map { "V$it" }

    /** Active [target] et désactive tous les autres. */
    private fun applyIcon(target: String) {
        val pm = packageManager
        val prefix = "$packageName.Launcher"

        // On active D'ABORD — voir le point 2 en tête de classe.
        pm.setComponentEnabledSetting(
            ComponentName(packageName, "$prefix$target"),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )

        for (alias in aliases()) {
            if (alias == target) continue
            pm.setComponentEnabledSetting(
                ComponentName(packageName, "$prefix$alias"),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    /** L'alias actuellement actif. */
    private fun currentAlias(): String {
        val pm = packageManager
        val prefix = "$packageName.Launcher"

        for (alias in aliases()) {
            val state = pm.getComponentEnabledSetting(
                ComponentName(packageName, "$prefix$alias")
            )
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return alias
            }
        }
        // Aucun n'est explicitement activé : c'est que l'app n'a jamais
        // changé d'icône, et que le défaut du manifeste s'applique.
        return defaultAlias
    }
}
