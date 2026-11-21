// Unreal Agency phone reader: shows the Android phones plugged in by USB in the browser (one or several) and passes touches/keys back.
// No dependencies, only Node built-ins. Video = scrcpy 5.0.1 (H.264) -> WebSocket -> WebCodecs in the page.
// Protocol checked against scrcpy v5.0.1 (Streamer.java, ControlMessageReader.java).
import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import * as RTC from './webrtc.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const env = (k, d) => process.env[k] ?? d;
const CFG = {
  HOST: env('HOST', '127.0.0.1'),
  PORT: +env('PORT', 8100),
  ADB: env('ADB', 'adb'),
  SCRCPY_SERVER: env('SCRCPY_SERVER', path.join(HERE, 'tools', 'scrcpy-server')),
  SCRCPY_VERSION: env('SCRCPY_VERSION', '5.0.1'),
  PHONE_SERIAL: env('PHONE_SERIAL', 'usb'),
  TUNNEL_PORT: +env('TUNNEL_PORT', 27199),
  MAX_SIZE: +env('MAX_SIZE', 1280),
  BIT_RATE: +env('BIT_RATE', 3000000),
  MAX_FPS: +env('MAX_FPS', 30),
  IDLE_STOP_MS: +env('IDLE_STOP_MS', 120000),
  GATE_URL: env('GATE_URL', ''),                 // empty = no gate (local tests only)
  PHONE_HOST: env('PHONE_HOST', ''),
  FRAME_ANCESTORS: env('FRAME_ANCESTORS', ''),
  FAKE_DEVICE_PORT: +env('FAKE_DEVICE_PORT', 0),  // test mode: connect to a fake phone, no adb
  PUBLIC_DIR: path.join(HERE, 'public'),
};
const log = (...a) => console.log(new Date().toISOString(), ...a);

// ---------------- access gate ----------------
const gateCache = new Map(); // pass -> { ok, until }
async function gateOk(pass) {
  if (!CFG.GATE_URL) return true;
  if (!pass || !/^[A-Za-z0-9._~-]{20,400}$/.test(pass)) return false;
  const c = gateCache.get(pass);
  if (c && c.until > Date.now()) return c.ok;
  let ok = false;
  try {
    const r = await fetch(`${CFG.GATE_URL}?host=${encodeURIComponent(CFG.PHONE_HOST)}`, {
      headers: { 'x-pass': pass }, signal: AbortSignal.timeout(8000),
    });
    ok = r.status === 200;
  } catch (e) { log('gate error', e.message); ok = false; }
  gateCache.set(pass, { ok, until: Date.now() + (ok ? 60000 : 10000) });
  if (gateCache.size > 500) for (const [k, v] of gateCache) if (v.until < Date.now()) gateCache.delete(k);
  return ok;
}
const isLocal = req => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress) && !req.headers['cf-connecting-ip'] && !req.headers['cf-ray'];
const LOCAL_ORIGINS = () => [`http://localhost:${CFG.PORT}`, `http://127.0.0.1:${CFG.PORT}`];
const SITE_ORIGINS = ['https://unrealagency.ai', 'https://www.unrealagency.ai'];
const cookieOf = req => {
  const m = /(?:^|;\s*)vb_pass=([^;]+)/.exec(req.headers.cookie || '');
  return m ? m[1] : '';
};
const SEC_HEADERS = () => {
  const h = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
  if (CFG.FRAME_ANCESTORS) h['Content-Security-Policy'] = `frame-ancestors ${CFG.FRAME_ANCESTORS}`;
  return h;
};

