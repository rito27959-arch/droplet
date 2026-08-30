package com.droplet.droplet

import android.content.ContentValues
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

/**
 * DEUX SERVICES NATIFS que Flutter ne sait pas rendre seul : couper une
 * vidéo, et déposer un fichier dans la galerie du téléphone.
 *
 * ── Pourquoi couper une vidéo demande du natif ────────────────────────
 *
 * Une vidéo n'est pas un fichier qu'on tronque : c'est un conteneur
 * (MP4) qui décrit où se trouve chaque image, et des images compressées
 * qui dépendent les unes des autres. Couper les octets à la moitié
 * produit un fichier illisible.
 *
 * La solution habituelle est d'embarquer ffmpeg — mais cela ajoute
 * plusieurs dizaines de méga-octets à l'application, pour un usage
 * marginal. Android sait déjà le faire : `MediaExtractor` lit les images
 * une à une, `MediaMuxer` les réécrit dans un nouveau conteneur. On
 * RECOPIE les images telles quelles, sans les décoder ni les
 * recompresser : c'est quasi instantané, sans perte de qualité, et sans
 * une ligne de dépendance supplémentaire.
 *
 * ── Pourquoi déposer un fichier demande du natif ──────────────────────
 *
 * Depuis Android 10, une application n'écrit plus librement dans les
 * dossiers publics. Elle doit passer par `MediaStore`, qui range le
 * fichier au bon endroit et prévient la galerie de son existence. Sans
 * cela, un fichier enregistré n'apparaîtrait nulle part.
 */
