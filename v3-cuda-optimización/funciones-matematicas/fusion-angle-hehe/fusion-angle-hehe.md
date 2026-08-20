# Fusión de `angle` con `vec_norm`+`scalar_product` en `He_dihydrogen`

## Objetivo

Investigando por qué `vpot_t`/`He_dihydrogen` escala peor de lo lineal en
3000 walkers (ver `derananum-split-concurrente.md`), se preguntó si
`v_hehe`/`vp_hehe`/`angle`/`scalar_product`/`vec_norm` se podían paralelizar
como se hizo con `derananum`. No se puede: son subrutinas
`attributes(host,device)` normales (no kernels `attributes(global)`), y en
CUDA Fortran no se puede lanzar un kernel desde dentro de otro -- solo el
host puede lanzar kernels con `<<<...>>>`. Además, `angle` no es
independiente de `vec_norm`/`scalar_product`: comparte cálculo con ellas,
como se documenta abajo.

Mirando el código para responder esa pregunta se encontró algo distinto y
mejor: **trabajo duplicado de verdad**, no un problema de paralelismo.

## La redundancia (He_dihydrogen.f líneas 379-384)

```fortran
       call vec_norm(rvec,rnorm)                    ! linea 379
       call vec_norm(orHH(:,1),onorm)                ! linea 380
       call angle (rvec,orHH(:,1),theta)              ! linea 381
       call scalar_product(rvec,orHH(:,1),ror)        ! linea 382
       fi=ror/(rnorm*onorm)                           ! linea 383
```

`angle(vec1,vec2,ang)` (`angle_scalar_vec_mod.cuf:8-27`) calcula por dentro,
desde cero, exactamente las mismas 3 cantidades que ya se han calculado por
separado justo antes:

```fortran
attributes(host, device) subroutine angle(vec1, vec2, ang)
    ...
    do id=1,3
        x1=vec1(id)
        x2=vec2(id)
        sprod=sprod+x1*x2      ! = scalar_product(rvec,orHH(:,1),ror) -- MISMO calculo
        norm1=norm1+x1*x1      ! = vec_norm(rvec,rnorm)**2            -- MISMO calculo
        norm2=norm2+x2*x2      ! = vec_norm(orHH(:,1),onorm)**2       -- MISMO calculo
    end do
    norm1=dsqrt(norm1)
    norm2=dsqrt(norm2)
    ang=myacos(sprod/(norm1*norm2))
end subroutine angle
```

`angle` recibe los MISMOS `rvec`/`orHH(:,1)` que las llamadas de al lado, así
que `sprod=ror`, `norm1=rnorm`, `norm2=onorm` -- son las mismas 3 cantidades,
solo con otro nombre local. Y `fi=ror/(rnorm*onorm)` (línea 383, ya se
calcula de todas formas para lo que viene después) es matemáticamente
idéntico al argumento que `angle` le pasa a `myacos` por dentro
(`sprod/(norm1*norm2)`).

Es decir: se ejecutan 2 bucles de 3 iteraciones + 2 `dsqrt` (dentro de
`angle`) que ya se habían ejecutado justo antes (en `vec_norm`×2 +
`scalar_product`), solo para poder llamar a `myacos`.

`theta` (la salida de `angle`) sí se usa después (línea 281 de
`He_dihydrogen.f`, en `mycos(theta)`/`mysin(theta)` dentro de la fórmula del
potencial) -- no es código muerto, es trabajo genuinamente duplicado.

## El cambio

Sustituir la llamada a `angle` por una llamada directa a `myacos` sobre el
`fi` que ya se calcula, reordenando para que `fi` esté listo antes:

```fortran
! ANTES:
       call vec_norm(rvec,rnorm)
       call vec_norm(orHH(:,1),onorm)
       call angle (rvec,orHH(:,1),theta)
       call scalar_product(rvec,orHH(:,1),ror)
       fi=ror/(rnorm*onorm)

! DESPUES:
       call vec_norm(rvec,rnorm)
       call vec_norm(orHH(:,1),onorm)
       call scalar_product(rvec,orHH(:,1),ror)
       fi=ror/(rnorm*onorm)
       theta=myacos(fi)
```

Cambios de imports en la cabecera de `He_dihydrogen` (línea 259):
`use angle_scalar_vec, only: angle, scalar_product, vec_norm` pierde
`angle` (ya no se llama) y se añade `use glibc_acos_mod, only: myacos`.

Mismo resultado bit a bit esperado: `fi` y `sprod/(norm1*norm2)` son la
misma expresión matemática con los mismos valores de entrada -- no cambia
qué se calcula, solo se deja de recalcular 2 veces.

