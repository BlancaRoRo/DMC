const logEl = document.getElementById("log");
const inmcvEl = document.getElementById("inmcv");
const btnCompile = document.getElementById("btn-compile");
const btnRun = document.getElementById("btn-run");
const btnResetPreset = document.getElementById("btn-reset-preset");
const binaryStatusEl = document.getElementById("binary-status");
const runsListEl = document.getElementById("runs-list");
const resultsPanel = document.getElementById("panel-results");
const resultsRunIdEl = document.getElementById("results-run-id");

function logLine(text) {
  logEl.textContent += text + "\n";
  logEl.scrollTop = logEl.scrollHeight;
}

async function streamSSE(url, options, handlers) {
  const resp = await fetch(url, options);
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf("\n\n")) !== -1) {
      const chunk = buf.slice(0, idx);
      buf = buf.slice(idx + 2);
      const eventMatch = chunk.match(/^event: (.+)$/m);
      const dataMatch = chunk.match(/^data: (.+)$/m);
      if (!dataMatch) continue;
      const event = eventMatch ? eventMatch[1] : "message";
      const data = JSON.parse(dataMatch[1]);
      if (handlers[event]) handlers[event](data);
    }
  }
}

async function refreshBinaryStatus() {
  const r = await fetch("/api/binary-status");
  const j = await r.json();
  if (j.exists) {
    binaryStatusEl.textContent = "binario compilado (" + j.path + ")";
    binaryStatusEl.className = "status ok";
  } else {
    binaryStatusEl.textContent = "binario no compilado todavia";
    binaryStatusEl.className = "status err";
  }
}

async function loadDefaultPreset() {
  const r = await fetch("/api/default-inmcv");
  const j = await r.json();
  inmcvEl.value = j.content;
}

async function refreshRunsList() {
  const r = await fetch("/api/runs");
  const j = await r.json();
  runsListEl.innerHTML = "";
  for (const runId of j.runs) {
    const li = document.createElement("li");
    const span = document.createElement("span");
    span.textContent = runId;
    const btn = document.createElement("button");
    btn.textContent = "ver resultados";
    btn.onclick = () => loadResults(runId);
    li.appendChild(span);
    li.appendChild(btn);
    runsListEl.appendChild(li);
  }
}

btnResetPreset.onclick = loadDefaultPreset;

btnCompile.onclick = async () => {
  btnCompile.disabled = true;
  btnRun.disabled = true;
  logLine("=== compilando ===");
  await streamSSE(
    "/api/compile",
    { method: "POST" },
    {
      log: (d) => logLine(d.line),
      done: (d) => {
        logLine("=== compilacion terminada (codigo " + d.returncode + ") ===");
        btnCompile.disabled = false;
        btnRun.disabled = false;
        refreshBinaryStatus();
      },
    }
  );
};

btnRun.onclick = async () => {
  btnCompile.disabled = true;
  btnRun.disabled = true;
  logLine("=== ejecutando ===");
  let runId = null;
  await streamSSE(
    "/api/run",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ inmcv: inmcvEl.value }),
    },
    {
      log: (d) => logLine(d.line),
      started: (d) => {
        runId = d.run_id;
      },
      done: (d) => {
        logLine("=== ejecucion terminada (codigo " + d.returncode + ") ===");
        btnCompile.disabled = false;
        btnRun.disabled = false;
        refreshRunsList();
        if (d.returncode === 0 && runId) loadResults(runId);
      },
    }
  );
};

function plotlyDarkLayout(extra) {
  return Object.assign(
    {
      paper_bgcolor: "#161923",
      plot_bgcolor: "#0c0e13",
      font: { color: "#e4e7ee", size: 11 },
      margin: { l: 40, r: 10, t: 30, b: 35 },
    },
    extra || {}
  );
}

async function loadResults(runId) {
  resultsPanel.hidden = false;
  resultsRunIdEl.textContent = "(" + runId + ")";
  resultsPanel.scrollIntoView({ behavior: "smooth" });

  const [histResp, confResp] = await Promise.all([
    fetch(`/api/runs/${runId}/histograms`),
    fetch(`/api/runs/${runId}/final-config`),
  ]);
  const hist = await histResp.json();
  const conf = await confResp.json();

  renderWalkers(conf);
  renderRadial(hist.radial || {});
  renderAngular(hist.angular || {});
}

function renderWalkers(conf) {
  const el = document.getElementById("plot-walkers");
  if (conf.error) {
    el.textContent = conf.error;
    return;
  }
  const xs = [], ys = [], zs = [];
  for (const walker of conf.walkers) {
    for (const [x, y, z] of walker) {
      xs.push(x); ys.push(y); zs.push(z);
    }
  }
  const trace = {
    type: "scatter3d",
    mode: "markers",
    x: xs, y: ys, z: zs,
    marker: { size: 1.6, color: "#5b8cff", opacity: 0.35 },
  };
  Plotly.newPlot(
    el,
    [trace],
    plotlyDarkLayout({
      scene: {
        xaxis: { color: "#8891a5" },
        yaxis: { color: "#8891a5" },
        zaxis: { color: "#8891a5" },
        bgcolor: "#0c0e13",
      },
      title: `${conf.nwalkers} walkers x ${conf.natom} puntos`,
    }),
    { responsive: true }
  );
}

function renderRadial(radial) {
  const container = document.getElementById("plots-radial");
  container.innerHTML = "";
  for (const key of Object.keys(radial)) {
    const h = radial[key];
    const div = document.createElement("div");
    div.className = "plot";
    container.appendChild(div);
    Plotly.newPlot(
      div,
      [{ type: "scatter", mode: "lines", x: h.x, y: h.y, line: { color: "#5b8cff" } }],
      plotlyDarkLayout({ title: h.label }),
      { responsive: true }
    );
  }
}

function renderAngular(angular) {
  const container = document.getElementById("plots-angular");
  container.innerHTML = "";
  for (const key of Object.keys(angular)) {
    const h = angular[key];
    const div = document.createElement("div");
    div.className = "plot";
    container.appendChild(div);
    Plotly.newPlot(
      div,
      [
        {
          type: "scatter",
          mode: "markers",
          x: h.x,
          y: h.y,
          marker: {
            size: 4,
            color: h.z,
            colorscale: "Viridis",
          },
        },
      ],
      plotlyDarkLayout({ title: h.label }),
      { responsive: true }
    );
  }
}

refreshBinaryStatus();
loadDefaultPreset();
refreshRunsList();