class MediaBridge(private val context: Context) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "videoDurationMs" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("ARG", "chemin manquant", null)
                    return
                }
                result.success(durationMs(path))
            }

            "thermalStatus" -> result.success(thermalStatus())
            "deviceMemoryMb" -> result.success(deviceMemoryMb())
            "installerPath" -> result.success(installerPath())

            "majWidget" -> {
                val nonLus = call.argument<Int>("nonLus") ?: 0
                val pairs = call.argument<Int>("pairs") ?: 0
                result.success(majWidget(nonLus, pairs))
            }

            "composerUssd" -> {
                val code = call.argument<String>("code")
                if (code == null) {
                    result.error("ARG", "code manquant", null)
                    return
                }
                result.success(composerUssd(code))
            }

            "ouvrirLien" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("ARG", "url manquante", null)
                    return
                }
                result.success(ouvrirLien(url))
            }

            "trimVideo" -> {
                val path = call.argument<String>("path")
                val maxMs = call.argument<Int>("maxMs")
                if (path == null || maxMs == null) {
                    result.error("ARG", "arguments manquants", null)
                    return
                }
                try {
                    result.success(trim(path, maxMs.toLong()))
                } catch (e: Exception) {
                    result.error("TRIM", e.message, null)
                }
            }

            "saveToGallery" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime")
                if (path == null || name == null) {
                    result.error("ARG", "arguments manquants", null)
                    return
                }
                try {
                    result.success(save(path, name, mime ?: ""))
                } catch (e: Exception) {
                    result.error("SAVE", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Niveau de surchauffe du téléphone, de 0 (aucune) à 6 (arrêt
     * imminent). -1 si l'information n'est pas disponible.
     *
     * ── Pourquoi une application de messagerie s'en soucie ────────────
     *
     * Parce qu'À PARTIR DE 3, ANDROID COUPE LES ENCODEURS VIDÉO. La
     * caméra continue d'afficher son aperçu, le micro continue
     * d'enregistrer — mais plus une seule image n'atteint l'encodeur.
     * Le fichier produit ne contient que du son, et Android le referme
     * sur une erreur.
     *
     * C'est ce qu'on a observé ici : `MPEG4Writer` annonçait « 3499
     * frames encodées — Audio » et « 0 frames — Video », avec
     * `Thermal Status: 4`. Sans cette lecture, l'application ne peut
     * que dire « l'enregistrement n'a rien capturé », ce qui laisse
     * croire à un défaut de l'application alors que le téléphone
     * demande simplement à refroidir.
     */
    /**
     * La mémoire vive TOTALE de l'appareil, en mégaoctets.
     *
     * ⚠️ ON MESURE LA RAM DE L'APPAREIL, PAS CELLE QUI RESTE LIBRE.
     *
     * La mémoire libre varie à la seconde selon ce que fait le reste du
     * système : la lire donnerait une valeur différente à chaque
     * démarrage, et donc une application qui change d'apparence sans
     * raison visible. La capacité totale, elle, est une propriété stable
     * du téléphone — c'est sur elle qu'on décide une fois pour toutes si
     * on peut se permettre les effets coûteux.
     *
     * `isLowRamDevice` est également consulté : certains constructeurs le
     * positionnent sur des appareils qui annoncent pourtant beaucoup de
     * RAM, parce qu'ils savent que la leur est lente ou partagée avec le
     * processeur graphique. Quand Android le dit, on le croit.
     */
    /**
     * Le chemin du fichier APK de Droplet, tel qu'il est installé.
     *
     * ── POURQUOI CETTE MÉTHODE EXISTE ─────────────────────────────────
     *
     * Droplet fonctionne sans internet. Or, jusqu'ici, il fallait
     * internet pour se le PROCURER — ce qui est un défaut de conception
     * assez comique pour une application dont l'argument est justement
     * de s'en passer, et un vrai obstacle là où les données mobiles se
     * paient au méga-octet.
     *
     * `sourceDir` donne le chemin de l'APK installé. Partagé par
     * Bluetooth, par Wi-Fi Direct ou par une carte mémoire, il installe
     * Droplet sur un autre téléphone sans qu'aucun des deux n'ait de
     * connexion.
     *
     * ⚠️ L'APK renvoyé est celui de CETTE architecture. Les versions
     * sont construites avec `--split-per-abi` : le fichier est complet
     * pour un téléphone semblable, mais il n'installera pas Droplet sur
     * une machine d'architecture différente. C'est le compromis assumé
     * du découpage par architecture, qui fait passer l'application de
     * 242 Mo à une cinquantaine.
     */
    /**
     * Ouvre le clavier téléphonique avec un code opérateur déjà saisi.
     *
     * ── ⚠️ ACTION_DIAL ET NON ACTION_CALL, DÉLIBÉRÉMENT ────────────────
     *
     * `ACTION_CALL` exécuterait le code tout seul — mais il exige la
     * permission `CALL_PHONE`, l'une des plus sensibles d'Android :
     * elle autorise une application à passer des appels sans rien
     * demander. La réclamer pour composer un code de paiement est
     * disproportionné, et c'est exactement le genre de permission qui
     * fait hésiter au moment d'installer, sur une application dont
     * l'argument principal est qu'elle ne prend rien.
     *
     * `ACTION_DIAL` n'exige RIEN. Le code apparaît déjà écrit dans le
     * clavier, la personne appuie sur appeler. Un geste de plus, zéro
     * permission — et surtout, elle voit ce qui va être composé avant
     * que ça parte.
     *
     * ⚠️ LE DIÈSE DOIT ÊTRE ENCODÉ. Un `#` brut dans une URI `tel:` est
     * lu comme un début d'ancre : `#150#` arriverait tronqué à `` et le
     * clavier s'ouvrirait vide. `Uri.encode` le transforme en `%23`.
     */
    private fun composerUssd(code: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(code)))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Ouvre un lien avec l'application qui sait le traiter.
     *
     * Sert à passer la main à WhatsApp avec un message déjà rédigé
     * (`https://wa.me/…?text=…`). Sans cela, la personne doit copier son
     * code, quitter Droplet, retrouver le bon contact, coller, puis
     * expliquer ce qu'elle a acheté — et le message qui arrive est le
     * plus souvent inexploitable.
     *
     * ⚠️ `FLAG_ACTIVITY_NEW_TASK` est obligatoire : on lance depuis un
     * contexte d'application, pas depuis une activité. Sans lui, Android
     * refuse le démarrage avec une exception.
     *
     * Renvoie `false` si rien ne sait ouvrir ce lien — WhatsApp non
     * installé, par exemple. L'appelant propose alors le chemin
     * habituel plutôt que de laisser croire à un échec.
     */
    private fun ouvrirLien(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Dépose ce que le widget doit afficher, et lui demande de se
     * redessiner.
     *
     * ⚠️ ON ÉCRIT DANS LE MÊME FICHIER QUE `shared_preferences`, avec
     * son préfixe. C'est ce qui permet au widget de lire sans que
     * Droplet ait à embarquer une dépendance de plus — et surtout sans
     * que le widget ait à ouvrir la base SQLite, ce qui pourrait la
     * corrompre (voir la note en tête de `WidgetDroplet`).
     *
     * Les valeurs sont écrites en Long parce que c'est ainsi que le
     * greffon Flutter range les entiers : un Int y serait relu comme
     * une valeur absente.
     */
    private fun majWidget(nonLus: Int, pairs: Int): Boolean {
        return try {
            context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            ).edit()
                .putLong("flutter.widget_non_lus", nonLus.toLong())
                .putLong("flutter.widget_pairs", pairs.toLong())
                .apply()
            WidgetDroplet.rafraichir(context)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun installerPath(): String? {
        return try {
            context.applicationInfo.sourceDir
        } catch (e: Exception) {
            null
        }
    }

    private fun deviceMemoryMb(): Int {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            val totalMb = (info.totalMem / (1024L * 1024L)).toInt()
            if (am.isLowRamDevice) minOf(totalMb, 2048) else totalMb
        } catch (e: Exception) {
            // Valeur inconnue : on renvoie 0, et l'appelant traitera
            // l'appareil comme modeste. Mieux vaut une interface sobre
            // sur un téléphone puissant que l'inverse.
            0
        }
    }

    private fun thermalStatus(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return -1
        return try {
            val power =
                context.getSystemService(Context.POWER_SERVICE) as PowerManager
            power.currentThermalStatus
        } catch (e: Exception) {
            -1
        }
    }

    /** Durée d'une vidéo, en millisecondes. -1 si illisible. */
    private fun durationMs(path: String): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: -1L
        } catch (e: Exception) {
            -1L
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Ne garde que les [maxMs] premières millisecondes de la vidéo.
     *
     * Renvoie le chemin du fichier produit, ou le chemin d'origine si la
     * vidéo était déjà assez courte.
     *
     * ⚠️ LA COUPE TOMBE SUR UNE IMAGE-CLÉ, pas exactement sur la
     * milliseconde demandée. Une vidéo compressée ne contient des images
     * complètes que de loin en loin ; les autres ne décrivent que les
     * différences avec la précédente. Couper ailleurs qu'à une image
     * complète laisserait la fin en bouillie. La durée obtenue est donc
     * légèrement INFÉRIEURE à la limite — jamais supérieure, ce qui est
     * le sens de la contrainte.
     */
    private fun trim(path: String, maxMs: Long): String {
        val source = File(path)
        if (!source.exists()) throw IllegalArgumentException("fichier absent")

        val duration = durationMs(path)
        // ⚠️ `duration < 0` signifie « durée illisible », PAS « trop
        // longue ». Découper un fichier qu'on n'a pas su lire, c'est le
        // casser à coup sûr : on le renvoie tel quel.
        if (duration < 0 || duration <= maxMs) return path

        val maxUs = maxMs * 1000

        val extractor = MediaExtractor()
        extractor.setDataSource(path)

        val target = File(
            source.parentFile,
            source.nameWithoutExtension + "_court.mp4",
        )
        if (target.exists()) target.delete()

        val muxer = MediaMuxer(
            target.absolutePath,
            MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
        )

        // ⚠️ L'ORIENTATION DOIT ÊTRE RECOPIÉE.
        //
        // Un téléphone filme toujours dans le sens du capteur et note à
        // part de combien il faut faire pivoter l'image. Cette note vit
        // dans le conteneur, pas dans les images — un nouveau conteneur
        // repart donc à zéro, et une vidéo filmée en portrait ressortait
        // couchée sur le côté.
        val rotation = MediaMetadataRetriever().let { r ->
            try {
                r.setDataSource(path)
                r.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
                )?.toIntOrNull() ?: 0
            } catch (e: Exception) {
                0
            } finally {
                try { r.release() } catch (_: Exception) {}
            }
        }
        if (rotation != 0) muxer.setOrientationHint(rotation)

        // Correspondance entre les pistes de la source et celles de la
        // sortie : leurs numéros ne coïncident pas forcément.
        val trackMap = HashMap<Int, Int>()
        var maxBufferSize = 0

        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            // On ne recopie que l'image et le son : les pistes de
            // sous-titres ou de métadonnées feraient échouer le muxer.
            if (!mime.startsWith("video/") && !mime.startsWith("audio/")) {
                continue
            }
            extractor.selectTrack(i)
            trackMap[i] = muxer.addTrack(format)

            if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                val size = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                if (size > maxBufferSize) maxBufferSize = size
            }
        }

        if (trackMap.isEmpty()) {
            extractor.release()
            muxer.release()
            target.delete()
            return path
        }

        // Un mégaoctet par défaut : suffisant pour une image en haute
        // définition, et le format annonce rarement sa taille maximale.
        if (maxBufferSize <= 0) maxBufferSize = 1 shl 20

        val buffer = ByteBuffer.allocate(maxBufferSize)
        val info = android.media.MediaCodec.BufferInfo()

        // ⚠️ CHAQUE PISTE S'ARRÊTE POUR ELLE-MÊME.
        //
        // L'image et le son sont entrelacés, mais pas au même rythme :
        // l'un des deux franchit la limite avant l'autre. La version
        // précédente sortait de la boucle au PREMIER échantillon trop
        // tardif, toutes pistes confondues — elle interrompait donc la
        // copie alors qu'il restait des images à écrire, et pouvait
        // sortir avant d'avoir rien écrit du tout.
        val finished = HashSet<Int>()
        var written = 0
        var ok = false

        try {
            muxer.start()
            while (finished.size < trackMap.size) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                val trackIndex = extractor.sampleTrackIndex
                val target2 = trackMap[trackIndex]
                val time = extractor.sampleTime

                if (target2 != null && !finished.contains(trackIndex)) {
                    if (time > maxUs) {
                        finished.add(trackIndex)
                    } else {
                        info.offset = 0
                        info.size = sampleSize
                        info.presentationTimeUs = time
                        info.flags = extractor.sampleFlags
                        muxer.writeSampleData(target2, buffer, info)
                        written++
                    }
                }
                extractor.advance()
            }
            // `stop()` est ce qui ÉCRIT l'index du fichier. Sans lui, le
            // MP4 n'a ni en-tête ni table des images : c'est très
            // exactement l'erreur qu'ExoPlayer signalait par
            // « NoDeclaredBrand ».
            muxer.stop()
            ok = written > 0
        } catch (e: Exception) {
            ok = false
        } finally {
            try { muxer.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }

        // Le résultat n'est utilisé que s'il est RÉELLEMENT lisible. En
        // cas de doute on renvoie l'original : une vidéo trop longue
        // reste préférable à une vidéo illisible.
        if (!ok || !target.exists() || target.length() < 1024 ||
            durationMs(target.absolutePath) <= 0
        ) {
            target.delete()
            return path
        }

        return target.absolutePath
    }

    /**
     * Dépose une copie du fichier dans la galerie ou les téléchargements.
     *
     * Le dossier est choisi d'après le type : une photo dans Images, une
     * vidéo dans Vidéos, le reste dans Téléchargements. C'est ce que
     * l'utilisateur attend — chercher une photo reçue dans le dossier
     * « Téléchargements » serait absurde.
     */
    private fun save(path: String, name: String, mime: String): String {
        val source = File(path)
        if (!source.exists()) throw IllegalArgumentException("fichier absent")

        val isImage = mime.startsWith("image/")
        val isVideo = mime.startsWith("video/")

        val collection = when {
            isImage -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            isVideo -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }

        val folder = when {
            isImage -> Environment.DIRECTORY_PICTURES + "/Droplet"
            isVideo -> Environment.DIRECTORY_MOVIES + "/Droplet"
            else -> Environment.DIRECTORY_DOWNLOADS + "/Droplet"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            if (mime.isNotEmpty()) {
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
                // `IS_PENDING` cache le fichier tant qu'il n'est pas
                // complet : sans lui, la galerie pourrait l'afficher à
                // moitié copié et le juger corrompu.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("enregistrement refusé")

        resolver.openOutputStream(uri).use { output ->
            if (output == null) throw IllegalStateException("écriture refusée")
            source.inputStream().use { it.copyTo(output) }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }

        return folder
    }
}
