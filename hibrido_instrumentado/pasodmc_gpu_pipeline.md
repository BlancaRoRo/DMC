# `pasodmc_gpu_pipeline`: qué hace, cómo, y por qué

Documento de referencia (no de investigación) para entender la subrutina que procesa
**un paso DMC completo** en la vía de producción (`opcion=7`). Definida en
`msteps.f90:310-591`, llamada una vez por cada `ipaso` desde `mmontecarlo.f90:235`.

Escrito para alguien que conoce lo básico de CUDA (unidades de paralelización,
niveles de memoria) pero no los mecanismos concretos que usa este pipeline —
streams, eventos, CUDA Graphs. Si ya los conoces, salta directamente al
["Recorrido paso a paso"](#recorrido-paso-a-paso).

## Panorama general

La CPU actúa como "jefe de obra": organiza el trabajo, decide qué walkers viven o
mueren, lleva la contabilidad — y en el momento del cálculo físico pesado, se lo
manda entero a la GPU, espera, y recoge el resultado. Cada llamada a esta subrutina
es "un paso" de ese ciclo.

## Conceptos CUDA que aparecen en este documento

- **Kernel**: una función que se lanza para correr en muchísimos hilos a la vez en la
  GPU (`attributes(global)`). Se lanza una vez; la GPU la ejecuta simultáneamente en,
  por ejemplo, 4.000 hilos, cada uno con su propio índice.
- **Función `host`/`device`**: una función normal de CPU es `attributes(host)`. Una
  que un kernel puede llamar desde dentro (corre en GPU) es `attributes(device)`.
  Algunas están marcadas `attributes(host, device)` — el compilador genera dos
  versiones, mismo código fuente, una para cada lado (caso de `myexp`, `V_hehe`,
  `rand1p_gpu`... — así se pueden probar también desde CPU).
- **Stream**: una "cola" de trabajo en la GPU. Lo que se mete en la misma cola se
  ejecuta en orden. Lo que se mete en colas *distintas* puede solaparse — así corren
  a la vez `derananum` y `vpot`.
- **Evento (`cudaEvent`)**: una marca que permite decir "esta cola, espera aquí a que
  esa otra cola llegue a este punto" — sincronización entre streams sin bloquear toda
  la GPU.
- **CUDA Graph**: en vez de lanzar 8 kernels uno a uno en cada paso (pagando el coste
  de "pedir turno" 8 veces, cada vez), se graba la secuencia completa **una sola
  vez** y se relanza entera de golpe — mucho más barato que 8 lanzamientos sueltos
  repetidos miles de veces.
- **H2D / D2H**: copiar datos de CPU a GPU (*host to device*) y de vuelta (*device to
  host*) — el puente entre los dos mundos, con un coste real cada vez que se cruza.

## Recorrido paso a paso

### 1. Sincroniza `etrial`

```fortran
call sincroniza_etrial_gpu   ! msync_gpu.cuf:136
```

De las 25 constantes físicas de la simulación, `etrial` (la energía de prueba) es la
**única** que cambia paso a paso — es el mecanismo de control de población (paso 11).
Se copia a GPU en cada paso, sola. Las otras 24 no se tocan aquí.

### 2. Inicialización — solo la primera vez que se llama

```fortran
if (.not.iniciado) then
  call sincroniza_constantes_gpu    ! msync_gpu.cuf:104
  call sacasemilla(irnmaster)       ! mrandom.f90:56
  call k_split_seeds<<<blocks,threads>>>(...)   ! rand_gpu.cuf:171
  call inicializa_pipeline(2*nwalkers)          ! dmc2_pipeline.cuf:142
  ! + empaqueta hb2m/b una sola vez
  iniciado = .true.
endif
```

Todo lo que **no cambia durante la corrida** se prepara una sola vez:

- **`sincroniza_constantes_gpu`**: sube las otras 24 constantes físicas a memoria
  global de GPU.
- **`sacasemilla` + `k_split_seeds`**: cada walker necesita su propia semilla,
  independiente de las demás. `sacasemilla` saca una semilla maestra; `k_split_seeds`
  es un kernel — un hilo por walker, cada uno avanza la semilla maestra un número
  distinto de veces (el mecanismo del fix `iw-1`, ver
  `v3-cuda-optimización/correccion-fisica/alineacion-semilla-walker1/`).
- **`inicializa_pipeline`**: reserva en memoria global de `device` todos los arrays
  que van a vivir toda la corrida, crea streams y eventos, fija el heap de `device` a
  512MB, y **graba el CUDA Graph** — ejecuta la secuencia de 8 fases una vez en modo
  "captura" en vez de "ejecuta de verdad", y CUDA la guarda como plantilla
  reutilizable.
- **`hb2m`/`b`**: constantes por átomo que no cambian nunca, se suben una sola vez.

### 3. Empaquetar `wsim` → arrays SoA (`msteps.f90:399-413`)

```fortran
do iwalker = 1, nwpaso
  do iatom = 1, natom
    atom_h(iwalker,iatom) = wsim(iwalker)%atom(iatom)
    ...
```

**No es una transposición** — es una conversión de formato: de *array-of-structs*
(`wsim`, cada walker es un bloque de datos junto) a *structs-of-arrays* (`atom_h`,
`sprop_h`... todos los `atom` de todos los walkers seguidos). A partir de aquí,
**`wsim` deja de tocarse en todo el camino hacia la GPU** — ni los kernels ni
`lanza_pipeline` saben que `wsim` existe, solo conocen `atom_p`, `sprop_p`, etc.
`wsim` solo reaparece en el paso 8 (desempaquetar) y el 9 (reparto), CPU puro.

### 4. Copia H2D (`msteps.f90:415-422`)

```fortran
atom_p(1:nwpaso,:) = atom_h; sprop_p(1:nwpaso,:) = sprop_h
```

Sube los arrays ya reordenados a los buffers de `device`. Cruce CPU→GPU número uno.

**¿Por qué no fusionar los pasos 3 y 4 y escribir directamente en `atom_p` desde el
bucle, ahorrándose `atom_h`?** Sale más caro, no más barato — ver la sección
["Por qué no fusionar `pack` y `H2D`"](#por-qué-no-fusionar-pack-y-h2d) más abajo.

### 5. Snapshot forense de entrada — condicional (`msteps.f90:427-458`)

```fortran
if (.not. volcado_hecho) then
  if (allocated(dump_atom)) deallocate(dump_atom, ...)
  allocate(dump_atom(nwpaso,natom), ...)
  dump_atom = atom_h; dump_sprop = sprop_h
  ...
endif
```

`dump_atom`, `dump_sprop`... **no son variables de GPU** — son arrays normales de
CPU (sin atributo `device`), y esta copia es puramente CPU↔CPU, no toca la GPU.

`volcado_hecho` empieza en `.false.` y solo pasa a `.true.` cuando el volcado se
escribe **a disco de verdad** (paso 10). Así que este bloque corre en **todos** los
pasos de toda la corrida mientras no haya habido un colapso — no es puntual. Es una
foto de seguridad barata: en cada paso, antes de lanzar la GPU, guarda en RAM (no en
disco) "así estaban las cosas justo antes de este paso". La siguiente llamada
**sobrescribe** la foto anterior — nunca se acumulan fotos de pasos previos, solo
existe la del último paso procesado.

**¿Por qué el `deallocate`+`allocate` en cada paso?** Porque `nwpaso` (cuántos
walkers hay) cambia cada paso — la población crece y mengua con las muertes/clones.
Fortran no permite redimensionar un `allocatable` con una `allocate` directa si ya
tenía otro tamaño reservado — hay que liberarlo primero. El `if (allocated(...))`
es solo para no intentar liberar algo que nunca se reservó (la primerísima llamada).

**Contraste importante con los arrays de GPU del paso 2**: esos se reservan **una
sola vez**, al tamaño **máximo** (`2*nwalkers`), y nunca se tocan de tamaño otra vez
— por el CUDA Graph: el grafo graba direcciones de memoria concretas; si esos arrays
cambiaran de tamaño/sitio cada paso, el grafo grabado dejaría de ser válido. Por eso
se reserva de golpe al máximo que jamás hará falta, y `nw_actual` es solo un contador
que dice "de estos huecos reservados, usa solo los primeros N", sin mover nada de
sitio. `dump_*` no tiene esa restricción (nada depende de que su dirección se
mantenga fija entre llamadas), así que redimensionar exacto cada vez es más simple y
no tiene coste oculto.

### 6. Lanza el grafo CUDA — el corazón del paso

```fortran
call lanza_pipeline(nwpaso)   ! dmc2_pipeline.cuf:279
```

Fija `nw_actual` y hace `cudaGraphLaunch` — reproduce las 8 fases grabadas:

1. **`k_fase_a`**: preparación inicial por walker.
2. **La horquilla**: `k_derananum_he4_t` + `k_derananum_resto_t` (streams `a`/`c`)
   corren **a la vez** que `k_vpot_t` (stream `b`) — cinética y potencial en
   paralelo. Un evento avisa a `k_derananum_join_t` cuando `resto_t` termina, para
   combinar los resultados parciales.
3. **Fases c-g**: pasos más pequeños del método Metropolis/DMC.
4. **`k_fase_h`**: acumula los histogramas de densidad, pesando cada walker por
   `nsons` — ver `v3-cuda-optimización/arquitectura-lanzamiento/fase3-arquitecturas-alternativas/prueba_denssumapaso/prueba_denssumapaso.md`.

### 7. Copia D2H (`msteps.f90:466-474`)

Trae de vuelta posiciones/propiedades actualizadas, energías (`kin`, `pot`, `eimp`,
`erot`...), y sobre todo `nsons` — cuántas copias produce cada walker (0 = muere).
Cruce GPU→CPU número uno.

### 8. Desempaquetar de vuelta en `wsim` (`msteps.f90:476-492`)

El inverso exacto del paso 3, en CPU.

### 9. Reparto / compactación de población (`msteps.f90:494-541`)

Todo CPU, secuencial, sin GPU de por medio: los walkers que sobreviven (`nsons>0`)
se compactan al principio del array; cada copia extra hereda el estado de su padre
pero **decorrela su semilla** con `rand1p_gpu` (`attributes(host,device)` — la misma
función que usa `k_split_seeds`, aquí llamada desde CPU) — el fix que evitó que
clones compartieran trayectoria y colapsaran la población entera.

### 10. Corte de emergencia — condicional (`msteps.f90:556-573`)

Si `nwfin==0` (todos murieron), en vez de dejar que `log(0)` propague
`NaN`/`Inf` en silencio: **aquí** es donde el snapshot mantenido en RAM desde el
paso 5 se escribe **a disco de verdad** (`open`/`write`/`close` en
`snapshot_colapso.dat`), y el programa para con `stop 1`.

El diseño en dos fases (RAM cada paso, disco solo si hace falta) es puro coste: 
escribir a disco 50.000 veces sería carísimo cuando el 99,99% de los pasos nunca
colapsan. `dump_*` no es una variable que "verifique" nada activamente — es evidencia
que se preserva por si acaso, para poder investigar offline con `driver_replay.f90`
si algún día hace falta.

### 11. Calcula `egrow`, realimenta `etrial` (`msteps.f90:575-584`)

```fortran
egrow = etrial - log(nwnew/nwold)/dtau
```

La señal de si la población crece o mengua. Cada `ncetrial` pasos, `etrial` se ajusta
con la media acumulada (`segrow`) — el control de población que mantiene el tamaño
estable, y lo que se sube a GPU en el paso 1 del siguiente paso.

### 12. `nwpaso = nwfin` (`msteps.f90:586`)

Última línea: actualiza la variable de CPU que recibió la llamada
(`intent(inout)`), para que quien la llamó (`mmontecarlo.f90`) vea el nuevo recuento
sin bajar nada más — la bajada ya ocurrió en el paso 7, esto solo lee un valor de
CPU ya al día.

## Cómo funciona la captura del CUDA Graph: `inicializa_pipeline` vs `lanza_pipeline`

Es fácil leer el paso 2 (inicialización) y el paso 6 (lanzamiento) como si ambos
"llamaran a los kernels" — pero solo uno de los dos lo hace de verdad, y conviene
entender por qué.

### El "modo captura" es un estado del *stream*, no del código

```fortran
istat = cudaStreamBeginCapture(stream_a, cudaStreamCaptureModeGlobal)  ! dmc2_pipeline.cuf:206
call k_fase_a<<<blocks,threads,0,stream_a>>>(...)
call k_derananum_he4_t<<<blocks,threads,0,stream_a>>>(...)
... (las 8 fases) ...
istat = cudaStreamEndCapture(stream_a, pipeline_graph)                 ! dmc2_pipeline.cuf:266
istat = cudaGraphInstantiate(pipeline_graph_exec, pipeline_graph, 0_8) ! dmc2_pipeline.cuf:268
```

`cudaStreamBeginCapture` no cambia nada en el código Fortran — cambia el **estado
interno** que CUDA lleva sobre ese `stream` concreto, a nivel de driver. Desde ahí
hasta `cudaStreamEndCapture`, cualquier cosa que se mande a ese stream (lanzar un
kernel, una copia, un evento) el driver la **intercepta**: en vez de ejecutarla de
verdad en la GPU, la anota como un nodo del grafo que está construyendo, y devuelve
el control al programa inmediatamente, como si el lanzamiento hubiera ocurrido —
pero sin que ocurra nada real. Por eso no importa que `atom_p` esté vacío/con
basura en ese momento: **ningún cálculo real pasa durante la captura**, solo se
graba la forma (qué kernels, en qué orden, con qué parámetros), no el contenido.

La misma línea de código (`call k_fase_a<<<...>>>(...)`) se comporta distinto según
si el stream está "en modo captura" o no — el código no cambia, cambia lo que el
driver hace con él.

### `inicializa_pipeline`: las llamadas a kernel aparecen aquí, una sola vez

Todo el bloque de arriba vive dentro de `inicializa_pipeline`
(`dmc2_pipeline.cuf:142-272`), que se ejecuta **una sola vez**, la primera vez que
se llama a `pasodmc_gpu_pipeline` en toda la corrida (paso 2 del recorrido). Las
llamadas reales a los 8 kernels están escritas **una única vez en todo el fichero
fuente**, aquí dentro.

### `lanza_pipeline`: no vuelve a tocar esas líneas

```fortran
attributes(host) subroutine lanza_pipeline(nwpaso_actual)   ! dmc2_pipeline.cuf:279
   nw_actual = nwpaso_actual
   istat = cudaGraphLaunch(pipeline_graph_exec, stream_a)
end subroutine lanza_pipeline
```

Esto es **todo** el cuerpo de `lanza_pipeline` (la que se llama en el paso 6, en
cada paso DMC). No contiene ninguna llamada a kernel. `cudaGraphLaunch` no vuelve a
pasar por las líneas Fortran de `k_fase_a<<<...>>>` — reproduce directamente el
**objeto grafo** (`pipeline_graph_exec`) ya grabado y validado, a nivel de
driver/GPU, sin volver a tocar el código fuente en absoluto.

### Por qué merece la pena

Cada `call kernel<<<...>>>(...)` normal, aunque el kernel corra en GPU, tiene un
coste real **en la CPU**: el driver valida parámetros, resuelve direcciones, monta
la orden de lanzamiento — trabajo que se repite en cada llamada. Con 8 kernels por
paso, son 8 "papeleos" de lanzamiento, en cada uno de miles de pasos. Con el grafo,
todo ese papeleo se hace **una sola vez**, durante la captura +
`cudaGraphInstantiate` (que valida y prepara el grafo entero de golpe). Lo que
queda después es un objeto ligero ya validado — relanzarlo con `cudaGraphLaunch`
es mucho más barato que repetir 8 papeleos sueltos, paso tras paso. Mismo principio
que "una copia H2D grande en vez de miles pequeñas" (ver más abajo): concentrar el
coste fijo en un solo sitio, una sola vez, en vez de repartirlo y repetirlo.

## Por qué `k_derananum_join_t` tiene que ser su propio kernel

`k_derananum_join_t` (`derananum_split_mod.cuf:146-247`) es el tercer kernel de la
horquilla del split de `derananum`: lee los resultados que dejaron
`k_derananum_he4_t` y `k_derananum_resto_t` en arrays globales persistentes
(`wfhe4_s`, `d1wfhe4_s`... de la pieza He4; `wfhe3_s`, `wfm_s`, `wfx_s`... de la
pieza "resto"), y los combina en el resultado final: `wf = wfhe4*wfhe3*wfm*wfx`,
más la energía cinética, que incluye **términos cruzados** entre las derivadas de
las dos piezas (`2*dot_product(d1wfhe4, d1wfm)`, etc. — términos que no existen en
ninguna pieza por separado, solo aparecen al combinarlas).

**¿Por qué no evitar el kernel aparte y que cada pieza vaya escribiendo/sumando
directamente en el resultado final, ya que todo vive en memoria global?**

Que algo sea memoria **global** solo dice **quién puede verlo** (cualquier kernel,
en teoría) — no dice **cuándo es seguro leerlo**. `he4_t` y `resto_t` corren **a la
vez**, en streams distintos, sin ningún orden garantizado entre ellos. Si uno
intentara leer lo que el otro escribe mientras ambos siguen corriendo
concurrentemente, no hay ninguna garantía de que el otro ya haya terminado de
escribir — podría leer un valor a medio calcular. La "globalidad" del array no
resuelve ese problema de visibilidad entre kernels concurrentes; hace falta un
punto de sincronización explícito (el evento `ev_resto1`/`ev_resto2`), y ese aviso
solo se puede consumir **entre lanzamientos de kernel**, no dentro de uno que ya
está corriendo — de ahí que haga falta un kernel nuevo, lanzado *después* de que el
evento confirme que ambas piezas han terminado.

Y aunque se pudiera garantizar el orden de escritura: `wf` es un **producto**, no
una suma — no hay forma de "ir acumulando" un producto con `atomicAdd` como se
haría con una suma. Y el término cruzado de la cinética necesita **las dos piezas a
la vez** para calcularse, venga el dato de donde venga. Así que incluso sin el
problema de sincronización, seguiría haciendo falta un paso que tenga ambos
resultados delante al mismo tiempo — y para que ese paso viva dentro del grafo
capturado sin salir a CPU, tiene que ser un kernel propio.

## Nota: el reseteo de histogramas dentro de `inicializa_pipeline`

`inicializa_pipeline` reserva los 12 arrays de histogramas (`allocate`,
`dmc2_pipeline.cuf:187-190`) y **justo después** llama a `resetea_histogramas_gpu`
(línea 191) — antes de que empiece la captura del grafo (línea 206). Es necesario
porque la memoria de `device` recién reservada **no viene garantizada a cero** —
puede contener basura de lo que hubiera antes en esa región de memoria de la
tarjeta.

Esto plantea una duda real: `mmontecarlo.f90:230` **también** llama a
`resetea_histogramas_gpu`, una vez al empezar cada bloque, **antes** de que
`pasodmc_gpu_pipeline` (y por tanto `inicializa_pipeline`) se ejecute por primera
vez dentro de ese bloque. En el bloque 1 de toda la corrida, eso significa intentar
resetear arrays `device, allocatable` que **todavía no se han reservado**.

Verificado con una prueba mínima aparte (asignar a un array `device, allocatable`
sin haberlo reservado con `nvfortran`): **no falla** — un array sin reservar tiene
tamaño 0, así que la asignación de array completo recorre cero elementos y no hace
nada, sin error. Así que:

- El reseteo de `mmontecarlo.f90:230` en el **bloque 1** es un no-op inofensivo (los
  histogramas aún no existen).
- El reseteo dentro de `inicializa_pipeline` (línea 191) es el que de verdad limpia
  la basura inicial, justo después de reservar.
- Desde el **bloque 2** en adelante, el reseteo de `mmontecarlo.f90:230` ya actúa de
  verdad — los histogramas ya están reservados desde el bloque anterior.

No hay redundancia peligrosa ni bug: son dos reseteos con propósitos distintos
(limpiar basura tras `allocate`, y separar los datos de un bloque del siguiente)
que dan la casualidad de solaparse, sin coste, solo en el primerísimo bloque.

## Por qué no fusionar `pack` y `H2D`

Medido en `v3-cuda-optimización/perfilado-medicion/fase2-medicion-mejoras/aos-to-soa.md`
(réplica fiel del bucle real, 3.000 walkers):

| | pack (el bucle, paso 3) | H2D (la copia, paso 4) |
|---|---|---|
| `atom`+`sprop`+`dwf`+`dphi`+`wf`+`kin`+`pot`+`ene` | 3,975 ms | 1,114 ms |

El bucle de `pack` corre entero en CPU, sin tocar la GPU, y al final se hace **una
sola copia de golpe** que el compilador convierte en una única `cudaMemcpy` por
array — de ahí que el H2D de *todos* los walkers juntos cueste solo 1,114 ms.

Si en vez de eso cada asignación del bucle escribiera directamente en un array
`device` (`atom_p(iwalker,iatom) = wsim(iwalker)%atom(iatom)`), cada una de las
~63.000 asignaciones (3.000 walkers × 21 átomos, solo para `atom`) dispararía **su
propia transferencia GPU individual** — miles de transferencias diminutas, cada una
pagando el coste fijo de cruzar el puente CPU-GPU, en vez de una transferencia
grande que lo paga una sola vez. Mismo principio que `vuelca_histogramas_gpu`: la
ganancia está en juntar todo en una copia, no en repartirla.

Por el mismo motivo, sacar los valores de `dump_*` de `atom_p` (GPU) en vez de
`atom_h` (CPU) sería peor, no mejor: añadiría una transferencia D2H completamente
innecesaria para traer de vuelta un dato que ya está delante, en CPU, sin haber
salido de ahí.

El coste real del `pack` (3,975 ms) no viene de "tener una variable intermedia" —
viene de la propia reorganización (leer campos dispersos de 3.000 *structs* y
ordenarlos en arrays planos), trabajo que hay que hacer sí o sí, esté el destino en
CPU o en GPU. `aos-to-soa.md` ya atacó el coste real de esta zona, pero por el otro
lado: quitando del `pack`/H2D los datos que no hacía falta mover en absoluto
(`hb2m`/`b`, que no cambian nunca; `wfhe4`/`wfhe3`/`wfm`/`wfx`, que nadie lee) — no
fusionando `pack` y H2D, que habría ido en la dirección que empeora.

## Gestión de semillas: `irn` vs `rn`, `sacasemilla`, `k_split_seeds`

### `irn` es el estado; `rn` es un número de usar y tirar

`rand1_gpu`/`rand1p_gpu` (`rand_gpu.cuf`) son generadores pseudoaleatorios tipo
**LCG** (*Linear Congruential Generator*) de 48 bits. Cada llamada hace dos cosas,
en este orden:

1. **Avanza el estado**: `irn` se transforma con una fórmula fija (multiplicar,
   sumar, quedarse con 48 bits) — da el siguiente estado, distinto del anterior.
2. **Lee ese nuevo estado como un real**: `rn = ior(irn,1_i8) * 2^-48`.

`irn` es lo que hay que **conservar** entre llamadas (`intent(inout)`) — es el
"estado de la máquina" necesario para seguir generando números en el futuro. `rn`
es un número de usar y tirar (`intent(out)`), derivado del `irn` ya avanzado — se
consume ahí mismo y no hace falta guardarlo para nada.

### `sacasemilla`: solo lee el estado actual, no lo avanza

```fortran
integer(kind=i8), private, save :: irn = 1_i8   ! mrandom.f90:10, unico estado en toda la CPU
subroutine sacasemilla(irnout)
  irnout = irn   ! copia, no avanza
end subroutine
```

`irn` aquí es la variable de módulo del lado CPU — el único estado de RNG que usa
todo el código original en su bucle secuencial de walkers. `sacasemilla` copia su
valor actual (`irnmaster`, dentro de `pasodmc_gpu_pipeline`), sin tocarlo.

### `k_split_seeds`: usa `irn`, descarta `rn` a propósito

```fortran
irn = irnin
do i = 1, iw-1
  call rand1p_gpu(rn, irn)   ! rn se calcula pero se tira en cada vuelta
enddo
seeds(iw) = irn               ! solo se guarda el ESTADO final
```

No genera un número aleatorio para usar ya — genera **semillas de partida**, una
por walker, para que cada uno tenga su propio estado independiente del que tirar
más adelante durante la simulación. `rn` se calcula porque la fórmula de
`rand1p_gpu` siempre lo calcula, pero se sobrescribe en cada vuelta sin guardarse.

### Dos LCG independientes, separados a propósito

| | multiplicador | suma | se usa en |
|---|---|---|---|
| `rand1_gpu` | 44485709377909 | 96309754297 | `gauss3_gpu` — la física real (movimientos de difusión) |
| `rand1p_gpu` | 34522712143931 | 55789347517 | `k_split_seeds`, decorrelación de clones en el reparto (paso 9) |

No son la misma función con dos nombres — son dos secuencias completamente
independientes. Mantenerlas separadas es deliberado: todo lo que tiene que ver con
**repartir/decorrelar semillas** usa una secuencia distinta de la que usa la
**física real**, para que manipular semillas nunca introduzca una correlación
oculta en el muestreo aleatorio de la simulación.

### `fijasemilla_gpu` y `randv3_gpu`: portadas, sin llamador en este pipeline

`mrandom.f90`/`mrandom2.f90` (CPU) se porteó como módulo completo a `rand_gpu.cuf`
(`rand1`↔`rand1_gpu`, `rand1p`↔`rand1p_gpu`, `rn1`↔`rn1_gpu`, `randv3`↔`randv3_gpu`,
`gauss3`↔`gauss3_gpu`, `fijasemilla`↔`fijasemilla_gpu`) — pero dos piezas de ese
espejo no tienen ningún llamador en el camino real de producción:

- **`fijasemilla_gpu`**: enmascara una semilla en bruto a 48 bits y la fija como
  `irn` inicial — pero la CPU ya hace ese enmascarado una vez, al arrancar el
  programa (`fijasemilla`, `mmontecarlo.f90:656`, dentro de `inimontecarlo`), antes
  de que `sacasemilla` lea el valor. Para cuando la semilla llega al lado GPU, ya
  viene enmascarada — el trabajo de `fijasemilla_gpu` ya está hecho por el lado CPU.
- **`randv3_gpu`**: llama a `rand1_gpu` 3 veces para llenar un vector uniforme de 3
  componentes — pero `gauss3_gpu` (la única que hace falta en producción) llama a
  `rand1_gpu` directamente 4 veces por su cuenta, sin pasar por `randv3_gpu`.

**Se dejan tal cual, no se borran.** Comprobado con `cuobjdump --dump-resource-usage`
sobre `rand_gpu.o` compilado: el compilador **sí** las compila como funciones
`device` independientes, con su propio recuento de registros
(`mrandgpu_randv3_gpu_`: 38 registros; `mrandgpu_fijasemilla_gpu_`: 24) — no las
elimina, porque son procedimientos **públicos** de un módulo Fortran y, compilando
`rand_gpu.cuf` como unidad aislada (sin optimización de programa completo), el
compilador no puede demostrar que ningún otro fichero las llama en algún sitio; las
compila "por si acaso".

Lo que sí es cierto: como de verdad no las llama nadie, ese recuento de registros
queda **aislado** — no se suma ni afecta al de `k_split_seeds` (16 registros, línea
propia en la tabla) ni al de ningún kernel real del pipeline. El coste real es
binario más grande (código compilado sin usar, unos pocos cientos de bytes), **no**
coste de ejecución ni de ocupación de ningún kernel que sí se lanza.

Mantener el espejo 1:1 con el módulo original tiene valor real pese a ese coste
mínimo: quien audite el porteo después ve el mismo conjunto de funciones en los dos
lados, sin preguntarse si algo se perdió sin querer. Distinto de casos como
`F00`...`F6` en `He_dihydrogen.f` o `derananum()` monolítico tras el split, que se
conservan como **referencia de verificación** de algo que sí está en uso — aquí no
hay ninguna pieza en producción que se construyera "a partir de"
`fijasemilla_gpu`/`randv3_gpu`, simplemente no acabaron teniendo un llamador.

## Jerarquía de memoria en el device

Ver también el diagrama visual (artifact HTML publicado en esta conversación).

- **Global** (toda la GPU, toda la corrida): `atom_p`, `sprop_p`, `wf_p`/`kin_p`/
  `eimp_p`/`erot_p`/`pot_p`/`ene_p`, `dwf_p`/`dphi_p`, `nsons_p`, `activo_p`,
  `irn_p`, `nw_actual`, `hb2m_p`/`b_p`, `wfhe4_s`/`d1wfhe4_s`/`d2wfhe4_s` (y el resto
  de arrays persistentes del split de `derananum`), los 12 histogramas
  (`h44_p`...`hybhe_p`).
- **Compartida** (un bloque de hilos): **no se usa en ningún kernel de este pipeline
  hoy** (confirmado con `ncu`, `SHARED:0` en todos —
  `v4-cuda-pruebas/prueba2-threads-por-bloque/`). Los intentos que la habrían usado
  (repartir el bucle de parejas O(n²) entre hilos de un walker) se probaron y
  fallaron — ver `v3-cuda-optimización/arquitectura-lanzamiento/fase1-bloque-por-walker/`.
- **Local** (un hilo, pero fuera del chip — misma DRAM que global, por eso no es
  rápida pese al nombre): los 8 arrays del `derananum()` monolítico original
  (`d1wfhe4`, `d2wfhe4`, `d1wfhe3`, `d2wfhe3`, `d1wfm`, `d2wfm`, `d1wfx`, `d2wfx` —
  `derananum.md` Parte 9), dimensionados con variables `device` en tiempo de
  ejecución, no caben en registros. Tráfico medido: ~1,15GB en `k_derananum_t`
  (antes del split), ~276MB en `k_vpot_t` (sigue así hoy — ver
  `v3-cuda-optimización/ideas-optimizacion-futuras.md`).
- **Registros** (un hilo, en el chip — la más rápida y la más escasa): los
  escalares vivos en un momento dado, p.ej. `x`, `x2`...`x11`, `F`, `Fp`, `sum1`,
  `sum2`, `expbase`, `Vap`, `Vbp` dentro de `V_and_Vp_hehe`. Medidos hoy: 106
  registros/hilo en `k_vpot_t`, 88/126/40 en `k_derananum_he4_t`/`_resto_t`/`_join_t`.

## Ficheros relacionados

- `msteps.f90`: `pasodmc_gpu_pipeline` (líneas 310-591), objeto de este documento.
- `dmc2_pipeline.cuf`: `inicializa_pipeline`, `lanza_pipeline`, las 8 fases del
  grafo, `resetea_histogramas_gpu`, `vuelca_histogramas_gpu`.
- `msync_gpu.cuf`: `sincroniza_etrial_gpu`, `sincroniza_constantes_gpu`.
- `rand_gpu.cuf`: `k_split_seeds`, `rand1p_gpu`.
- `mrandom.f90`: `sacasemilla`.
- `mmontecarlo.f90`: quien llama a `pasodmc_gpu_pipeline`, y la estructura de bloques
  (`resetea_histogramas_gpu`/`vuelca_histogramas_gpu` una vez por bloque).