// ---------------- phone sessions (one shared capture per phone) ----------------
// key = the phone's adb serial ('fake' in test mode). Each phone gets its own tunnel port.
const SESSIONS = new Map();
const SERIAL_RE = /^[A-Za-z0-9._:-]{1,64}$/;
function session(key) {
  let S = SESSIONS.get(key);
  if (!S) {
    S = { key, serial: key, port: CFG.TUNNEL_PORT + SESSIONS.size, viewers: new Set(), gen: 0, sess: null, state: 'idle', name: '', w: 0, h: 0, config: null, configRaw: null, haveKey: false, lastKeyReq: 0, video: null, control: null, proc: null, idleTimer: null, retry: null, error: '' };
    SESSIONS.set(key, S);
  }
  return S;
}
// phones adb sees right now: [{ serial, state, model }]
async function listDevices() {
  if (CFG.FAKE_DEVICE_PORT) return [{ serial: 'fake', state: 'device', model: 'Test phone' }];
  const out = await sh(CFG.ADB, ['devices', '-l']).catch(() => '');
  return out.split('\n').slice(1).map(l => l.trim()).filter(Boolean).map(l => {
    const [serial, state] = l.split(/\s+/); const m = /model:(\S+)/.exec(l);
    return { serial, state: state || '', model: m ? m[1].replace(/_/g, ' ') : '' };
  }).filter(d => SERIAL_RE.test(d.serial) && !d.serial.startsWith('emulator-'));
}
// which phone a viewer asked for: ?d=<serial>, or the configured one, or the first phone found
async function pickKey(wanted) {
  if (CFG.FAKE_DEVICE_PORT) return 'fake';
  const devs = await listDevices();
  if (wanted && SERIAL_RE.test(wanted) && devs.some(d => d.serial === wanted)) return wanted;
  if (CFG.PHONE_SERIAL !== 'usb' && devs.some(d => d.serial === CFG.PHONE_SERIAL)) return CFG.PHONE_SERIAL;
  return devs.length ? devs[0].serial : (wanted && SERIAL_RE.test(wanted) ? wanted : '_none');
}

const sh = (cmd, args, t = 20000) => new Promise((res, rej) => execFile(cmd, args, { timeout: t }, (e, so, se) => e ? rej(new Error((se || e.message).trim())) : res(so)));
const adbArgs = serial => ['-s', serial];

function sendAll(S, buf) { for (const v of S.viewers) if (v.ready && v.bufferedAmount() < 4e6) v.send(buf); }
function setState(S, st, error = '') { S.state = st; S.error = error; const m = JSON.stringify({ state: st, error, name: S.name, serial: S.serial }); for (const v of S.viewers) v.sendText(m); }

async function startCapture(S) {
  if (S.state === 'starting' || S.state === 'live') return;
  clearTimeout(S.retry);
  const gen = ++S.gen; const failG = m => { if (gen === S.gen) fail(S, m); };
  setState(S, 'starting');
  try {
    let video, control;
    if (CFG.FAKE_DEVICE_PORT) {
      video = await connectFirstByte(CFG.FAKE_DEVICE_PORT, 50, () => gen !== S.gen); control = await connectRetry(CFG.FAKE_DEVICE_PORT, 20, true);
    } else {
      const a = adbArgs(S.serial);
      const devs = await sh(CFG.ADB, ['devices']);
      sh(CFG.ADB, [...a, 'shell', 'input', 'keyevent', '224']).catch(() => {});
      const line = devs.split('\n').slice(1).find(l => l.split(/\s+/)[0] === S.serial);
      if (!line) throw new Error('No phone found on USB. Plug it in, unlock it.');
      if (/unauthorized/.test(line)) throw new Error('Phone says unauthorized: on the phone tap "Always allow this computer" then Allow.');
      if (/offline/.test(line)) throw new Error('Phone is offline: unplug and replug the cable.');
      if (!fs.existsSync(CFG.SCRCPY_SERVER)) throw new Error('scrcpy-server file missing. Run the installer again.');
      await sh(CFG.ADB, [...a, 'push', CFG.SCRCPY_SERVER, '/data/local/tmp/scrcpy-server.jar']);
      const scid = (crypto.randomInt(1, 0x7fffffff)).toString(16).padStart(8, '0');
      await sh(CFG.ADB, [...a, 'forward', 'tcp:' + S.port, 'localabstract:scrcpy_' + scid]).catch(() => {});
      // keep this command short: some Samsung phones crash the video encoder if the line is over ~255 chars
      const cmd = `CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server ${CFG.SCRCPY_VERSION} scid=${scid} audio=false max_size=${CFG.MAX_SIZE} video_bit_rate=${CFG.BIT_RATE} max_fps=${CFG.MAX_FPS} tunnel_forward=true stay_awake=true clipboard_autosync=false`;
      S.proc = spawn(CFG.ADB, [...a, 'shell', cmd], { stdio: ['ignore', 'pipe', 'pipe'] });
      let out = ''; const keep = d => { out = (out + d).slice(-2000); };
      S.proc.stdout.on('data', keep); S.proc.stderr.on('data', keep);
      S.proc.on('exit', () => { if (S.state !== 'idle') { log('scrcpy server exited', out.slice(-300)); const last = out.trim().split('\n').filter(Boolean).slice(-2).join(' ').slice(0, 220); failG(out.includes('stack corruption') ? 'Phone video encoder crashed (command too long).' : 'Phone stopped sharing.' + (last ? ' (' + last + ')' : '')); } });
      video = await connectFirstByte(S.port, 100, () => gen !== S.gen);
      control = await connectRetry(S.port, 100);
      sh(CFG.ADB, [...a, 'forward', '--remove', 'tcp:' + S.port]).catch(() => {});
    }
    if (gen !== S.gen) { video.destroy(); control.destroy(); return; }
    S.video = video; S.control = control;
    control.on('error', () => {}); control.on('close', () => failG('Control link closed.'));
    video.on('error', () => {}); video.on('close', () => failG('Phone stopped sharing.'));
    readVideo(S, video, failG);
  } catch (e) { failG(e.message); }
}

