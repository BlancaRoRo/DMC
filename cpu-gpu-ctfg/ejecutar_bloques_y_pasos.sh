#!/bin/bash
# Lanza bloques-pequenos y pasos-pequenos en serie (nunca dos corridas a
# la vez, mismo protocolo que el resto de la sesion).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/ejecutar_test_bloques_pequenos.sh"
"$HERE/ejecutar_test_pasos_pequenos.sh"
