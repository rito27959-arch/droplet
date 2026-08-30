// ============================================================================
// NEXUS SHADER — Le cœur visuel de la connexion Droplet
// ============================================================================
//
// Ce shader produisait CHAQUE PIXEL de l'expérience Nexus, en temps réel,
// sur le GPU du téléphone. Aucun GIF, aucune vidéo, aucun asset pré-rendu :
// tout est calculé procéduralement à chaque image.
//
// Les cinq effets superposés :
//
//   1. FLUID SIMULATION — champs de vitesse turbulent (noise de Simplex
//      à 3 octaves), qui donne le mouvement organique à toute la scène.
//
//   2. CAUSTIQUES — les motifs lumineux qu'on voit au fond d'une piscine,
//      produits par la réfraction de la lumière à travers une surface
//      d'eau en mouvement.
//
//   3. VOLUMETRIC LIGHT — rayons de lumière progressant à travers le
//      volume, comme des faisceaux dans un brouillard épais.
//
//   4. BLOOM + CHROMATIC ABERRATION — halo lumineux autour des zones
//      brillantes, et léger décalage RGB sur les bords de l'écran.
//
//   5. GLASS DISTORTION — déformation de type cristal/verre liquide,
//      qui donne sa qualité de « matière transparente » à la goutte.
//
// Les uniformes sont CALÉS sur ce que Dart envoie via `FragmentShader` :
//   uSize, uTime, uPhase, uPhaseProgress, uOverallProgress,
//   uSeed (xyzw), uColor (xyzw), uIntensity, uDpr
// ============================================================================

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// ── Uniformes ────────────────────────────────────────────────────────────────
uniform vec2  uSize;             // Taille logique de la zone (points)
uniform float uTime;             // Temps écoulé en secondes
uniform float uPhase;            // Phase courante (0=idle 1=awake 2=birth 3=wave 4=sync 5=identity 6=done)
uniform float uPhaseProgress;    // Progression dans la phase courante (0→1)
uniform float uOverallProgress;  // Progression globale de l'expérience (0→1)
uniform float uSeedX;            // Aléatoire partagé X
uniform float uSeedY;            // Aléatoire partagé Y
uniform float uSeedZ;            // Aléatoire partagé Z
uniform float uSeedW;            // Aléatoire partagé W
uniform float uColorR;           // Couleur signature R (0→1)
uniform float uColorG;           // Couleur signature G (0→1)
uniform float uColorB;           // Couleur signature B (0→1)
uniform float uColorA;           // Couleur signature A (0→1)
uniform float uIntensity;        // Intensité globale (0→1)
uniform float uDpr;              // Device pixel ratio

out vec4 fragColor;

// ============================================================================
// FONCTIONS UTILITAIRES
// ============================================================================

// ── Simplex Noise 2D ────────────────────────────────────────────────────────
// Implémentation compacte du bruit de Simplex par Ashima Arts.
// Beaucoup plus rapide et plus beau que le bruit de Perlin classique :
// pas d'artefacts en grille, et les gradients sont distribués plus
// uniformément sur le cercle unité.
const vec3 F3 = vec3(0.3333333);
const vec3 G3 = vec3(0.1666667);

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 10.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(0.1666667, 0.3333333);
    const vec3 D = vec3(0.0, 0.5, 1.0);

    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289(i);
    vec4 p = permute(permute(permute(
        i.z + vec4(0.0, i1.z, i2.z, 1.0))
      + i.y + vec4(0.0, i1.y, i2.y, 1.0))
      + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    vec3 ns = n_ * D.zxy - D.xxx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = taylorInvSqrt(vec4(
        dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)
    ));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    vec4 m = max(0.5 - vec4(
        dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)
    ), 0.0);
    m = m * m;
    return 105.0 * dot(m * m, vec4(
        dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)
    ));
}

