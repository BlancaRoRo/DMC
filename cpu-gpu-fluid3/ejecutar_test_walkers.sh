#!/bin/bash
# ejecutar_test_walkers.sh -- repite en otra maquina (pensado para fluid3,
# Tesla V100 de la UAL) la misma bateria que cpu-gpu-ctfg/
# ejecutar_test_walkers_pequenos.sh ejecuto en el PC personal:
#   bloques de calculo=100 y pasos por bloque=100 fijos,
#   walkers = 1,5,10,15,20,25,30,40,50,75,100,150,250,500,
#   etrial=-631.8, semilla fija, conf.20.00.HH fresco antes de cada corrida.
#
# A diferencia de la bateria original, no depende de rutas absolutas: compila
# las dos versiones a partir de un checkout del repositorio
# (https://github.com/BlancaRoRo/DMC) en la propia maquina, para que el
# binario GPU se genere para la arquitectura de su GPU.
#   GPU = dmc-hibrido/qmccluster_pipeline (opcion=5, nvfortran)
#         -- equivale bit a bit a hibrido_instrumentado con opcion=7
#   CPU = dmc-cpu/qmccluster (opcion=4, gfortran)
#
# Uso:
#   ./ejecutar_test_walkers.sh [ruta_al_repo_DMC] [etiqueta_maquina]
# ruta_al_repo_DMC: copia de la rama main (dmc-cpu/ y dmc-hibrido/).
# Variables opcionales:
#   WALKERS="5 10 ..."   lista de walkers (por defecto, la de la bateria original)
#   REPETICIONES=N       corridas por configuracion y version (por defecto 1)
#   FORZAR_COMPILAR=1    recompila aunque ya existan los binarios
#   CUDA_VISIBLE_DEVICES elegir GPU si la maquina tiene varias
set -e
# Punto decimal en wall=... aunque el sistema este en es_ES (resumen.py lo espera asi)
export LC_NUMERIC=C
HERE="$(cd "$(dirname "$0")" && pwd)"

REPO="$(cd "${1:-$HERE/..}" && pwd)"
ETIQUETA="${2:-$(hostname -s)}"
WALKERS="${WALKERS:-1 5 10 15 20 25 30 40 50 75 100 150 250 500}"
REPETICIONES="${REPETICIONES:-1}"
BLOQ_CALC=100
PASOS=100

GPU_DIR="$REPO/dmc-hibrido"
CPU_DIR="$REPO/dmc-cpu"
PLANTILLA="$HERE/_plantillas/in.mcv.base"
CONF_FRESCO="$HERE/_plantillas/conf.20.00.HH.base"
HEH2M="$HERE/_plantillas/heh2m.pot"
SALIDA="$HERE/test-walkers-$ETIQUETA"
PROGRESO="$HERE/progreso_walkers_$ETIQUETA.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$PROGRESO"; }

# --- Comprobaciones previas -------------------------------------------------
for d in "$GPU_DIR" "$CPU_DIR"; do
  [ -d "$d" ] || { echo "No existe $d -- ¿es la ruta del repositorio DMC?" >&2; exit 1; }
done
command -v python3 >/dev/null || { echo "Falta python3" >&2; exit 1; }
command -v gfortran >/dev/null || { echo "Falta gfortran (version CPU)" >&2; exit 1; }
if ! command -v nvfortran >/dev/null; then
  echo "Falta nvfortran en el PATH. Si el NVIDIA HPC SDK esta instalado, prueba con" >&2
  echo "  module load nvhpc   o   export PATH=/opt/nvidia/hpc_sdk/Linux_x86_64/<version>/compilers/bin:\$PATH" >&2
  exit 1
fi

# --- Compilacion ------------------------------------------------------------
if [ "${FORZAR_COMPILAR:-0}" = 1 ] || [ ! -x "$GPU_DIR/qmccluster_pipeline" ]; then
  echo "Compilando version GPU (nvfortran) en $GPU_DIR ..."
  (cd "$GPU_DIR" && make clean >/dev/null && make -j"$(nproc)")
fi
if [ "${FORZAR_COMPILAR:-0}" = 1 ] || [ ! -x "$CPU_DIR/qmccluster" ]; then
  echo "Compilando version CPU (gfortran) en $CPU_DIR ..."
  (cd "$CPU_DIR" && ./compilar_gfortran.sh)
fi

# --- Registro del entorno (para la tabla de caracteristicas) -----------------
mkdir -p "$SALIDA"
{
  echo "== fecha";      date
  echo "== hostname";   hostname
  echo "== uname";      uname -r
  echo "== os";         (grep PRETTY_NAME /etc/os-release || true)
  echo "== lscpu";      lscpu
  echo "== nvidia-smi"; nvidia-smi
  echo "== nvidia-smi -q (resumen)"
  nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap --format=csv
  echo "== nvfortran";  nvfortran --version
  echo "== gfortran";   gfortran --version | head -1
  echo "== repo";       (cd "$REPO" && git log -1 --oneline 2>/dev/null || echo "sin git")
} > "$SALIDA/entorno.txt" 2>&1

# Maquina compartida: avisar si hay otros procesos usando la GPU
otros=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || true)
if [ -n "$otros" ]; then
  echo "AVISO: hay otros procesos usando la GPU (los tiempos pueden verse afectados):"
  echo "$otros"
fi

# correr(destino_dir, tag, opcion, binario_src, walkers, repeticion)
correr() {
  local dir="$1" tag="$2" opcion="$3" binario_src="$4" walkers="$5" rep="$6"
  local binario nombre_log
  binario="$(basename "$binario_src")"
  nombre_log="salida-$(basename "$dir")-${tag}-r${rep}.log"
  mkdir -p "$dir"
  cp "$binario_src" "$dir/$binario"
  cp "$HEH2M" "$dir/heh2m.pot"
  python3 "$HERE/genera_inmcv.py" "$PLANTILLA" "$dir/in.mcv-${tag}" "$opcion" "$walkers" 1 "$BLOQ_CALC" "$PASOS" >/dev/null
  cp "$CONF_FRESCO" "$dir/conf.20.00.HH"
  echo "procesos en GPU al empezar: $(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | wc -l)" > "$dir/$nombre_log"

  log "INICIO $(basename "$dir") [$tag] r$rep w=$walkers bloq=$BLOQ_CALC pasos=$PASOS"
  local t0 t1 dt rc
  t0=$(date +%s.%N)
  set +e
  (cd "$dir" && ./"$binario" < "in.mcv-${tag}" >> "$nombre_log" 2>&1)
  rc=$?
  set -e
  t1=$(date +%s.%N)
  dt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.9f", b-a}')
  echo "wall=${dt}s rc=${rc}" >> "$dir/$nombre_log"
  if [ "$rc" -ne 0 ]; then
    log "FALLO  $(basename "$dir") [$tag] r$rep wall=${dt}s rc=${rc} -- ver $dir/$nombre_log"
  else
    log "FIN    $(basename "$dir") [$tag] r$rep wall=${dt}s"
  fi
}

log "===== test-walkers ($ETIQUETA): INICIO -- walkers: $WALKERS; repeticiones: $REPETICIONES ====="
for w in $WALKERS; do
  for rep in $(seq 1 "$REPETICIONES"); do
    d="$SALIDA/test-${w}w"
    correr "$d" gpu 5 "$GPU_DIR/qmccluster_pipeline" "$w" "$rep"
    correr "$d" cpu 4 "$CPU_DIR/qmccluster" "$w" "$rep"
  done
done
log "===== test-walkers ($ETIQUETA): TERMINADO ====="

python3 "$HERE/resumen.py" "$SALIDA"
