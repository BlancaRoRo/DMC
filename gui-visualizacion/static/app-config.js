const logEl = document.getElementById("log");
const btnCompile = document.getElementById("btn-compile");
const btnRun = document.getElementById("btn-run");
const btnStop = document.getElementById("btn-stop");
const binaryStatusEl = document.getElementById("binary-status");
const inputNombreRun = document.getElementById("input-nombre-run");

// mapa linea(string) -> elemento del formulario (input/select), para
// leer los valores editables al enviar /api/run. Las filas 'par'
// guardan un array [inputV1, inputV2].
const inputsPorLinea = {};

// si se importo un in.mcv, su texto completo se guarda aqui -- se
// manda tal cual como base al ejecutar, en vez del in.mcv de
// referencia por defecto (ver /api/run, parametro base_inmcv).
let baseInmcvText = null;

const inputImportar = document.getElementById("input-importar-inmcv");
const importMsgEl = document.getElementById("import-msg");

// configuracion inicial (.HH) elegida en el navegador o recuperada del
// historial: su texto se manda al ejecutar (parametro conf de /api/run) y
// el servidor la copia a la carpeta de la ejecucion. null = no se manda.
let confText = null;
// nombre del fichero (.HH) cargado: el servidor comprueba que es el que
// abre el simulador con el in.mcv de la ejecucion
let confNombre = null;

const inputImportarConf = document.getElementById("input-importar-conf");
const btnQuitarConf = document.getElementById("btn-quitar-conf");
const confMsgEl = document.getElementById("conf-msg");
const selectHistorial = document.getElementById("select-historial");
const historialMsgEl = document.getElementById("historial-msg");

function logLine(text) {
  logEl.textContent += text + "\n";
  logEl.scrollTop = logEl.scrollHeight;
}

// job_id de la compilacion/ejecucion en curso (viene del evento SSE
// "started"), usado para poder pararla con /api/jobs/<job_id>/stop.
let currentJobId = null;

function jobStarted(jobId) {
  currentJobId = jobId;
  btnStop.hidden = false;
  btnStop.disabled = false;
}

function jobFinished() {
  currentJobId = null;
  btnStop.hidden = true;
}

// ---- estimacion de tiempo mientras corre una simulacion (no una
// compilacion) -- se apoya en las lineas de bloque que el propio
// binario va imprimiendo por stdout, con formato Fortran fijo
// "(3i8,3f16.8,f10.2)":
//     Bloque  Blq/Proc  Proceso  E_bloque  E_calculo  E_growth  Poblacion
//        1       1        1    -637.29844966 ...          1993.35
// y en dos lineas separadoras que marcan el cambio de fase:
//   "==================Bloques para EQUILIBRIO=================="
//   "=====================Bloques de CALCULO====================="
// Los bloques de equilibrio se dan por completados en cuanto empieza
// la fase de calculo (equilibrio siempre termina antes). El total de
// bloques esperados (equilibrio + calculo) los da el servidor, leidos del
// in.mcv de la propia ejecucion.
const runProgressEl = document.getElementById("run-progress");
const runProgressTextEl = document.getElementById("run-progress-text");
const RE_LINEA_BLOQUE = /^\s*(\d+)\s+\d+\s+\d+\s+-?\d+\.\d+\s+-?\d+\.\d+\s+-?\d+\.\d+\s+-?\d+\.\d+\s*$/;

let progreso = null;