// ── FBM (Fractional Brownian Motion) ────────────────────────────────────────
// Superposition de plusieurs couches de bruit à des échelles différentes.
// 3 octaves = bon compromis qualité/performance sur mobile GPU.
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 3; i++) {
        value += amplitude * snoise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// ── Smoothstep amélioré ─────────────────────────────────────────────────────
// Plus doux que le smoothstep standard, évite les dérivées nulles aux bornes.
float smootherstep(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// ── Palette de couleurs Nexus ───────────────────────────────────────────────
// La teinte signature est injectée via uColor ; le shader la module
// pour créer les tons clair/sombre/éclair du volume.
vec3 palette(float t, vec3 base) {
    vec3 a = base;
    vec3 b = base * 0.5 + vec3(0.3, 0.3, 0.5);
    vec3 c = vec3(1.0);
    vec3 d = vec3(0.0, 0.15, 0.3);
    return a + b * cos(6.28318 * (c * t + d));
}

// ============================================================================
// EFFET 1 — FLUID SIMULATION
// ============================================================================
// Un champ de vitesse turbulent qui déforme les coordonnées UV.
// Utilisé par TOUS les effets en aval : caustiques, lumière volumétrique,
// et la distorsion de la goutte elle-même.
//
// Le mouvement est composé de deux couches :
//   - Un courant lent et large (fréquence basse) : la masse du fluide.
//   - Des tourbillons fins (fréquence haute) : les détails organiques.
vec2 fluidDisplace(vec2 uv, float time, float strength) {
    float t = time * 0.15;
    // Courant principal — lent, large, organique
    vec3 p1 = vec3(uv * 1.8, t);
    float field1 = fbm(p1);
    // Tourbillons fins — rapides, petits, détails
    vec3 p2 = vec3(uv * 4.5, t * 1.3 + 10.0);
    float field2 = fbm(p2);
    // Combinaison : le champ principal gouverne, les détails ajoutent
    // de la vie sans dominer.
    vec2 displacement = vec2(
        field1 * 0.6 + field2 * 0.4,
        field1 * 0.4 - field2 * 0.6
    ) * strength;
    return uv + displacement;
}

// ============================================================================
// EFFET 2 — CAUSTIQUES
// ============================================================================
// Les motifs lumineux du fond d'une piscine. Produits par l'intersection
// de plusieurs ondelettes circulaires déformées par le champ de fluide.
//
// Le principe physique : quand la lumière passe à travers une surface
// d'eau ondulante, elle se concentre en lignes brillantes (caustiques)
// et laisse des zones sombres. On simule ça en calculant l'amplitude
// de plusieurs vagues et en prenant le carré de leur somme : les crêtes
// s'additionnent et brillent, les creux s'annulent et s'assombrissent.
float caustics(vec2 uv, float time, float intensity) {
    float t = time * 0.4;
    float c = 0.0;
    // Trois ondelettes à des fréquences et directions différentes
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 dir = vec2(
            cos(fi * 2.094 + t * 0.3),
            sin(fi * 2.094 + t * 0.3)
        );
        float wave = dot(uv, dir) * 6.0 + t * (1.0 + fi * 0.4);
        c += sin(wave) * sin(wave * 1.5 + fi);
    }
    // Le carré concentre les maxima en lignes brillantes
    c = pow(abs(c / 3.0), 2.5);
    return c * intensity;
}

// ============================================================================
// EFFET 3 — VOLUMETRIC LIGHT
// ============================================================================
// Rayons de lumière progressant dans un volume diffusant (brouillard,
// fumée, eau trouble). Inspiré de la technique de marching cubes.
//
// Pour chaque pixel, on lance un rayon vers la source de lumière et
// on accumule la densité du long du chemin. Plus le chemin traverse
// de matière « dense » (noise), plus le rayon est visible.
//
// La technique est allégée pour mobile : pas de vraie densité 3D, juste
// une évaluation 2D du bruit le long du rayon, avec 6 échantillons.
float volumetricLight(vec2 uv, vec2 lightPos, float time, float intensity) {
    vec2 rayDir = normalize(lightPos - uv);
    float dist = length(lightPos - uv);
    float accumulation = 0.0;
    float density = 0.0;
    const int SAMPLES = 6;
    float stepSize = 1.0 / float(SAMPLES);

    for (int i = 0; i < SAMPLES; i++) {
        float t = float(i) * stepSize;
        vec2 samplePos = uv + rayDir * t * dist * 0.6;
        float d = fbm(vec3(samplePos * 3.0, time * 0.2 + t * 2.0));
        d = smoothstep(-0.2, 0.8, d);
        accumulation += d * (1.0 - t);
        density += d;
    }

    accumulation /= float(SAMPLES);
    // Atténuation avec la distance (loi de l'inverse carré, approximée)
    float attenuation = 1.0 / (1.0 + dist * dist * 2.0);
    return accumulation * attenuation * intensity * 0.5;
}

// ============================================================================
// EFFET 4 — BLOOM
// ============================================================================
// Halo lumineux autour des zones brillantes. Simulé par un simple
// sample de la luminosité locale à une échelle plus large.
float bloom(vec2 uv, float time, float intensity) {
    float b = 0.0;
    const int SAMPLES = 8;
    float totalWeight = 0.0;
    for (int i = 0; i < SAMPLES; i++) {
        float angle = float(i) * 0.785398; // pi/4
        vec2 offset = vec2(cos(angle), sin(angle));
        float weight = 1.0 / (1.0 + float(i) * 0.5);
        float n = snoise(vec3((uv + offset * 0.08) * 5.0, time * 0.3));
        b += max(n, 0.0) * weight;
        totalWeight += weight;
    }
    return (b / totalWeight) * intensity;
}

// ============================================================================
// EFFET 5 — CHROMATIC ABERRATION
// ============================================================================
// Décalage léger des canaux RGB sur les bords de l'écran, comme un
// prisme. Effet optique qui donne de la profondeur et un aspect
// « matière vivante » sans être kitsch.
vec3 chromaticAberration(vec2 uv, vec2 center, float time, float amount) {
    vec2 dir = uv - center;
    float dist = length(dir);
    float offset = dist * dist * amount;
    // L'aberration est radiale : chaque canal se décale à une distance
    // différente du centre, comme dans un vrai objectif défectueux.
    float r = offset * 1.0;
    float g = offset * 0.0;
    float b = -offset * 1.0;
    return vec3(r, g, b);
}

// ============================================================================
// EFFET 6 — GLASS DISTORTION
// ============================================================================
// Déformation de type verre/cristal liquide. Produit des motifs de
// réfraction qui donnent à la goutte sa qualité de matière transparente.
// Basé sur le noise de Simplex à haute fréquence, filtré pour créer
// des facets plutôt que du grain.
float glassDistortion(vec2 uv, float time, float intensity) {
    vec3 p = vec3(uv * 8.0, time * 0.5);
    float n1 = snoise(p);
    float n2 = snoise(p * 2.0 + 100.0);
    // Les facettes viennent du quantization discret du bruit
    float facets = floor(n1 * 5.0) / 5.0;
    return (facets * 0.5 + n2 * 0.5) * intensity;
}

// ============================================================================
// CONCENTRATEUR DE GOUTTE
// ============================================================================
// Masque radial qui dessine la forme de la goutte au centre.
// Pas un simple cercle : c'est un cercle déformé par le bruit pour
// qu'il ait un bord organique, comme une vraie goutte.
float dropletShape(vec2 uv, vec2 center, float radius, float time, float softness) {
    vec2 d = uv - center;
    float dist = length(d);
    // Légère déformation organique du bord
    float angle = atan(d.y, d.x);
    float deform = snoise(vec3(
        cos(angle) * 2.0,
        sin(angle) * 2.0,
        time * 0.8
    )) * radius * 0.12;
    float r = radius + deform;
    return smootherstep(r, r * softness, dist);
}

// ============================================================================
// MAIN
// ============================================================================
void main() {
    vec2 uv = FlutterFragCoord().xy / (uSize * uDpr);
    vec2 center = vec2(0.5, 0.5);
    float t = uTime;
    vec3 baseColor = vec3(uColorR, uColorG, uColorB);
    float intensity = uIntensity;

    // ── Fond sombre avec respiration ─────────────────────────────────────
    // Le fond n'est pas noir pur : il a une teinte très sombre issue de
    // la couleur signature, et il « respire » très légèrement.
    float breath = sin(t * 0.5) * 0.5 + 0.5;
    vec3 bg = baseColor * 0.03 * (0.8 + breath * 0.4);

    // ── Champ de fluide (utilisé par tous les effets) ────────────────────
    float fluidStr = intensity * 0.15;
    vec2 fluidUv = fluidDisplace(uv, t, fluidStr);

    // ── Génération des effets selon la phase ─────────────────────────────
    vec3 result = bg;
    float dropletMask = 0.0;

    // Phase 1+ : Caustiques en arrière-plan (très subtiles)
    if (uPhase >= 1.0) {
        float caustStrength = smootherstep(0.0, 0.3, uPhaseProgress) * 0.08 * intensity;
        float caust = caustics(fluidUv * 2.0, t, caustStrength);
        result += baseColor * caust * 0.4;
    }

    // Phase 2+ : La goutte apparaît
    if (uPhase >= 2.0) {
        float birthT = uPhase == 2.0 ? uPhaseProgress : 1.0;
        // La goutte « naît » en croissant de taille
        float radius = smootherstep(0.0, 1.0, birthT) * 0.18;
        // Pulsation subtile une fois pleine taille
        radius += sin(t * 2.0) * 0.008;
        dropletMask = dropletShape(fluidUv, center, radius, t, 0.4);

        // Intérieur de la goutte : verre + caustiques fortes
        float glass = glassDistortion(fluidUv, t, 0.3 * dropletMask);
        float innerCaust = caustics(fluidUv * 4.0, t, 0.35 * dropletMask);
        // Refraction : la couleur derrière la goutte est décalée
        vec2 refracted = uv + (fluidUv - uv) * 0.3 * dropletMask;
        vec3 glassColor = palette(
            snoise(vec3(refracted * 3.0, t * 0.4)) * 0.5 + 0.5,
            baseColor
        );
        // Mélange verre + caustiques intérieures
        vec3 dropInterior = glassColor * (0.3 + glass * 0.4 + innerCaust * 0.5);
        // Bord de la goutte : halolumineux (comme un bord de verre)
        float edge = smoothstep(0.3, 0.0, abs(dropletMask - 0.5)) * 0.6;
        dropInterior += baseColor * edge;

        result = mix(result, dropInterior, dropletMask * birthT);
    }

    // Phase 3+ : L'onde de connexion se propage
    if (uPhase >= 3.0) {
        float waveT = uPhase == 3.0 ? uPhaseProgress : 1.0;
        // L'onde part du centre et se propage vers l'extérieur
        float waveDist = length(uv - center);
        float waveFront = waveT * 1.2;
        // Front large avec turbulence
        float turbulence = fbm(vec3(uv * 5.0, t * 0.6)) * 0.08;
        float wave = smootherstep(
            waveFront - 0.15 + turbulence,
            waveFront + 0.05 + turbulence,
            waveDist
        );
        // La déformation est maximale sur le front
        float deformStrength = exp(-pow((waveDist - waveFront) * 8.0, 2.0));
        vec2 waveOffset = normalize(uv - center) * deformStrength * 0.04;

        // Appliquer la déformation à tous les effets
        vec2 waveUv = uv + waveOffset;
        float waveCaust = caustics(waveUv * 3.0, t, 0.2 * deformStrength);
        result += baseColor * waveCaust * wave;

        // Halolumineux du front d'onde
        float crest = exp(-pow((waveDist - waveFront) * 15.0, 2.0));
        result += baseColor * crest * 0.35 * wave;
    }

    // Phase 4+ : Sync dual — les deux écrans ne font qu'un
    if (uPhase >= 4.0) {
        float syncT = uPhase == 4.0 ? uPhaseProgress : 1.0;
        // Réseau de points lumineux (représentation mesh)
        float network = 0.0;
        const int NODES = 12;
        for (int i = 0; i < NODES; i++) {
            float fi = float(i);
            // Position pseudo-aléatoire stable (dépend de la seed)
            vec2 nodePos = center + vec2(
                    cos(fi * 2.399 + uSeedX * 6.283) * 0.25,
                    sin(fi * 2.399 + uSeedY * 6.283) * 0.25
            );
            // Taille variable
            float nodeSize = 0.003 + sin(fi + t) * 0.001;
            float d = length(uv - nodePos);
            network += exp(-d * d * 8000.0) * nodeSize * 50.0;

            // Lignes de connexion entre nœuds proches
            for (int j = i + 1; j < NODES; j++) {
                float fj = float(j);
                vec2 nodeJ = center + vec2(
                    cos(fj * 2.399 + uSeedX * 6.283) * 0.25,
                    sin(fj * 2.399 + uSeedY * 6.283) * 0.25
                );
                vec2 mid = (nodePos + nodeJ) * 0.5;
                float lineD = length(uv - mid);
                float lineLen = length(nodePos - nodeJ);
                // Pulsation le long de la ligne
                float pulse = sin(t * 3.0 + fi + fj) * 0.5 + 0.5;
                network += exp(-lineD * lineD * 15000.0)
                    * smootherstep(lineLen * 0.5, lineLen * 0.3, lineD)
                    * pulse * 0.3;
            }
        }
        result += baseColor * network * syncT * 0.8;
    }

    // Phase 5+ : Identité — texte « projeté dans la lumière »
    // (le texte est géré par le widget Dart, mais on ajoute un halo ici)
    if (uPhase >= 5.0) {
        float idT = uPhase == 5.0 ? uPhaseProgress : 1.0;
        // Halo descendant depuis le centre — comme un projecteur
        float spotlight = 1.0 - smootherstep(0.0, 0.5, length(uv - vec2(0.5, 0.35)));
        result += baseColor * spotlight * 0.12 * idT;
    }

    // ── Volumetric Light ─────────────────────────────────────────────────
    // Toujours présent mais subtil, ajoutant de la profondeur
    if (uPhase >= 1.0) {
        vec2 lightPos = vec2(0.5, 0.1);
        float vol = volumetricLight(fluidUv, lightPos, t, 0.15 * intensity);
        result += baseColor * vol * 0.3;
    }

    // ── Bloom ────────────────────────────────────────────────────────────
    float b = bloom(uv, t, 0.12 * intensity);
    result += baseColor * b * 0.2;

    // ── Chromatic Aberration (subtile, surtout sur les bords) ────────────
    vec3 chroma = chromaticAberration(uv, center, t, 0.008 * intensity);
    float r = result.r + chroma.r;
    float g = result.g + chroma.g;
    float bCh = result.b + chroma.b;

    // ── Vignette ─────────────────────────────────────────────────────────
    // Assombrit les bords de l'écran pour focaliser l'attention au centre.
    float vignette = 1.0 - dot(uv - center, uv - center) * 1.5;
    vignette = smootherstep(0.0, 1.0, vignette);

    // ── Assemblage final ─────────────────────────────────────────────────
    vec3 final = vec3(r, g, bCh) * vignette;

    // Le tout est modulé par l'intensité globale pour que le fond
    // reste visible quand le Nexus n'est pas en cours.
    final = mix(bg, final, intensity);

    fragColor = vec4(final, 1.0);
}
