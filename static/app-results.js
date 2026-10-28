const resultsRunIdEl = document.getElementById("results-run-id");
const runSelectorEl = document.getElementById("run-selector");
const walkerSelectEl = document.getElementById("walker-select");
const noRunMsgEl = document.getElementById("no-run-msg");
const resultsTabsWrapEl = document.getElementById("results-tabs-wrap");
const estadoRunEl = document.getElementById("estado-run");
const tabButtons = document.querySelectorAll(".tab-btn");
const tabContents = document.querySelectorAll(".tab-content");

// sin ejecucion cargada todavia -- se ocultan las pestanas (NUBE,
// ANGULARES, RADIALES, NUMERICOS) y se muestra el letrero en su lugar,
// en vez de dejarlas visibles y vacias.
function mostrarSinResultados() {
  resultsTabsWrapEl.hidden = true;
  noRunMsgEl.hidden = false;
  resultsRunIdEl.textContent = "";
}

function mostrarResultados() {
  noRunMsgEl.hidden = true;
  resultsTabsWrapEl.hidden = false;
}

let currentConf = null;
let currentHist = null;
let currentRunId = null;

// pestanas ya dibujadas -- 'nube' se dibuja al cargar la corrida (ya
// esta visible desde el principio). angulares/radiales se dibujan la
// PRIMERA vez que se abren, con su contenedor ya visible de verdad --
// crear un plot de Plotly mientras su caja esta en display:none le da
// un tamano incorrecto que luego no siempre se recalcula bien.
const pestanasDibujadas = new Set();

for (const btn of tabButtons) {
  btn.onclick = () => {
    for (const b of tabButtons) b.classList.remove("active");
    for (const c of tabContents) c.classList.remove("active");
    btn.classList.add("active");
    document.getElementById(btn.dataset.tab).classList.add("active");
    dibujarPestanaSiHaceFalta(btn.dataset.tab);
  };
}

function dibujarPestanaSiHaceFalta(tab) {
  if (pestanasDibujadas.has(tab)) {
    // ya dibujada antes -- solo hace falta que Plotly recalcule tamano
    // por si el contenedor cambio de tamano mientras estaba oculta.
    window.dispatchEvent(new Event("resize"));
    return;
  }
  if (tab === "tab-angulares" && currentHist) {
    renderAngular(currentHist.angular || {});
    pestanasDibujadas.add(tab);
  } else if (tab === "tab-radiales" && currentHist) {
    renderRadial(currentHist.radial || {});
    pestanasDibujadas.add(tab);
  } else if (tab === "tab-numericos" && currentRunId) {
    loadNumericos(currentRunId);
    pestanasDibujadas.add(tab);
  }
}

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

async function refreshRunSelector(selected) {
  const r = await fetch("/api/runs");
  const j = await r.json();
  runSelectorEl.innerHTML = '<option value="">(elige una ejecución)</option>';
  for (const run of j.runs) {
    const opt = document.createElement("option");
    opt.value = run.run_id;
    opt.textContent = run.nombre;
    if (run.run_id === selected) opt.selected = true;
    runSelectorEl.appendChild(opt);
  }
}

runSelectorEl.onchange = () => {
  const runId = runSelectorEl.value;
  if (!runId) return;
  const url = new URL(window.location);
  url.searchParams.set("run", runId);
  window.history.replaceState({}, "", url);
  loadResults(runId);
};

// aviso sobre el estado de la ejecucion cuyos resultados se ven: si no
// termino bien, lo que se muestre puede estar incompleto o no existir.
function mostrarEstadoRun(h, error) {
  let msg = null;
  let esError = false;
  if (error) {
    msg = "No se pudieron cargar los resultados: " + error;
    esError = true;
  } else if (h && h.estado === "corriendo") {
    msg = "Esta ejecución sigue en curso: los resultados pueden estar incompletos.";
  } else if (h && h.estado === "detenida") {
    msg = "Esta ejecución se detuvo antes de terminar: no hay resultados finales.";
    esError = true;
  } else if (h && h.estado === "terminada" && h.returncode !== 0) {
    msg = "Esta ejecución terminó con error (código " + h.returncode + ").";
    esError = true;
  }
  estadoRunEl.textContent = msg || "";
  estadoRunEl.classList.toggle("error", esError);
  estadoRunEl.hidden = !msg;
}

