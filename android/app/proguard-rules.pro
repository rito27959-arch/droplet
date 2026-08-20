# =====================================================================
#  RÈGLES DE CONSERVATION R8 — Droplet
# ---------------------------------------------------------------------
#  À QUOI SERT CE FICHIER ?
#
#  En compilation « release », R8 parcourt tout le code Java/Kotlin de
#  l'application et de ses bibliothèques, puis SUPPRIME tout ce qui n'est
#  atteint par personne, et RENOMME le reste en noms d'une lettre. Le
#  résultat est plus petit et plus difficile à rétro-analyser.
#
#  Le raisonnement de R8 est purement statique : il suit les appels
#  écrits dans le code. Or une bonne partie d'une app Flutter est appelée
#  AUTREMENT — par réflexion depuis le moteur Flutter, ou depuis du code
#  natif C qui remonte vers Java par JNI. Ces appels-là, R8 ne les voit
#  pas. Il conclut donc que la classe est morte, et la supprime.
#
#  ⚠️ Le symptôme est traître : la compilation réussit, l'app démarre,
#  et elle plante seulement quand on atteint la fonction concernée —
#  avec un `ClassNotFoundException` portant un nom illisible parce que
#  tout a été renommé. C'est la raison pour laquelle chaque règle
#  ci-dessous porte la justification de ce qu'elle protège.
# =====================================================================


# ── Flutter lui-même ────────────────────────────────────────────────
#
# Le moteur Flutter instancie ses greffons par réflexion, à partir du
# nom de classe inscrit dans le manifeste généré.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**


# ── Notre propre code natif ─────────────────────────────────────────
#
# `MediaBridge.kt` (découpe vidéo, état thermique) est appelé depuis
# Dart via un MethodChannel : le nom de la classe et celui des méthodes
# transitent sous forme de CHAÎNES de caractères. R8 ne peut pas faire
# le lien, et renommerait la classe sans rien casser à ses yeux.
-keep class com.droplet.droplet.** { *; }


# ── SQLite (cartes hors connexion, cache de tuiles) ─────────────────
#
# `sqlite3_flutter_libs` embarque une bibliothèque C. Les liaisons
# passent par JNI, donc depuis du code que R8 ne lit pas.
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**


# ── Service premier plan (le mesh continue app fermée) ──────────────
#
# Un Service Android est instancié PAR LE SYSTÈME, à partir du nom
# inscrit dans le manifeste. Aucun appel dans le code ne le désigne.
-keep class com.pravera.flutter_foreground_task.** { *; }


# ── Notifications ───────────────────────────────────────────────────
#
# Les receveurs de diffusion (rappels programmés, actions depuis la
# notification) sont eux aussi lancés par le système via le manifeste.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends android.app.NotificationManager { *; }
# Cette bibliothèque sérialise ses notifications programmées en JSON via
# Gson, qui lit les champs par réflexion : les renommer casse la
# relecture des notifications déjà enregistrées.
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*


# ── Appels audio/vidéo (WebRTC) ─────────────────────────────────────
#
# WebRTC est massivement natif : la couche C++ rappelle Java par JNI
# pour livrer les flux et les changements d'état.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**


# ── Localisation (carte, check-ins de sécurité) ─────────────────────
-keep class com.baseflow.geolocator.** { *; }
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.gms.**


# ── Bluetooth et Wi-Fi Direct (le mesh) ─────────────────────────────
#
# Le cœur de Droplet. Les rappels de découverte de pairs et de
# changement d'état de connexion viennent du système Android.
-keep class com.polidea.** { *; }
-keep class * extends android.content.BroadcastReceiver { *; }


# ── Désucrage Java 8+ ───────────────────────────────────────────────
-dontwarn java.lang.invoke.**
-dontwarn **$$serializer


# ── Lisibilité des rapports de plantage ─────────────────────────────
#
# Sans ces attributs, une pile d'appels de release ne contient plus ni
# nom de fichier ni numéro de ligne : elle devient indéchiffrable. Pour
# une app qui n'a AUCUN serveur de télémétrie — donc dont le seul
# diagnostic possible est le journal local (`crash_journal.dart`) et ce
# que l'utilisateur veut bien envoyer — s'en priver reviendrait à
# renoncer à corriger quoi que ce soit après publication.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