function connectFirstByte(port, tries, cancelled) {
  return new Promise((resolve, reject) => {
    let n = 0;
    const attempt = () => {
      if (cancelled()) return reject(new Error('cancelled'));
      const s = net.connect(port, '127.0.0.1'); let done = false;
      const retry = () => { if (done) return; done = true; s.destroy(); if (++n >= tries) reject(new Error('The phone did not start sharing its screen. Unlock the phone and keep it plugged in.')); else setTimeout(attempt, 100); };
      s.once('error', retry); s.once('close', retry);
      s.once('data', d => { if (done) return; done = true; s.removeAllListeners(); s.setNoDelay(true); s.pause(); s.first = d; resolve(s); });
    };
    attempt();
  });
}
function connectRetry(port, tries, fake = false) {
  return new Promise((resolve, reject) => {
    let n = 0;
    const attempt = () => {
      const s = net.connect(port, '127.0.0.1');
      s.once('connect', () => { s.setNoDelay(true); resolve(s); });
      s.once('error', () => { s.destroy(); if (++n >= tries) reject(new Error('Could not reach the phone sharing app.')); else setTimeout(attempt, 100); });
    };
    attempt();
  });
}

function fail(S, msg) {
  S.gen++; // ignore later events from this dead attempt
  log(S.key, 'capture stopped:', msg);
  teardown(S);
  setState(S, 'error', msg);
  if (S.viewers.size) S.retry = setTimeout(() => { if (S.viewers.size) startCapture(S); }, 3000); // reconnect on its own
}
function teardown(S) {
  for (const k of ['video', 'control']) { try { S[k]?.destroy(); } catch {} S[k] = null; }
  try { S.proc?.kill(); } catch {} S.proc = null;
  S.config = null; S.sess = null; S.haveKey = false; S.w = 0; S.h = 0; S.state = 'idle';
}
function stopCapture(S) { clearTimeout(S.retry); S.gen++; teardown(S); setState(S, 'idle'); log(S.key, 'capture stopped (nobody watching)');
  if (!CFG.FAKE_DEVICE_PORT) sh(CFG.ADB, [...adbArgs(S.serial), 'shell', 'input', 'keyevent', '223']).then(() => log(S.key, 'phone screen off')).catch(() => {}); }

