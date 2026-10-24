// Beat timing rules for the booth loop. Run: node --test scripts/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Run beats.js as the browser does (a classic script setting globals) in a sandbox.
const page = {};
vm.runInNewContext(readFileSync(new URL('../assets/beats.js', import.meta.url), 'utf8'), page);
// Copied out through JSON so arrays compare with this realm's arrays.
const beats = JSON.parse(JSON.stringify(page.ROAMORY_BEATS));
const { IN: HEADLINE_IN, OUT: HEADLINE_OUT, PX: HEADLINE_PX } = page.ROAMORY_HEADLINE;

test('beats tile 0..total with no gaps', () => {
  assert.equal(beats[0].start, 0);
  for (let i = 1; i < beats.length; i++) assert.equal(beats[i].start, beats[i - 1].end, beats[i].id);
});

test('total length is 30–36 s', () => {
  const total = beats.at(-1).end;
  assert.ok(total >= 30 && total <= 36, `total ${total}`);
});

test('ids and moods are the plan table', () => {
  assert.deepEqual(beats.map((b) => b.id), ['hook', 'setup', 'start', 'buffer', 'save', 'studio']);
  assert.deepEqual(beats.map((b) => b.mood), ['wave', 'happy', 'sleepy', 'sleepy', 'excited', 'happy']);
});

test('every headline holds at least 1.5 s', () => {
  for (const b of beats) assert.ok(b.end - HEADLINE_OUT - (b.start + HEADLINE_IN) >= 1.5, b.id);
});

test('headline size is at least 72 px', () => {
  assert.ok(HEADLINE_PX >= 72);
});

test('save beat says press twice', () => {
  assert.match(beats[4].headline, /Press\..*Press again/);
});
