#!/usr/bin/env bash
#
# run_test.sh — compila y ejecuta una version del codigo DMC en una copia
# aislada (sandbox), para que la ejecucion nunca sobrescriba los ficheros
# de datos "originales" (conf.*.HH, in.mcv, etc.) del directorio de codigo.
#
# Pensado para ser portable a cualquier version futura del codigo: solo
# necesita un directorio con codigo fuente + un Makefile, y un fichero que
# el binario resultante lea por entrada estandar (stdin).
#
# Uso:
#   scripts/run_test.sh -c <dir_codigo> -f <Makefile> -i <fichero_entrada> [opciones]
#
# Opciones obligatorias:
#   -c DIR     Directorio con el codigo fuente y el Makefile (p.ej. Compilacion-GPU)
#   -f FICH    Nombre del Makefile a usar, relativo a DIR (p.ej. Makefile.gpu)
#   -i FICH    Fichero que se pasa por stdin al binario (p.ej. in.mcv, o una copia
#              modificada para pruebas rapidas)
#
# Opciones opcionales:
#   -b NOMBRE  Nombre del binario que genera el Makefile (por defecto: qmccluster)
#   -o DIR     Directorio raiz donde crear las carpetas de ejecucion aisladas
#              (por defecto: <raiz_repo>/runs)
#   -n TEXTO   Etiqueta para el nombre de la carpeta de esta ejecucion
#   -e "VAR=val"
#              Variable extra para pasar a 'make' (sobreescribe la del
#              Makefile), p.ej. -e "FC=gfortran" si el compilador por
#              defecto del Makefile no esta instalado en esta maquina.
#              Repetible: -e "FC=gfortran" -e "FFLAGS=-O2 -Kieee" para
#              pasar varias variables, incluso con espacios dentro del
#              valor (p.ej. flags compuestas).
#   -p         Purgar (borrar) la carpeta de ejecucion al terminar si todo fue bien
#              (por defecto se conserva, para poder inspeccionar resultados/logs)
#   -h         Muestra esta ayuda
#
# Ejemplos:
#   scripts/run_test.sh -c Compilacion-GPU -f Makefile.gpu -i Compilacion-GPU/in.mcv
#   scripts/run_test.sh -c Original -f Makefile.serie -i Original/in.mcv -e "FC=gfortran"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BINARIO="qmccluster"
RUNS_ROOT="$REPO_ROOT/runs"
ETIQUETA=""
PURGAR=0
EXTRA_MAKE_ARR=()

uso() {
  sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while getopts "c:f:i:b:o:n:e:ph" opt; do
  case "$opt" in
    c) CODE_DIR="$OPTARG" ;;
    f) MAKEFILE="$OPTARG" ;;
    i) INPUT_FILE="$OPTARG" ;;
    b) BINARIO="$OPTARG" ;;
    o) RUNS_ROOT="$OPTARG" ;;
    n) ETIQUETA="$OPTARG" ;;
    e) EXTRA_MAKE_ARR+=("$OPTARG") ;;
    p) PURGAR=1 ;;
    h) uso; exit 0 ;;
    *) uso; exit 1 ;;
  esac
done

if [[ -z "${CODE_DIR:-}" || -z "${MAKEFILE:-}" || -z "${INPUT_FILE:-}" ]]; then
  echo "Error: faltan argumentos obligatorios (-c, -f, -i)." >&2
  uso
  exit 1
fi

if [[ ! -d "$CODE_DIR" ]]; then
  echo "Error: el directorio de codigo '$CODE_DIR' no existe." >&2
  exit 1
fi
CODE_DIR="$(cd "$CODE_DIR" && pwd)"

if [[ ! -f "$CODE_DIR/$MAKEFILE" ]]; then
  echo "Error: no se encuentra '$MAKEFILE' dentro de '$CODE_DIR'." >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: el fichero de entrada '$INPUT_FILE' no existe." >&2
  exit 1
fi
INPUT_FILE="$(cd "$(dirname "$INPUT_FILE")" && pwd)/$(basename "$INPUT_FILE")"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
NOMBRE_CARPETA="${TIMESTAMP}__$(basename "$CODE_DIR")__${MAKEFILE}"
if [[ -n "$ETIQUETA" ]]; then
  NOMBRE_CARPETA="${NOMBRE_CARPETA}__${ETIQUETA}"
fi
SANDBOX="$RUNS_ROOT/$NOMBRE_CARPETA"

mkdir -p "$SANDBOX"

echo "==> Copiando '$CODE_DIR' a la carpeta aislada de ejecucion:"
echo "    $SANDBOX"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude 'runs' --exclude '.git' "$CODE_DIR"/ "$SANDBOX"/
else
  cp -a "$CODE_DIR"/. "$SANDBOX"/
fi

# Se eliminan binario y objetos que pudieran venir ya compilados en el
# directorio de codigo original, para forzar una compilacion 100% limpia
# dentro del sandbox (evita ejecutar por error un binario de una version
# o de un compilador distinto al indicado en -f).
rm -f "$SANDBOX"/*.o "$SANDBOX"/*.mod "$SANDBOX/$BINARIO"

echo "==> Compilando con 'make -f $MAKEFILE ${EXTRA_MAKE_ARR[*]:-}' dentro del sandbox..."
(
  cd "$SANDBOX"
  make -f "$MAKEFILE" "${EXTRA_MAKE_ARR[@]}" clean >/dev/null 2>&1 || true
  make -f "$MAKEFILE" "${EXTRA_MAKE_ARR[@]}"
) > "$SANDBOX/build.log" 2>&1
BUILD_STATUS=$?

if [[ $BUILD_STATUS -ne 0 || ! -x "$SANDBOX/$BINARIO" ]]; then
  echo "!! La compilacion ha fallado (o no genero '$BINARIO')." >&2
  echo "   Revisa el log completo en: $SANDBOX/build.log" >&2
  tail -n 30 "$SANDBOX/build.log" >&2
  exit 1
fi
echo "    Compilacion OK."

echo "==> Ejecutando '$BINARIO' con la entrada:"
echo "    $INPUT_FILE"
set +e
( cd "$SANDBOX" && ./"$BINARIO" < "$INPUT_FILE" > run.log 2>&1 )
RUN_STATUS=$?
set -e

echo
echo "================================================================"
echo " Directorio de codigo (intacto, no modificado): $CODE_DIR"
echo " Carpeta de esta ejecucion (sandbox):            $SANDBOX"
echo " Codigo de salida del binario:                   $RUN_STATUS"
echo "================================================================"
echo
echo "Ultimas lineas de run.log:"
tail -n 20 "$SANDBOX/run.log" || true

if [[ $RUN_STATUS -eq 0 && $PURGAR -eq 1 ]]; then
  echo
  echo "==> -p indicado: borrando el sandbox (la ejecucion fue correcta)."
  rm -rf "$SANDBOX"
fi

exit $RUN_STATUS
