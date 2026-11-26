const { writeFileSync } = require('node:fs');
const { join } = require('node:path');

// This original waveform is synthesized from scratch and uses no external audio or samples.
// It imitates two walnuts knocking softly: a dry, slightly hollow "kotsu" with almost no
// low end. A very short impact excites a few inharmonic wooden resonances that die
// within milliseconds. A fixed-seed generator keeps the bundled file reproducible.
const sampleRate = 44100;
const durationSeconds = 0.04;
const sampleCount = Math.round(sampleRate * durationSeconds);
const dataSize = sampleCount * 2;
const wav = Buffer.alloc(44 + dataSize);

wav.write('RIFF', 0);
wav.writeUInt32LE(wav.length - 8, 4);
wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); // PCM header size
wav.writeUInt16LE(1, 20); // PCM
wav.writeUInt16LE(1, 22); // Mono
wav.writeUInt32LE(sampleRate, 24);
wav.writeUInt32LE(sampleRate * 2, 28);
wav.writeUInt16LE(2, 32); // Bytes per frame
wav.writeUInt16LE(16, 34);
wav.write('data', 36);
wav.writeUInt32LE(dataSize, 40);

let seed = 0x4b616e6f;
const random = () => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed / 0x100000000 * 2 - 1;
};

// [frequency Hz, decay seconds, gain]: inharmonic shell modes of a small hard nut.
const modes = [[920, 0.006, 1.0], [1480, 0.004, 0.5], [2240, 0.0026, 0.22], [3350, 0.0015, 0.1]];
const samples = new Float64Array(sampleCount);
let low = 0;
for (let index = 0; index < sampleCount; index++) {
  const seconds = index / sampleRate;
  low += 0.3 * (random() - low); // softened noise so the contact is not sharp
  let ring = 0;
  for (const [frequency, decay, gain] of modes) {
    ring += gain * Math.sin(2 * Math.PI * frequency * seconds) * Math.exp(-seconds / decay);
  }
  const impact = low * Math.exp(-seconds / 0.0006);
  const attack = Math.min(1, seconds / 0.0008);
  samples[index] = attack * (ring + 0.45 * impact);
}
// Fade the tail so the clip never ends on a non-zero sample.
const fade = Math.round(sampleRate * 0.006);
for (let index = 0; index < fade; index++) { samples[sampleCount - 1 - index] *= index / fade; }
const peak = samples.reduce((max, value) => Math.max(max, Math.abs(value)), 0);
for (let index = 0; index < sampleCount; index++) {
  wav.writeInt16LE(Math.round(15000 * samples[index] / peak), 44 + index * 2);
}

writeFileSync(join(__dirname, '../entry/src/main/resources/rawfile/key_click.wav'), wav);