function readVideo(S, sock, fail) {
  let buf = sock.first || Buffer.alloc(0), stage = 0; sock.first = null; // 0: dummy byte, 1: device name (64), 2: codec id (4), 3: packets
  const parse = () => {
    for (;;) {
      if (stage === 0) { if (buf.length < 1) return; buf = buf.subarray(1); stage = 1; }
      else if (stage === 1) { if (buf.length < 64) return; S.name = buf.subarray(0, 64).toString('utf8').replace(/\0.*$/, ''); buf = buf.subarray(64); stage = 2; }
      else if (stage === 2) {
        if (buf.length < 4) return;
        const codec = buf.readUInt32BE(0); buf = buf.subarray(4);
        if (codec === 0 || codec === 1) return fail('The phone refused screen capture. Unlock it and try again.');
        if (codec !== 0x68323634) return fail('Unexpected video format.'); // "h264"
        stage = 3;
      } else {
        if (buf.length < 12) return;
        const hi = buf.readUInt32BE(0);
        if (hi & 0x80000000) { // session packet: flags(4) width(4) height(4)
          S.w = buf.readUInt32BE(4); S.h = buf.readUInt32BE(8); buf = buf.subarray(12);
          S.haveKey = false;
          const m = Buffer.alloc(9); m[0] = 1; m.writeUInt32BE(S.w, 1); m.writeUInt32BE(S.h, 5);
          sendAll(S, m); S.sess = m; continue;
        }
        const size = buf.readUInt32BE(8);
        if (size > 8e6) return fail('Bad video data.');
        if (buf.length < 12 + size) return;
        const flagsHi = hi, config = !!(flagsHi & 0x40000000), key = !!(flagsHi & 0x20000000);
        // pts is the low 61 bits; we only need relative time, so we stamp our own send time
        const ptsUs = Number(buf.readBigUInt64BE(0) & 0x1fffffffffffffffn);
        const data = Buffer.from(buf.subarray(12, 12 + size)); buf = buf.subarray(12 + size);
        if (config) { S.configRaw = data; S.config = Buffer.concat([Buffer.from([2]), data]); sendAll(S, S.config); }
        else {
          if (key) S.haveKey = true;
          let wsMsg = null;
          for (const v of S.viewers) {
            if (!v.ready) continue;
            if (v.rtc && v.rtc.connected) { v.rtc.frame(data, key, ptsUs, S.configRaw); if (v.rtcPlaying) continue; }
            // too far behind? drop old frames and jump to the next key frame instead of queuing them
            if (v.waitKey && !key) continue;
            if (v.bufferedAmount() > 600000) { v.waitKey = true; requestKeyFrame(S); continue; }
            if (key) v.waitKey = false;
            if (!wsMsg) { const h = Buffer.alloc(10); h[0] = 3; h[1] = key ? 1 : 0; h.writeDoubleBE(Date.now(), 2); wsMsg = Buffer.concat([h, data]); }
            v.send(wsMsg);
          }
        }
        if (S.state !== 'live') setState(S, 'live');
      }
    }
  };
  sock.on('data', d => { buf = buf.length ? Buffer.concat([buf, d]) : d; parse(); });
  parse(); sock.resume();
}

function requestKeyFrame(S) {
  const now = Date.now();
  if (now - S.lastKeyReq < 3000 || !S.control) return;
  S.lastKeyReq = now; S.control.write(Buffer.from([17])); // RESET_VIDEO
}

// ---------------- control messages from the browser ----------------
// Only exact sizes are forwarded: one malformed message would shift the whole stream.
const BLOCKED_KEYS = new Set([24, 25, 164, 91, 280, 281, 282, 283]); // volume up/down, mute, mic mute, notification swipe keys
function validControl(b) {
  if (!b.length) return false;
  const t = b[0], n = b.length;
  switch (t) {
    case 0: return n === 14 && !BLOCKED_KEYS.has(b.readInt32BE(2)); // never volume / mute
    case 1: { if (n < 5) return false; const len = b.readUInt32BE(1); return len <= 300 && n === 5 + len; }
    case 2: return n === 32;
    case 3: return n === 21;
    case 4: return n === 2;
    case 7: case 17: return n === 1;          // no notification panel (5, 6), no rotate (11)
    case 9: { if (n < 14) return false; const len = b.readUInt32BE(10); return len <= 200000 && n === 14 + len; }
    case 10: return n === 2;
    default: return false;
  }
}

