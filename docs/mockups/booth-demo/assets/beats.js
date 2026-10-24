// The booth loop's beats: the one place timings and headline copy live.
// A classic script: index.html loads it before the scene, scripts/beats.test.mjs runs it in a sandbox.
// *word* marks the one accent-coloured word or phrase in a headline.
(function (root) {
  const beats = [
    { id: 'hook', start: 0, end: 4, mood: 'wave',
      headline: 'Put the phone *away.*', sub: 'Roamory films your trip for you.' },
    { id: 'setup', start: 4, end: 10, mood: 'happy',
      headline: 'Tell it about *your trip.*', sub: "Style · where · who's coming · how long" },
    { id: 'start', start: 10, end: 15, mood: 'sleepy',
      headline: 'Clip it on. *The screen goes dark.*', sub: 'It keeps filming quietly, easy on the battery.' },
    { id: 'buffer', start: 15, end: 20, mood: 'sleepy',
      headline: 'It always holds the *last 45 seconds.*', sub: 'Old footage rolls off. Nothing fills up.' },
    { id: 'save', start: 20, end: 25, mood: 'excited',
      headline: "Something happens? *Press.* Press again. It's saved.", sub: 'Volume key, shutter remote or AirPods' },
    { id: 'studio', start: 25, end: 30, mood: 'happy',
      headline: 'One highlight video, *cut by Claude* on your Mac.', sub: '' },
  ];
  root.ROAMORY_BEATS = beats;
  // Headline words are fully in by start + IN, start leaving at end - OUT; PX is the headline size.
  root.ROAMORY_HEADLINE = { IN: 1.2, OUT: 0.3, PX: 80 };
})(this);
