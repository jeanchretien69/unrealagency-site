// Optional WebRTC video path (UDP: a late frame is dropped instead of freezing the stream).
// Uses the "werift" library if it is installed next to the reader; if not, the reader keeps using the WebSocket only.
// Signaling (offer/answer) goes through the existing WebSocket. Touch/keys still go through the WebSocket.
let W = null;
try { W = await import('werift'); } catch { W = null; }
export const available = !!W;

const MTU = 1150;
const splitNals = buf => { // Annex-B -> array of NAL units (no start codes)
  const out = []; let i = 0, start = -1;
  while (i + 3 <= buf.length) {
    if (buf[i] === 0 && buf[i + 1] === 0 && (buf[i + 2] === 1 || (buf[i + 2] === 0 && buf[i + 3] === 1))) {
      if (start >= 0) out.push(buf.subarray(start, i));
      i += buf[i + 2] === 1 ? 3 : 4; start = i;
    } else i++;
  }
  if (start >= 0 && start < buf.length) out.push(buf.subarray(start));
  return out.map(n => { let e = n.length; while (e > 0 && n[e - 1] === 0) e--; return n.subarray(0, e); }).filter(n => n.length);
};

export class RtcViewer {
  constructor({ send, onKeyRequest, log }) {
    this.send = send; this.onKeyRequest = onKeyRequest; this.log = log;
    this.connected = false; this.waitKey = true; this.seq = Math.floor(Math.random() * 65535); this.closed = false;
    const codec = new W.RTCRtpCodecParameters({
      mimeType: 'video/H264', clockRate: 90000,
      rtcpFeedback: [{ type: 'nack' }, { type: 'nack', parameter: 'pli' }],
      parameters: 'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f',
    });
    this.pc = new W.RTCPeerConnection({ codecs: { video: [codec], audio: [] }, iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }, { urls: 'stun:stun.l.google.com:19302' }] });
    this.track = new W.MediaStreamTrack({ kind: 'video' });
    const tr = this.pc.addTransceiver(this.track, { direction: 'sendonly' });
    tr.sender.onPictureLossIndication.subscribe(() => { this.waitKey = true; this.onKeyRequest(); });
    this.pc.connectionStateChange.subscribe(st => {
      this.log('webrtc', st);
      if (st === 'connected') { this.connected = true; this.waitKey = true; this.onKeyRequest(); this.send({ webrtc: 'connected' }); }
      if (st === 'failed' || st === 'closed' || st === 'disconnected') { this.connected = false; if (st !== 'disconnected') this.send({ webrtc: 'failed' }); }
    });
  }
  async start() {
    await this.pc.setLocalDescription(await this.pc.createOffer());
    // wait (max 1.5 s) so the offer carries the candidates
    const t0 = Date.now();
    while (this.pc.iceGatheringState !== 'complete' && Date.now() - t0 < 1500) await new Promise(r => setTimeout(r, 50));
    this.send({ webrtc: 'offer', sdp: this.pc.localDescription.sdp });
  }
  async answer(sdp) { await this.pc.setRemoteDescription({ type: 'answer', sdp }); }
  // one access unit from scrcpy (Annex-B), config = SPS/PPS Annex-B or null
  frame(data, key, ptsUs, config) {
    if (!this.connected || this.closed) return;
    if (this.waitKey && !key) return;
    if (key) this.waitKey = false;
    const ts = Number((BigInt(Math.round(ptsUs)) * 9n / 100n) & 0xffffffffn);
    const nals = (key && config ? splitNals(config) : []).concat(splitNals(data));
    nals.forEach((nal, idx) => {
      const last = idx === nals.length - 1;
      if (nal.length <= MTU) return this.rtp(nal, ts, last);
      const hdr = nal[0], fuInd = (hdr & 0xe0) | 28, type = hdr & 0x1f;
      for (let off = 1; off < nal.length; off += MTU) {
        const end = Math.min(off + MTU, nal.length);
        const fuHdr = (off === 1 ? 0x80 : 0) | (end === nal.length ? 0x40 : 0) | type;
        this.rtp(Buffer.concat([Buffer.from([fuInd, fuHdr]), nal.subarray(off, end)]), ts, last && end === nal.length);
      }
    });
  }
  rtp(payload, ts, marker) {
    const p = new W.RtpPacket(new W.RtpHeader({ payloadType: 96, sequenceNumber: this.seq = (this.seq + 1) & 0xffff, timestamp: ts, marker, ssrc: 1 }), payload);
    try { this.track.writeRtp(p); } catch {}
  }
  close() { this.closed = true; try { this.pc.close(); } catch {} }
}
