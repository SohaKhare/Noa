import test from 'node:test';
import assert from 'node:assert/strict';
import { wavFromPCM, allConsented } from './audio.mjs';

test('every human participant must consent; an added participant fails closed', () => {
  assert.equal(allConsented(['alice', 'bob'], ['alice']), false);
  assert.equal(allConsented(['alice', 'bob'], ['alice', 'bob']), true);
  assert.equal(allConsented(['alice', 'bob', 'eve'], ['alice', 'bob']), false);
  assert.equal(allConsented([], ['alice']), false);
});
test('silence is not sent to the transcriber', () => {
  assert.equal(wavFromPCM(Buffer.alloc(48000 * 4)).audible, false);
});
test('installed DAVE and Opus implementations load without a Discord connection', async () => {
  const dave = await import('@snazzah/davey');
  assert.ok(Object.keys(dave).length > 0);
  const { xchacha20poly1305 } = await import('@noble/ciphers/chacha.js');
  const cipher = xchacha20poly1305(new Uint8Array(32), new Uint8Array(24));
  const packet = new TextEncoder().encode('test audio');
  assert.deepEqual(cipher.decrypt(cipher.encrypt(packet)), packet);
  const { default: prism } = await import('prism-media');
  const decoder = new prism.opus.Decoder({ rate: 48000, channels: 2, frameSize: 960 });
  const chunks = [];
  await new Promise((resolve, reject) => {
    decoder.on('data', (chunk) => chunks.push(chunk));
    decoder.once('end', resolve); decoder.once('error', reject);
    decoder.end(Buffer.from([0xf8, 0xff, 0xfe]));
  });
  assert.ok(Buffer.concat(chunks).length > 0);
});

test('48kHz stereo becomes a valid, bounded 16kHz mono WAV', () => {
  const pcm = Buffer.alloc(48000 * 4);
  for (let n = 0; n < pcm.length; n += 2) pcm.writeInt16LE(1000, n);
  const { wav, audible } = wavFromPCM(pcm);
  assert.equal(audible, true);
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wav.toString('ascii', 8, 12), 'WAVE');
  assert.equal(wav.readUInt32LE(24), 16000);
  assert.equal(wav.readUInt16LE(22), 1);
  assert.equal(wav.length, 32044);
  assert.equal(wav.readInt16LE(44), 1000);
});
