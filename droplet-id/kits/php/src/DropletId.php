<?php
/**
 * Droplet ID pour PHP — sans dépendance (PHP 8.1+, extensions openssl et json).
 * Fonctionne aussi sur un hébergement mutualisé.
 *
 *   $did = new DropletMesh\DropletId('mon-site', 'https://mon-site.cm/connexion/retour');
 *   [$url, $attente] = $did->commencer();   // $_SESSION['droplet_id_attente'] = $attente;
 *   header('Location: ' . $url);
 *   // … au retour :
 *   $session = $did->terminer($urlComplete, $_SESSION['droplet_id_attente']);
 *   $session['sub'];                       // identifiant propre à votre site
 *
 * Standard OpenID Connect : code + PKCE (S256), state, nonce ; l'ID token est
 * vérifié (signature ES256 via JWKS, émetteur, audience, dates, nonce).
 */

declare(strict_types=1);

namespace DropletMesh;

final class ErreurDropletId extends \RuntimeException
{
    public function __construct(public readonly string $codeErreur, string $description = '')
    {
        parent::__construct($description !== '' ? "$codeErreur: $description" : $codeErreur);
    }
}

final class DropletId
{
    public const EMETTEUR = 'https://id.dropletmesh.app';
    public const EMETTEUR_TEST = 'https://id-test.dropletmesh.app';

    private ?array $config = null;
    private ?array $cles = null;
    private array $portees;
    private string $emetteur;

    public function __construct(
        private readonly string $clientId,
        private readonly string $redirectUri,
        private readonly ?string $clientSecret = null,
        string $emetteur = self::EMETTEUR,
        array $portees = ['openid'],
    ) {
        $this->emetteur = rtrim($emetteur, '/');
        $this->portees = in_array('openid', $portees, true) ? $portees : ['openid', ...$portees];
    }

    // ── Découverte ────────────────────────────────────────────────────
    public function configuration(): array
    {
        if ($this->config === null) {
            $c = self::json($this->emetteur . '/.well-known/openid-configuration');
            if (($c['issuer'] ?? null) !== $this->emetteur) {
                throw new ErreurDropletId('decouverte', 'émetteur inattendu');
            }
            $this->config = $c;
        }
        return $this->config;
    }

    // ── Connexion ─────────────────────────────────────────────────────
    /** @return array{0: string, 1: array} [adresse de Droplet ID, attente à garder en session] */
    public function commencer(?string $langue = null): array
    {
        $verifier = self::b64url(random_bytes(32));
        $attente = ['verifier' => $verifier, 'state' => self::b64url(random_bytes(16)), 'nonce' => self::b64url(random_bytes(16))];
        $params = [
            'client_id' => $this->clientId,
            'response_type' => 'code',
            'redirect_uri' => $this->redirectUri,
            'scope' => implode(' ', $this->portees),
            'code_challenge' => self::b64url(hash('sha256', $verifier, true)),
            'code_challenge_method' => 'S256',
            'state' => $attente['state'],
            'nonce' => $attente['nonce'],
        ];
        if ($langue !== null) {
            $params['ui_locales'] = $langue;
        }
        return [$this->configuration()['authorization_endpoint'] . '?' . http_build_query($params, '', '&', PHP_QUERY_RFC3986), $attente];
    }

    /** Au retour : vérifie tout et rend ['sub' => …, 'pseudo' => …, 'id_token' => …, …]. */
    public function terminer(string $urlDeRetour, ?array $attente): array
    {
        parse_str((string) parse_url($urlDeRetour, PHP_URL_QUERY), $q);
        if (isset($q['error'])) {
            throw new ErreurDropletId((string) $q['error'], (string) ($q['error_description'] ?? ''));
        }
        if ($attente === null || !hash_equals((string) $attente['state'], (string) ($q['state'] ?? ''))) {
            throw new ErreurDropletId('state', 'réponse inattendue (state)');
        }
        if (isset($q['iss']) && $q['iss'] !== $this->emetteur) {
            throw new ErreurDropletId('iss', 'émetteur inattendu');
        }
        $donnees = [
            'grant_type' => 'authorization_code',
            'code' => (string) ($q['code'] ?? ''),
            'redirect_uri' => $this->redirectUri,
            'client_id' => $this->clientId,
            'code_verifier' => $attente['verifier'],
        ];
        if ($this->clientSecret !== null) {
            $donnees['client_secret'] = $this->clientSecret;
        }
        $t = self::json($this->configuration()['token_endpoint'], $donnees);
        $claims = $this->verifierIdToken($t['id_token'], $attente['nonce']);
        $pseudo = null;
        if (in_array('profile', $this->portees, true)) {
            $info = self::json($this->configuration()['userinfo_endpoint'], null, ['Authorization: Bearer ' . $t['access_token']]);
            if (($info['sub'] ?? null) !== $claims['sub']) {
                throw new ErreurDropletId('userinfo', 'sub différent');
            }
            $pseudo = $info['preferred_username'] ?? null;
        }
        return [
            'sub' => $claims['sub'],
            'pseudo' => $pseudo,
            'id_token' => $t['id_token'],
            'access_token' => $t['access_token'],
            'refresh_token' => $t['refresh_token'] ?? null,
            'expire_le' => time() + (int) ($t['expires_in'] ?? 0),
        ];
    }

