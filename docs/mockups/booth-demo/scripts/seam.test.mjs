// The loop-seam check must catch a small difference where the eye looks (Roamy, the phone).
// Needs ffmpeg and a rendered roamory-how-it-works.mp4; skipped without them. Run: node --test scripts/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const here = new URL('.', import.meta.url).pathname;
const mp4 = join(here, '../roamory-how-it-works.mp4');
const seam = join(here, 'seam.sh');
const skip = !existsSync(mp4) && 'render roamory-how-it-works.mp4 first';

const dir = mkdtempSync(join(tmpdir(), 'seam-'));
const first = join(dir, 'first.png'), last = join(dir, 'last.png');
const ff = (...args) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...args]);
if (!skip) {
  ff('-i', mp4, '-frames:v', '1', first);
  ff('-sseof', '-0.5', '-i', mp4, '-update', '1', last);
}
const passes = (a, b) => spawnSync('bash', [seam, a, b]).status === 0;
const painted = (name, box) => {
  const out = join(dir, name);
  ff('-i', first, '-vf', `drawbox=${box}:t=fill`, out);
  return out;
};

test('the real first and last frames pass', { skip }, () => {
  assert.ok(passes(first, last));
});

test("Roamy's face painted out fails", { skip }, () => {
  assert.ok(!passes(first, painted('noface.png', 'x=980:y=220:w=110:h=90:color=0x3cfd8a')));
});

test('the phone boxed out fails', { skip }, () => {
  assert.ok(!passes(first, painted('nophone.png', 'x=1160:y=60:w=460:h=960:color=0x0b0b10')));
});