// ---- columnas redundantes de la tabla de bloques ----
// El binario es la version serie (mserie.f90, ncpar=1): "Blq/Proc" siempre
// coincide con "Bloque" y "Proceso" siempre vale 1, asi que se quitan del
// log mostrado (salida.log no se toca). La cabecera usa '(3a10,...)': se
// recortan sus columnas 2 y 3. Una linea de bloque solo se recorta si de
// verdad es redundante; si no (p. ej. un binario paralelo), se deja tal cual.
const RE_CABECERA_BLOQUES = /^\s*Bloque\s+Blq\/Proc\s+Proceso/;
const RE_COLUMNAS_BLOQUE = /^(\s*\d+)\s+(\d+)\s+(\d+)(\s+-?\d+\.\d+.*)$/;
// la cabecera original ('a15') no cae encima de los datos ('i8,3f16.8,f10.2'):
// se reescribe con los anchos de las columnas de datos
const CABECERA_ALINEADA = "Bloque".padStart(8) +
  ["<E_bloque>", "<E_calculo>", "<E_growth>"].map((t) => t.padStart(16)).join("") +
  " <Poblacion>";  // un caracter mas ancho que 'f10.2' para no pegarse a <E_growth>

// la ultima cabecera de bloques vista se copia a #log-cabecera, que queda
// fija encima del log aunque este siga avanzando
const logCabeceraEl = document.getElementById("log-cabecera");

function fijarCabecera(lineas) {
  for (const linea of lineas) {
    if (RE_CABECERA_BLOQUES.test(linea)) {
      logCabeceraEl.textContent = quitarColumnasRedundantes(linea);
      logCabeceraEl.hidden = false;
    }
  }
}

function quitarColumnasRedundantes(linea) {
  if (RE_CABECERA_BLOQUES.test(linea)) return CABECERA_ALINEADA;
  const m = RE_COLUMNAS_BLOQUE.exec(linea);
  if (m && m[1].trim() === m[2] && m[3] === "1") return m[1] + m[4];
  return linea;
}

