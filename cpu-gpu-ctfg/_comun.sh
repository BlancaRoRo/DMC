# _comun.sh -- funciones y rutas compartidas de esta bateria. No se
# ejecuta solo, se hace "source" desde el script principal.
#
# Reutiliza los binarios y la Configuracion Inicial de
# v4-cuda-pruebas/pruebas-sfu (misma fuente de verdad, sin duplicar
# ficheros de configuracion).
GPU_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion/hibrido_instrumentado"
CPU_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion/cpu-original-gfortran"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
SFU_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v4-cuda-pruebas/pruebas-sfu"
PLANTILLA="$SFU_DIR/_plantillas/in.mcv.base"
HEH2M="$SFU_DIR/_plantillas/heh2m.pot"
GENERA_INMCV="$SFU_DIR/genera_inmcv.py"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# correr(destino_dir, tag, opcion, binario_src, nombre_binario, walkers, bloq_calc, pasos)
correr() {
  local destino="$1" tag="$2" opcion="$3" binario_src="$4" binario_nombre="$5" walkers="$6" bloq_calc="$7" pasos="$8"
  local dir="$destino"
  mkdir -p "$dir"
  cp "$binario_src" "$dir/${binario_nombre}"
  cp "$HEH2M" "$dir/heh2m.pot"
  python3 "$GENERA_INMCV" "$PLANTILLA" "$dir/in.mcv-${tag}" "$opcion" "$walkers" 1 "$bloq_calc" "$pasos"
  cp "$CONF_FRESCO" "$dir/conf.20.00.HH"

  log "INICIO $(basename "$destino") [$tag] w=$walkers bloq=$bloq_calc pasos=$pasos"
  local t0 t1 dt rc
  t0=$(date +%s.%N)
  set +e
  (cd "$dir" && ./"${binario_nombre}" < "in.mcv-${tag}" > "salida-$(basename "$destino")-${tag}.log" 2>&1)
  rc=$?
  set -e
  t1=$(date +%s.%N)
  dt=$(echo "$t1 - $t0" | bc)
  echo "wall=${dt}s rc=${rc}" >> "$dir/salida-$(basename "$destino")-${tag}.log"
  if [ "$rc" -ne 0 ]; then
    log "FALLO  $(basename "$destino") [$tag] wall=${dt}s rc=${rc} -- ver $dir/salida-$(basename "$destino")-${tag}.log"
  else
    log "FIN    $(basename "$destino") [$tag] wall=${dt}s"
  fi
  return 0
}