// ---------------- websocket (RFC 6455, by hand) ----------------
function wsAccept(req, socket, S) {
  const key = req.headers['sec-websocket-key'];
  if (!key) return socket.destroy();
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' +
    crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64') + '\r\n\r\n');
  socket.setNoDelay(true);
  const v = {
    ready: false, closed: false,
    bufferedAmount: () => socket.writableLength,
    send(b) { frame(socket, 2, b); },
    sendText(s) { frame(socket, 1, Buffer.from(s)); },
  };
  let buf = Buffer.alloc(0), frag = [], firstOp = 2;
  socket.on('data', d => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      if (buf.length < 2) return;
      const b0 = buf[0], b1 = buf[1], fin = !!(b0 & 0x80), op = b0 & 15, masked = !!(b1 & 0x80);
      let len = b1 & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (!masked) return socket.destroy();            // browsers must mask
      if (len > 400000) return socket.destroy();
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4); const p = Buffer.from(buf.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < p.length; i++) p[i] ^= mask[i & 3];
      buf = buf.subarray(off + 4 + len);
      if (op === 8) { socket.end(); return; }
      if (op === 9) { frame(socket, 10, p); continue; }
      if (op === 0 || op === 1 || op === 2) {
        if (op !== 0) firstOp = op;
        frag.push(p); if (!fin) continue;
        const msg = Buffer.concat(frag); frag = [];
        if (firstOp === 1) { onViewerText(S, v, msg.toString()); continue; }
        onViewerMessage(S, v, msg);
      }
    }
  });
  const gone = () => { if (v.closed) return; v.closed = true; try { v.rtc?.close(); } catch {} S.viewers.delete(v); log(S.key, 'viewer left,', S.viewers.size, 'watching'); if (!S.viewers.size) { clearTimeout(S.idleTimer); S.idleTimer = setTimeout(() => { if (!S.viewers.size) stopCapture(S); }, CFG.IDLE_STOP_MS); } };
  socket.on('close', gone); socket.on('error', gone);
  clearTimeout(S.idleTimer);
  S.viewers.add(v); v.ready = true; v.waitKey = true;
  log(S.key, 'viewer joined,', S.viewers.size, 'watching');
  v.sendText(JSON.stringify({ state: S.state, error: S.error, name: S.name, serial: S.serial }));
  if (S.key === '_none') { v.sendText(JSON.stringify({ state: 'error', error: 'No phone found on USB. Plug it in, unlock it.', name: '', serial: '' })); setTimeout(() => socket.end(), 4000); }
  else if (S.state === 'live') { if (S.sess) v.send(S.sess); if (S.config) v.send(S.config); requestKeyFrame(S); }
  else startCapture(S);
  // heartbeat so the page knows the link is alive even when the screen is still (no pictures)
  const hb = setInterval(() => { if (v.closed) return clearInterval(hb); v.sendText('{"ping":1}'); }, 10000);
}
function frame(socket, op, payload) {
  if (socket.destroyed) return;
  const n = payload.length; let h;
  if (n < 126) h = Buffer.from([0x80 | op, n]);
  else if (n < 65536) { h = Buffer.alloc(4); h[0] = 0x80 | op; h[1] = 126; h.writeUInt16BE(n, 2); }
  else { h = Buffer.alloc(10); h[0] = 0x80 | op; h[1] = 127; h.writeBigUInt64BE(BigInt(n), 2); }
  socket.write(Buffer.concat([h, payload]));
}
async function onViewerText(S, v, text) {
  let m; try { m = JSON.parse(text); } catch { return; }
  if (m.webrtc === 'start' && RTC.available && !v.rtc) {
    try {
      v.rtc = new RTC.RtcViewer({ send: o => v.sendText(JSON.stringify(o)), onKeyRequest: () => requestKeyFrame(S), log });
      await v.rtc.start();
    } catch (e) { log('webrtc start failed', e.message); v.rtc = null; v.sendText('{"webrtc":"failed"}'); }
  } else if (m.webrtc === 'answer' && v.rtc && typeof m.sdp === 'string') {
    try { await v.rtc.answer(m.sdp); } catch (e) { log('webrtc answer failed', e.message); v.rtc.close(); v.rtc = null; v.sendText('{"webrtc":"failed"}'); }
  } else if (m.webrtc === 'playing' && v.rtc) { v.rtcPlaying = true; log('viewer on webrtc');
  } else if (m.webrtc === 'stop') { if (v.rtc) v.rtc.close(); v.rtc = null; v.rtcPlaying = false; v.waitKey = true; requestKeyFrame(S); }
}
function onViewerMessage(S, v, msg) {
  if (msg.length === 1 && msg[0] === 0xff) return requestKeyFrame(S);      // page asked for a key frame
  if (!S.control || S.state !== 'live') return;
  if (!validControl(msg)) return;
  S.control.write(msg);
}