async function loadResults(runId) {
  mostrarResultados();
  const opcionElegida = runSelectorEl.querySelector(`option[value="${runId}"]`);
  resultsRunIdEl.textContent = "(" + (opcionElegida ? opcionElegida.textContent : runId) + ")";
  currentRunId = runId;

  try {
    const [histResp, confResp] = await Promise.all([
      fetch(`/api/runs/${runId}/histograms`),
      fetch(`/api/runs/${runId}/final-config`),
    ]);
    currentHist = await histResp.json();
    currentConf = await confResp.json();
  } catch (e) {
    currentHist = null;
    currentConf = null;
    mostrarEstadoRun(null, String(e));
    return;
  }
  mostrarEstadoRun(currentHist, currentHist && currentHist.error);

  pestanasDibujadas.clear();
  fillWalkerSelect(currentConf);
  renderWalkers(currentConf, "all");
  pestanasDibujadas.add("tab-nube");

  // si ya hay una pestana angular/radial activa (p.ej. al recargar con
  // ?run=... estando ya en esa pestana), dibujarla ahora tambien.
  const activa = document.querySelector(".tab-btn.active");
  if (activa && activa.dataset.tab !== "tab-nube") {
    dibujarPestanaSiHaceFalta(activa.dataset.tab);
  }
}

function fillWalkerSelect(conf) {
  walkerSelectEl.innerHTML = '<option value="all">todos (nube)</option>';
  if (conf.error) return;
  for (let i = 0; i < conf.nwalkers; i++) {
    const opt = document.createElement("option");
    opt.value = String(i);
    opt.textContent = "walker #" + i;
    walkerSelectEl.appendChild(opt);
  }
}

walkerSelectEl.onchange = () => {
  if (currentConf) renderWalkers(currentConf, walkerSelectEl.value);
};

function splitByAtomType(atoms, nhe4, nhe3) {
  return {
    he4: atoms.slice(0, nhe4),
    he3: atoms.slice(nhe4, nhe4 + nhe3),
    impureza: atoms.slice(nhe4 + nhe3),
  };
}

function renderWalkers(conf, selection) {
  const el = document.getElementById("plot-walkers");
  if (conf.error) {
    el.textContent = conf.error;
    return;
  }

  const nhe4 = conf.nhe4 || conf.natom;
  const nhe3 = conf.nhe3 || 0;

  let traces;
  let title;

  if (selection === "all") {
    const xs = [], ys = [], zs = [];
    for (const walker of conf.walkers) {
      for (const [x, y, z] of walker) {
        xs.push(x); ys.push(y); zs.push(z);
      }
    }
    traces = [{
      type: "scatter3d",
      mode: "markers",
      name: "todos los walkers",
      x: xs, y: ys, z: zs,
      marker: { size: 1.4, color: "#5b8cff", opacity: 0.25 },
    }];
    title = `${conf.nwalkers} walkers x ${conf.natom} átomos (nube completa)`;
  } else {
    const idx = parseInt(selection, 10);
    const atoms = conf.walkers[idx];
    const { he4, he3, impureza } = splitByAtomType(atoms, nhe4, nhe3);
    traces = [];
    if (he4.length) {
      traces.push({
        type: "scatter3d", mode: "markers", name: "He4",
        x: he4.map((a) => a[0]), y: he4.map((a) => a[1]), z: he4.map((a) => a[2]),
        marker: { size: 5, color: "#5b8cff" },
      });
    }
    if (he3.length) {
      traces.push({
        type: "scatter3d", mode: "markers", name: "He3",
        x: he3.map((a) => a[0]), y: he3.map((a) => a[1]), z: he3.map((a) => a[2]),
        marker: { size: 5, color: "#4caf7d" },
      });
    }
    if (impureza.length) {
      traces.push({
        type: "scatter3d", mode: "markers+lines", name: "impureza",
        x: impureza.map((a) => a[0]), y: impureza.map((a) => a[1]), z: impureza.map((a) => a[2]),
        marker: { size: 8, color: "#e0616b" },
        line: { color: "#e0616b", width: 3 },
      });
    }
    title = `walker #${idx} -- ${nhe4} He4, ${nhe3} He3, ${impureza.length} impureza`;
  }

  Plotly.newPlot(
    el,
    traces,
    plotlyDarkLayout({
      showlegend: selection !== "all",
      scene: {
        xaxis: { color: "#8891a5" },
        yaxis: { color: "#8891a5" },
        zaxis: { color: "#8891a5" },
        bgcolor: "#0c0e13",
      },
      title,
    }),
    { responsive: true }
  );
}

