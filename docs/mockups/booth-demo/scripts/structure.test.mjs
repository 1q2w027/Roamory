// The HTML agrees with assets/beats.js: video length, headline windows and headline size.
// Choreography inside each beat is written in compositions/film.html; this pins the parts beats.js promises.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const page = {};
vm.runInNewContext(read('../assets/beats.js'), page);
const beats = JSON.parse(JSON.stringify(page.ROAMORY_BEATS));
const H = page.ROAMORY_HEADLINE;
const total = beats.at(-1).end;
const index = read('../index.html');
const film = read('../compositions/film.html');

// data-start / data-duration of the element with this id.
function windowOf(html, id) {
  const tag = html.match(new RegExp(`<[^>]*\\bid="${id}"[^>]*>`));
  assert.ok(tag, `#${id} not found`);
  const num = (attr) => Number(tag[0].match(new RegExp(`${attr}="([0-9.]+)"`))[1]);
  return { start: num('data-start'), duration: num('data-duration') };
}

test('the video and its scene last as long as the beats', () => {
  assert.equal(windowOf(index, 'root').duration, total);
  assert.equal(windowOf(index, 'film').duration, total);
});

test('each headline shows exactly over its beat', () => {
  for (const b of beats) assert.deepEqual(windowOf(film, 'h-' + b.id), { start: b.start, duration: b.end - b.start }, b.id);
});

test('the headline size is HEADLINE_PX', () => {
  const size = film.match(/\.headline h1 \{[^}]*font-size: (\d+)px/);
  assert.ok(size, '.headline h1 font-size not found');
  assert.equal(Number(size[1]), H.PX);
});
