// Ventana modal de Ajustes: carpetas de ejecuciones / codigo a compilar
// / binario compilado. Compartido entre config.html y results.html
// (ambas cargan este script antes de su propio app-*.js) para no
// duplicar la misma logica en las dos paginas.

const btnToggleSettings = document.getElementById("btn-toggle-settings");
const settingsModalEl = document.getElementById("settings-modal");
const btnCloseSettings = document.getElementById("btn-close-settings");
const inputRunsDir = document.getElementById("input-runs-dir");
const inputSourceDir = document.getElementById("input-source-dir");
const inputBinaryDir = document.getElementById("input-binary-dir");
const btnSaveSettings = document.getElementById("btn-save-settings");
const settingsMsgEl = document.getElementById("settings-msg");

function abrirAjustes() {
  settingsMsgEl.textContent = "";
  settingsModalEl.hidden = false;
  loadSettings();
}

function cerrarAjustes() {
  settingsModalEl.hidden = true;
}

btnToggleSettings.onclick = abrirAjustes;
btnCloseSettings.onclick = cerrarAjustes;

// cerrar al pinchar fuera de la caja (en el fondo oscurecido) o con Escape.
settingsModalEl.onclick = (ev) => {
  if (ev.target === settingsModalEl) cerrarAjustes();
};
document.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape" && !settingsModalEl.hidden) cerrarAjustes();
});

async function loadSettings() {
  const r = await fetch("/api/settings");
  const j = await r.json();
  inputRunsDir.value = j.runs_dir;
  inputSourceDir.value = j.source_dir;
  inputBinaryDir.value = j.binary_dir;
}

// un unico boton "Elegir carpeta..." por campo -- data-campo dice a que
// input y a que clave de /api/settings corresponde cada uno.
const INPUTS_POR_CAMPO = {
  runs_dir: inputRunsDir,
  source_dir: inputSourceDir,
  binary_dir: inputBinaryDir,
};

for (const btn of document.querySelectorAll(".btn-pick-folder")) {
  btn.onclick = async () => {
    const campo = btn.dataset.campo;
    settingsMsgEl.textContent = "abriendo el gestor de archivos...";
    btn.disabled = true;
    try {
      const r = await fetch("/api/settings/pick-folder", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ campo }),
      });
      const j = await r.json();
      if (!r.ok) {
        settingsMsgEl.textContent = "error: " + j.error;
      } else if (j.cancelled) {
        settingsMsgEl.textContent = "";
      } else {
        INPUTS_POR_CAMPO[campo].value = j.path;
        settingsMsgEl.textContent = "carpeta elegida -- pulsa \"Guardar ajustes\" para aplicarla";
      }
    } catch (e) {
      settingsMsgEl.textContent = "error: " + e;
    } finally {
      btn.disabled = false;
    }
  };
}

btnSaveSettings.onclick = async () => {
  settingsMsgEl.textContent = "guardando...";
  let r, j;
  try {
    r = await fetch("/api/settings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        runs_dir: inputRunsDir.value,
        source_dir: inputSourceDir.value,
        binary_dir: inputBinaryDir.value,
      }),
    });
    j = await r.json();
  } catch (e) {
    settingsMsgEl.textContent = "error: no se pudo contactar con el servidor (" + e + ")";
    return;
  }
  if (r.ok) {
    settingsMsgEl.textContent = "ajustes guardados";
    // solo existe en la pagina de Configuracion -- en Resultados no hay
    // nada que compilar/ejecutar, así que no hay estado que refrescar.
    if (typeof refreshBinaryStatus === "function") refreshBinaryStatus();
  } else {
    settingsMsgEl.textContent = "error: " + j.error;
  }
};
