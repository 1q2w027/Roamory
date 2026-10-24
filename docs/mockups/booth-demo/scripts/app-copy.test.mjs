// The dark recording screen in the film uses the app's own copy. Run: node --test scripts/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const film = readFileSync(new URL('../compositions/film.html', import.meta.url), 'utf8');
const curtain = readFileSync(new URL('../../../../ios/Roamory/Roamory/Recording/RecordingCurtain.swift', import.meta.url), 'utf8');

// Each string is in the app's RecordingCurtain.swift and must be in the film.
const CURTAIN = [
  'Recording',
  'Screen at 0% brightness',
  'Tap and hold to wake',
  'Capturing · 30 fps',
  'Not saving',
  'Saving · ',
  'Shutter remote, volume key or AirPods: press to start or stop saving',
];

for (const s of CURTAIN) {
  test(`curtain copy "${s}" matches the app`, () => {
    assert.ok(curtain.includes(s), `the app no longer says "${s}": update this list and the film`);
    assert.ok(film.includes(s), `the film is missing "${s}"`);
  });
}

test('the film does not show a pill the curtain does not have', () => {
  assert.ok(!film.includes('Stop saving'), 'the curtain has no "Stop saving" pill; the button sits under it');
});