function fmt(n, dec) {
  return typeof n === "number" ? n.toFixed(dec === undefined ? 4 : dec) : "--";
}

function formatoDuracion(segundos) {
  segundos = Math.max(0, Math.round(segundos));
  const h = Math.floor(segundos / 3600);
  const m = Math.floor((segundos % 3600) / 60);
  const s = segundos % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function tarjetaHero(etiqueta, valor, unidad, error) {
  const div = document.createElement("div");
  div.className = "stat-hero";
  div.innerHTML = `
    <div class="stat-hero-label">${etiqueta}</div>
    <div class="stat-hero-value">${valor}<span class="stat-hero-unit">${unidad || ""}</span></div>
    ${error !== undefined && error !== null ? `<div class="stat-hero-error">± ${error} ${unidad || ""}</div>` : ""}
  `;
  return div;
}

function tarjeta(etiqueta, valor, unidad, error, color, icono) {
  const div = document.createElement("div");
  div.className = "stat-card";
  if (color) div.style.setProperty("--stat-accent", color);
  div.innerHTML = `
    <div class="stat-card-top">
      ${icono ? `<span class="stat-icon">${icono}</span>` : ""}
      <span class="stat-label">${etiqueta}</span>
    </div>
    <div class="stat-value">${valor}${unidad ? ` <span class="stat-unit">${unidad}</span>` : ""}</div>
    ${error !== undefined && error !== null ? `<div class="stat-error">± ${error}</div>` : ""}
  `;
  return div;
}

function chip(etiqueta, valor) {
  const div = document.createElement("div");
  div.className = "stat-chip";
  div.innerHTML = `<span class="stat-chip-label">${etiqueta}</span><span class="stat-chip-value">${valor}</span>`;
  return div;
}

const COLORES = {
  cinetica: "#6c8fff",
  potencial: "#8f6cff",
  rotacion: "#4dd0e1",
  traslacion: "#ff8a65",
  growth: "#4fd58d",
};

function renderStatsCards(stats) {
  const el = document.getElementById("stats-cards");
  el.innerHTML = "";
  const meV = stats.resumen.meV || {};

  if (meV["Energia total"]) {
    el.appendChild(tarjetaHero("Energía total", fmt(meV["Energia total"].valor, 4), "meV", fmt(meV["Energia total"].error, 4)));
  }

  const grid = document.createElement("div");
  grid.className = "stats-grid";
  el.appendChild(grid);

  if (meV["Energia cinetica"]) {
    grid.appendChild(tarjeta("Cinética", fmt(meV["Energia cinetica"].valor, 4), "meV", fmt(meV["Energia cinetica"].error, 4), COLORES.cinetica, "⚡"));
  }
  if (meV["Energia potencial"]) {
    grid.appendChild(tarjeta("Potencial", fmt(meV["Energia potencial"].valor, 4), "meV", fmt(meV["Energia potencial"].error, 4), COLORES.potencial, "◈"));
  }
  if (meV["Energia rotacion"]) {
    grid.appendChild(tarjeta("Rotación", fmt(meV["Energia rotacion"].valor, 4), "meV", fmt(meV["Energia rotacion"].error, 4), COLORES.rotacion, "↻"));
  }
  if (meV["Energia trasl impur"]) {
    grid.appendChild(tarjeta("Traslación impureza", fmt(meV["Energia trasl impur"].valor, 4), "meV", fmt(meV["Energia trasl impur"].error, 4), COLORES.traslacion, "→"));
  }
  if (meV["Energia growth"]) {
    grid.appendChild(tarjeta("Growth", fmt(meV["Energia growth"].valor, 4), "meV", fmt(meV["Energia growth"].error, 4), COLORES.growth, "↗"));
  }
  if (stats.energia_final !== null) {
    grid.appendChild(tarjeta("Final (configuración)", fmt(stats.energia_final, 4), "meV", null, "#e0b84f", "◆"));
  }

  const chips = document.createElement("div");
  chips.className = "stats-chips";
  el.appendChild(chips);

  if (stats.poblacion_media) {
    chips.appendChild(chip("Población media", fmt(stats.poblacion_media.valor, 1) + " ± " + fmt(stats.poblacion_media.error, 1)));
  }
  // "walkers finales" no se muestra: el binario imprime nwsim, que nunca se
  // actualiza con la poblacion real (nwpaso) y siempre vale nwalkers
  if (stats.walkers_iniciales !== null) {
    chips.appendChild(chip("Walkers iniciales", String(stats.walkers_iniciales)));
  }
  // tiempo real (de reloj) medido por el servidor, no el tiempo de CPU del binario
  if (stats.tiempo_real_s !== null) {
    chips.appendChild(chip("Duración de la simulación", formatoDuracion(stats.tiempo_real_s)));
  }
}

function renderStatsCharts(bloques) {
  const equilibrio = bloques.filter((b) => b.fase === "equilibrio");
  const calculo = bloques.filter((b) => b.fase === "calculo");

  const xEq = equilibrio.map((b, i) => i);
  const xCa = calculo.map((b, i) => equilibrio.length + i);

  Plotly.newPlot(
    document.getElementById("plot-growth"),
    [
      { type: "scatter", mode: "lines", name: "equilibrio", x: xEq, y: equilibrio.map((b) => b.e_growth), line: { color: "#8f6cff" } },
      { type: "scatter", mode: "lines", name: "cálculo", x: xCa, y: calculo.map((b) => b.e_growth), line: { color: "#6c8fff" } },
      { type: "scatter", mode: "lines", name: "E_bloque (cálculo)", x: xCa, y: calculo.map((b) => b.e_bloque), line: { color: "#4a5064", width: 1 }, opacity: 0.6 },
    ],
    plotlyDarkLayout({
      title: "Crecimiento de la energía por bloque (E_growth)",
      xaxis: { title: "bloque (equilibrio → cálculo)", color: "#8891a5" },
      yaxis: { title: "meV", color: "#8891a5" },
      legend: { orientation: "h" },
    }),
    { responsive: true }
  );

  Plotly.newPlot(
    document.getElementById("plot-poblacion"),
    [
      { type: "scatter", mode: "lines", name: "equilibrio", x: xEq, y: equilibrio.map((b) => b.poblacion), line: { color: "#8f6cff" } },
      { type: "scatter", mode: "lines", name: "cálculo", x: xCa, y: calculo.map((b) => b.poblacion), line: { color: "#4fd58d" } },
    ],
    plotlyDarkLayout({
      // <Poblacion> del binario: media acumulada desde el inicio de la fase
      title: "Población media acumulada por bloque",
      xaxis: { title: "bloque (equilibrio → cálculo)", color: "#8891a5" },
      yaxis: { title: "walkers (media acumulada)", color: "#8891a5" },
      legend: { orientation: "h" },
    }),
    { responsive: true }
  );
}

function renderStatsTabla(bloques) {
  const el = document.getElementById("stats-tabla");
  const table = document.createElement("table");
  table.className = "static-table";
  const thead = document.createElement("thead");
  thead.innerHTML = "<tr><th>fase</th><th>bloque</th><th>E_bloque</th><th>E_calculo</th><th>E_growth</th><th>Población (media acum.)</th></tr>";
  table.appendChild(thead);
  const tbody = document.createElement("tbody");
  for (const b of bloques) {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${b.fase}</td><td>${b.bloque}</td><td>${fmt(b.e_bloque, 4)}</td>` +
      `<td>${fmt(b.e_calculo, 4)}</td><td>${fmt(b.e_growth, 4)}</td><td>${fmt(b.poblacion, 2)}</td>`;
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  el.innerHTML = "";
  el.appendChild(table);
}

async function loadNumericos(runId) {
  const r = await fetch(`/api/runs/${runId}/stats`);
  const stats = await r.json();
  if (stats.error) {
    document.getElementById("stats-cards").textContent = stats.error;
    return;
  }
  renderStatsCards(stats);
  renderStatsCharts(stats.bloques);
  renderStatsTabla(stats.bloques);
}

const SIN_HISTOGRAMAS = "No hay histogramas para esta ejecución (puede que siga en curso o que no haya terminado).";

function renderRadial(radial) {
  const container = document.getElementById("plots-radial");
  container.innerHTML = "";
  if (Object.keys(radial).length === 0) {
    container.textContent = SIN_HISTOGRAMAS;
    return;
  }
  for (const key of Object.keys(radial)) {
    const h = radial[key];
    const div = document.createElement("div");
    div.className = "plot";
    container.appendChild(div);
    // mdensidades.f90: 2000 celdas de 0.01 A hasta 20 A; cada valor es el
    // numero medio de pares (por walker) con distancia en esa celda, asi
    // que la curva suma el numero de pares (N(N-1)/2, o N con la impureza)
    Plotly.newPlot(
      div,
      [{ type: "scatter", mode: "lines", x: h.x, y: h.y, line: { color: "#5b8cff" } }],
      plotlyDarkLayout({
        title: h.label,
        margin: { l: 60, r: 10, t: 30, b: 45 },
        xaxis: { title: { text: "r, distancia entre las dos partículas (Å)" }, color: "#8891a5" },
        yaxis: { title: { text: "pares por intervalo de 0,01 Å" }, color: "#8891a5" },
      }),
      { responsive: true }
    );
  }
}

function renderAngular(angular) {
  const container = document.getElementById("plots-angular");
  container.innerHTML = "";
  if (Object.keys(angular).length === 0) {
    container.textContent = SIN_HISTOGRAMAS;
    return;
  }
  for (const key of Object.keys(angular)) {
    const h = angular[key];
    const div = document.createElement("div");
    div.className = "plot";
    container.appendChild(div);
    // mdensidades.f90: x = z a lo largo del eje molecular, y = rho = r*sin(theta)
    // (d2d*, >= 0) o rho con el signo de la componente y del sistema
    // molecular (d2yd*); distancias siempre en A (las de entrada en ua se
    // pasan a A). z del mapa: cuentas/muestra pesadas con 1/sin(theta), sin
    // dividir por el volumen de la celda -> unidades arbitrarias.
    const ejeY = key.startsWith("d2yd")
      ? "y, distancia al eje con signo (Å)"
      : "ρ, distancia al eje (Å)";
    Plotly.newPlot(
      div,
      [
        {
          type: "heatmap",
          x: h.x,
          y: h.y,
          z: h.z,
          colorscale: "Viridis",
          colorbar: { title: { text: "densidad<br>(u. arb.)", side: "right" } },
        },
      ],
      plotlyDarkLayout({
        title: h.label,
        margin: { l: 60, r: 10, t: 30, b: 45 },
        xaxis: { title: { text: "z, eje molecular (Å)" }, color: "#8891a5" },
        yaxis: { title: { text: ejeY }, color: "#8891a5" },
      }),
      { responsive: true }
    );
  }
}

(async function init() {
  const params = new URLSearchParams(window.location.search);
  const runId = params.get("run");
  await refreshRunSelector(runId);
  // solo se cargan resultados si se ha pedido una ejecucion concreta
  // (por URL, o justo al terminar de ejecutar/parar una simulacion) --
  // aterrizar en esta pagina sin haber elegido nada debe mostrar
  // siempre el letrero de "todavia no hay resultados", nunca la ultima
  // ejecucion guardada por su cuenta.
  if (runId) {
    loadResults(runId);
  } else {
    mostrarSinResultados();
  }
})();