// ---------------- http ----------------
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };
const noGate = new Set([]);
const deny = res => { res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', ...SEC_HEADERS() }); res.end('<!doctype html><meta name=viewport content="width=device-width"><body style="font:16px system-ui;background:#0b0b0e;color:#fff;display:grid;place-items:center;height:100vh;margin:0"><p>Open the phone from your account on unrealagency.ai</p>'); };

const server = http.createServer(async (req, res) => {
  try {
    const u = new URL(req.url, 'http://x');
    // arrive with ?vbpass=...: check it, keep it in a cookie, then show the same page without the pass in the address
    const q = u.searchParams.get('vbpass');
    if (q) {
      if (!(await gateOk(q))) return deny(res);
      u.searchParams.delete('vbpass');
      res.writeHead(303, { 'Set-Cookie': `vb_pass=${q}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=43200`, Location: u.pathname + (u.search || ''), 'Cache-Control': 'no-store', ...SEC_HEADERS() });
      return res.end();
    }
    if (u.pathname === '/health' && isLocal(req)) {
      const o = req.headers.origin, cors = SITE_ORIGINS.includes(o) ? { 'Access-Control-Allow-Origin': o, 'Access-Control-Allow-Private-Network': 'true', 'Access-Control-Allow-Methods': 'GET', 'Vary': 'Origin' } : {};
      if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...cors });
      const phones = [...SESSIONS.values()].map(S => ({ serial: S.serial, state: S.state, name: S.name, viewers: S.viewers.size, w: S.w, h: S.h, error: S.error }));
      const first = phones[0] || { state: 'idle', name: '', viewers: 0, w: 0, h: 0, error: '' };
      return res.end(JSON.stringify({ ok: true, ...first, phones }));
    }
    if (!isLocal(req) && !(await gateOk(cookieOf(req)))) return deny(res);
    if (u.pathname === '/devices') {
      const devs = await listDevices();
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...SEC_HEADERS() });
      return res.end(JSON.stringify({ devices: devs.map(d => ({ ...d, live: (SESSIONS.get(d.serial) || {}).state === 'live' })) }));
    }
    let p = u.pathname === '/' ? '/index.html' : decodeURIComponent(u.pathname);
    const f = path.normalize(path.join(CFG.PUBLIC_DIR, p));
    if (!f.startsWith(CFG.PUBLIC_DIR + path.sep) || !fs.existsSync(f) || !fs.statSync(f).isFile()) { res.writeHead(404, SEC_HEADERS()); return res.end('Not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store', ...SEC_HEADERS() });
    fs.createReadStream(f).pipe(res);
  } catch (e) { res.writeHead(500); res.end('error'); }
});
server.on('upgrade', async (req, socket) => {
  try {
    const wu = new URL(req.url, 'http://x');
    if (wu.pathname !== '/ws') return socket.destroy();
    const pick = async () => session(await pickKey(wu.searchParams.get('d') || ''));
    const origin = req.headers.origin;
    if (isLocal(req)) { if (!LOCAL_ORIGINS().includes(origin)) { socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return socket.destroy(); } return wsAccept(req, socket, await pick()); }
    if (!(await gateOk(cookieOf(req)))) { socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return socket.destroy(); }
    if (origin && CFG.PHONE_HOST && new URL(origin).host !== CFG.PHONE_HOST) { socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return socket.destroy(); }
    wsAccept(req, socket, await pick());
  } catch { socket.destroy(); }
});
server.listen(CFG.PORT, CFG.HOST, () => log(`phone reader on http://${CFG.HOST}:${CFG.PORT}`, RTC.available ? '(webrtc on)' : '(webrtc off)', CFG.GATE_URL ? '(gate on)' : '(NO GATE: local test only)', CFG.FAKE_DEVICE_PORT ? '(fake phone)' : ''));
const shutdown = () => { for (const S of SESSIONS.values()) teardown(S); process.exit(0); };
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