    public function verifierIdToken(string $jwt, ?string $nonce = null): array
    {
        $parts = explode('.', $jwt);
        if (count($parts) !== 3) {
            throw new ErreurDropletId('id_token', 'format');
        }
        [$h, $c, $s] = $parts;
        $entete = json_decode(self::deB64url($h), true, 512, JSON_THROW_ON_ERROR);
        $claims = json_decode(self::deB64url($c), true, 512, JSON_THROW_ON_ERROR);
        if (($entete['alg'] ?? '') !== 'ES256') {
            throw new ErreurDropletId('id_token', 'algorithme');
        }
        $brute = self::deB64url($s);
        if (strlen($brute) !== 64) {
            throw new ErreurDropletId('id_token', 'signature');
        }
        $ok = openssl_verify("$h.$c", self::signatureDer($brute), $this->cle($entete['kid'] ?? null), OPENSSL_ALGO_SHA256);
        if ($ok !== 1) {
            throw new ErreurDropletId('id_token', 'signature');
        }
        $aud = $claims['aud'] ?? null;
        if (($claims['iss'] ?? null) !== $this->emetteur) {
            throw new ErreurDropletId('id_token', 'émetteur');
        }
        if ($aud !== $this->clientId && !(is_array($aud) && in_array($this->clientId, $aud, true))) {
            throw new ErreurDropletId('id_token', 'audience');
        }
        if (($claims['exp'] ?? 0) < time() - 60) {
            throw new ErreurDropletId('id_token', 'expiré');
        }
        if ($nonce !== null && !hash_equals($nonce, (string) ($claims['nonce'] ?? ''))) {
            throw new ErreurDropletId('id_token', 'nonce');
        }
        return $claims;
    }

    public function urlDeDeconnexion(string $idToken, ?string $retour = null): string
    {
        $p = ['id_token_hint' => $idToken, 'client_id' => $this->clientId];
        if ($retour !== null) {
            $p['post_logout_redirect_uri'] = $retour;
        }
        return $this->configuration()['end_session_endpoint'] . '?' . http_build_query($p, '', '&', PHP_QUERY_RFC3986);
    }

    // ── Outils ────────────────────────────────────────────────────────
    private function cle(?string $kid): \OpenSSLAsymmetricKey
    {
        if ($this->cles === null || ($kid !== null && !isset($this->cles[$kid]))) {
            $this->cles = [];
            foreach (self::json($this->configuration()['jwks_uri'])['keys'] as $k) {
                if (($k['kty'] ?? '') === 'EC' && ($k['crv'] ?? '') === 'P-256') {
                    // SubjectPublicKeyInfo d'une clé P-256 : en-tête fixe + 04 ‖ x ‖ y.
                    $der = hex2bin('3059301306072a8648ce3d020106082a8648ce3d030107034200') . "\x04" . self::deB64url($k['x']) . self::deB64url($k['y']);
                    $pem = "-----BEGIN PUBLIC KEY-----\n" . chunk_split(base64_encode($der), 64, "\n") . "-----END PUBLIC KEY-----\n";
                    $this->cles[$k['kid'] ?? ''] = openssl_pkey_get_public($pem);
                }
            }
        }
        $cle = $this->cles[$kid ?? ''] ?? (array_values($this->cles)[0] ?? null);
        if (!$cle) {
            throw new ErreurDropletId('id_token', 'aucune clé');
        }
        return $cle;
    }

    /** Signature JWS (r ‖ s, 64 octets) → DER, comme l'attend OpenSSL. */
    private static function signatureDer(string $brute): string
    {
        $entier = static function (string $o): string {
            $o = ltrim($o, "\x00");
            if ($o === '' || ord($o[0]) > 0x7f) {
                $o = "\x00" . $o;
            }
            return "\x02" . chr(strlen($o)) . $o;
        };
        $seq = $entier(substr($brute, 0, 32)) . $entier(substr($brute, 32));
        return "\x30" . chr(strlen($seq)) . $seq;
    }

    private static function json(string $url, ?array $formulaire = null, array $entetes = []): array
    {
        $options = ['http' => ['method' => 'GET', 'header' => ['Accept: application/json', ...$entetes], 'ignore_errors' => true, 'timeout' => 10]];
        if ($formulaire !== null) {
            $options['http']['method'] = 'POST';
            $options['http']['header'][] = 'Content-Type: application/x-www-form-urlencoded';
            $options['http']['content'] = http_build_query($formulaire, '', '&');
        }
        $corps = @file_get_contents($url, false, stream_context_create($options));
        $statut = isset($http_response_header[0]) && preg_match('#\s(\d{3})\s#', $http_response_header[0], $m) ? (int) $m[1] : 0;
        $j = json_decode((string) $corps, true);
        if ($corps === false || $statut >= 400 || !is_array($j)) {
            throw new ErreurDropletId(is_array($j) ? (string) ($j['error'] ?? "http_$statut") : "http_$statut", is_array($j) ? (string) ($j['error_description'] ?? '') : '');
        }
        return $j;
    }

    private static function b64url(string $o): string
    {
        return rtrim(strtr(base64_encode($o), '+/', '-_'), '=');
    }

    private static function deB64url(string $s): string
    {
        return (string) base64_decode(strtr($s, '-_', '+/') . str_repeat('=', (4 - strlen($s) % 4) % 4), true);
    }
}
