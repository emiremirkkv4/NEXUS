"use strict";
const $ = id => document.getElementById(id);
const titles = ["Processor", "Memory", "System disk", "Uptime", "Upload", "Download"];
const cards = titles.map(title => {
  const node = document.createElement("article");
  node.className = "card";
  node.innerHTML = "<h2></h2><strong class='value'></strong><p></p>";
  node.firstChild.textContent = title;
  $("cards").append(node);
  return node;
});
let points = [], session = 0, timer, token = "";
const size = n => (n / 2 ** 30).toFixed(1) + " GiB";
const rate = n => n == null ? "—" : (n / 1024).toFixed(1) + " KiB/s";
function readings(s) {
  const rows = s ? [
    [s.cpu_percent + "%", s.cpu_mhz == null ? "Frequency unavailable" : Math.round(s.cpu_mhz) + " MHz"],
    [s.ram_percent + "%", size(s.ram_available) + " available / " + size(s.ram_total)],
    [s.disk_percent + "%", size(s.disk_free) + " free / " + size(s.disk_total)],
    [Math.floor(s.uptime_seconds / 86400) + "d " + Math.floor(s.uptime_seconds / 3600) % 24 + "h", Math.floor(s.uptime_seconds / 60) % 60 + " min since last full hour"],
    [rate(s.upload_bps), s.sent_bytes == null ? "Counter unavailable" : size(s.sent_bytes) + " sent"],
    [rate(s.download_bps), s.received_bytes == null ? "Counter unavailable" : size(s.received_bytes) + " received"]
  ] : titles.map(() => ["—", "Awaiting telemetry"]);
  rows.forEach(([value, detail], i) => {
    cards[i].children[1].textContent = value;
    cards[i].children[2].textContent = detail;
  });
  $("host").textContent = s ? s.hostname + "  /  " + s.os : "Pair with your PC to view live telemetry.";
  $("stamp").textContent = s ? "Sampled " + new Date(s.sampled_at * 1000).toLocaleTimeString() : "Awaiting sample";
}
function draw() {
  const c = $("chart"), w = c.clientWidth, h = c.clientHeight, scale = devicePixelRatio || 1;
  c.width = w * scale; c.height = h * scale;
  const g = c.getContext("2d"); g.scale(scale, scale);
  g.font = "11px monospace";
  for (const percent of [0,25,50,75,100]) {
    const y = 9 + (100-percent) / 100 * (h-18);
    g.fillStyle = "#91a5bf"; g.fillText(percent+"%",0,y+3);
    g.strokeStyle = "#293a50"; g.beginPath(); g.moveTo(38,y); g.lineTo(w,y); g.stroke();
  }
  if (!points.length) return;
  const end = points[points.length-1].sampled_at;
  for (const [field,color] of [["cpu_percent","#60e9fe"],["ram_percent","#8199ff"]]) {
    g.strokeStyle = g.fillStyle = color; g.lineWidth = 2; g.beginPath();
    points.forEach((p,i) => {
      const x = w-2-(end-p.sampled_at)/60*(w-40), y = 9+(100-p[field])/100*(h-18);
      if (!i) g.moveTo(x,y); else g.lineTo(x,y);
      g.fillRect(x-1.5,y-1.5,3,3);
    });
    g.stroke();
  }
}
function state(label, message = "") {
  $("status").textContent = label; $("status").className = label === "Online" ? "live" : "";
  $("message").textContent = message;
}
function disconnect() {
  session++; clearTimeout(timer); token = ""; points = [];
  $("pair").hidden = false; $("disconnect").hidden = true;
  readings(null); draw(); state("Disconnected");
}
async function poll(id) {
  try {
    const r = await fetch("/api/v1/stats", {headers:{Authorization:"Bearer "+token}, redirect:"error", signal:AbortSignal.timeout(5000)});
    if (id !== session) return;
    if (r.status === 401) { disconnect(); state("Pairing failed","Copy the current token from the PC and try again."); return; }
    if (!r.ok) throw new Error(r.status === 503 ? "Waiting for fresh telemetry." : "Server returned HTTP "+r.status);
    const s = await r.json();
    if (id !== session) return;
    if (!points.length || points[points.length-1].sampled_at !== s.sampled_at) points.push(s);
    points = points.filter(p => s.sampled_at-p.sampled_at <= 60);
    readings(s); draw(); state("Online");
  } catch (e) {
    if (id !== session) return;
    points = []; readings(null); draw();
    state("Unavailable", (e.message || "PC unreachable") + " Retrying. Check Wi-Fi and the Windows server.");
  }
  timer = setTimeout(() => poll(id), 2000);
}
$("pair").onsubmit = event => {
  event.preventDefault(); token = $("token").value.trim(); $("token").value = "";
  $("pair").hidden = true; $("disconnect").hidden = false; state("Connecting"); poll(++session);
};
$("disconnect").onclick = disconnect;
new ResizeObserver(draw).observe($("chart")); disconnect();
