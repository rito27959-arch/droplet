// ============================================================================
// SHADER DE RÉFRACTION LIQUIDE
// ----------------------------------------------------------------------------
// Un « shader » est un petit programme exécuté par la carte graphique du
// téléphone, une fois POUR CHAQUE PIXEL affiché, à chaque image. C'est ce
// qui permet des effets impossibles à obtenir avec des widgets ordinaires :
// ici, déformer l'image comme si on la regardait à travers une goutte
// d'eau en mouvement.
//
// LE PRINCIPE : au lieu d'afficher chaque pixel là où il devrait être, on
// va chercher sa couleur LÉGÈREMENT À CÔTÉ, selon une onde qui se
// déplace. L'œil interprète ce décalage comme de la matière transparente
// qui bouge — exactement ce que fait une vraie goutte d'eau posée sur une
// photo.
//
// Trois effets se superposent :
//   1. Une ONDE qui traverse l'écran (le « front » du liquide).
//   2. Une DÉFORMATION plus forte au niveau de ce front, nulle ailleurs.
//   3. Un LISERÉ LUMINEUX sur la crête, comme la lumière qui se
//      concentre au bord d'une goutte.
// ============================================================================

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// ── Entrées fournies par Flutter ────────────────────────────────────────
uniform vec2  uSize;      // Taille de la zone à dessiner, en pixels.
uniform float uTime;      // Temps écoulé, pour animer l'onde.
uniform float uProgress;  // Avancement de la transition, de 0 à 1.
uniform float uStrength;  // Intensité de la déformation (0 = aucune).
uniform sampler2D uTexture; // L'image d'origine à déformer.

out vec4 fragColor;

// Bruit simple et rapide : produit une valeur pseudo-aléatoire mais
// STABLE pour une position donnée. C'est ce qui évite que le liquide ait
// l'air d'une onde parfaitement régulière (donc artificielle) — un vrai
// fluide a toujours de légères irrégularités.
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Interpolation douce du bruit : sans ça, le bruit brut donnerait un
// grain de télévision. On lisse entre les valeurs voisines.
float smoothNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    // Courbe d'adoucissement (« smoothstep » manuel) : accélère puis
    // décélère, ce qui supprime les cassures visibles entre cellules.
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = noise(i);
    float b = noise(i + vec2(1.0, 0.0));
    float c = noise(i + vec2(0.0, 1.0));
    float d = noise(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
    // Coordonnées normalisées : (0,0) en haut à gauche, (1,1) en bas à
    // droite — indépendantes de la taille réelle de l'écran.
    vec2 uv = FlutterFragCoord().xy / uSize;

    // ── 1. LE FRONT DE L'ONDE ───────────────────────────────────────
    // Il balaie l'écran de haut en bas au fil de `uProgress`. On le fait
    // partir légèrement au-dessus et finir en dessous pour que l'écran
    // soit entièrement traversé.
    float front = uProgress * 1.4 - 0.2;

    // Distance verticale entre ce pixel et le front de l'onde.
    float dist = uv.y - front;

    // ── 2. L'INTENSITÉ DE DÉFORMATION ───────────────────────────────
    // Maximale juste sur le front, elle retombe vite de part et d'autre.
    // `exp(-x²)` donne une cloche : c'est ce qui concentre l'effet sur
    // une bande étroite au lieu de déformer tout l'écran.
    float band = exp(-(dist * dist) / 0.012);

    // ── 3. L'ONDULATION ─────────────────────────────────────────────
    // Deux ondes de fréquences différentes qui se superposent, plus un
    // peu de bruit : combinées, elles ne se répètent jamais exactement à
    // l'identique, ce qui donne son aspect organique au liquide.
    float wave =
        sin(uv.x * 14.0 + uTime * 2.2) * 0.5 +
        sin(uv.x * 27.0 - uTime * 1.4) * 0.3 +
        (smoothNoise(vec2(uv.x * 6.0, uTime * 0.5)) - 0.5) * 0.4;

    // Le décalage appliqué au pixel. Il est surtout vertical (le liquide
    // s'écoule vers le bas) avec une composante horizontale plus faible,
    // qui donne l'impression que la matière glisse latéralement.
    vec2 offset = vec2(
        wave * band * uStrength * 0.020,
        band * uStrength * 0.045
    );

    // On va chercher la couleur à la position décalée. `clamp` évite de
    // sortir de l'image (ce qui produirait des bords étirés disgracieux).
    vec2 sampleUv = clamp(uv + offset, vec2(0.0), vec2(1.0));
    vec4 color = texture(uTexture, sampleUv);

    // ── 4. LE LISERÉ LUMINEUX ───────────────────────────────────────
    // Sur la crête de l'onde, la lumière se concentre — comme le bord
    // brillant d'une goutte d'eau. Très subtil (0.18 maximum) : au-delà,
    // ça vire à l'effet spécial de science-fiction.
    float crest = exp(-(dist * dist) / 0.0015);
    color.rgb += vec3(crest * uStrength * 0.18);

    fragColor = color;
}
