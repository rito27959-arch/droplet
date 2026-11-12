<?php
// Petit programme d'essai du kit PHP : `commencer` puis `terminer`.
require __DIR__ . '/../php/src/DropletId.php';
[, $emetteur, $clientId, $retour, $etape] = $argv;
$did = new DropletMesh\DropletId($clientId, $retour, null, $emetteur, ['openid', 'profile']);
if ($etape === 'commencer') {
    [$url, $attente] = $did->commencer();
    echo json_encode(['url' => $url, 'attente' => $attente]);
} else {
    $s = $did->terminer($argv[5], json_decode($argv[6], true));
    echo json_encode(['sub' => $s['sub'], 'pseudo' => $s['pseudo']]);
}
