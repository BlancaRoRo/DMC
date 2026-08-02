# `Original-VapFix`

Copia de [`../Original`](../Original) con **un único cambio**: en `bh_heh2m.f`, la función `Vp_hehe` inicializa `Vap=0.d0` antes del `if` que la calcula de verdad, en vez de dejarla sin inicializar fuera de la ventana `[xx1_HeHe, xx2_HeHe]`.

**Por qué existe esta carpeta:** `Vap` sin inicializar es un bug real del código original (memoria de pila leída sin asignar, comportamiento indefinido — documentado en detalle en [`../v1-cuda-desarrollo/docs-kernels/V_hehe_Vp_hehe.md`](../v1-cuda-desarrollo/docs-kernels/V_hehe_Vp_hehe.md) §5 y confirmado varias veces más en [`gpu_vs_gfortran_arbol.md`](../v1-cuda-desarrollo/docs-kernels/gpu_vs_gfortran_arbol.md)). Compilar contra el `Original` sin corregir hace que la referencia de CPU cambie de un build a otro (con el compilador, con las flags, con la versión del SDK...) sin que eso tenga nada que ver con el port a GPU. Esta copia existe para que, **a partir de ahora**, la referencia de `gfortran` usada para validar cada kernel nuevo no arrastre ese ruido.

**Ningún otro cambio.** Ni fórmulas, ni estructura, ni ningún otro fichero — es mecánicamente `Original` + esa única línea.

## Convención a partir de aquí

- La referencia de CPU (`gfortran`) de los kernels nuevos se compila desde **esta** carpeta (o desde una copia de sus ficheros, como se ha hecho hasta ahora con `bh_heh2m.f` en cada carpeta de kernel), no desde `Original`.
- **Todas** las compilaciones (GPU, CPU-`nvfortran`, CPU-`gfortran`) de los kernels nuevos se hacen con flags de coma flotante estricta:
  - `nvfortran`: `-Kieee -Mnofma`
  - `gfortran`: `-ffp-contract=off` (equivalente: desactiva la fusión FMA: es lo único que `gfortran` necesita, no reordena ni usa fast-math por defecto)
- Los kernels ya documentados (`calpleg` ... `vpot`, en `v1-cuda-desarrollo/docs-kernels/`) **no se han vuelto a hacer** con esta convención — quedan como registro histórico de lo que se encontró sin ella. Los ULPs que documentan siguen siendo reales y válidos; simplemente no se ha repetido ese trabajo con la referencia corregida ni con flags por defecto.
