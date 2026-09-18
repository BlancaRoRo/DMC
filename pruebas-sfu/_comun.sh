# _comun.sh -- funciones y rutas compartidas por los 4 scripts de la
# bateria. No se ejecuta solo, se hace "source" desde cada uno.
# Rutas relativas a $HERE (v4-cuda-pruebas/pruebas-sfu) para que funcione
# igual en cualquier checkout del repo (PC personal, fluid3, etc.), sin
# depender de la ruta absoluta donde esté clonado.
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
GPU_DIR="$REPO_ROOT/v2-cuda-integracion/hibrido_instrumentado"
CPU_DIR="$REPO_ROOT/v2-cuda-integracion/cpu-original-gfortran"
CONF_FRESCO="$REPO_ROOT/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
PLANTILLA="$HERE/_plantillas/in.mcv.base"
HEH2M="$HERE/_plantillas/heh2m.pot"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# correr(destino_dir, tag, opcion, binario_src, nombre_binario, walkers, bloq_calc, pasos)
correr() {
  local destino="$1" tag="$2" opcion="$3" binario_src="$4" binario_nombre="$5" walkers="$6" bloq_calc="$7" pasos="$8"
  local dir="$destino"
  mkdir -p "$dir"
  cp "$binario_src" "$dir/${binario_nombre}"
  cp "$HEH2M" "$dir/heh2m.pot"
  python3 "$HERE/genera_inmcv.py" "$PLANTILLA" "$dir/in.mcv-${tag}" "$opcion" "$walkers" 1 "$bloq_calc" "$pasos"
  cp "$CONF_FRESCO" "$dir/conf.20.00.HH"

  log "INICIO $(basename "$destino") [$tag] w=$walkers bloq=$bloq_calc pasos=$pasos"
  local t0 t1 dt
  t0=$(date +%s.%N)
  (cd "$dir" && ./"${binario_nombre}" < "in.mcv-${tag}" > "salida-$(basename "$destino")-${tag}.log" 2>&1)
  t1=$(date +%s.%N)
  dt=$(echo "$t1 - $t0" | bc)
  echo "wall=${dt}s" >> "$dir/salida-$(basename "$destino")-${tag}.log"
  log "FIN    $(basename "$destino") [$tag] wall=${dt}s"
}
