const API = 'https://ljhpdqttcxwgufcejfor.supabase.co/rest/v1/rpc/';
const KEY = 'sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY';
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
if (new URLSearchParams(location.search).get('setup')) document.body.classList.add('page');

async function rpc(fn, body) {
  const r = await fetch(API + fn, { method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error((j && (j.message || j.hint)) || ('HTTP ' + r.status));
  return j;
}
const hm = m => { m = Math.round(Number(m) || 0); return m >= 60 ? `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}` : `${m} min`; };
const ago = ts => { const s = Math.max(0, (Date.now() - new Date(ts)) / 1000); return s < 3600 ? `${Math.floor(s / 60)} min` : `${Math.floor(s / 3600)}h ${String(Math.floor(s % 3600 / 60)).padStart(2, '0')}`; };

function setup(err) {
  $('#dot').className = 'dot';
  $('#m').innerHTML = `<p><b>Welcome!</b> Paste the setup code Gael gave you.</p>
    <input id="code" placeholder="setup code" autocomplete="off">
    <button id="go">Start tracking</button>${err ? `<div class="msg">${esc(err)}</div>` : ''}
    <p class="mut" style="margin-top:12px">This only tracks this Chrome profile: which site is open, how long, and activity counts (never what you type or your passwords).</p>`;
  $('#go').onclick = async () => {
    const token = $('#code').value.trim();
    if (!token) return;
    try { await rpc('tracker_tasks', { p_token: token }); } catch (e) { return setup('That code does not work. Ask Gael for a new one.'); }
    await chrome.storage.local.set({ token, task: null, queue: [] });
    chrome.runtime.sendMessage({ t: 'beatNow' });
    render();
  };
}

async function render() {
  const s = await chrome.storage.local.get(['token', 'task', 'lastOk', 'err']);
  if (!s.token) return setup();
  const ok = s.lastOk && Date.now() - s.lastOk < 120000;
  $('#dot').className = 'dot ' + (ok ? 'on' : s.err ? 'err' : '');
  $('#dot').title = ok ? 'Tracking' : (s.err || 'Waiting for first sync');
  let data, quick;
  try { [data, quick] = await Promise.all([rpc('tracker_tasks', { p_token: s.token }), rpc('focus_quick', { p_token: s.token }).catch(() => ({}))]); }
  catch (e) { if (/bad token/i.test(e.message)) { await chrome.storage.local.remove('token'); return setup('Your code was turned off. Ask Gael for a new one.'); } $('#m').innerHTML = `<div class="msg">Can't reach the server: ${esc(e.message)}</div>`; return; }
  const cur = data.current;
  // keep the local "current task" in sync with the server
  await chrome.storage.local.set({ task: cur ? { id: cur.task_id, text: cur.text } : null });
  const secs = [...new Set(data.tasks.map(t => t.section))];
  $('#m').innerHTML = `
    <div class="stat"><div><b>${hm(quick.active)}</b><span>active today</span></div><div><b>${hm(quick.total)}</b><span>tracked today</span></div></div>
    ${cur ? `<div class="cur"><small>Working on · ${ago(cur.since)}</small><div class="t">${esc(cur.text)}</div>
      <div class="row"><button class="dark" data-a="done" data-id="${cur.task_id}">✓ Done</button><button class="ghost" data-a="stop" data-id="${cur.task_id}">Pause</button></div></div>`
      : `<p class="mut" style="margin:0 0 6px">Press <b>Start</b> on the task you are doing.</p>`}
    ${secs.map(sec => `<div class="sec">${esc(sec)}</div>` + data.tasks.filter(t => t.section === sec).map(t => `
      <div class="task ${t.done ? 'done' : ''}"><div class="t">${t.done ? '✓ ' : ''}${esc(t.text)}</div>${t.hint ? `<div class="h">${esc(t.hint)}</div>` : ''}
        <div class="row">${t.done ? `<button class="ghost" data-a="undo" data-id="${t.id}">Undo</button>`
          : cur && cur.task_id === t.id ? '' : `<button data-a="start" data-id="${t.id}">▶ Start</button><button class="ghost" data-a="done" data-id="${t.id}">✓ Done</button>`}</div></div>`).join('')).join('') || '<p class="mut">No tasks yet.</p>'}
    <p class="mut" style="margin-top:10px">Tasks come from unrealagency.ai · tracking ${ok ? 'on ✓' : 'starting…'}</p>`;
  document.querySelectorAll('[data-a]').forEach(b => b.onclick = async () => {
    b.disabled = true;
    try { await rpc('tracker_task', { p_token: s.token, p_task: b.dataset.id, p_action: b.dataset.a }); } catch (e) { alert(e.message); }
    chrome.runtime.sendMessage({ t: 'beatNow' });
    render();
  });
}
render();
