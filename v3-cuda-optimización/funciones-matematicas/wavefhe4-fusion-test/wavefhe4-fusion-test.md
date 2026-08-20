# ¿Es la fusión wavefhe4+derwavefhe4 la causante de la falta de mejora en derananum?

## Hipótesis

`derananum` es, con diferencia, el kernel más caro del pipeline (73,9% del
tiempo total de kernels, ver `v4-cuda-pruebas/prueba2-threads-por-bloque/`).
Dentro de él, la parte que más pesa es el bucle de parejas He4-He4
(`wavef_derwavefhe4`, ~190 pares con `nhe4=20`). Esa función es una fusión
manual de `wavefhe4`+`derwavefhe4` hecha en `optimización-mypow` para
reutilizar `rij`/`log(rij)` una sola vez por par en vez de dos. La duda: al
fusionar dos subrutinas en una sola, ¿puede que ahora haya más variables
vivas a la vez dentro de esa única función, y que eso cueste más registros/
ocupación de lo que ahorra en cómputo evitado?

## Prueba

Copia aislada de producción (`gpu-sin-fusion/`), un solo cambio en
`derananum_mod.cuf`:

```fortran
! antes (produccion):
call wavef_derwavefhe4(atom(1:nhe4), wfhe4, d1wfhe4, d2wfhe4)

! prueba:
call wavefhe4(atom(1:nhe4), wfhe4)
call derwavefhe4(atom(1:nhe4), d1wfhe4, d2wfhe4)
```

`wavefhe4`/`derwavefhe4` (las versiones sin fusionar) ya estaban en
`der_wavefhe4_mod.cuf`, intactas como referencia -- no hizo falta escribir
nada nuevo, solo cambiar la llamada. `gpu-fusion/` es una copia sin tocar de
producción, para comparar contra el mismo binario en las mismas condiciones.

## Resultado: negativo -- la fusión no es el problema

**Registros** (`ncu --metrics launch__registers_per_thread` sobre
`k_derananum_t`, 2000 walkers): **126 en ambos casos, sin ninguna
diferencia.** La fusión no le cuesta ni un registro a la ocupación.

**Físca**: energía final bit a bit idéntica en ambas variantes
(`-676.2974256246 meV`, 2000 walkers, semilla 11) -- confirma que
deshacer la fusión es exactamente equivalente, como ya se había verificado
al fusionar.

**Tiempo real** (2000w, 1+59 bloques x 20 pasos = 1200 pasos, 2 rondas
alternas para controlar deriva térmica):

| Ronda | Fusionado (producción) | Sin fusionar |
|---|---|---|
| 1 | 59,08 s | 58,94 s |
| 2 | 55,95 s | 60,40 s |
| Media | 57,51 s | 59,67 s |

La diferencia media (~3,8%) es del mismo orden que la dispersión DENTRO de
cada variante entre sus 2 rondas (fusionado: 55,95-59,08 s, ~5,6% de
dispersión) -- es decir, está dentro del ruido térmico ya caracterizado en
esta sesión (`myexp-optimizacion.md`), no una diferencia real y repetible.

## Conclusión

La fusión `wavef_derwavefhe4` **no** es la causante de que `derananum` siga
siendo el cuello de botella dominante. Los registros son idénticos (126=126)
-- la razón más fuerte para descartarlo, ya que es una propiedad de
compilación, no depende de una sola medida de tiempo con posible ruido. Se
mantiene la fusión en producción (es una mejora real y verificada de
`optimización-mypow`, no se toca). El cuello de botella de `derananum` sigue
siendo el ya identificado: tamaño de grid insuficiente (`waves per SM =
0,33`), no presión de registros dentro de esta función.

## Ficheros

- `gpu-fusion/`: **eliminada** -- era una copia sin modificar de
  producción (referencia), nada que editar que conservar.
- `gpu-sin-fusion/`: **recortada** a `derananum_mod.cuf` (la llamada
  desfusionada, la prueba en sí), `in.mcv`, `tiempos_opcion7.dat`.
- `compilar_sin_fusion.sh`: referencia de qué `FILES` se usaban.
