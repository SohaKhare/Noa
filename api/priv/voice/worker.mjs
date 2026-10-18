import { Client, GatewayIntentBits } from 'discord.js';
import { joinVoiceChannel, entersState, VoiceConnectionStatus, EndBehaviorType } from '@discordjs/voice';
import prism from 'prism-media';
import readline from 'node:readline';
import { allConsented, wavFromPCM } from './audio.mjs';

const emit = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates, GatewayIntentBits.GuildMembers] });
const sessions = new Map();
const CHUNK = 48000 * 2 * 2 * 5;
let ready = false;
client.once('clientReady', () => { ready = true; emit({ type: 'ready' }); });
client.on('error', () => emit({ type: 'worker_error', code: 'gateway_failed' }));

function members(channel) {
  return [...channel.members.values()].filter((m) => !m.user.bot).map((m) => ({ id: m.id, name: m.displayName.slice(0, 100) }));
}
function flush(session, userId) {
  const stream = session.streams.get(userId);
  if (!stream?.bytes) return;
  const pcm = Buffer.concat(stream.buffers, stream.bytes);
  stream.buffers = []; stream.bytes = 0;
  const { wav, audible } = wavFromPCM(pcm);
  if (audible) emit({ type: 'audio', meeting_id: session.id, speaker_id: userId,
    start_ms: stream.start, end_ms: Math.min(3600000, Date.now() - session.started), wav: wav.toString('base64') });
  pcm.fill(0);
}
function stop(id, reason = 'requested') {
  const s = sessions.get(id);
  if (!s) return;
  sessions.delete(id); clearTimeout(s.timer);
  for (const [userId, stream] of s.streams) {
    stream.decoder.removeAllListeners('data'); stream.decoder.removeAllListeners('end');
    flush(s, userId); stream.input.destroy(); stream.decoder.destroy();
  }
  s.connection.destroy();
  emit({ type: 'stopped', meeting_id: id, reason });
}
client.on('voiceStateUpdate', (_old, state) => {
  for (const s of sessions.values()) {
    if (state.guild.id !== s.guild) continue;
    if (state.id === client.user.id && state.channelId !== s.channel) { stop(s.id, 'bot_disconnected'); continue; }
    if (state.channelId === s.channel && !state.member?.user.bot && !s.consenting.includes(state.id)) stop(s.id, 'participant_changed');
  }
});

async function run(message) {
  if (!ready) throw new Error('voice_not_ready');
  if (message.op === 'stop') { stop(message.meeting_id); return {}; }
  const guild = client.guilds.cache.get(message.guild_id);
  if (!guild) throw new Error('server_unavailable');
  if (message.op === 'members') {
    const member = await guild.members.fetch(message.user_id);
    const channel = member.voice.channel;
    if (!channel || channel.type !== 2) throw new Error('join_voice_first');
    return { voice_channel_id: channel.id, participants: members(channel) };
  }
  if (message.op !== 'join') throw new Error('invalid_operation');
  if (sessions.size >= 1) throw new Error('voice_busy');
  const channel = guild.channels.cache.get(message.voice_channel_id);
  if (!channel || channel.type !== 2) throw new Error('voice_channel_unavailable');
  const current = members(channel);
  if (!allConsented(current.map((m) => m.id), message.consenting_ids)) throw new Error('participant_changed');
  const connection = joinVoiceChannel({ guildId: guild.id, channelId: channel.id, adapterCreator: guild.voiceAdapterCreator, selfDeaf: false, selfMute: true, daveEncryption: true });
  try { await entersState(connection, VoiceConnectionStatus.Ready, 30000); }
  catch { connection.destroy(); throw new Error('voice_connection_failed'); }
  // Joining itself takes time: verify membership again before subscribing to any audio.
  const afterJoin = members(channel);
  if (!allConsented(afterJoin.map((m) => m.id), message.consenting_ids)) { connection.destroy(); throw new Error('participant_changed'); }
  const s = { id: message.meeting_id, guild: guild.id, channel: channel.id, connection,
    consenting: message.consenting_ids, streams: new Map(), started: Date.now() };
  sessions.set(s.id, s);
  s.timer = setTimeout(() => stop(s.id, 'duration_limit'), 30 * 60000);
  connection.on('error', () => stop(s.id, 'voice_connection_failed'));
  connection.on(VoiceConnectionStatus.Disconnected, () => stop(s.id, 'voice_disconnected'));
  connection.receiver.speaking.on('start', (userId) => {
    if (!sessions.has(s.id)) return;
    if (!s.consenting.includes(userId)) { stop(s.id, 'participant_changed'); return; }
    if (s.streams.has(userId)) return;
    const input = connection.receiver.subscribe(userId, { end: { behavior: EndBehaviorType.AfterSilence, duration: 800 } });
    const decoder = new prism.opus.Decoder({ rate: 48000, channels: 2, frameSize: 960 });
    const stream = { input, decoder, buffers: [], bytes: 0, start: Date.now() - s.started };
    s.streams.set(userId, stream);
    decoder.on('data', (pcm) => {
      if (!sessions.has(s.id)) return;
      if (stream.bytes === 0) stream.start = Date.now() - s.started;
      stream.buffers.push(pcm); stream.bytes += pcm.length;
      if (stream.bytes >= CHUNK) flush(s, userId);
    });
    decoder.on('end', () => { if (sessions.has(s.id)) flush(s, userId); s.streams.delete(userId); });
    input.on('error', () => stop(s.id, 'audio_decode_failed'));
    decoder.on('error', () => stop(s.id, 'audio_decode_failed'));
    input.pipe(decoder);
  });
  return { recording: true };
}

const allowedErrors = new Set(['voice_not_ready', 'server_unavailable', 'join_voice_first', 'voice_busy', 'participant_changed', 'voice_channel_unavailable', 'voice_connection_failed']);
client.login(process.env.DISCORD_VOICE_BOT_TOKEN || process.env.DISCORD_BOT_TOKEN)
  .catch(() => emit({ type: 'worker_error', code: 'gateway_login_failed' }));
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
  if (line.length > 20000) continue;
  let message;
  try { message = JSON.parse(line); const data = await run(message); emit({ id: message.id, ok: true, data }); }
  catch (error) { emit({ id: message?.id, ok: false, error: allowedErrors.has(error.message) ? error.message : 'voice_worker_failed' }); }
}
for (const id of [...sessions.keys()]) stop(id, 'shutdown');
client.destroy();

function shutdown() { for (const id of [...sessions.keys()]) stop(id, 'shutdown'); client.destroy(); process.exit(0); }
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