## Verificación

- Compilar en copia aislada (`gpu-fusion-angle/`), verificar energía final
  bit a bit idéntica a producción sin tocar (2000w, semilla 11, conf
  restaurado antes de la corrida).
- Medir registros de `He_dihydrogen` (`cuobjdump --dump-resource-usage`)
  antes/después -- comprobar si eliminar el bucle+sqrt duplicado libera
  algo, aunque el objetivo principal es el ahorro de cómputo, no de
  registros.
- Medir tiempo real (rondas alternas, conf restaurado) a 2000w.

## Resultado: neutro/negativo -- no se lleva a producción

Verificado bit a bit correcto (`-676.2974256246 meV`, 2000w, semilla 11,
idéntico a producción en las 4 corridas de la comparación).

**Registros de `He_dihydrogen`**: contrario a lo esperado, **suben**, no
bajan -- de 106 a **136** (`cuobjdump --dump-resource-usage`). Eliminar la
llamada indirecta a `angle()` (que tenía su propia ventana de registros
como función separada) y llamar a `myacos` directamente desde
`He_dihydrogen` aumenta la presión de registros de `He_dihydrogen` en vez
de reducirla -- el ahorro de cómputo (2 raíces cuadradas + 2 bucles de 3
iteraciones menos) no se traduce en menos registros porque el patrón de
llamada cambia de forma que el compilador no esperaba.

**Tiempo real** (2000w, 2 rondas alternas para controlar deriva térmica):

| Ronda | Producción | Fusión angle |
|---|---|---|
| 1 | 59,10 s | 58,02 s |
| 2 | 56,89 s | 57,92 s |
| **Media** | **57,995 s** | **57,97 s** |

Diferencia de medias: **0,04%** -- dentro del ruido térmico ya
caracterizado en esta sesión, no una mejora real y repetible (de hecho el
orden se invierte entre rondas: en la 1 gana la fusión, en la 2 gana
producción).

## Por qué suben los registros (verificado, no solo hipótesis)

Primera hipótesis (razonable pero incorrecta, comprobada y descartada):
que `myacos` pasara de llamada aparte a inlinearse dentro de
`He_dihydrogen` al quitar la indirección de `angle()`. Se comprobó
contando las llamadas reales (`CALL.ABS.NOINC`) en el SASS
(`cuobjdump --dump-sass`) dentro de la función `He_dihydrogen`:

| | Llamadas reales (`CALL.ABS.NOINC`) | Tamaño de la función (líneas SASS) |
|---|---|---|
| Producción | 65 | 3.380 |
| Fusión angle | 66 | 3.524 |

El número de llamadas es prácticamente el mismo (65→66: se quita 1
llamada a `angle`, se añade 1 a `myacos`, mismo balance) -- **no es un
cambio de inlining**. La función creció ~150 líneas sin añadir llamadas.

**Explicación real**: el orden de las operaciones cambió (antes:
`vec_norm, vec_norm, angle, scalar_product, fi=...` -- después:
`vec_norm, vec_norm, scalar_product, fi=..., myacos(fi)`). Aunque el
trabajo total es menor, el nuevo orden hace que más variables locales
coincidan vivas a la vez en algún punto del código (el asignador de
registros necesita tantos registros como el momento de mayor
solapamiento de rangos de vida, no como el volumen total de trabajo -- ver
`derananum-split-concurrente.md` para la explicación completa de "pico,
no suma"). No es predecible mirando el código a simple vista, solo
midiendo -- la hipótesis inicial (inlining) se comprobó y se descartó en
vez de darse por buena, mismo criterio de todo el árbol.

## Conclusión

Aunque la redundancia de cómputo es real y está bien identificada (mismo
`sprod`/`norm1`/`norm2` calculados dos veces), eliminarla **no se traduce
en una mejora medible** -- el aumento de presión de registros en
`He_dihydrogen` (106→136) parece compensar exactamente el ahorro de
cómputo conseguido. Se descarta, no se lleva a producción. Queda como
lección: "menos trabajo aritmético" no garantiza "más rápido" si cambia el
patrón de registros -- mismo principio ya visto con el cambio (b) de
`myexp-optimizacion.md` (Parte 9.6), aunque aquí sin la magnitud de aquel
caso (esto es neutro, no una regresión del 40%).

## Ficheros

- `gpu-fusion-angle/`: **recortada** a `He_dihydrogen.f` (el cambio,
  llamada a `angle` sustituida por `myacos(fi)` directo), `in.mcv` y
  `tiempos_opcion7.dat` -- ya no es copia completa.
- `compilar_fusion_angle.sh`: referencia de qué `FILES` se usaban.