function formatoDuracion(segundos) {
  segundos = Math.max(0, Math.round(segundos));
  const h = Math.floor(segundos / 3600);
  const m = Math.floor((segundos % 3600) / 60);
  const s = segundos % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function iniciarProgreso(transcurridoS, totalEq, totalCa) {
  progreso = { t0: Date.now() - (transcurridoS || 0) * 1000, totalEq, totalCa, fase: "equilibrio", bloqueActual: 0 };
  runProgressEl.hidden = false;
  actualizarProgresoTexto();
  progreso.timer = setInterval(actualizarProgresoTexto, 1000);
}

function procesarLineaProgreso(line) {
  if (!progreso) return;
  if (line.includes("Bloques para EQUILIBRIO")) {
    progreso.fase = "equilibrio";
  } else if (line.includes("Bloques de CALCULO")) {
    progreso.fase = "calculo";
  } else {
    const m = RE_LINEA_BLOQUE.exec(line);
    if (m) {
      progreso.bloqueActual = parseInt(m[1], 10);
      actualizarProgresoTexto();
    }
  }
}

function actualizarProgresoTexto() {
  if (!progreso) return;
  const transcurridoS = (Date.now() - progreso.t0) / 1000;
  const total = progreso.totalEq + progreso.totalCa;
  const hechos = progreso.fase === "calculo" ? progreso.totalEq + progreso.bloqueActual : progreso.bloqueActual;

  if (total > 0 && hechos > 0) {
    const estimadoTotalS = transcurridoS * (total / hechos);
    const restanteS = Math.max(0, estimadoTotalS - transcurridoS);
    runProgressTextEl.textContent =
      `Ejecutando -- bloque ${hechos}/${total} -- transcurrido ${formatoDuracion(transcurridoS)}` +
      ` -- estimado restante ~${formatoDuracion(restanteS)}`;
  } else {
    runProgressTextEl.textContent = `Ejecutando -- transcurrido ${formatoDuracion(transcurridoS)} -- calculando estimación...`;
  }
}

function pararProgreso() {
  if (progreso && progreso.timer) clearInterval(progreso.timer);
  progreso = null;
  runProgressEl.hidden = true;
}

btnStop.onclick = async () => {
  const url = currentRunId
    ? "/api/runs/" + encodeURIComponent(currentRunId) + "/stop"
    : currentJobId ? "/api/jobs/" + encodeURIComponent(currentJobId) + "/stop" : null;
  if (!url) return;
  btnStop.disabled = true;
  logLine("=== parando ===");
  try {
    const r = await fetch(url, { method: "POST" });
    if (!r.ok) {
      const j = await r.json();
      logLine("no se pudo parar: " + j.error);
      btnStop.disabled = false;
    }
  } catch (e) {
    logLine("no se pudo parar: " + e);
    btnStop.disabled = false;
  }
};

// ---- ejecucion en segundo plano ----
// La simulacion corre en el servidor, desacoplada de esta pagina (escribe
// su salida en salida.log). Aqui solo se SIGUE: cada segundo se pide lo
// nuevo de la salida y el estado. Si se recarga la pagina, al cargar se
// pregunta si hay una ejecucion en curso y se reengancha desde el
// principio del log.
let currentRunId = null;
let logOffset = 0;
let seguimientoTimer = null;

async function seguirEjecucion(runId, recargarLog) {
  currentRunId = runId;
  logOffset = 0;
  if (recargarLog) logEl.textContent = "";
  logCabeceraEl.hidden = true;
  btnCompile.disabled = true;
  btnRun.disabled = true;
  btnStop.hidden = false;
  btnStop.disabled = false;
  if (progreso) pararProgreso();
  await sondearEjecucion();
}

async function sondearEjecucion() {
  let j;
  try {
    const r = await fetch(`/api/runs/${encodeURIComponent(currentRunId)}/seguimiento?desde=${logOffset}`);
    j = await r.json();
    if (!r.ok) throw new Error(j.error || r.statusText);
  } catch (e) {
    // el servidor puede estar reiniciandose: la simulacion sigue viva, se reintenta
    runProgressEl.hidden = false;
    runProgressTextEl.textContent = "Sin conexión con el servidor -- la simulación sigue en marcha, reintentando...";
    seguimientoTimer = setTimeout(sondearEjecucion, 2000);
    return;
  }

  if (!progreso) iniciarProgreso(j.elapsed_s, j.bloques_eq, j.bloques_ca);
  else progreso.t0 = Date.now() - (j.elapsed_s || 0) * 1000;

  if (j.texto) {
    const lineas = j.texto.split("\n");
    fijarCabecera(lineas);
    logEl.textContent += lineas.map(quitarColumnasRedundantes).join("\n");
    logEl.scrollTop = logEl.scrollHeight;
    for (const linea of j.texto.split("\n")) procesarLineaProgreso(linea);
    logOffset = j.siguiente;
  }

  if (j.estado === "corriendo") {
    seguimientoTimer = setTimeout(sondearEjecucion, 1000);
    return;
  }
  finalizarEjecucion(j);
}

function finalizarEjecucion(j) {
  const runId = currentRunId;
  currentRunId = null;
  pararProgreso();
  btnStop.hidden = true;
  btnCompile.disabled = false;
  btnRun.disabled = false;
  if (j.estado === "terminada") {
    logLine("=== ejecucion terminada (codigo " + j.returncode + ") ===");
    if (j.returncode === 0) window.location.href = "/resultados?run=" + encodeURIComponent(runId);
  } else {
    logLine("=== ejecucion detenida ===");
  }
}

async function streamSSE(url, options, handlers) {
  const resp = await fetch(url, options);
  if (!resp.ok) {
    // el servidor rechazo la peticion antes de empezar (no hay stream SSE)
    let mensaje = resp.statusText;
    try { mensaje = (await resp.json()).error || mensaje; } catch (e) { /* cuerpo no JSON */ }
    return { ok: false, error: mensaje };
  }
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
  return { ok: true };
}

async function refreshBinaryStatus() {
  const r = await fetch("/api/binary-status");
  const j = await r.json();
  if (j.exists) {
    binaryStatusEl.textContent = "binario compilado";
    binaryStatusEl.className = "status ok";
  } else {
    binaryStatusEl.textContent = "binario no compilado";
    binaryStatusEl.className = "status err";
  }
}

// ---- pestanas del formulario de configuracion ----
// mismo patron que las pestanas de Resultados: un boton .tab-btn activa
// el .tab-content con su mismo data-tab/id. Ademas, cada pestana (salvo
// la ultima) tiene un boton "Siguiente" que activa la que le sigue, para
// no obligar a volver arriba a pinchar en la pestana siguiente.
const configTabButtons = document.querySelectorAll("#config-tabs .tab-btn");
const configTabContents = document.querySelectorAll(".config-frame .tab-content");

function activarPestanaConfig(tabId) {
  for (const b of configTabButtons) b.classList.toggle("active", b.dataset.tab === tabId);
  for (const c of configTabContents) c.classList.toggle("active", c.id === tabId);
}

for (const btn of configTabButtons) {
  btn.onclick = () => activarPestanaConfig(btn.dataset.tab);
}

for (const btn of document.querySelectorAll(".tab-next-btn")) {
  btn.onclick = () => activarPestanaConfig(btn.dataset.next);
}

// placeholder del nombre de la ejecucion: muestra el nombre que se le
// pondria por defecto (fecha y hora) si se deja vacio, en el mismo
// formato que usa el servidor (dd-mm-aa_hh:mm).
function nombrePorDefecto() {
  const d = new Date();
  const dos = (n) => String(n).padStart(2, "0");
  return `${dos(d.getDate())}-${dos(d.getMonth() + 1)}-${dos(d.getFullYear() % 100)}_${dos(d.getHours())}:${dos(d.getMinutes())}`;
}
inputNombreRun.placeholder = "por defecto: " + nombrePorDefecto();

// ---- formulario de configuracion ----

function crearInputCampo(campo) {
  let el;
  if (campo.tipo === "select") {
    el = document.createElement("select");
    for (const opt of campo.opciones) {
      const o = document.createElement("option");
      o.value = opt;
      o.textContent = opt;
      el.appendChild(o);
    }
    el.value = campo.valor;
  } else {
    el = document.createElement("input");
    el.type = "text";
    el.value = campo.valor;
  }
  inputsPorLinea[campo.linea] = el;
  return el;
}

function crearBadgeFijo() {
  const badge = document.createElement("span");
  badge.className = "badge-fijo";
  badge.textContent = "fijo";
  return badge;
}

function crearValorFijo(valor) {
  const span = document.createElement("span");
  span.className = "valor-fijo";
  span.textContent = valor;
  return span;
}

function crearFilaCampo(campo) {
  const row = document.createElement("div");
  row.className = "form-row" + (campo.editable ? "" : " static");
  const label = document.createElement("label");
  label.textContent = campo.etiqueta;
  if (!campo.editable) {
    label.appendChild(crearBadgeFijo());
    row.appendChild(label);
    row.appendChild(crearValorFijo(campo.valor));
    return row;
  }
  row.appendChild(label);
  row.appendChild(crearInputCampo(campo));
  return row;
}

// Las celdas de las tablas por "l" (impureza-He4/He3) van muy
// apretadas (6 columnas: l + b/nu/alfa/p4/p5) -- meter 2 inputs
// separados por celda las dejaba casi invisibles. Se combinan los 2
// valores en UNA sola caja de texto ("v1 v2", tal cual estan
// separados en el fichero) -- recogerValores() la vuelve a partir por
// espacios al enviar.
function crearCeldaPar(campo) {
  const td = document.createElement("td");
  td.className = "par-cell";
  if (!campo.editable) {
    td.appendChild(crearValorFijo(campo.v1 + "  " + campo.v2));
    return td;
  }
  const input = document.createElement("input");
  input.type = "text";
  input.value = campo.v1 + "  " + campo.v2;
  inputsPorLinea[campo.linea] = { combinado: input };
  td.appendChild(input);
  return td;
}

function crearTablaPares(tabla) {
  const wrap = document.createElement("div");
  wrap.className = "static-table-wrap";
  const h4 = document.createElement("h4");
  h4.textContent = tabla.titulo;
  wrap.appendChild(h4);

  const table = document.createElement("table");
  table.className = "static-table editable-table";
  const thead = document.createElement("thead");
  thead.innerHTML = "<tr><th>parámetro</th><th>valor 1</th><th>valor 2</th></tr>";
  table.appendChild(thead);
  const tbody = document.createElement("tbody");
  for (const campo of tabla.filas) {
    const tr = document.createElement("tr");
    if (!campo.editable) tr.className = "fila-fija";
    const tdLabel = document.createElement("td");
    tdLabel.textContent = campo.etiqueta;
    if (!campo.editable) tdLabel.appendChild(crearBadgeFijo());
    tr.appendChild(tdLabel);

    const tdV1 = document.createElement("td");
    const tdV2 = document.createElement("td");
    if (!campo.editable) {
      tdV1.appendChild(crearValorFijo(campo.v1));
      tdV2.appendChild(crearValorFijo(campo.v2));
    } else {
      const inV1 = document.createElement("input");
      inV1.type = "text";
      inV1.value = campo.v1;
      const inV2 = document.createElement("input");
      inV2.type = "text";
      inV2.value = campo.v2;
      inputsPorLinea[campo.linea] = [inV1, inV2];
      tdV1.appendChild(inV1);
      tdV2.appendChild(inV2);
    }
    tr.appendChild(tdV1);
    tr.appendChild(tdV2);
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  wrap.appendChild(table);
  return wrap;
}

function crearTablaL(tabla) {
  const wrap = document.createElement("div");
  wrap.className = "static-table-wrap";
  const h4 = document.createElement("h4");
  h4.innerHTML = `${tabla.titulo} &mdash; lmax = `;
  if (!tabla.lmax.editable) {
    h4.appendChild(crearBadgeFijo());
    h4.appendChild(crearValorFijo(tabla.lmax.valor));
  } else {
    const lmaxInput = crearInputCampo(tabla.lmax);
    lmaxInput.classList.add("inline-input");
    h4.appendChild(lmaxInput);
  }
  wrap.appendChild(h4);

  const table = document.createElement("table");
  table.className = "static-table editable-table";
  const thead = document.createElement("thead");
  thead.innerHTML = "<tr><th>l</th><th>b</th><th>nu</th><th>alfa</th><th>p4</th><th>p5</th></tr>";
  table.appendChild(thead);
  const tbody = document.createElement("tbody");
  for (const fila of tabla.filas) {
    const tr = document.createElement("tr");
    const tdLabel = document.createElement("td");
    tdLabel.textContent = fila.etiqueta;
    tr.appendChild(tdLabel);
    for (const campo of fila.campos) {
      tr.appendChild(crearCeldaPar(campo));
    }
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  wrap.appendChild(table);
  return wrap;
}

// lineas de "pasos y bloques" (seccion 2) -- se agrupan en su propia
// columna, separadas del resto de parametros Monte Carlo.
const LINEAS_PASOS_BLOQUES = new Set([39, 40, 41, 42, 43, 44]);

function renderConfigSchema(schema) {
  const sec1 = document.getElementById("seccion-1");
  const sec2mc = document.getElementById("seccion-2-mc");
  const sec2pasos = document.getElementById("seccion-2-pasos");
  const sec3 = document.getElementById("seccion-3");

  for (const linea of Object.keys(inputsPorLinea)) delete inputsPorLinea[linea];
  sec1.innerHTML = "";
  sec2mc.innerHTML = "";
  sec2pasos.innerHTML = "";
  sec3.innerHTML = "";

  for (const campo of schema.secciones[0].campos) sec1.appendChild(crearFilaCampo(campo));
  for (const campo of schema.secciones[1].campos) {
    const destino = LINEAS_PASOS_BLOQUES.has(campo.linea) ? sec2pasos : sec2mc;
    destino.appendChild(crearFilaCampo(campo));
  }

  const tablas = schema.secciones[2].tablas;
  sec3.appendChild(crearTablaPares(tablas[0]));
  sec3.appendChild(crearTablaL(tablas[1]));
  sec3.appendChild(crearTablaL(tablas[2]));
  // la seccion 4 (calculo paralelo, solo ncadapvm, fijo) no se muestra:
  // el pipeline GPU no usa PVM
}

async function loadConfigSchema() {
  const r = await fetch("/api/config-schema");
  renderConfigSchema(await r.json());
}

function recogerValores() {
  // inputsPorLinea solo contiene campos editables (los fijos se
  // renderizan como texto plano y nunca se registran aqui).
  const valores = {};
  for (const [linea, el] of Object.entries(inputsPorLinea)) {
    if (Array.isArray(el)) {
      valores[linea] = [el[0].value, el[1].value];
    } else if (el && el.combinado) {
      const partes = el.combinado.value.trim().split(/\s+/);
      valores[linea] = [partes[0] || "", partes[1] || ""];
    } else {
      valores[linea] = el.value;
    }
  }
  return valores;
}

btnCompile.onclick = async () => {
  btnCompile.disabled = true;
  btnRun.disabled = true;
  logLine("=== compilando ===");
  const resCompile = await streamSSE(
    "/api/compile",
    { method: "POST" },
    {
      started: (d) => jobStarted(d.job_id),
      log: (d) => logLine(d.line),
      done: (d) => {
        logLine("=== compilacion terminada (codigo " + d.returncode + ") ===");
        jobFinished();
        btnCompile.disabled = false;
        btnRun.disabled = false;
        refreshBinaryStatus();
      },
    }
  );
  if (!resCompile.ok) {
    logLine("error: " + resCompile.error);
    btnCompile.disabled = false;
    btnRun.disabled = false;
  }
};

btnRun.onclick = async () => {
  btnCompile.disabled = true;
  btnRun.disabled = true;
  logLine("=== ejecutando ===");
  let j;
  try {
    const r = await fetch("/api/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        valores: recogerValores(),
        base_inmcv: baseInmcvText,
        conf: confText,
        conf_nombre: confNombre,
        nombre: inputNombreRun.value.trim(),
      }),
    });
    j = await r.json();
    if (!r.ok) throw new Error(j.error || r.statusText);
  } catch (e) {
    logLine("error: " + e.message);
    btnCompile.disabled = false;
    btnRun.disabled = false;
    return;
  }
  if (j.conf) {
    logLine("Usando la configuración inicial " + j.conf);
  } else {
    logLine("Creando configuraciones");
  }
  logLine("run_id=" + j.run_id + " -- la simulación corre en segundo plano: puedes recargar o cerrar esta página");
  await seguirEjecucion(j.run_id, false);
};

