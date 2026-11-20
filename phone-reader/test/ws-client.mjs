// Tiny test client: connects to the reader like the browser does, counts video packets, sends a tap.
import http from 'node:http'; import crypto from 'node:crypto';
const [host, port, cookie] = [process.argv[2]||'127.0.0.1', +process.argv[3]||8100, process.argv[4]||''];
const key = crypto.randomBytes(16).toString('base64');
const req = http.request({host, port, path:'/ws', headers:{Connection:'Upgrade',Upgrade:'websocket','Sec-WebSocket-Key':key,'Sec-WebSocket-Version':'13', ...(cookie?{Cookie:'vb_pass='+cookie}:{})}});
req.on('response', r => { console.log('HTTP', r.statusCode); process.exit(r.statusCode===101?0:3); });
req.on('upgrade', (res, sock) => {
  console.log('upgrade OK'); let buf = Buffer.alloc(0); const seen = {1:0,2:0,3:0,key:0,text:[]};
  const mask = p => { const m = crypto.randomBytes(4); const o = Buffer.from(p); for(let i=0;i<o.length;i++) o[i]^=m[i&3]; const h = Buffer.from([0x82, 0x80|o.length]); return Buffer.concat([h,m,o]); };
  sock.on('data', d => { buf = Buffer.concat([buf,d]); for(;;){ if(buf.length<2) return; let len=buf[1]&127, off=2; if(len===126){ if(buf.length<4) return; len=buf.readUInt16BE(2); off=4;} else if(len===127){ if(buf.length<10) return; len=Number(buf.readBigUInt64BE(2)); off=10;} if(buf.length<off+len) return; const op=buf[0]&15, p=buf.subarray(off,off+len); buf=buf.subarray(off+len); if(op===2){ seen[p[0]]++; if(p[0]===3&&p[1]===1) seen.key++; } else if(op===1) seen.text.push(p.toString()); } });
  setTimeout(()=>{ // a valid tap (32 bytes) and a bad one (31 bytes)
    const good = Buffer.alloc(32); good[0]=2; sock.write(mask(good)); const bad = Buffer.alloc(31); bad[0]=2; sock.write(mask(bad)); const evil = Buffer.from([99,1,2]); sock.write(mask(evil)); }, 1500);
  setTimeout(()=>{ console.log('RESULT', JSON.stringify(seen)); process.exit(0); }, 3500);
});
req.end();
