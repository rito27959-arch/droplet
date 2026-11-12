package app.dropletmesh.id

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

/**
 * Se connecter avec Droplet ID depuis une app Android (Kotlin), par-dessus
 * AppAuth (la bibliothèque de référence d'OpenID pour Android).
 *
 * ```kotlin
 * val did = DropletId(context, clientId = "mon-app", redirectUri = Uri.parse("cm.monapp:/connexion"))
 * // 1. ouvrir Droplet ID
 * lanceur.launch(did.intentionDeConnexion())
 * // 2. au retour (ActivityResult)
 * val session = did.terminer(resultat.data!!)
 * session.sub   // identifiant propre à votre app
 * ```
 *
 * Flux « authorization code + PKCE » ; la page s'ouvre dans un onglet
 * sécurisé (Custom Tab), jamais une WebView. AppAuth vérifie l'ID token
 * (émetteur, audience, dates, nonce).
 */
class DropletId(
    context: Context,
    val clientId: String,
    val redirectUri: Uri,
    val emetteur: Uri = Uri.parse(EMETTEUR),
    portees: List<String> = listOf("openid"),
) {
    companion object {
        const val EMETTEUR = "https://id.dropletmesh.app"
        const val EMETTEUR_TEST = "https://id-test.dropletmesh.app"

        /** Le contenu (non vérifié) d'un JWT ; la vérification est faite par AppAuth. */
        internal fun claims(jwt: String): JSONObject {
            val parts = jwt.split('.')
            require(parts.size == 3) { "format" }
            return JSONObject(String(Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)))
        }

        internal fun avecOpenid(p: List<String>) = if ("openid" in p) p else listOf("openid") + p
    }

    val portees: List<String> = avecOpenid(portees)
    private val service = AuthorizationService(context.applicationContext)
    private var config: AuthorizationServiceConfiguration? = null

    data class Session(
        /** Identifiant de la personne, propre à VOTRE app. Stable. */
        val sub: String,
        val pseudo: String?,
        val idToken: String,
        val accessToken: String,
        val refreshToken: String?,
    )

    class Erreur(val code: String, description: String = "") : Exception(if (description.isEmpty()) code else "$code: $description")

    private suspend fun configuration(): AuthorizationServiceConfiguration =
        config ?: suspendCoroutine { c ->
            AuthorizationServiceConfiguration.fetchFromIssuer(emetteur) { conf, ex ->
                if (conf != null) { config = conf; c.resume(conf) } else c.resumeWithException(Erreur("decouverte", ex?.message ?: ""))
            }
        }

    /** L'intention qui ouvre Droplet ID (à lancer avec un ActivityResultLauncher). */
    suspend fun intentionDeConnexion(langue: String? = null): Intent {
        val requete = AuthorizationRequest.Builder(configuration(), clientId, ResponseTypeValues.CODE, redirectUri)
            .setScopes(portees)
            .apply { if (langue != null) setUiLocales(langue) }
            .build() // PKCE (S256), state et nonce sont générés par AppAuth.
        return service.getAuthorizationRequestIntent(requete)
    }

    /** Au retour : échange le code et rend la session. */
    suspend fun terminer(donnees: Intent): Session {
        AuthorizationException.fromIntent(donnees)?.let { throw Erreur(it.error ?: "erreur", it.errorDescription ?: "") }
        val reponse = AuthorizationResponse.fromIntent(donnees) ?: throw Erreur("reponse", "absente")
        val jetons = suspendCoroutine { c ->
            service.performTokenRequest(reponse.createTokenExchangeRequest()) { t, ex ->
                if (t != null) c.resume(t) else c.resumeWithException(Erreur(ex?.error ?: "jeton", ex?.errorDescription ?: ""))
            }
        }
        val idToken = jetons.idToken ?: throw Erreur("jeton", "id_token absent")
        val claims = claims(idToken)
        return Session(
            sub = claims.getString("sub"),
            pseudo = claims.optString("preferred_username").ifEmpty { null },
            idToken = idToken,
            accessToken = jetons.accessToken ?: throw Erreur("jeton", "access_token absent"),
            refreshToken = jetons.refreshToken,
        )
    }

    fun fermer() = service.dispose()
}
