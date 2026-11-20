// Pretends to be the scrcpy server so the reader can be tested without a phone.
import net from 'node:net'; import { execFileSync } from 'node:child_process'; import fs from 'node:fs';
const port = +process.argv[2] || 28100; const out = '/tmp/fake.h264';
if (!fs.existsSync(out)) execFileSync('ffmpeg', ['-y','-f','lavfi','-i','testsrc=size=360x640:rate=30','-t','3','-pix_fmt','yuv420p','-c:v','libx264','-profile:v','baseline','-g','30','-f','h264',out],{stdio:'ignore'});
const data = fs.readFileSync(out);
const starts = []; for (let i=0;i+3<data.length;i++) if (data[i]===0&&data[i+1]===0&&(data[i+2]===1)) starts.push(i); // 3-byte start codes
const nals = starts.map((s,i)=>{ let e = i+1<starts.length?starts[i+1]:data.length; let b = data.subarray(s,e); while(b.length&&b[b.length-1]===0) b=b.subarray(0,b.length-1); return Buffer.concat([Buffer.from([0,0,0,1]), b.subarray(3)]); });
const type = n => n[4]&31;
let conn = 0; globalThis.controlGot = [];
net.createServer(sock => {
  const id = conn++;
  if (id % 2 === 1) { sock.on('data', d => { console.log('FAKE control got', d.length, 'bytes type', d[0]); }); return; }
  sock.write(Buffer.from([0])); const name = Buffer.alloc(64); name.write('Fake Galaxy'); sock.write(name);
  const c = Buffer.alloc(4); c.writeUInt32BE(0x68323634); sock.write(c);
  const sess = Buffer.alloc(12); sess.writeUInt32BE(0x80000000,0); sess.writeUInt32BE(360,4); sess.writeUInt32BE(640,8); sock.write(sess);
  const hdr = (flagsHi, size) => { const h = Buffer.alloc(12); h.writeUInt32BE(flagsHi,0); h.writeUInt32BE(size,8); return h; };
  const cfg = Buffer.concat(nals.filter(n=>type(n)===7||type(n)===8)); sock.write(hdr(0x40000000, cfg.length)); sock.write(cfg);
  const vcl = nals.filter(n=>type(n)===5||type(n)===1); let i=0;
  const t = setInterval(()=>{ const n = vcl[i++%vcl.length]; sock.write(hdr(type(n)===5?0x20000000:0, n.length)); sock.write(n); }, 33);
  sock.on('close',()=>clearInterval(t)); sock.on('error',()=>clearInterval(t));
}).listen(port,'127.0.0.1',()=>console.log('fake phone on',port));
