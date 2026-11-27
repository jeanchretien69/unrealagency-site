// Unreal Work: every 30 s, records what the person is doing in this Chrome profile
// (site, page title, active / idle / away, activity counts, current task) and sends it to unrealagency.ai.
const API = 'https://ljhpdqttcxwgufcejfor.supabase.co/rest/v1/rpc/';
const KEY = 'sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY';
const BEAT = 30;

let act = { clicks: 0, keys: 0, scrolls: 0, switches: 0 };

async function rpc(fn, body) {
  const r = await fetch(API + fn, { method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error((j && (j.message || j.hint)) || ('HTTP ' + r.status));
  return j;
}

async function state() { return (await chrome.storage.local.get(['token', 'queue', 'task', 'lastOk', 'paused'])); }

async function activeTab() {
  try {
    const w = await chrome.windows.getLastFocused({ populate: false });
    if (!w || !w.focused) return { focused: false };
    const [t] = await chrome.tabs.query({ active: true, windowId: w.id });
    if (!t || !t.url) return { focused: true };
    const u = new URL(t.url);
    return { focused: true, domain: /^https?:$/.test(u.protocol) ? u.hostname.replace(/^www\./, '') : u.protocol.replace(':', ''), path: u.pathname.slice(0, 200), title: (t.title || '').slice(0, 200), incognito: t.incognito };
  } catch (e) { return { focused: false }; }
}

async function beat() {
  const s = await state();
  if (!s.token) return;
  const idle = await chrome.idle.queryState(60); // active | idle | locked
  const tab = await activeTab();
  let st = idle === 'locked' ? 'locked' : idle === 'idle' ? 'idle' : tab.focused ? 'chrome' : 'other';
  if (tab.incognito) { tab.domain = 'incognito'; tab.path = ''; tab.title = ''; }
  const b = {
    ts: Date.now(), sec: BEAT, state: st, idle_sec: idle === 'active' ? 0 : 60,
    domain: tab.focused ? (tab.domain || null) : null, path: tab.focused ? (tab.path || null) : null, title: tab.focused ? (tab.title || null) : null,
    clicks: act.clicks, keys: act.keys, scrolls: act.scrolls, switches: act.switches,
    labels: s.task ? { task: s.task.text.slice(0, 120), task_id: s.task.id } : null
  };
  act = { clicks: 0, keys: 0, scrolls: 0, switches: 0 };
  const queue = (s.queue || []).concat([b]).slice(-2000); // keeps ~16 h offline
  try {
    for (let i = 0; i < queue.length; i += 250) await rpc('focus_ingest', { p_token: s.token, p_beats: queue.slice(i, i + 250) });
    await chrome.storage.local.set({ queue: [], lastOk: Date.now(), err: null });
  } catch (e) {
    await chrome.storage.local.set({ queue, err: String(e.message || e) });
  }
  badge(st, s.task);
}

function badge(st, task) {
  chrome.action.setBadgeText({ text: task ? '●' : '' });
  chrome.action.setBadgeBackgroundColor({ color: st === 'chrome' ? '#16a34a' : '#f59e0b' });
}

chrome.runtime.onMessage.addListener((m, sender, reply) => {
  if (m.t === 'act') { act.clicks += m.clicks || 0; act.keys += m.keys || 0; act.scrolls += m.scrolls || 0; return; }
  if (m.t === 'beatNow') { beat().then(() => reply(true)); return true; }
});
chrome.tabs.onActivated.addListener(() => act.switches++);

function schedule() { chrome.alarms.create('beat', { periodInMinutes: 0.5 }); }
chrome.runtime.onInstalled.addListener(() => { schedule(); chrome.storage.local.get('token').then(s => { if (!s.token) chrome.tabs.create({ url: chrome.runtime.getURL('popup.html?setup=1') }); }); });
chrome.runtime.onStartup.addListener(schedule);
chrome.alarms.onAlarm.addListener(a => { if (a.name === 'beat') beat(); });
schedule();
