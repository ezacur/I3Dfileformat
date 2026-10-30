# Auditoría completa del formato `.i3d` — 2026-10-13

Esta auditoría junta cinco fuentes, y en ella no se ha editado nada del formato, de los lectores ni del escritor:

1. **SPEC**, leída sola. Se pasaron 19 ficheros límite por la DLL y por Python.
2. **Núcleo C++ y API C**: ocho ficheros leídos enteros y sondas contra la DLL.
3. **Fuzzing diferencial DLL ⇄ Python**: 10 000 mutantes de 16 semillas.
4. **Escritor MATLAB** contra la forma canónica (§9).
5. **Lo que han destapado los dos lectores nuevos** (TypeScript y C#).
   - **TypeScript**: los mismos 10 000 mutantes, comparados con la DLL.
   - **C#**: envolver la API C.

Cada afirmación lleva su etiqueta:
- **[MEDIDO]**: hay una sonda o una corrida que lo muestra;
- **[LEÍDO]**: sale de leer el código o la SPEC;
- **[NO VERIFICADO]**: lo dice así, sin prueba.

Las sondas están en el scratchpad de la sesión (`audit2\`, `ts_i3d\`) y **no** en el repo; la §6 dice qué merece pasar a `tests/`.

---

## 0. Resumen

**Lo que está bien, medido:**
- **La DLL no se cae ni se cuelga** en 10 000 mutantes.
- **No hay ni un solo caso** en que dos lectores acepten el mismo fichero y den datos distintos: ni DLL ⇄ Python (4 062 aceptados por los dos) ni DLL ⇄ TypeScript (2 896).
- `first_frame()` es igual a `data(:,:,:,1)` en todos los mutantes que la DLL acepta.
- El escritor produce ficheros canónicos que vuelven **bit a bit** en todos los casos probados, incluidos los raros: 1×1, int64/uint64 en sus extremos, NaN/−0/±Inf, RGB, tensores y UTF-8.
- El C# compara bit a bit con Python en los 43 ficheros reales (3 680 comprobaciones, 0 fallos).

**Lo que falla se reparte en tres clases:**

| clase | qué es | cuántos |
|---|---|---|
| **la SPEC no decide** | dos lectores razonables hacen cosas distintas y los dos cumplen el texto | ~15 |
| **un lector es laxo** | acepta lo que la SPEC prohíbe. Casi siempre Python (el de referencia), a veces la DLL | ~20 |
| **robustez** | ficheros hostiles: reservas de gigas, desbordamientos, cuelgues | 6 |

**Las cinco cosas que yo arreglaría primero:**

1. **El escritor se cuelga** con Lazy si los ficheros cuelgan de la raíz de una unidad (W1). Es el único defecto ALTO que afecta a un uso normal.
2. **`i3d_open(NULL)` mata el proceso** (C1). Es la frontera de todos los wrappers.
3. **Un fichero de 127 bytes hace reservar 1,5 GB** antes de comprobar nada (C2).
4. **Las claves futuras con `( )` rompen los lectores v0** (S1): o se decide ya, o la v0 no podrá leer la v1.
5. **`first_frame` no tiene test de regresión en el repo** (T1). Es la API que más se usa en lectura parcial y la que acaba de estrenar el visor.

---

## 1. SPEC

### 1.1 Decisiones que faltan (los lectores ya divergen) — ALTA

| # | caso | DLL | Python | TS | propuesta |
|---|---|---|---|---|---|
| S1 | clave desconocida con `( )` (`labels(:,:,:,1) = …`) | `badHeader` | `badHeader` | `badHeader` | **Decidir.** «Una clave desconocida se ignora» (§2) existe para la compatibilidad hacia delante, y hoy no la cumple justo el caso de §8 (LABELS/FIELDS). Propuesta: `( )` en una clave **desconocida** ignora la entrada; en una conocida que no es `data`, error. Va con el open item 12 (`I3D 0.2`) |
| S2 | enteros con `+`, con `_`, o `-0` en un offset | `+1` y `_` rechazados; `@-0` aceptado | acepta `+1` y `_` | rechaza los tres | Gramática explícita en §2: entero `[0-9]+` (o con `-` donde aplique) y doble con patrón propio, **no** «lo que acepte strtod» |
| S3 | números que desbordan (`1e309`, `1e-400`) | `badNumber` | inf / 0 | `badNumber` | Decir que es error |
| S4 | `data()` vacío y `data(:,:,1,)` | **acepta los dos** | error / error | error / error | Prohibirlo en §2: «cada subíndice es no vacío» |
| S5 | `data(:,:,:,1:-1)` | **lo lee como `1:`** (usa −1 como marca interna) | error | error | Es un defecto de la DLL, no un hueco: arreglar `parse_sub` |
| S6 | componente solo con `:` | `badData` | extensión 1 | `badData` | Decir en §5.2 que `:` no fija la extensión |
| S7 | `$VAR$` o `info.X` repetidos | `badHeader` | gana el último (310 mutantes) | `badHeader` | §2 ya lo dice; Python lo incumple |
| S8 | rango compacto `0.0:1.0:3.0` | acepta | exige espacios | acepta | Decir que los espacios alrededor de `:` son opcionales |
| S9 | primera línea con un espacio delante (` I3D 0.1`) | **acepta** | — | rechaza | «Los 4 primeros bytes son `I3D `»: un visor detecta el formato por ahí, y un fichero así no se reconocería |

### 1.2 Contradicciones internas — MEDIA

- **§1, diagrama: «header: ASCII text».** Es UTF-8 (l.49).
- **§7: «v0 readers decode aux in raw and zlib».** También png, que es el canónico de los thumbnails.
- **§9.1, Lazy: «ASCII path».** Resto anterior: el escritor acepta UTF-8, y la §1 lo da por medido con la carpeta `año`.
- **§5.7: «la forma canónica mantiene el primer instante en bloques propios».** Falso con `'Blocks','volume'`, que es canónico según la tabla de §9. [MEDIDO] `firstFrame` cuesta 0,015 s, frente a 0,017 s leyéndolo todo y 0,005 s con `auto`. **Decidir:** quitar `volume`, o que deje aparte el instante 1, o matizar §5.7.
- **§2: «Any key may take a descriptor».** Los lectores lo rechazan en X/Y/Z/T, transform y rescale (open item 15). Ponerlo en el texto de §2.
- **§7 frente a §2: números con o sin `.0`** (`info.planes.series` son índices). Decir cuál manda.
- **§13** ya no tiene defectos abiertos: pasarla a «historia».

### 1.3 Huecos — BAJA o MEDIA

- **`crc` y `frames`:**
  - `crc` en `<dicom>`/`<missing>` (MEDIA): la DLL lo acepta **y no lo comprueba**, una integridad falsa.
  - `frames 0:0` lee todos los frames.
  - `frames` en raw/zlib se ignora.
  - Propuesta: rechazarlos al parsear (C7).
- **El `$` literal en una ruta:** no se puede escribir. `//srv/C$/x.dcm` da `badVariable`, y el escritor **materializa en silencio** los planos que lo llevan (W2). Propuesta: escape `$$`.
- **Valores no finitos:** `transform`, `rescale` y `window` no finitos, pendiente 0, ancho ≤ 0, y rejillas `nan`/`inf` con un solo valor. Hoy unos lectores lo aceptan y otros no. Propuesta: exigir valores finitos, pendiente ≠ 0 y ancho > 0.
- **Límites normativos que no están:**
  - dimensiones (la API admite 16);
  - valores por rejilla (la DLL, 2^31);
  - elementos totales (2^59);
  - tamaño de la cabecera en claro (sin tope: un binario cualquiera se lee entero antes del `badHeader`).
- **Caracteres de control y NUL dentro de cadenas:** §2 los excluye, y los dos lectores los aceptan. La API C, además, **corta** la cabecera en el NUL (C10).
- **zlib con bytes sobrantes dentro de su longitud:** la DLL y Python los toleran; TS y la cabecera I3Db exigen el final exacto. Decidir una sola regla (propuesta: exacto, como I3Db).
- **`{shape}` con unos sobrantes al final** (`{4 3 1 1 1}`): C++ lo acepta y Python no.
- **Tokens del descriptor:**
  - dos tipos (`<raw uint16 int16 …>`): Python se queda con el último y **reinterpreta los datos**;
  - dos `@`: los dos lectores se quedan con uno;
  - tokens en `<missing>`.
  - Propuesta: un token de cada clase, y `<missing>` sin tokens.
- **Redacción:**
  - orden de los tokens (los lectores aceptan cualquiera);
  - tipos en minúsculas;
  - `inf/-inf/nan` en minúsculas;
  - redondeo del `.5` en `round` de §3.1;
  - PNG entrelazado;
  - continuación de línea tras una línea en blanco;
  - las líneas sueltas `# aux.X skipped` en la fila *layout* de §9.

### 1.4 Afirmaciones MEASURED sin test en el repo

La l.24 promete que «MEASURED» quiere decir que hay test o banco en el repo. **No es así** para:

| afirmación | estado | prioridad |
|---|---|---|
| **T1** §5.7 `first_frame`, 43 ficheros, 335× | sólo en el scratchpad; **ningún test del repo llama a `first_frame`** | **alta** |
| §4 `check_dicom.m`, 61 ficheros | existe, pero **no se ha relanzado** desde que se recompiló DCMTK (wide-char, sin dcmjpls) | media |
| §7 `planes`, 12 contra su `.dcm` | sólo scratchpad, y depende de `d:\DICOMS` | media |
| §9 «`check_roundtrip` comprueba la forma canónica» | parcial: `canon_` no mira el orden de líneas, la forma de las rejillas ni las listas de una fila por valor | media |
| §4 «encoding desconocido: error al pedirlo» | ningún test pide un aux con encoding desconocido | media |
| §1 UTF-8 de punta a punta en MATLAB | parcial | media |

---

## 2. Núcleo C++ y API C

| # | gravedad | qué | evidencia | arreglo |
|---|---|---|---|---|
| **C1** | **ALTA** | `i3d_open(NULL)`, o un nombre/valor NULL en `i3d_open_vars`, da **access violation**: el proceso muere en vez de devolver un error. El C# lo filtra por su cuenta; los demás wrappers no | [MEDIDO] | Comprobar NULL y devolver `badInput` |
| **C2** | **MEDIA-ALTA** | Reservas gigantes **antes** de mirar el tamaño del fichero | [MEDIDO] 127 B → 1 466 MB (zlib declarado de 1,5 GB); 20 B → 1 059 MB (I3Db con L = 2^30); 113 B → 1 561 MB (rejilla de 10^8 valores) | Comparar `offset+len` y L con el tamaño del fichero antes de reservar |
| C3 | MEDIA | `read_aux`: `n *= s` desborda y da un **éxito falso** (`{2^32 2^32}` → 0 bytes, rc 0) | [MEDIDO] | Multiplicación con comprobación de desbordamiento, también en `read_box_` y `data_bytes` |
| C4 | MEDIA | `<dicom>` recarga el `.dcm` entero **por bloque**: es cuadrático en multiframe | [MEDIDO] 200 bloques de 1 frame: 93× más lento que 1 de 200 | Caché del último `DcmFileFormat` por ruta |
| C5 | MEDIA | `<png>` aceptado **como bloque de data** (SPEC: sólo aux) | [MEDIDO] (Python y TS lo rechazan) | `badDescriptor` en `build_data_` |
| C6 | MEDIA | `PALETTE COLOR` devuelve **índices de paleta** como si fueran grises; MONOCHROME1 e YBR pasan sin aviso | [MEDIDO] | Aceptar sólo MONOCHROME1/2 (y decidir MONOCHROME1, open item 18) |
| C7 | BAJA-MEDIA | Se aceptan y se ignoran: `crc` en `<dicom>`, `frames 0:0` (lee todo), `frames` en raw | [MEDIDO] | Rechazarlos al parsear |
| C8 | BAJA-MEDIA | Validador UTF-8 incompleto: surrogates, *overlong*, > U+10FFFF y F5–F7 pasan (Python y TS los rechazan; 11 mutantes) | [MEDIDO] | Validador estricto RFC 3629 |
| C9 | MEDIA | Claves con `isalnum` dependiente del locale: con cp1252, `info.Ê` es una clave válida, y el mensaje de error corta un carácter UTF-8 por la mitad. **La API devuelve UTF-8 inválido** en `i3d_last_error` y el wrapper Python revienta con `UnicodeDecodeError` (59 mutantes) | [MEDIDO] | Comprobación ASCII explícita |
| C10 | BAJA | Un NUL dentro de la cabecera corta lo que devuelven `i3d_header` e `i3d_entry` | [MEDIDO] | Rechazar caracteres de control |
| C11 | BAJA | `missing_box` dice ndims = 17 y escribe 16; `i3dinfo` no mira los rc y deja `nd` sin inicializar | [MEDIDO] | Error si hay más de 16 dims; comprobar rc |
| C12 | BAJA | `i3d_open_vars` con `"$FX$"` no aplica la variable y no da ningún error (el MEX y el C# quitan los `$`; la API no) | [MEDIDO] | Quitarlos en el núcleo, o error |
| C13 | BAJA-MEDIA | Cobertura O(n²) en número de bloques | [MEDIDO] 40 000 bloques: 2,6 s al abrir | Barrido ordenado por (t, k) |
| C14 | BAJA | Un `ifstream` nuevo por bloque | [LEÍDO, no medido] | Stream compartido |
| C15 | BAJA | Sólo se atrapan `i3d::Error` y `std::exception`; en el MEX, un `mxCreate…` que falla hace `longjmp` con objetos C++ vivos | [LEÍDO] | `catch(...)`; crear los `mxArray` después |
| C16 | BAJA | `err` por handle sin protección entre hilos | [LEÍDO] | Documentar «un handle, un hilo» |
| C17 | BAJA | Primera línea ` I3D 0.1` aceptada (S9); `data()` y `data(…,)` aceptados (S4); `a:-1` leído como `a:` (S5); `<uint8 @6:EOF>` (sin encoding) abre si el bloque no se lee | [MEDIDO, DLL ⇄ TS] | Parser estricto |
| C18 | — | Comentarios desfasados (`i3d.hpp`: «png no se decodifica», «aux raw/zlib»); `build_dcmtk.bat` sigue compilando `dcmjpls`/`dcmtkcharls` | [LEÍDO] | Actualizar |

**Ergonomía de la API C** (la ve quien escribe un wrapper; sale del C#):
- **`i3d.dll` choca con un `I3D.dll`** gestionado, porque Windows no distingue mayúsculas: da `EntryPointNotFoundException`. Le pasará a cualquier lenguaje que genere un `I3D.dll`. Propuesta: **renombrar la nativa a `libi3d.dll`**.
- `i3d_data_type`, `i3d_aux_count` e `i3d_entry_count` fallan **sin dejar mensaje** en `i3d_last_error`.
- **No hay `i3d_aux_bytes`**: el tamaño de un aux hay que calcularlo a mano.
- `tests/i3d_ctypes.py` no declara `argtypes` en `i3d_missing_box` ni en `i3d_missing_count`. En 64 bits el handle no cabe en un `int` (`OverflowError`).

---

## 3. Lector Python de referencia

Es **el más laxo de los tres**. Como es «la referencia», cada laxitud es una ambigüedad que alguien copiará.

| defecto | casos | gravedad |
|---|---|---|
| claves repetidas aceptadas (gana la última o la primera) | 310 | media |
| **no lee `rescale` ni `window`** (`rescale = "abc"` pasa) | 47 | media |
| dos tipos en un descriptor: se queda con el último y **reinterpreta los datos** | — | media |
| bloque que se sale del fichero o queda corto: **corta en silencio** | 7 | media |
| `<jpegls uint32>` decodificado (§4 sólo admite (u)int8/16) | — | media |
| **aux raw sin comprobar la longitud**: devolvió 24 bytes de un PNG como píxeles, **el único caso de datos erróneos devueltos en silencio** en toda la auditoría | 1 | media |
| rangos que agotan la memoria (`0 : 1e-12 : 1`) | 9 | media |
| `1_000`, `1e309` → inf, offset > int64 | 13 | baja |
| excepciones internas (`IndexError`, `KeyError`) en vez de `I3DError` | ~30 | baja |
| tipos mezclados sin promoción (open item 16) | 11 | conocido |

---

## 4. Escritor MATLAB

| # | gravedad | qué | arreglo |
|---|---|---|---|
| **W1** | **ALTA** | **Lazy se cuelga** si los ficheros cuelgan de la raíz de una unidad (`D:/A/…`, `D:/B/…`): `fileparts('D:/')` no cambia `p` y el `while` no termina [MEDIDO, lógica replicada] | Salir si `p` no cambia; o prefijo común por componentes |
| W2 | MEDIA | `$` en la ruta → los planos se **materializan en silencio** | Escape `$$` en la SPEC; mientras tanto, un comentario |
| W3 | MEDIA | WindowCenter distinto entre cortes: **desaparece** sin línea ni comentario (el rescale, en cambio, da error) | `# window skipped: varies between slices` |
| W4 | MEDIA | `SpatialTransform` en single da `i3d_num2str:badInput`, sin decir qué | `double(A)` |
| W5 | MEDIA | transform no finito o nulo: se escribe, con un comentario absurdo (`singular values NaN`) | `write_I3D:badTransform` |
| W6 | MEDIA | `'Blocks','volume'` contra §5.7 (ver 1.2) | decidir |
| W7–W17 | BAJA | `Verify` sin validar; motivos de «skipped» engañosos (NaN → «a double»); int64 > 2^53 pierde precisión; thumbnail vacío sin comentario; `X = [-0 1]` con un comentario que se contradice; mensaje de `rescaleNotCommon` impreciso; `read_I3D` deja que `info.rescale` pise `INFO.rescale`; `'Info','Auto'` en mayúscula ignorado; zlib con componentes sin partir por c; `Blocks` ignorado con jpegls sin decirlo; reflexión pura descrita como «rot 180 + reflection» | ver parte 4 |

**Docstrings desfasados** [LEÍDO]:
- `write_I3D.m`: «ASCII» (l.20, 65, 106); «Todavía NO escribe … rescale por bloque ni atributos de corte» (l.67-68); «para raw no hay límite» (l.130); falta `write_I3D:png` en ERROR IDENTIFIERS; no describe `info.series`/`info.planes`.
- `read_I3D.m`: «aux raw/zlib» (l.25); «png no se decodifica» (l.39); «no hay lectura parcial» (l.40); «rescale por bloque» (l.41).

---

## 5. Los lectores nuevos, como auditores

**TypeScript** (`MultiPlaneReconstruction/src/i3d.ts`):
- Sobre los 10 000 mutantes, contra la DLL: 2 896 aceptados por los dos **con datos idénticos**, 5 807 rechazados por los dos y **0 aceptados con datos distintos**.
- Las 1 214 diferencias por `<dicom>` son a propósito: un navegador no abre rutas de disco, y lo dice.
- En los 43 ficheros reales es idéntico en todos los que no son Lazy.
- Las demás divergencias (≈90) son **todas** la DLL siendo laxa: S4, S5, S9, C5, C8 y zlib con bytes sobrantes.
- Mientras se probaba aparecieron **tres defectos del propio TS**, y están arreglados:
  - aceptaba un BOM (`TextDecoder` lo quita por defecto, y `trim()` de JS lo trata como espacio);
  - no comprobaba que `$VAR$` fuera una cadena;
  - convertía `1e309` en infinito.

**C#** (`csharp/`): 3 680 comprobaciones, 0 fallos. Sus hallazgos están en la §2, en la ergonomía de la API.

---

## 6. Qué pasaría a `tests/`

1. **`first_frame`** (T1) en `check_roundtrip`, con los tres lectores más el TS, y un caso `Blocks volume`.
2. Los **casos mínimos del fuzz** (`minimal.py`, 52) a `check_invalid.py`, cada uno con el veredicto que la SPEC decida.
3. El **corpus de mutantes** como regresión diferencial: semilla fija, regenerable, sin guardar los 10 000 ficheros. Hoy son tres lectores; con el TS, cuatro.
4. Relanzar **`check_dicom.m`**.
5. Un aux con **encoding desconocido** que no impida leer `data`.

---

## 7. Opinión honesta

**El formato está sano**, y no lo digo por cortesía: en 10 000 ficheros mutados, ningún lector que acepta un fichero devuelve datos distintos de otro. Eso es lo que importa en un formato de intercambio, y no es lo habitual. La forma canónica estricta (§9) fue una buena decisión: casi todos los hallazgos están en la **gramática general** que se conserva para la lectura, no en lo que se escribe.

Lo débil está en otra parte:
- **La SPEC delega en «lo que acepte strtod»** y en dejar implícitos los casos raros. Con un solo lector daba igual; con cuatro (C++, Python, MATLAB a través del MEX y TS, más el C# encima de la DLL), cada hueco es una divergencia esperando a pasar. Hace falta **una gramática con expresiones regulares** para números, enteros, subíndices y tokens del descriptor.
- **El lector «de referencia» es el más laxo.** Debería ser al revés: o se endurece Python hasta que sea de verdad la referencia, o se declara que la referencia es la DLL y Python pasa a ser un lector más. Yo endurecería Python: es pequeño y legible, y para eso sirve.
- **Robustez frente a ficheros hostiles** (C1, C2, C3): si el `.i3d` sólo lo abren tus propias herramientas sobre tus propios ficheros, es baja prioridad. Si va a circular (es un formato de intercambio, y ahora lo abre un visor web), C1 y C2 son lo primero.
- **¿Mereció la pena el visor web?** Sí, y por una razón que no esperaba: obligó a escribir un **tercer lector independiente**, y un lector independiente es la mejor auditoría de una SPEC. Confirmó por su cuenta las laxitudes de la DLL que el fuzz ya había visto (S5, C5, C8). Encontró además tres que el fuzz DLL ⇄ Python no podía ver: S9, el subíndice vacío `data(…,)` y el bloque sin encoding. Python no lo marcaba como diferencia porque tenía la misma laxitud o una equivalente.
