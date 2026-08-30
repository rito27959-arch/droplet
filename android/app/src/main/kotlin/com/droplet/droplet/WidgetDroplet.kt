package com.droplet.droplet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * LE WIDGET D'ÉCRAN D'ACCUEIL.
 *
 * ── ⚠️ POURQUOI IL NE LIT PAS LA BASE DE DONNÉES ──────────────────────
 *
 * La tentation serait d'ouvrir la base SQLite de Droplet pour y compter
 * les messages non lus. Ce serait une faute : un widget est réveillé par
 * Android à n'importe quel moment, y compris pendant que l'application
 * écrit. Deux processus sur le même fichier SQLite, sans coordination,
 * c'est la base corrompue — et elle contient des conversations
 * qu'AUCUN serveur ne peut restituer.
 *
 * L'application dépose donc ce qu'il faut afficher dans les préférences
 * partagées, et le widget se contente de les lire. Une lecture ne
 * corrompt rien.
 *
 * ── ⚠️ CE QU'IL N'AFFICHE JAMAIS ─────────────────────────────────────
 *
 * Ni le contenu d'un message, ni le nom de son auteur. Un widget est
 * visible par quiconque regarde l'écran d'accueil par-dessus une
 * épaule — dans un taxi, au marché. Une application dont l'argument
 * principal est que les messages ne sortent pas du téléphone ne peut
 * pas les afficher en grand sur l'écran verrouillé.
 *
 * Il montre un NOMBRE : combien de messages attendent, combien de pairs
 * sont à portée. C'est utile, et cela ne révèle rien.
 */
class WidgetDroplet : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        for (id in ids) {
            dessiner(context, manager, id)
        }
    }

    private fun dessiner(context: Context, manager: AppWidgetManager, id: Int) {
        // ⚠️ LE PRÉFIXE « flutter. » N'EST PAS DÉCORATIF.
        //
        // Le greffon `shared_preferences` range TOUT sous ce préfixe,
        // dans un fichier nommé FlutterSharedPreferences. Le chercher
        // ailleurs, ou sans le préfixe, renvoie systématiquement la
        // valeur par défaut — et le widget afficherait des zéros pour
        // toujours, sans la moindre erreur.
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val nonLus = prefs.getLong("flutter.widget_non_lus", 0L).toInt()
        val pairs = prefs.getLong("flutter.widget_pairs", 0L).toInt()

        val vues = RemoteViews(context.packageName, R.layout.widget_droplet)

        vues.setTextViewText(R.id.widget_nombre, nonLus.toString())
        vues.setTextViewText(
            R.id.widget_libelle,
            if (nonLus == 0) "Aucun message" else if (nonLus == 1) "message" else "messages",
        )
        vues.setTextViewText(
            R.id.widget_pairs,
            when (pairs) {
                0 -> "Personne à portée"
                1 -> "1 personne à portée"
                else -> "$pairs personnes à portée"
            },
        )

        // Toucher le widget ouvre l'application.
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        // FLAG_IMMUTABLE est obligatoire depuis Android 12 : sans lui,
        // le système refuse de créer l'intention et le widget devient
        // inerte au toucher, sans message d'erreur.
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        vues.setOnClickPendingIntent(R.id.widget_racine, pending)

        manager.updateAppWidget(id, vues)
    }

    companion object {
        /**
         * Demande à Android de redessiner tous les widgets posés.
         *
         * Appelé depuis Flutter après chaque changement (message reçu,
         * pair qui apparaît). Sans cet appel, Android ne rafraîchit le
         * widget que toutes les trente minutes au mieux — un compteur
         * de messages en retard d'une demi-heure ne sert à rien.
         */
        fun rafraichir(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, WidgetDroplet::class.java),
            )
            if (ids.isEmpty()) return
            val intent = Intent(context, WidgetDroplet::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
