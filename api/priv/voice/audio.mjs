export function allConsented(members, consenting) {
  return members.length > 0 && members.every((id) => consenting.includes(id));
}

// Discord PCM is 48 kHz stereo. ASR receives a bounded 16 kHz mono WAV.
export function wavFromPCM(pcm) {
  const samples = Math.floor(pcm.length / 12);
  const out = Buffer.alloc(44 + samples * 2);
  out.write('RIFF', 0); out.writeUInt32LE(out.length - 8, 4); out.write('WAVEfmt ', 8);
  out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(16000, 24); out.writeUInt32LE(32000, 28);
  out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34); out.write('data', 36);
  out.writeUInt32LE(samples * 2, 40);
  let energy = 0;
  for (let n = 0; n < samples; n++) {
    let sum = 0;
    for (let j = 0; j < 6; j++) sum += pcm.readInt16LE(n * 12 + j * 2);
    const value = Math.round(sum / 6);
    out.writeInt16LE(value, 44 + n * 2); energy += value * value;
  }
  return { wav: out, audible: samples >= 1600 && Math.sqrt(energy / samples) > 50 };
}