async function importarInmcv(content, origenLabel) {
  const r = await fetch("/api/parse-inmcv", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content }),
  });
  const schema = await r.json();

  if (!r.ok) {
    importMsgEl.textContent = "no se pudo cargar " + origenLabel + ": " + schema.error;
    importMsgEl.className = "hint err-text";
    return false;
  }

  baseInmcvText = schema.base_inmcv;
  renderConfigSchema(schema);
  importMsgEl.textContent = "configuración cargada desde " + origenLabel +
    " -- se usará como base al ejecutar";
  importMsgEl.className = "hint ok-text";
  return true;
}

inputImportar.onchange = async () => {
  const file = inputImportar.files[0];
  if (!file) return;
  importMsgEl.textContent = "leyendo " + file.name + "...";
  const content = await file.text();
  const ok = await importarInmcv(content, file.name);
  if (!ok) inputImportar.value = "";
};

function fijarConf(texto, nombreFichero, origenLabel) {
  confText = texto;
  confNombre = texto === null ? null : nombreFichero;
  btnQuitarConf.hidden = texto === null;
  if (texto === null) {
    confMsgEl.textContent = "sin configuración inicial: el simulador creará las configuraciones";
    confMsgEl.className = "hint";
  } else {
    confMsgEl.textContent = "configuración inicial " + nombreFichero + " cargada desde " +
      (origenLabel || "el equipo") + " -- se copiará a la carpeta de la ejecución";
    confMsgEl.className = "hint ok-text";
  }
}

