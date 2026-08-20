/**
 * Tests du Worker :  node --test serveur/tests.mjs
 *
 * ⚠️ CE QU'ILS PROTÈGENT.
 *
 * Le format du numéro de téléphone n'a pas été deviné : il a été
 * DÉDUIT en interrogeant l'API de Fapshi, qui refuse `237678963221`
 * avec « Phone number must be a valid MTN or Orange » et accepte
 * `678963221`. C'est exactement le genre de détail qu'on ne retrouve
 * dans aucune documentation lisible, et dont la régression ne se voit
 * qu'en production — sur un message d'erreur que l'utilisateur
 * attribue à son propre numéro plutôt qu'à l'application.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normaliserTelephone, normaliserAppareil } from './index.js';

test('le numéro part en neuf chiffres locaux, jamais avec l\'indicatif', () => {
  // Ce que Fapshi attend.
  assert.equal(normaliserTelephone('678963221'), '678963221');

  // Ce que les gens collent depuis leurs contacts — l'indicatif est
  // accepté en entrée, puis retiré.
  assert.equal(normaliserTelephone('237678963221'), '678963221');
  assert.equal(normaliserTelephone('+237 678 96 32 21'), '678963221');
  assert.equal(normaliserTelephone('678 96 32 21'), '678963221');
});

test('un numéro qui n\'est pas camerounais est refusé avant l\'appel', () => {
  // Refuser ici coûte un message clair ; laisser passer coûte un
  // aller-retour réseau et une erreur incompréhensible.
  assert.equal(normaliserTelephone('778963221'), null, 'ne commence pas par 6');
  assert.equal(normaliserTelephone('67896322'), null, 'huit chiffres');
  assert.equal(normaliserTelephone('6789632210'), null, 'dix chiffres');
  assert.equal(normaliserTelephone(''), null);
  assert.equal(normaliserTelephone(null), null);
  assert.equal(normaliserTelephone('abcdefghi'), null);
});

test('le code d\'appareil fait seize caractères hexadécimaux', () => {
  assert.equal(normaliserAppareil('a1b2-c3d4-e5f6-0718'), 'a1b2c3d4e5f60718');
  assert.equal(normaliserAppareil('A1B2C3D4E5F60718'), 'a1b2c3d4e5f60718');
  assert.equal(normaliserAppareil('a1b2 c3d4 e5f6 0718'), 'a1b2c3d4e5f60718');

  // Trop court, trop long, ou pas hexadécimal : refusé.
  assert.equal(normaliserAppareil('a1b2c3d4'), null);
  assert.equal(normaliserAppareil('a1b2c3d4e5f607189'), null);
  assert.equal(normaliserAppareil('zzzz-zzzz-zzzz-zzzz'), null);
  assert.equal(normaliserAppareil(''), null);
});
