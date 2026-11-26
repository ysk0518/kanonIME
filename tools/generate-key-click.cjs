const { writeFileSync } = require('node:fs');
const { join } = require('node:path');

// This original waveform is synthesized from scratch and uses no external audio or samples.
const sampleRate = 44100;
const durationSeconds = 0.028;
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

for (let index = 0; index < sampleCount; index++) {
  const seconds = index / sampleRate;
  const attack = Math.min(1, seconds / 0.0005);
  const envelope = attack * Math.exp(-seconds / 0.0035);
  const wave = Math.sin(2 * Math.PI * 1550 * seconds);
  wav.writeInt16LE(Math.round(22000 * envelope * wave), 44 + index * 2);
}

writeFileSync(join(__dirname, '../entry/src/main/resources/rawfile/key_click.wav'), wav);