inputImportarConf.onchange = async () => {
  const file = inputImportarConf.files[0];
  if (!file) return;
  fijarConf(await file.text(), file.name);
};

btnQuitarConf.onclick = () => {
  inputImportarConf.value = "";
  fijarConf(null);
};

// ---- historial: valores de entrada + configuracion inicial guardados
// en cada ejecucion (in.mcv y conf_inicial.HH de su carpeta) ----
async function refreshHistorial() {
  try {
    const r = await fetch("/api/runs");
    const j = await r.json();
    selectHistorial.innerHTML = '<option value="">(cargar del historial)</option>';
    for (const run of j.runs) {
      const opt = document.createElement("option");
      opt.value = run.run_id;
      opt.textContent = run.nombre;
      selectHistorial.appendChild(opt);
    }
  } catch (e) { /* sin servidor: el historial queda vacio */ }
}

async function cargarDeHistorial(runId, origenLabel) {
  const r = await fetch(`/api/runs/${encodeURIComponent(runId)}/inmcv`);
  const j = await r.json();
  if (!r.ok) {
    historialMsgEl.textContent = "no se pudo cargar " + origenLabel + ": " + j.error;
    historialMsgEl.className = "hint err-text";
    return false;
  }
  if (!(await importarInmcv(j.content, origenLabel))) return false;
  inputImportar.value = "";

  inputImportarConf.value = "";
  const rc = await fetch(`/api/runs/${encodeURIComponent(runId)}/conf-inicial`);
  const jc = await rc.json();
  if (rc.ok) {
    fijarConf(jc.content, jc.nombre, origenLabel);
    historialMsgEl.textContent = "cargados los valores de entrada y la configuración inicial de " + origenLabel;
  } else {
    fijarConf(null);
    historialMsgEl.textContent = "cargados los valores de entrada de " + origenLabel +
      " (sin configuración inicial: " + jc.error + ")";
  }
  historialMsgEl.className = "hint ok-text";
  return true;
}

// como el selector de Resultados: carga en cuanto se elige
selectHistorial.onchange = async () => {
  const runId = selectHistorial.value;
  if (!runId) return;
  const opt = selectHistorial.selectedOptions[0];
  await cargarDeHistorial(runId, "la ejecución " + opt.textContent);
};

refreshBinaryStatus();
refreshHistorial();
fijarConf(null);

// si hay una simulacion en marcha (p. ej. tras recargar la pagina), seguirla
(async function reengancharEjecucionActiva() {
  try {
    const r = await fetch("/api/run-activa");
    const j = await r.json();
    if (j.run_id) {
      logLine("=== simulación en curso: " + j.nombre + " ===");
      await seguirEjecucion(j.run_id, false);
    }
  } catch (e) { /* sin servidor: no hay nada que reenganchar */ }
})();

// si se llega desde "recrear esta configuracion" en Resultados
// (?recrear=run_XXXXXXXX_XXXXXX), cargar esa corrida en vez del preset
// por defecto.
(async function initConfig() {
  const params = new URLSearchParams(window.location.search);
  const recrearId = params.get("recrear");
  if (recrearId && (await cargarDeHistorial(recrearId, "la ejecución " + recrearId))) return;
  loadConfigSchema();
})();
