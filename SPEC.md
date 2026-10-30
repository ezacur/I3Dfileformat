# I3D file format — specification, draft v0

| field | value |
|---|---|
| **Status** | draft, 2026-10-14 (changes: [below](#changes)) |
| **Scope** | ONE image stack per file (one `@I3D`). A container for several stacks, `.mi3d`, is in [section 14](#14-the-container-mi3d-decided-2026-10-24). |
| **Producer** | MATLAB (`write_I3D`, fed by `DICOMstackCollect` or any `@I3D`) |
| **Consumers** | the C++ library, wrapped for Python and JS |

```
I = readI3D('serie.i3d');   I.X;   I.data;   I.aux('thumbnailK') -> null
```

Implemented and tested (tests/, [section 12](#12-tests)):

| language | files |
|---|---|
| C++ | `cpp/i3d.hpp` + `i3d.cpp` (the reader), `i3d_write.cpp` (THE writer of the canonical form), `i3d_c.h` (C API, the stable boundary for the wrappers): `build/i3d.dll`; `mi3d.hpp` + `mi3d.cpp` (the container: write, append, remove, compact) and `mi3d_c.h`: `build/mi3d.dll`; `i3dinfo.exe` |
| MATLAB | no MEX: `matlab/lib/` holds the two DLLs, loaded with `loadlibrary` (`enableI3Dlibrary`) and called with `calllib`. `write_I3D.m`, `read_I3D.m`, `hideI3Dfile.m` / `showI3Dfile.m` and the container's `write_MI3D.m`, `append_MI3D.m`, `remove_MI3D.m`, `read_MI3D.m` only translate an `@I3D` (and its DICOMstack) to those calls |
| Python | `tests/read_i3d.py` (an independent REFERENCE reader) and `tests/i3d_ctypes.py` (a thin ctypes wrapper of the DLL) |
| bundled | verbatim, in `third_party/`: zlib 1.3.2, CharLS 2.4.5, lodepng 20261006, a subset of DCMTK 3.7.0 (each with its `ORIGIN.txt`) |

Items marked **[OPEN]** are not decided yet; they are all listed in [section 11](#11-open-items-in-one-place).
**MEASURED** means there is a test or bench in this repository that shows it.

---

## 1. File layout

```
+------------------------------+
| header: ASCII text, lines    |   human readable, editable by hand
| ...                          |
| ---                          |   terminator line
+------------------------------+
| binary section               |   raw bytes, addressed by offsets
+------------------------------+
```

- Extension: `.i3d`
- The first line is the magic and version, optionally with a comment:
  ```
  I3D 0.1  # DICOMstackCollect, series 12 'cine 4ch'
  ```
  **[OPEN]** what a reader does with another version (`I3D 0.2`). The v0 readers accept only `I3D 0.1`.
- The file STARTS with exactly those bytes, `I3D 0.1` (or `I3Db`, [1.1](#11-the-hidden-variant-i3db)): nothing before them, not a space, not a BOM (decided 2026-10-23). The first 4 bytes are the signature an application recognises the format by; a file that hides them behind a space would not be recognised. ` I3D 0.1` is `badMagic`.
- The header ends at the first line that is exactly `---` (three hyphens, nothing else but an optional CR). The binary section starts at the byte that follows that line's LF. A file whose values are all literals or external references may have an empty binary section.
- **ALL OFFSETS ARE RELATIVE TO THE START OF THE BINARY SECTION**, not to the start of the file. This is what lets the header be edited by hand (fix a string, add a comment) without breaking a single offset — and what makes the hidden variant ([1.1](#11-the-hidden-variant-i3db)) a rewrite of the start of the file only. MEASURED: a file with a hand-added comment line reads exactly as the original.
- Line endings: LF. Readers must also accept CRLF.
- **Character set: UTF-8**, without BOM (decided 2026-10-13). Keys, encodings, types and numbers are ASCII; strings (values, paths, comments) may carry any character except control characters — DICOM text such as `"Muñoz^José"` or `"Resonancia cardíaca"` is written as it is. A header that is not valid UTF-8 (a Latin-1 file written by hand, stray bytes) is `badHeader`. MEASURED end to end: a Latin-1 DICOM series (`ISO_IR 100`) in a folder `año` → `write_I3D` (plain and hidden, Lazy) → `read_I3D` gives back exactly what `dicominfo` gave, and the Python and C++ readers agree.

### 1.1 The hidden variant (I3Db)

To keep the header from the casual reader, a file may store it COMPRESSED and OBFUSCATED instead of in plain text. **It is NOT protection**: everything needed to read it is in this section. It only raises the bar above a text editor. The pixels are untouched.

```
+--------------------------------------------------+
| "I3Db"                 4 bytes                   |  magic (the text form
| L                      uint64 little-endian      |  starts "I3D "): the 4th
| hidden header          L bytes                   |  byte tells them apart
+--------------------------------------------------+
| binary section         byte for byte the same    |
+--------------------------------------------------+
```

- The hidden header is the plain-text header (its UTF-8 bytes, from its `I3D 0.1` line to the line before `---`, lines ending in LF), compressed as one zlib stream (RFC 1950) `z` of EXACTLY L bytes (no bytes after the end of the stream); the stream REVERSED, `r(i) = z(L-1-i)`; and then, byte by byte,
  ```
  k(i)      = ( ( i * 0x5C2D8F1B + 0x49334462 ) mod 2^32  >>  8 )  AND 0xFF      0x49334462 = "I3Db"
  hidden(i) = ( NOT r(i) ) XOR k(i)            i = 0 .. L-1
  ```
  (32-bit unsigned arithmetic; NOT is the bit flip of the byte.) A reader undoes it — `r(i) = NOT( hidden(i) XOR k(i) )`, `z` is `r` reversed —, inflates, and parses the text exactly as [section 2](#2-header-grammar) says. The `<hidden>` block of [1.2](#12-a-hidden-part-of-the-header-decided-2026-10-23) is obfuscated the same way with constants of its own. (Until 2026-10-24: no reversal, and the multiplier 2654435761 — Knuth's, known at sight in a disassembly.)
- The inflated size is NOT stored: the zlib stream knows where it ends, and its Adler-32 checks what it inflates to. A reader inflates in chunks (and may refuse an absurd size; the C++ core refuses L or an inflated header over 1 GiB).
- The binary section starts right after the hidden header, at byte `12 + L`. Offsets stay relative to it, so hiding or showing a header rewrites only the start of the file. MEASURED: `showI3Dfile(hidden)` and `hideI3Dfile(text)` give, byte for byte, what the writer gives in each form.

### 1.2 A hidden PART of the header (decided 2026-10-23)

Some entries can be kept out of the readable header while the rest stays in plain text, editable by hand. `write_I3D` does it BY DEFAULT: everything needed to read data stays visible, and of the `info.*` only a few ([section 9](#9-the-canonical-form-what-a-writer-must-produce), example in [section 10](#10-a-complete-example)). Like I3Db, **it is NOT protection**: it keeps the casual reader away, and everything needed to read it is in this section.

```
I3D 0.1  # write_I3D 2026-10-23
X[512] = 0.0 : 0.8984 : 459.0824
...
header = <hidden @3935131:3936020>  # the rest of the header
---
binary section: ... the <hidden> block, 890 bytes ...
```

- The key `header` takes the descriptor `<hidden @where>` and nothing else: no type, no `{shape}`, no path. `crc` is optional (the CRC-32 of the inflated bytes); `write_I3D` does not write it.
- Its bytes are encoded in the spirit of the hidden header of I3Db ([1.1](#11-the-hidden-variant-i3db)), but with a step more and constants of its own (decided 2026-10-24): one zlib stream `z` of the text, of L bytes; the stream REVERSED, `r(i) = z(L-1-i)`; and then, with i counted from the first byte of the block,
  ```
  k(i)      = ( ( i * 0x7A3F5C29 + 0x68696464 ) mod 2^32  >>  8 )  AND 0xFF      0x68696464 = "hidd"
  hidden(i) = ( NOT r(i) ) XOR k(i)
  ```
  A reader undoes it: `r(i) = NOT( hidden(i) XOR k(i) )`, `z` is `r` reversed, and inflates. WHY THE REVERSAL: the fixed start of a zlib stream (`78 DA`) is no longer the start of every block, and it lands at a different i — so a different k — in each file, since blocks differ in length. (I3Db: the same procedure with `0x5C2D8F1B` and `0x49334462` = `"I3Db"`: the two do not share the sequence k.) The stream takes exactly the bytes of the block.
- The text is header lines, UTF-8, LF: entries, their continuation lines and comments. It has no `I3D 0.1` line and no `---`, and it cannot hold another `header` entry (one level).
- A reader reads those lines **as if they were written in the place of the `header` entry**. The rules of the header apply to all the lines together: a key repeated between the visible and the hidden part is `badHeader`, and so on. The hidden lines may hold anything, `data` included: offsets stay relative to the binary section.
- The block can be anywhere in the binary section. The canonical form puts it FIRST (`@0:n-1`), followed by a gap of 0 to 31 bytes (zeros) before the next block. WHY THE GAP: if the hidden lines hold offsets of the blocks after it (data), those offsets depend on the size of the block, which depends on them; the writer estimates the start D of the next block, encodes, and accepts when the block fits (n ≤ D) leaving less than 32 bytes, otherwise it estimates again from n. Bytes of the binary section that no descriptor points to are ignored by a reader, as those of a block dropped by hand ([5.1](#51-data-is-assigned-in-blocks)).
- It combines with I3Db. **What a reader shows as the header (`i3d_header`, `i3dinfo --header`, `showI3Dfile`) is the header AS WRITTEN, with the `header = <hidden ...>` line, not its content.** So someone who can dump an I3Db file still does not see the hidden part. A reader's entries (`i3d_entry`) do include the hidden ones: it needs them.
- `<hidden>` anywhere else (a data block, an aux) is `badDescriptor`.
- A reader older than this section does not know the key `header` and ignores it ([2](#2-header-grammar)): it loses the hidden lines — a coverage error if they held data, silence if they held `info.*`. There are no such readers outside this repository.

MEASURED: `tests/check_invalid.py` (hidden part in text and in I3Db, first or last in the binary, with and without crc; and bad crc, two `header` entries, `header` inside `<hidden>`, `header( )`, another encoding, a type, past the end, a byte too many, `<hidden>` as data; the dump), `tests/check_roundtrip.m` (`'Visible',{}` on every case: all `info.*` hidden, three readers, `showI3Dfile` byte for byte).

---

## 2. Header grammar

**Four kinds of brackets, one meaning each:**

| bracket | meaning | example |
|---|---|---|
| `[ ... ]` | FOR HUMANS. An annotation; the reader skips it. | `X[255]` |
| `( ... )` | WHERE: which part of an array the entry assigns. | `data(:,:,1:10,1)` |
| `< ... >` | HOW: how to obtain the bytes (a descriptor, [4](#4-descriptors)). | `<zlib int16 @0:1830219>` |
| `{ ... }` | SHAPE of an array, inside a descriptor ([4](#4-descriptors)). | `<png uint8 {128 97 1 25} @...>` |

```
line        := blank | comment | entry | continuation
comment     := '#' anything-to-end-of-line
entry       := key [ '[' anything ']' ] [ '(' sub { ',' sub } ')' ] '=' value
sub         := ':' | n | a ':' b | a ':' | ':' b        (n a b: decimal digits only, >= 1)
continuation:= one or more spaces/tabs, then more of the PREVIOUS entry's value
```

- `#` starts a comment anywhere outside a quoted string. Comments are never normative: a reader ignores them. The writer puts them at the END of the line they are about (the rotation the matrix represents, the size of data, the steps of a non-uniform grid, ...).
- Blank lines are ignored.
- key: `[A-Za-z0-9_.]+`, case-sensitive; or a variable, `$[A-Za-z0-9_]+$` (below).
- **AN UNKNOWN KEY IS IGNORED** by a reader (so that a later version can add keys without breaking v0 readers). Implemented that way; **[OPEN]** to confirm.
- `[ ... ]` after a key is an annotation, like a comment glued to the key. The writer puts the number of elements of every grid there — `X[255]` — so that the size is visible at a glance. It is NOT NORMATIVE: the reader skips it, and the size is the value's own count. A `[n]` left stale by a hand edit lies to the human reader and nobody notices; the writer always regenerates it.
- `( subs )` after a key MEANS ASSIGNMENT OF THAT PART OF THE ARRAY, as `key(subs) = value` in MATLAB:
  ```
  data(:,:,1:10,1) = <zlib ...>     assigns planes 1..10 of instant 1
  ```
  `:` is "the whole dimension"; its extent is defined elsewhere (for data, by the grids). Open ranges `a:` and `:b` run to the last / from the first. No steps and no `end`. Missing subscripts follow [5.2](#52-subscripts-of-a-block) for data; for any other key, an entry without `( )` assigns the whole value (and grids take no `( )`).
  A subscript is never empty: `data()` and `data(:,:,1,)` are `badSubscript` (an empty one is not `:`), and so is a sign (`1:-1`, `+2`).
  In v0, `( )` is defined for `data` only. On another key that v0 KNOWS (`X Y Z T transform rescale window fill`, `aux.*`, `info.*`, `$VAR$`) it is `badHeader`. On an UNKNOWN key it is ignored, like the key itself (decided 2026-10-23): so a v0 reader opens a file of a later version that adds arrays assigned in blocks — `labels(:,:,:,1) = <...>`, [section 8](#8-what-of-i3d-is-not-in-v0). MEASURED (`tests/check_invalid.py`).
- An array may be assigned in several entries (data usually is); the entries must cover it **EXACTLY ONCE**: an element assigned twice, or never, makes the file invalid. There is no "last one wins". A key without `( )` appears once.
- **VARIABLES.** An entry whose key is `$NAME$` defines a variable; its value is a quoted string. Inside a `"path"` of a descriptor, `$NAME$` is replaced by it:
  ```
  $DICOMDIR$ = "D:/DICOMS/MR 001/DICOM/000062D6"
  data(:,:,1) = <dicom uint16 "$DICOMDIR$/AA77D253/00000001">
  ```
  A reader MUST let the caller give variables at open time that OVERRIDE the file's (C: `i3d_open_vars`; MATLAB: `read_I3D(f,'Variables',{'DICOMDIR',p})`): the referenced files can move without editing the `.i3d`. MEASURED. An undefined variable is an error when the block that uses it is requested.
  **A literal `$` in a path is written `$$`** (decided 2026-10-23): `\\srv\C$\x.dcm` is `"//srv/C$$/x.dcm"`. A `$` with no partner is `badVariable`. The VALUE of a variable is inserted as it is — a `$` in it is literal, and it is not searched for variables again — so `$DICOMDIR$ = "//srv/C$"` needs no escape. `write_I3D` escapes the paths it writes. MEASURED (`tests/check_dicom_fixtures.py`).
- Key order is free for a READER, which resolves dependencies itself (X Y Z T before data). A WRITER uses the canonical order ([section 9](#9-the-canonical-form-what-a-writer-must-produce)).
- A value is either a LITERAL or a DESCRIPTOR `<...>` ([section 4](#4-descriptors)). Any key may take a descriptor; the v0 readers read descriptors in data and aux only.

### Literals

| kind | form | example |
|---|---|---|
| number | a decimal literal, as accepted by C `strtod` (no hex floats) | `2.0`, `-180.1`, `0.703125`, `1e-07`, `inf`, `-inf`, `nan`; integers `384` |
| list | numbers separated by whitespace | `0.0 8.0 16.0 24.000000000000004` |
| range | `start : step : end` | `0.0 : 1.40625 : 357.1875` |
| string | double-quoted, escapes `\"` and `\\` (any other `\` is literal); any UTF-8 character except control characters | `"cine 4ch"`, `"Muñoz^José"` |
| string list | strings separated by whitespace (continuation lines allowed) | `"1.3.12.2...16" "1.3.12.2...14"` |
| word | a bare token, no spaces | `int16`, `zlib` |

### Floating values: shortest round-trip form

**Floating values are written in their SHORTEST ROUND-TRIP FORM**: the shortest decimal string that parses back to the same IEEE double (what Python `repr`, JS `Number.toString` and C++17 `std::to_chars` produce), with ONE cosmetic rule on top:

- an integer-valued double gets `.0`: `0.0` `2.0` `-180.0` `357.0`
- zero included: +0 is `0.0`, and −0 is `-0.0` (a different double; the sign bit is kept)
- a form that already carries an exponent, `inf` or `nan` is left alone: `1e+20`, `inf`, `nan`

So: `0.0`, `2.0`, `0.1`, `0.703125`, `0.7071067811865476` — never `2.000000000000000`, and never a bare `2` or `0` for a double. MEASURED (`tests/check_num2str.m`): 240 003 values written by MATLAB, all exact and all shortest according to Python. A NaN loses sign and payload in text (**[OPEN]** 11).

**INTEGER quantities** — counts, sizes, subscripts, byte offsets and lengths, and any value of an integer-typed array (`fill` for int16 data, say) — are integers and are written without `.0`: `X[255]`, `@0:1830219`, `data(:,:,1:10,1)`, `fill = 0`. So the `.0` doubles as a type hint for whoever reads the header: `0` is an integer zero, `0.0` a floating one. A reader accepts `2` where a double is expected.

Readers MUST parse with a correctly rounded conversion (`strtod` / `std::from_chars` / Python `float` / JS `Number` all are; the C++ core uses `std::from_chars`). This is what makes the text both readable and exact.

---

## 3. Geometry

### 3.1 Grids: `X` `Y` `Z` `T` (all four required)

- Each is strictly increasing. `numel(X)`, `numel(Y)`, `numel(Z)`, `numel(T)` ARE the sizes ni, nj, nk, nt of the volume: there is no separate size key. The `[n]` annotation only shows it ([section 2](#2-header-grammar)).
- A single value is a valid grid: `Z[1] = 0.0`
- A grid has AT MOST 2^24 (16 777 216) values (decided 2026-10-23). No axis of a real volume comes near it, and without a limit a file of a hundred bytes (`X = 0.0 : 1e-12 : 1.0`) makes a reader allocate gigabytes before anything else can be checked. More is `badGrid`.
- A RANGE `a : s : b` means EXACTLY
  ```
  n      = round( (b - a)/s ) + 1
  v(k)   = a + k*s          k = 0 .. n-1
  ```
  where `k*s` and the addition are two separate IEEE-754 double operations, round-to-nearest. **NO FUSED MULTIPLY-ADD**: a C/C++ reader must not let the compiler contract it (the C++ core computes `k*s` into a `volatile`). The file is INVALID unless `a + (n-1)*s == b` bit for bit. `s > 0`.
  (MATLAB's own `a:s:b` is NOT guaranteed to produce these bits; the writer checks against the formula above, not against colon.)

### 3.2 `transform`

The first three rows of the 4×4 affine A: 12 numbers, row by row. The fourth row is implicitly `0 0 0 1` (a writer must refuse an A whose fourth row is anything else). A reader also accepts two short forms (NOT canonical: a writer always writes the 12 numbers, [section 9](#9-the-canonical-form-what-a-writer-must-produce)):

| header | meaning |
|---|---|
| (no `transform` entry) | `A = eye(4)` |
| `transform = tx ty tz` | a pure translation: `A = [eye(3) t ; 0 0 0 1]` |

```
world = A * [ X(i) ; Y(j) ; Z(k) ; 1 ]        i,j,k 1-based
```

A is a general affine: rotation, scale, shear, negative determinant are all allowed. The writer starts the first row on the same line as `=` and ALIGNS EACH COLUMN ON THE DECIMAL POINT, so that

```
transform = 0.7071067811865476   0.0   -0.7071067811865475   -180.1
            0.0                  1.0    0.0                   -95.3
            0.7071067811865475   0.0    0.7071067811865476     41.0
```

reads as a matrix. Alignment is for humans: a reader just splits on whitespace. BELOW the matrix, in full-line comments (since 2026-10-23; until then at the end of the first two rows), the writer describes A (`# rot 45 deg about [0 -1 0]`, `(orthonormal to 6.4e-09)`, `+ reflection`, `+ scale` ...) and, in a second line, the same rotation as three turns about the FIXED axes — `turn -76.0761 deg about x, then 8.8475 about y, then 58.1851 about z (fixed axes)`, that is `Rz(c)·Ry(b)·Rx(a)` with right-handed rotation matrices (the same as MATLAB's `maketransform('rxyz',[a b c])`, MEASURED) —, written only when the writer has CHECKED that the angles rebuild it, and left out when the first row already says it (a single turn). The translation is not described: it is the last column.

- The world frame is whatever the writer's was. From DICOMstack it is the DICOM patient frame (LPS), in mm. It is not declared in the file.
- Units are not declared either. From DICOMstack: X Y Z in mm; T is what DICOMstack put in the `@I3D`, which **TODAY IS `0:nt-1`** (instant indices), not the TriggerTime. **[OPEN]** 2.

---

## 4. Descriptors

A descriptor, between `< >`, says HOW to obtain the bytes of a value:

```
< encoding  type  [{shape}]  [@where]  ["path"]  [key value ...] >
```

(in this line, `[ ]` marks an optional part, as usual in a grammar)

| part | meaning |
|---|---|
| `type` | `int8 uint8 int16 uint16 int32 uint32 int64 uint64 single double` (MATLAB names). logical is stored as uint8 0/1 — **[OPEN]** 3. |
| `{shape}` | `{n1 n2 ...}`, the size of the array, column-major (first index fastest). REQUIRED where nothing else gives the shape (aux in raw/zlib). In a data block the shape is its subscript `( )`, so it is not written; if it is, it must match. |
| `@where` | where the bytes are in the binary section (offsets relative to its start, [section 1](#1-file-layout)). Decimal integers — see below. |
| `"path"` | an external file. `$VARIABLES$` are substituted ([section 2](#2-header-grammar)); a relative result is relative to the directory of the `.i3d`; `/` and `\` are both accepted. |
| `key val` | options — see below. |

**`@where` forms:**

| form | meaning |
|---|---|
| `@a:b` | bytes a..b, BOTH INCLUDED, as `a:b` in MATLAB: b is the LAST byte of the block, length b−a+1. The form the writer uses: `@0:119`, then `@120:239` |
| `@a:EOF` | from a to the end of the file |
| `@a+n` | n bytes from a |
| `@a+Inf` | from a to the end of the file (same as `@a:EOF`) |
| `@a` | from a, length not given (raw only: it follows from the shape) |

`EOF` / `Inf` let a file be written by hand, or a header emitted BEFORE the length of the last compressed block is known. MEASURED: all four forms read the same. Only `@a:b` is canonical ([section 9](#9-the-canonical-form-what-a-writer-must-produce)).

**Options:**

| option | meaning |
|---|---|
| `frames a:b` | dicom only (frame numbers, 1-based, 1 ≤ a ≤ b), [5.3](#53-bytes-of-a-block). On another encoding, or `0`, or a sign: `badDescriptor` |
| `crc XXXXXXXX` | the CRC-32 of the block's DECODED bytes (below). Any block that has data — `<dicom>` included —, not `<missing>`. Optional for a reader; ALWAYS present in the canonical form ([section 9](#9-the-canonical-form-what-a-writer-must-produce)) |

### Encodings in v0

Which encoding a WRITER uses is not free: the canonical form fixes it by type ([section 9](#9-the-canonical-form-what-a-writer-must-produce)) — jpegls for 8/16-bit integers, zlib for the rest, dicom with Lazy, png for thumbnails. A READER decodes all of the ones below.

#### `<raw type @where>`
Little-endian, uncompressed. In a data block the length follows from the block's shape and may be omitted; if present it must match. Readers accept it; it is NOT canonical.

#### `<zlib type @where>`
A zlib stream (RFC 1950, with its Adler-32 check) that inflates to the little-endian bytes of the block. The length given is the COMPRESSED one, and must be given (or `EOF` / `Inf`). zlib and not raw deflate or gzip: Python's `zlib`, Java's `Deflater`, the browser's `DecompressionStream('deflate')` and the zlib C library all speak it natively.

#### `<jpegls type @where>`
A lossless JPEG-LS (ISO/IEC 14495-1, NEAR = 0) codestream of ONE single-component image holding WHOLE i,j planes: `data(:,:,kr,tr[,cr])`, any range of k, t and components (decided 2026-10-14; until then, one plane per block).

- Width = ni, height = nj × (the number of planes in the block): the planes stacked one under the other, in the order k, t, c (k fastest). The x of JPEG-LS is the i of `@I3D`, so the decoded samples ARE the block's bytes in column-major order `i j k t c` — no reordering. A block of one plane is exactly the old one-plane block.
- The image is AT MOST 65535 × 65535: a block that needs more is `badData`, and a writer splits it. WHY: a taller image needs the JPEG-LS oversize-dimension extension (an LSE segment), which CharLS 2.4.5 writes and reads but the CharLS of the browser (`@cornerstonejs/codec-charls`) and of Python's imagecodecs do not — MEASURED 2026-10-14: a 64 × 76800 image came back as 64 × 11264 (the height modulo 2^16) in the browser, and imagecodecs refused it. A file one reader opens and the others cannot is worse than one more block.
- type is uint8, int8, uint16 or int16, and the frame's bits per sample are those of the type (8 or 16).
- JPEG-LS knows only unsigned samples: a SIGNED type is stored offset by 2^(bits−1) — an XOR of the top bit, exact both ways.
- MEASURED (`bench/real_jpegls_results.txt`): 1.2 to 1.8 times smaller than zlib on real CT/MR, and the MATLAB writer 5–16× faster than with zlib.

#### `<dicom type "path" [frames a:b]>`
The pixel data of a DICOM file, decoded by the reader (DCMTK in the C++ core). Byte order and transfer syntax come FROM THE FILE.

- **What is returned, exactly:** one plane per frame, Columns × Rows with the column fastest (the i of `@I3D`: DICOMstack permutes dicomread's Rows × Columns); the STORED values — the BitsStored bits that end at HighBit, masked, and sign-extended when PixelRepresentation = 1 —, WITHOUT the DICOM's own Rescale (the authority is the `.i3d`'s `rescale`, [section 6](#6-rescale-window-image)).
- type must be the file's (BitsAllocated 8/16/32 with PixelRepresentation); it is written so that the type of the volume is known WITHOUT opening every referenced `.dcm`.
- SamplesPerPixel must be 1 in v0 (**[OPEN]** 13).
- Without `frames`, a single-frame file covers one plane and a multi-frame file as many planes as it has frames.
- A writer should reference only LOSSLESS transfer syntaxes: a lossy one decodes to different pixels in different decoders.
- MEASURED (`tests/check_dicom.m`, 61 files covering the transfer syntaxes, bits and signs of `d:\DICOMS`): where dicomread is right, the C++ reader gives exactly the same; where they differ, the C++ reader is right (`tests/probe_jpll.m`).
- The bundled DCMTK does not decode JPEG 2000 (**[OPEN]** 13).
- Its `crc` (decided 2026-10-14) is the CRC-32 of the pixels the block DECODES TO, so it checks the referenced `.dcm` where it matters: a file that changed, that was replaced, or that another DICOM decoder reads differently (dicomread's sign and JPEG-lossless faults, [section 9.1](#91-write_i3d-matlab)) gives `badCRC`. MEASURED (`tests/check_dicom_fixtures.py`).

#### `<missing>`
data only: this part of the volume could not be read. See [5.5](#55-coverage-and-what-a-reader-does-with-a-hole).

#### `<png uint8 {rows cols} @where>` , `<png uint8 {rows cols 1 frames} @where>`
aux only: ONE PNG image, 8-bit GREY (colour type 0, bit depth 8), of `rows` rows and `cols·frames` columns, the frames side by side. Its pixel at row y, column X goes to element `y + rows·X` of the array in column-major order — which is exactly the MATLAB array `{rows cols 1 frames}`: in MATLAB, `reshape(v, rows, [])` writes it and `reshape(img, [rows cols 1 frames])` reads it. Any other PNG (colour, 16 bits, a size that does not match `{shape}`) is `badBlock`: a reader must not convert it silently. The C++ core decodes it with the bundled lodepng; the Python reference reader with imagecodecs. MEASURED.

#### `<gif ...>`
aux only, reserved: NOT decoded by the v0 readers (they report it instead of failing the file).

### Rules common to all encodings

- `crc XXXXXXXX`: 8 hex digits, the CRC-32 of zlib (`crc32()`, the IEEE polynomial, as Python's `zlib.crc32` and Java's `java.util.zip.CRC32`) of the block's **DECODED** bytes — exactly the bytes the block contributes: its sub-array in its own type, little-endian, column-major `i j k t c` ([5.3](#53-bytes-of-a-block)); for a signed jpegls, after undoing the offset; for a `<dicom>`, the stored values as section 4 defines them; for an aux, its array in column-major order (a `<png>`: its pixels, not the PNG). A reader that finds a mismatch raises `badCRC` for that block. MEASURED.
  WHY THE DECODED BYTES, and not the bytes in the file (as until 2026-10-14): what has to be right is the DATA. A decoder that gets it wrong — the old CharLS inside DCMTK, dicomread's sign extension, a near-lossless JPEG-LS — passes a crc of the file bytes and fails this one; the same crc holds whatever the encoding, so a block re-encoded (zlib → jpegls) keeps it; and a `<dicom>` block, which has no bytes in the file, can carry one. The price: a reader decodes before it can check, so corrupted input reaches the decoder (which must be robust: the C++ core did not crash in 10 000 fuzzed files), and a file cannot be checked without its codecs. A zlib block also has its own Adler-32 of the inflated bytes.
- `<missing>` takes no `crc` (it has no data): `badDescriptor`.
- An unknown encoding is an error WHEN THAT VALUE IS REQUESTED, not when the file is opened: a reader that cannot decode one aux can still return the volume. MEASURED (a build without zlib opened zlib files and failed only on their data).
- Byte order of the binary section is little-endian, always. **[OPEN]** 5.

---

## 5. Data

### 5.1 data is assigned in blocks

There is no declaration entry. data is the array `@I3D` holds, `data(i,j,k,t,c...)`, and each entry assigns one rectangular block of it:

```
data(:,:,:,1)       = <zlib single @0:3660439>  # 255 x 208 x 12 x 25, single
data(:,:,1:10,2:25) = <zlib single @3660440:80084192>
data(:,:,11,2:25)   = <zlib single @80084193:84107947>
data(:,:,12,2:25)   = <missing>
```

(Canonical form, [section 9](#9-the-canonical-form-what-a-writer-must-produce): complete subscripts, no open ranges. A reader also accepts the short forms of [5.2](#52-subscripts-of-a-block): `data` for `data(:,:,:,1)`, `2:` for `2:25`.) The first instant goes alone so that a viewer that only wants it reads one block — a typical split for a cine.

**To drop a block by hand, change its line to `<missing>`.** The binary is not touched: its bytes stay, orphaned and harmless, and every other offset is still right. (There is no sentinel between blocks: bytes like `---\n` can occur inside any block, so a reader could not trust one anyway.)

### 5.2 Subscripts of a block

- **A BLOCK IS ANY RECTANGULAR SUB-ARRAY**: every position takes any sub of [section 2](#2-header-grammar) (`7`, `3:10`, `2:`, `:3`, `:`). Slabs of planes, one sagittal plane `data(10,:,:,1)`, tiles `data(1:256,1:256,:,:)` ... all are blocks.
  EXCEPTIONS: `<dicom>` and `<jpegls>` blocks are made of WHOLE i,j planes ([section 4](#4-descriptors)), and a `<jpegls>` block holds at most 65535 rows (nj × planes).
- **POSITIONS 1–4** are i j k t. Their extents are `numel(X Y Z T)`.
- **MISSING TRAILING SUBSCRIPTS** (a reader accepts them; a canonical file never has them, [section 9](#9-the-canonical-form-what-a-writer-must-produce)): i, j or k missing means `:`; t missing means 1; a component missing means 1. So

  | written | means | |
  |---|---|---|
  | `data` | `data(:,:,:,1)` | the first instant (grey) |
  | `data(:,:,2)` | `data(:,:,2,1)` | plane k=2 of the first instant |
  | `data(:,:,:,2:)` | | all the other instants (grey: no 5th subscript) |

  This is NOT MATLAB's rule — MATLAB folds trailing dimensions into a linear index, so `A(:,:,2)` on a 4-D A means something else. Here there is no folding, ever.
- **POSITIONS 5 ON** are the component dims (dims 5, 6 ... of `@I3D`):

  | written | means |
  |---|---|
  | no 5th subscript | one component (grey) |
  | `data(:,:,:,:,1) = ...` | component 1 (the R plane of an RGB, say) |
  | `data(:,:,7,:,1:3) = ...` | all three components of plane 7 |
  | `data(:,:,:,:,1:3,1:3)` | a 3×3 tensor per voxel |

  The extent of each component dim is the largest index any entry uses in it, so the number of components is never declared; the coverage rule guarantees none is left unassigned.

### 5.3 Bytes of a block

The block `data(ir,jr,kr,tr,cr)` holds that sub-array in COLUMN-MAJOR order `i j k t c...`, i the fastest index — components in planes, as in `@I3D`, exactly what MATLAB writes with `fwrite( data(ir,jr,kr,tr,cr) )`. There is NO other order: an `order` option (it existed until 2026-10-13) is an unknown descriptor token, `badDescriptor`. One layout means one placing loop in every reader, and nothing a writer can get subtly wrong.

A `<dicom>` block covers one or more whole i,j planes. A single-frame `.dcm` covers exactly one (k,t). With `frames a:b` the frames are assigned, in order, to the (k,t) planes of the block, k fastest.

> Reader note: placing a block is ONE generic operation — copy an N-d box into an N-d array — whatever its subscripts are.

### 5.4 The type of `I.data`

It is not declared: it is the **LOSSLESS PROMOTION** of the types of all the blocks — the smallest type that holds every value of each:

- all int16 → int16 (the normal case)
- int16 with uint16 → int32; uint8 with int8 → int16
- an integer type with a float → single only if the integer fits in 24 bits, double if in 53
- a combination with no lossless promotion (uint64 with any signed type, int64 with a float) is an invalid file

`<missing>` blocks do not take part. (NOT the table of `DICOMstackRead/promote_`, which is not lossless: it gives uint32 for uint32 with int8.)

### 5.5 Coverage, and what a reader does with a hole

- Every element of data is assigned EXACTLY ONCE ([section 2](#2-header-grammar)). Overlap or gap = invalid file (the C++ core checks it at open time: no two boxes overlap and their volumes add up to the total).
- A part that could not be read is not a gap: it is an explicit `<missing>` block. A reader returns the value of the `fill` key there (default 0 for integers, NaN for single/double) AND reports it: `I.missing()` lists the blocks concerned. A hole that is seen beats a hole disguised as black.

### 5.6 Granularity is the writer's trade-off

Asking for plane 3 out of a zlib block `data(:,:,1:10,1)` means inflating all ten planes; asking for the sagittal plane i=10 out of k-slabs means inflating all of them. Large blocks compress better; small blocks, or tiles, are cheaper to read alone. The format does not choose.

### 5.7 Reading part of data: the first frame

The ONE partial read the readers offer (decided 2026-10-13) is the **first frame**: `data(:,:,:,1,c...)`, the first instant with all its components, shape `ni × nj × nk × 1 × c...`. A reader decodes ONLY the blocks that cut it — which is why the canonical form keeps the first instant in blocks of its own (the `data(:,:,:,1)` block of jpegls and zlib, split along k only if it does not fit; one per plane in Lazy).

| reader | call |
|---|---|
| C API | `i3d_first_frame_bytes(f)` , `i3d_read_first_frame(f, out, nbytes)` |
| C++ | `File::first_frame_shape()` , `first_frame_bytes()` , `read_first_frame(out, nbytes)` |
| MATLAB | `I = read_I3D(f,'firstFrame')` — an `@I3D` with `T = T(1)` |
| Python (ctypes) | `I3DFile(f).first_frame()` |

MEASURED on the 43 files of `tests/out_piechnik_canon`: the first frame equals `data(:,:,:,1)` bit for bit in all of them; on the 400-instant cine (102×128×12×400) it takes 0.006 s against 2.16 s for the whole volume (335×).

---

## 6. Rescale, window, image

```
rescale = SLOPE INTERCEPT          default 1.0 0.0
window  = CENTER WIDTH             in RESCALED units
```

- `I.data` ALWAYS returns the stored values (in the type of [5.4](#54-the-type-of-idata)).
- `I.values()` is `slope*data + intercept` in double, and `I.image()` the grey in [0,1] with the CLEAN linear window, which is NOT the DICOM formula (no −0.5, no width−1):
  ```
  image = clamp( ( values - (center - width/2) ) / width , 0 , 1 )
  ```
  NaN stays NaN.
- **ONE rescale for the whole stack** (decided 2026-10-13). There is no per-block or per-plane rescale: a `rescale` option inside a descriptor is an unknown token, `badDescriptor`. A stack whose RescaleSlope/RescaleIntercept change from slice to slice (PET, some CT) cannot be written: `write_I3D` refuses it (`write_I3D:rescaleNotCommon`) rather than lose the physical values in silence.
- **[OPEN]** 7: the v0 readers return rescale and window but do NOT compute `values()` or `image()`. Also open: what `image()` does when there is no window key.

---

## 7. Aux and info

| key | |
|---|---|
| `aux.NAME` | auxiliary arrays — thumbnails, masks, anything that is not the volume. A descriptor with `{shape}`. `I.aux(name)` returns null when the key does not exist. |
| `info.NAME` | metadata, a literal (a string or numbers). A DICOM attribute goes under its DICOM keyword: `info.SeriesDescription`, ... |

An aux array's bytes are the array in column-major order, as MATLAB holds it; no other meaning. The v0 readers decode aux in raw, zlib and png.

**Thumbnails** (what `write_I3D` writes from `I.INFO.thumbnail*`, e.g. the ones of DICOMstackCollect): `aux.thumbnailK = <png uint8 {rows cols 1 frames} ...>`, a MATLAB image: dim 1 = rows top to bottom, dim 2 = columns, then one frame per instant — stored as ONE grey PNG with the frames side by side (section 4). `read_I3D` puts it back in `I.INFO.thumbnailK`, identical. MEASURED.

**Info from a DICOMstack** (`write_I3D 'Info'`, default `'auto'`):

- **everything COMMON to every slice of the stack** (`commonINFO`) — patient identifiers, every UID and ID included —, in commented blocks in the order of the DICOMstack display: `# -- Patient`, `Study`, `Series`, `Image`, `Device`, `Dates and times`, then `UIDs and IDs` and `Acquisition and others`. Each Date is followed by its Time. An attribute that names Patient, Study or Series goes to that block first (so PatientID is in Patient, StudyInstanceUID in Study);
- Patient, Study and Device attributes that are not in `commonINFO` come from the first file (marked `# from the first file`): they do not change between the series of a study. Never a per-SLICE attribute (SOPInstanceUID, InstanceNumber, ImagePositionPatient...) as if it were the stack's;
- left out: what is not a DICOM attribute (`Private_*`, DICOMstack's own `x*`, what MATLAB's dicominfo adds: Filename, FileModDate, Width, BitDepth...), the geometry (it is in X Y Z and `transform`), the pixel encoding (BitsAllocated..., given by the type of data). PhotometricInterpretation IS written: with MONOCHROME1 white is 0;
- a DICOM person name (PN, which dicominfo returns as a struct) is written in DICOM's own text form, `"Family^Given^Middle^Prefix^Suffix"` without trailing `^`: `info.PatientName = "Cine3D^Breathing"`;
- `info.PlaneName`: the acquisition plane DICOMstack GUESSES from ImageOrientationPatient (`AX`/`COR`/`SAG` within 1e-3 rad, otherwise the nearest cardiac view `hla`/`vla`/`lvot`/`sa`, with no distance threshold). Not a DICOM attribute, and its comment says so;
- what cannot be written is skipped WITH A COMMENT that says why: a string with control characters, a sequence (struct), more than 16 numbers;
- a number is a list of doubles (so an integer attribute such as SeriesNumber reads `5.0`);
- RescaleSlope/Intercept and WindowCenter/Width, when common to the stack, become the `rescale` and `window` keys ([section 6](#6-rescale-window-image)), not `info.*`.
- `'Info'` with a list writes exactly those attributes, in that order, without blocks; `{}` writes none.

**Series and planes** (what is NOT common to the stack: only these, decided 2026-10-13). A stack can be the fusion of several series (DICOMstackCollect joins, say, one series per slice), and every plane is its own image. The writer adds, after the blocks above:

```
# -- Series and planes (planes: k fastest, then t)
info.series.SeriesInstanceUID  = "1.3...324.9.0.0"  # series 1
                                 "1.3...324.8.0.0"  # series 2
info.series.SeriesNumber       = 28.0               # series 1
                                 27.0               # series 2
info.series.SeriesDescription  = "SA STACK CINE_segmented"  # series 1
                                 "SA STACK CINE_segmented"  # series 2
info.planes.series             = 1  # data(:,:,1,1)
                                 2  # data(:,:,2,1)
                                 ...
info.planes.SOPInstanceUID     = "1.3...516"  # data(:,:,1,1)
                                 "1.3...514"  # data(:,:,2,1)
                                 ...
info.planes.AcquisitionTime    = "111158.962500"  # data(:,:,1,1)
                                 ...
info.planes.AcquisitionDate    = ...              (ONLY if not common to the stack)
```

- ONE VALUE PER ROW: the first on the line of the key, the others as continuation lines. Each row ends in a comment that says what it is: `# series n` in the series table, and in a per-plane list THE BLOCK OF DATA the plane belongs to — its own subscript when the block is that plane (Lazy, or a block of one plane), or `data(:,:,k,t) in <block>` when the plane is inside a bigger jpegls or zlib block. The comments are for humans; a reader ignores them, as always.
- A per-plane list has `nk·nt` values, plane (k,t) at position `k + nk·(t−1)` — k fastest, as everything in this format. `info.planes.series` is the series of each plane (1-based); 0 and `""` = a plane with no file.
- The series table holds each series once; `info.planes.series` points into it. The common attributes (`info.SeriesInstanceUID` ... above) are still written when the stack is a single series.
- The image UID is the MediaStorageSOPInstanceUID DICOMstack groups by, which the standard makes equal to SOPInstanceUID.
- `read_I3D` returns a string list as a cellstr row (`I.INFO.planes_SOPInstanceUID{q}`). MEASURED on the 10 series of the PIECHNIK short-axis stack (250 planes): 12 planes spread over the stack, each against its own `.dcm`, give the same SOPInstanceUID, series UID, number, description and AcquisitionTime.

The dot is just part of a name: `aux.thumbnailK` is one key, not a hierarchy. **[OPEN]** 8: whether readers expose `info.a.b` as nested.

---

## 8. What of `@I3D` is not in v0

| | what |
|---|---|
| **in v0** | X Y Z T, SpatialTransform, data (with components), thumbnails and chosen DICOM attributes (aux/info), rescale and window |
| **later** | LABELS + LABELS_INFO, FIELDS on the same grid — as more named arrays next to data, assigned in blocks the same way. **[OPEN]** 9 |
| **never** | POINTER (a MATLAB recipe), isGPU/GPUvars (runtime state), INFO.DICOMstack (a MATLAB object; selected attributes go to `info.*`), MESHES/CONTOURS/LANDMARKS until someone needs them |
| **[OPEN] 10** | the interpolation settings (SpatialInterpolation, BoundaryMode, OutsideValue, ...) as `info.*`, so a round trip keeps them |

---

## 9. The canonical form (what a writer MUST produce)

Sections 1–8 are the **general grammar**: what a READER must accept — files written by hand, edited, or by an older writer. This section is the **canonical form**: what a WRITER must produce. One way of writing each thing, so that nobody writes a minimal or clever file that only some readers understand. `write_I3D` produces only this, and `tests/check_roundtrip.m` checks every file it writes against it.

| what | canonical form | not allowed in a canonical file (but readers accept it) |
|---|---|---|
| layout | the header lines in this order: magic + comment, `X Y Z T`, `transform` (its description in full-line comments below it), `rescale`, `window`, `$DICOMDIR$` (Lazy), data blocks, `aux.*`, a BLANK line, `info.*`, a BLANK line, `---`. Those two blank lines and no other; comments at the end of their line otherwise (and `# -- block` titles in `info.*`). The comment of the first line ends with the size of data: `# write_I3D 2026-10-23 10:00:00, [ 192 x 156 x 14 x 30 ]` | any other order, other blank lines |
| what is visible (by default) | everything needed to read data — the magic line, `X Y Z T`, `transform`, `rescale`, `window`, ALL the data blocks and the `aux.*` — and the `info.*` of `'Visible'` (by default StudyDate StudyTime StudyDescription SeriesDescription DeviceSerialNumber Manufacturer ManufacturerModelName ImplementationVersionName InstitutionName InstitutionAddress), with the titles and comments that precede them. The other `info.*` (with the titles and comments that precede them) and `$DICOMDIR$` are the hidden part ([1.2](#12-a-hidden-part-of-the-header-decided-2026-10-23)), and `header = <hidden …>` goes right before the first data block. A file with nothing to hide has no `header` line. With `'Visible','all'` every `info.*` is visible; `$DICOMDIR$` stays hidden. The writer's C API says it per entry: `i3d_add_info_*( … , visible , … )`, 1 visible, 0 hidden | — |
| grids | a range `a : s : b` if the grid is uniform BIT FOR BIT under [3.1](#31-grids-x-y-z-t-all-four-required), otherwise the list in shortest form, with the `[n]` annotation | a near-uniform grid snapped to a range |
| `transform` | ALWAYS present, ALWAYS 12 numbers (3 rows), also for `eye(4)` or a pure translation | omitted (= identity); 3 numbers (= translation) |
| data subscripts | COMPLETE: i, j, k, t and every component dimension. i and j: `:`. k and t: `n` for one index, `:` for the whole dimension (of more than one), `a:b` otherwise. Component dimensions: always `n` or `1:n` | missing positions (`data`, `data(:,:,2)`); open ranges `a:` and `:b` |
| data encoding | FIXED BY TYPE: `uint8 int8 uint16 int16` (and logical, as uint8) → `<jpegls>`; any other type → `<zlib>`. From a DICOMstack with Lazy: `<dicom>`, one block per `.dcm`. A part that could not be read: `<missing>` | `<raw>`; zlib for a type jpegls holds |
| data blocks | jpegls and zlib alike: the FIRST INSTANT (all its planes and components) in ONE block, and the other instants in the FEWEST blocks that fit — whole instants if at least one fits, otherwise each instant split along k. What fits: 2^31−9 bytes (a Java array, for zlib), and for jpegls also 65535 rows. So a cine is `data(:,:,:,1)` + `data(:,:,:,2:nt)`, and a stack is one block | one block per plane where they fit in one; any other split by default |
| offsets | `@a:b`, both inclusive | `@a+n`, `@a+Inf`, `@a:EOF`, `@a` |
| hidden part | `header = <hidden @0:b>` right before the first data block, the hidden lines in their order, the block FIRST in the binary section followed by 0–31 zero bytes, NO crc ([1.2](#12-a-hidden-part-of-the-header-decided-2026-10-23)) | the block elsewhere; a gap of 32 bytes or more; a crc |
| `crc` | ON EVERY BLOCK THAT HAS DATA — jpegls, zlib, `<dicom>` — and on every aux: the CRC-32 of its decoded bytes ([section 4](#4-descriptors)). `<missing>` has none | a block or an aux without its `crc` |
| thumbnails | `aux.thumbnailK = <png uint8 {rows cols 1 frames} @a:b>`: ONE 8-bit grey PNG of rows × (cols·frames), the frames side by side ([section 7](#7-aux-and-info)), with ONLY the chunks IHDR, IDAT, IEND — so its bytes depend on the pixels alone (MATLAB's imwrite adds a tIME with the clock: two writes of the same image differed) | `<zlib>` / `<raw>` thumbnails, colour PNG, ancillary chunks (tIME, text...) |
| per-plane metadata | only `info.series.*` (SeriesInstanceUID, SeriesNumber, SeriesDescription) and `info.planes.*` (series, SOPInstanceUID, AcquisitionTime, and AcquisitionDate if not common), as lists, k fastest, ONE VALUE PER ROW with its comment (`# series n` / the block of data of the plane) ([section 7](#7-aux-and-info)) | any other per-plane attribute; several values on a row |
| `rescale` | ONE key for the whole stack (or none = 1.0 0.0); a writer refuses a stack whose rescale changes from slice to slice ([section 6](#6-rescale-window-image)) | — (there is no per-block rescale any more) |
| text | UTF-8 as it is, no escapes but `\"` and `\\` ([section 1](#1-file-layout)) | — |
| numbers | shortest round-trip form with `.0` ([section 2](#2-header-grammar)) | anything else |

WHY jpegls for the 8/16-bit integers: MEASURED on real series (`bench/real_jpegls_results.txt`), 1.2–1.8× smaller than zlib and 5–16× faster to write. The other types do not fit in JPEG-LS. WHY png for thumbnails: decided 2026-10-13; zlib compressed them badly (in a Lazy file the thumbnail was the whole file).

### 9.1 `write_I3D` (MATLAB)

```
write_I3D( I , filename , options ... )
```

There is no encoding argument: the canonical form fixes it (passing `'raw'`, `'zlib'` or `'jpegls'` is the error `write_I3D:badEncoding`). Nor a `'CRC'` option (since 2026-10-14): every block and every aux carries its crc, always; passing `'CRC'` is `write_I3D:badOption`.

| option | |
|---|---|
| `'Comment'` | the comment of the first line (default `write_I3D <date>`) |
| `'Blocks'` | `'auto'` (default) \| `'volume'` \| `'t'` |
| `'MaxBlockBytes'` | the largest block, uncompressed (2^31−9, a Java array's limit) |
| `'Hidden'` | the I3Db variant ([1.1](#11-the-hidden-variant-i3db)) |
| `'Lazy'` | from a DICOMstack: `<dicom>` references instead of pixels |
| `'Verify'` | (with Lazy, default true) check each reference with the reader |
| `'DicomDir'` | the value of `$DICOMDIR$` (default: the common root of the files) |
| `'Info'` | the DICOM attributes for `info.*`: `'auto'` (default, everything common to the stack, [section 7](#7-aux-and-info)), a list, or `{}` = none |
| `'Visible'` | the `info.*` names that stay visible (`*` wildcard); default the 10 of section 9 (the layout rows). `'all'`: every `info.*` visible; `{}`: none. The others go to the hidden part ([1.2](#12-a-hidden-part-of-the-header-decided-2026-10-23)), as a block FIRST in the binary section, then 0–31 bytes of gap, without crc. Combines with `'Hidden'` |

- **Blocks `'auto'`** (zlib and jpegls): the FIRST INSTANT in its own block, the others in the FEWEST blocks that fit MaxBlockBytes (and, in jpegls, 65535 rows); an instant that does not fit is split along k. `'volume'`: all of data in the fewest blocks; `'t'`: one block per instant. Lazy: one block per plane.
- From DICOMstack, X and Y come out as ranges and Z as a list.
- A thumbnail that is not uint8 grey is not written: it becomes a `# aux.X skipped: ...` comment.
- **`'Lazy'`:** a plane is REFERENCED only if its file
  - is in a lossless transfer syntax the C++ reader decodes (native LE/BE, RLE, JPEG lossless .57/.70, JPEG-LS lossless .80),
  - is one single-frame grey plane of the class of `I.data`,
  - appears once (its path may carry any character but control characters: the header is UTF-8),
  - and — with `'Verify'` — THE C++ READER gives EXACTLY that plane of `I.data`.

  With the reader and not with dicomread: MEASURED (`tests/probe_jpll.m`), dicomread of R2022a decodes JPEG lossless of 10 and 15 bits wrongly and does not sign-extend when BitsStored < BitsAllocated, so the file must reproduce `I.data` as the reader will see it. Otherwise the plane is materialised, in the encoding its type fixes. A plane with no file and all zeros is `<missing>`. The `$DICOMDIR$` line says how many planes were referenced, materialised and missing.
  Each `<dicom>` reference carries the crc of ITS PLANE OF `I.data` — what the writer had, not what a reader may later see —, so the guarantee of `'Verify'` travels with the file: a referenced `.dcm` that later changes, or that another reader decodes differently, gives `badCRC` instead of other pixels. Without `'Verify'` the crc is still there, and a wrong reference fails when it is read rather than when it is written.

---

## 10. A complete example

Real `write_I3D` output with the defaults (section 9): three slices of a short-axis cine, from three series, collected by `DICOMstackCollect(F,'onlyK','info')`; 182 × 224 × 3 × 25, uint16, 2.4 MiB. MEASURED: read back exactly by `read_I3D`.

What anyone sees — the header as written, and what `i3dinfo --header` or `showI3Dfile` give. Everything needed to read the volume is here:

```
I3D 0.1  # write_I3D 2026-10-24 00:25:50, [ 182 x 224 x 3 x 25 ]
X[182] = 0.0 : 1.7857142686844 : 323.2142826318764
Y[224] = 0.0 : 1.7857142686844 : 398.21428191662125
Z[3]   = 0.0 9.999997924440159 19.99999801794808  # not uniform: steps 9.999997924440159 .. 10.000000093507921
T[25]  = 0.0 : 1.0 : 24.0
transform =  0.5094810470925264    -0.29231538930220785    -0.809308825993258      10.997576549529
             0.8424009484735542    -0.022353693757300598    0.53838736462352     -146.18483502633
            -0.17546995373669877   -0.9560606808945254      0.2348579778997409    264.92239171762
# rot 97.9904 deg about [-0.7545 -0.32 0.5729] (orthonormal to 2.7e-14)
# turn -76.1985 deg about x, then 10.106 about y, then 58.8346 about z (fixed axes)
header = <hidden @0:2921>  # the rest of the header
data(:,:,:,1)    = <jpegls uint16 @2938:76206 crc 3546fe20>  # 182 x 224 x 3 x 25, uint16
data(:,:,:,2:25) = <jpegls uint16 @76207:1804968 crc cb23ba8f>
aux.thumbnailK = <png uint8 {98 384 1 25} @1804969:2499206 crc 6ddd56a9>

info.StudyDate = "20171028"
info.StudyTime = "101635.290000"
info.StudyDescription = "Cardiac^32_CHANNEL"
info.SeriesDescription = "SA STACK CINE_segmented"
info.DeviceSerialNumber = "69648"
info.Manufacturer = "SIEMENS"
info.ManufacturerModelName = "Avanto_fit"
info.ImplementationVersionName = "OFFIS_DCMTK_360"
info.InstitutionName = "OCMR"
info.InstitutionAddress = "Headington StreetNo,Oxford,District,GB,Zip Code"

---
```

The binary section starts with the `<hidden>` block (bytes 0..2921), then 16 zero bytes, then the first instant (`@2938`). What the block holds — the `info.*` that are not visible, read as if they were written in the place of the `header` line (316 lines; here the first 12 and the start of the per-plane lists):

```
# -- Patient
info.PatientBirthDate = "19670304"
info.PatientID = "O1.5T_C00-00_422"
info.PatientPosition = "HFS"
info.PatientName = "Cine3D^Breathing"
info.PatientSex = "M"
info.PatientAge = "050Y"
info.PatientSize = 1.76
info.PatientWeight = 83.0
# -- Study
info.StudyInstanceUID = "1.3.12.2.1107.5.2.41.69648.30000017102717151705200000007"
info.StudyID = "1"
...
# -- Series and planes (planes: k fastest, then t)
info.series.SeriesInstanceUID  = "1.3.12.2.1107.5.2.41.69648.2017102811273129917514324.2.0.0"  # series 1
                                 "1.3.12.2.1107.5.2.41.69648.2017102811273129917514324.1.0.0"  # series 2
                                 "1.3.12.2.1107.5.2.41.69648.2017102811273129917514324.0.0.0"  # series 3
info.series.SeriesNumber       = 21.0  # series 1
                                 20.0  # series 2
                                 19.0  # series 3
info.series.SeriesDescription  = "SA STACK CINE_segmented"  # series 1
                                 "SA STACK CINE_segmented"  # series 2
                                 "SA STACK CINE_segmented"  # series 3
info.planes.series             = 1  # data(:,:,1,1) in data(:,:,:,1)
                                 2  # data(:,:,2,1) in data(:,:,:,1)
                                 3  # data(:,:,3,1) in data(:,:,:,1)
...
```

The whole study (8118 files, 42 stacks) in `tests/out_piechnik_canon` was written on 2026-10-14, before the hidden part and the current layout, with 8 rotating option sets (Lazy, Hidden, Verify off, Info lists, a comment of its own): 75.4 MiB on disk for 454 MiB of pixels (log: `convert_study_multi.log`; its 15 I3Db files re-obfuscated on 2026-10-24). MEASURED: all 42 read back exactly by `read_I3D`, and the Python reference reader (pydicom for `<dicom>`) agrees with the DLL (DCMTK) bit for bit on all 42 (`tests/check_dicom_py.py`).

---

## 11. Open items, in one place

| # | item | section |
|---|---|---|
| 1 | ~~header character set~~ — **decided 2026-10-13: UTF-8** (keys ASCII) | 1 |
| 2 | units, and T: DICOMstack gives instant indices, not TriggerTime | 3.2 |
| 3 | logical as its own type name | 4 |
| 4 | ~~integrity check for a referenced `.dcm`~~ — **decided 2026-10-14**: the crc of a block is of its DECODED bytes, so a `<dicom>` carries the crc of its pixels | 4 |
| 5 | little-endian always: confirm | 4 |
| 6 | more encodings and filters (zstd, shuffle, delta, JPEG 2000) — measured in `bench/`, not adopted. (~~several planes per `<jpegls>` block~~ — **decided 2026-10-14**: whole planes stacked in one image, at most 65535 rows) | 4 |
| 7 | `values()` / `image()` in the readers; `image()` without a window key. (The per-block rescale is gone: one rescale per stack, decided 2026-10-13) | 6 |
| 8 | `info.a.b` as nested in the readers | 7 |
| 9 | LABELS / FIELDS as arrays next to data | 8 |
| 10 | interpolation settings in `info.*` | 8 |
| 11 | NaN in the HEADER loses sign and payload (MATLAB's NaN is `fff8000000000000`, strtod's `7ff8000000000000`): matters for a signed-NaN sentinel; binary blocks keep the bits | 2 |
| 12 | what a reader does with another version, and confirm "unknown keys are ignored" (~~an unknown key with `( )`~~ — **decided 2026-10-23**: ignored too) | 1, 2 |
| 13 | `<dicom>` with SamplesPerPixel > 1 (colour), and JPEG 2000 (needs a decoder the bundled DCMTK does not have) | 4 |
| 14 | an UNKNOWN DESCRIPTOR OPTION: today it fails the file at open (both readers), while an unknown KEY is ignored. Proposed rule: an option that changes the bytes (a filter) must fail; say which, if any, may be ignored | 2, 4 |
| 15 | "any key may take a descriptor": the v0 readers reject one in X Y Z T / transform / rescale. Restrict v0 to data and aux, or implement it | 2 |
| 16 | lossless promotion of MIXED block types: specified and implemented in C++, produced by nobody, untested, not in the Python reader. Keep, or require one type per file in v0 | 5.4 |
| 17 | a reader without `<dicom>` (the JS/WebAssembly build) is conforming? | 4 |
| 18 | PhotometricInterpretation MONOCHROME1 in a `<dicom>`: the stored values come back as stored, and nothing in the file says white = 0. (The writer now records PhotometricInterpretation in `info.*`; the readers do not act on it) | 4 |
| 19 | ~~PER-SLICE attributes~~ — **decided 2026-10-13**: only the series (UID, number, description) and, per plane, its series, SOPInstanceUID and AcquisitionTime, as string/number lists `info.series.*` / `info.planes.*` (section 7) | 7 |

---

## 12. Tests

| file | what |
|---|---|
| `tests/check_num2str.m` | shortest-form numbers vs Python (240 003 values) |
| `tests/check_roundtrip.m` | the battery (94 files): every case × every writer option, read by THREE readers (Python reference, the DLL by ctypes, the DLL by `calllib` from MATLAB), bit for bit, thumbnails (PNG) included; EVERY file `write_I3D` writes is checked to be canonical (section 9: complete subscripts, 12-number transform, `@a:b`, the encodings of the profile, a crc on every block and aux); with negative controls (a corrupted byte; a crc that does not match the data, which all three must refuse with `badCRC`) and NON-canonical files the readers must still accept (header edited by hand, `@a+n` / `@a+Inf` / `@a:EOF`, a raw block); hide/show byte for byte. `check_roundtrip(outdir)` keeps the files |
| `tests/check_dicom.m` | `<dicom>` vs dicomread over the variety of `d:\DICOMS` |
| `tests/probe_jpll.m` | who decodes JPEG lossless 10/15-bit right (RLE as the arbiter) |
| `tests/check_dicom_py.py` | lazy files: pydicom vs DCMTK, bit for bit |
| `tests/check_invalid.py` | 56 hand-made files and 2 calls to the C API with NULL (2026-10-23: every case where the two readers used to diverge, files that would make a reader allocate gigabytes, `( )` on an unknown key; and before that:) 34, bad and odd-but-valid: each reader must refuse with the right error (bad magic, no terminator, repeated key, `( )` outside data, fill out of range, hidden stream cut / with a byte too many, range not closing, grid not increasing, overlap, gap, unknown option, an `order` option, a `rescale` option, a Latin-1 header, raw length, truncated, bad crc, a zlib crc of the COMPRESSED bytes, a crc on `<missing>`, undefined variable, near-lossless jpegls, a jpegls block that is not whole i,j planes, a jpegls image of 65536 rows) or read exactly (unknown key, CRLF, crc, a zlib crc of the decoded data, fill, NaN default, hidden, a UTF-8 header with accents, a jpegls block of two planes) |
| `tests/check_mi3d.py`, `tests/check_mi3d.m` | the container `.mi3d` ([section 14](#14-the-container-mi3d-decided-2026-10-24)): 47 hand-made cases for the two readers, and the MATLAB writer end to end. `python check_mi3d.py DIR` compares the DLL and Python on every `.mi3d` of DIR |
| `tests/check_dicom_fixtures.py` | `<dicom>` WITHOUT `d:\DICOMS` (15 cases; 2026-10-23: a `$$` path, a lone `$`, a `$` in a variable's value, `{…}` in a path): synthetic `.dcm` with known values (native 12-bit, signed 12-bit sign extension, RLE, JPEG-LS, multi-frame and `frames a:b`), a variable overridden at open, a `\` path, a non-ASCII folder; the crc of a `<dicom>` (RLE, JPEG-LS, `frames`, signed) and a `.dcm` that no longer matches its crc (`badCRC`) |
| `tests/try_*.m`, `convert_study.m` | real series and a whole study (not regression tests: they depend on `d:\DICOMS`) |
| `tests/dll_selftest.m` | a hand-made `.i3d` read through `calllib` (no `@I3D`, no writer): grids, transform, data with a `<missing>` and its fill, rescale/window, and the right error id for a bad file |

---

## 13. Where the v0 readers do not follow this text yet

Found by the audit of 2026-10-13 (`AUDIT_2026-10-13.md`, which has the details). The SPEC is the reference; these are defects of the readers, not of the format.

| AUDIT | what the text says | what the reader does | status |
|---|---|---|---|
| 2.1 | a `"path"` accepts `/` and `\`; the only string escapes are `\"` and `\\` | the C++ core took EVERY `\` in a descriptor string as an escape: `"sub\dir\x.dcm"` opened `subdirx.dcm` | **fixed** 2026-10-13, both readers; `check_dicom_fixtures.py` |
| 2.2 | a path is a path | the C++ core could not open a path with non-ASCII characters (`...\año\f.i3d`), nor DCMTK a `.dcm` there | **fixed**: paths are UTF-8, opened wide; DCMTK built with wide-char file I/O; `check_dicom_fixtures.py` |
| 2.3 | `<jpegls>` is NEAR = 0 | the C++ core decoded a near-lossless codestream without complaint (NEAR = 3: values off by up to 3) | **fixed**: `badBlock` in both readers; `check_invalid.py` |
| 2.4 | — | `read_I3D(f,'NOdata')` decoded the aux arrays | **fixed** |
| 2.5 | blocks exist so that a part can be read alone ([5.6](#56-granularity-is-the-writers-trade-off)) | no reader API read a part: they read every block | **fixed** for the one partial read wanted: the first frame ([5.7](#57-reading-part-of-data-the-first-frame)), 335× faster on a 400-instant cine |
| 2.10 | `( )` is defined for data only | an `aux.x(1:2) = ...` was accepted and its subscripts ignored | **fixed**: `badHeader` in both readers |
| — | `<dicom>` decodes the transfer syntaxes of section 4, JPEG-LS included | **EVERY JPEG-LS DICOM crashed the C++ reader** (access violation, 4 of 4 real files): DCMTK's JPEG-LS codec carries an old CharLS whose functions have the same names as the bundled CharLS 2.4.5, and the linker kept one. Found 2026-10-13 by the new synthetic DICOM tests; never seen before because dicomread cannot decode JPEG-LS, so those files had no reference | **fixed**: the C++ core takes the encapsulated frames from DCMTK and decodes them with its own CharLS; dcmjpls/dcmtkcharls no longer linked. The 4 real files: DLL == Python |

---

## 14. The container `.mi3d` (decided 2026-10-24)

**Implemented** (2026-10-24): `write_MI3D`, `append_MI3D`, `remove_MI3D`, `read_MI3D` (MATLAB), `i3d::Container` and the C API, the Python reference reader. One file that holds several `.i3d` files (the series of a study, say), each byte for byte as it was written, so that any one of them can be opened without reading the others.

```
MI3D 0.1  # write_MI3D 2026-10-24, 9 stacks
i3d(1) = <i3d @0:4355291>         # 001.Ax FIESTA ungated (AX).i3d [ 512 x 512 x 27 x 1 ]
i3d(2) = <i3d @4355330:9917404>   # 002.SA cine (SA).i3d [ 256 x 256 x 12 x 30 ]
i3d(3) = <missing>
...
i3d(9) = <i3d @61092866:66210140>

header = <hidden @66210178:66211067>  # the rest of the header

# -- common to every stack
info.StudyDate = "20250308"
info.StudyDescription = "Cardiac MR"
info.InstitutionName = "..."
#                                     (8192 bytes of reserve: a comment line of spaces)
---
****** # 001.Ax FIESTA ungated (AX).i3d [ 512 x 512 x 27 x 1 ]
I3D 0.1  # write_I3D ...                    <- stack 1, byte for byte
...
++++++ # 001.Ax FIESTA ungated (AX).i3d
****** # 002.SA cine (SA).i3d [ 256 x 256 x 12 x 30 ]
...
<the <hidden> block of the container>      <- always the LAST block
```

### 14.1 Layout and header

- Extension `.mi3d`. The file starts with exactly `MI3D 0.1` (nothing before it, as in [section 1](#1-file-layout)), optionally followed by a comment. The header is UTF-8 text lines up to the first `---` line; the binary section follows, and **all offsets are relative to the start of the binary section**. The rules of [section 2](#2-header-grammar) apply to the header (comments, literals, continuation lines, CRLF, UTF-8, a repeated key is `badHeader`).
- The container knows three keys: `i3d(n)`, `header` and `info.*`. Any other key is ignored, as an unknown key in an `.i3d`. In particular `X`, `data`, `aux.*` mean nothing in a container.
- **[OPEN]** an `MI3Db` variant (the whole header of the container hidden, as I3Db). Not proposed for now: the `<hidden>` part ([14.3](#143-the-summary-info-and-the-hidden-part)) covers what the container hides.

### 14.2 Members: `i3d(n)`

- `i3d(n) = <i3d @where>` declares member n: the bytes `@where` of the binary section are a complete `.i3d` file. `n` is ONE integer ≥ 1, digits only, as the subscripts of data ([5.2](#52-subscripts-of-a-block)): a range (`i3d(2:3)`), `end` or an empty `i3d()` is `badSubscript`. Each n appears at most once (`badHeader`). The order of the lines does not matter; `n` orders the members. A writer writes them in increasing n.
- `@where` takes any form of [section 4](#4-descriptors) (`@a:b`, `@a+n`); the canonical form is `@a:b`. `crc` is optional (the CRC-32 of the member's bytes); `write_MI3D` does not write it, since every member carries the crcs of its own blocks. Another encoding, a type or a `{shape}` is `badDescriptor`.
- **Members have no name, only a number.** The name of the file a member came from is a TAG: the writer puts it in the comments, and no reader needs it.
- **Holes.** The container has N members, N the largest n declared. An n in 1..N without a line, or with `i3d(n) = <missing>`, is a HOLE. `<missing>` is needed only for a hole at the end (delete the last member and N stays). Asking for a hole gives nothing — `[]` in MATLAB, `None` in Python, NULL with `missingMember` in C —; asking for n < 1 or n > N is `badIndex`. WHY HOLES: the numbers are stable. Deleting a member is dropping its line; no other member changes its number.
- **A member is an `.i3d` file of any variant**: plain, I3Db, with a hidden part, Lazy. It is read as if the bytes `@where` were the whole file: its offsets are relative to ITS OWN binary section, and its size is the size of the range (the checks of [section 4](#rules-common-to-all-encodings) against the size of the file use it). A member that is a `.mi3d` is `badBlock` (one level).
- **Paths in a Lazy member** (`<dicom "rel/path.dcm">`) are relative to the folder of the CONTAINER. A member copied from another folder keeps its bytes, so its relative paths now point elsewhere: `write_MI3D` refuses such a member unless the folders agree or it is told to (`'Lazy','keep'`).
- Bytes of the binary section that no descriptor points to are ignored, wherever they are. **The separators are not part of the format**: the writer puts `****** # tag [ dims ]` LF before each member and LF `++++++ # tag` LF after it, so that the file can be looked at with `less`; a reader seeks to `@a` and never reads them. Another writer may put anything there, or nothing.

### 14.3 The summary info and the hidden part

- The `info.*` of the container are a SUMMARY: an `info.key` is there when every member present has it, with the same value. The members keep theirs — **the members are the authority**; a reader takes the summary as it is and does not check it.
- An `info.key` of the summary is visible when it is visible in every member, and goes into the container's hidden part when it is hidden in any member. **An I3Db member counts as hiding all its `info.*`**: its whole header is obfuscated, and the summary must not show in plain text what it hides.
- `header = <hidden @a:b>` is exactly that of [1.2](#12-a-hidden-part-of-the-header-decided-2026-10-23) (same encoding and constants, read as if written in its place, one level, the dump shows the line and not its content), with one difference of layout: **in a container the `<hidden>` block is always the LAST block** of the binary section. WHY: adding a member then writes after the members and never moves them, and the hidden block, which may change with every member added, is rewritten at the end.

### 14.4 Adding and removing members without rewriting the file

The header is at the start, so a header that grew would move the whole binary section. The writer avoids it with a RESERVE:

- `write_MI3D` ends the header with a comment line of spaces (8192 bytes by default, `'Reserve'`), so that the header up to its `---` has a fixed length R. A header that changes is rewritten IN PLACE with the reserve adjusted to keep R.
- **Adding member N+1** (`append_MI3D`), in this order, so that the file is valid with the old content until the last step:
  1. write the new member, with its separators, at the end of the file;
  2. write the new `<hidden>` block of the container after it (the old one stays where it was, as unreferenced bytes);
  3. rewrite the header in place: `i3d(N+1)`, the summary recomputed, `header` pointing to the new block.

  Only step 3 is not atomic, and it is a few KB. If the header no longer fits in R, that append rewrites the whole file to a temporary one with a new reserve and renames it over the old one. With 8 KB and about 100 bytes per member line, about every 60 members.
- **Removing member n** (`remove_MI3D`): rewrite the header in place without its line (or with `<missing>` if it was the last). Its bytes stay until a compaction. If the summary changes, its new `<hidden>` block goes at the end; if it does not, the old one stays where it is.
- **Compacting** (`write_MI3D` on a container) rewrites the file without unreferenced bytes, with the hidden block last and a new reserve. It KEEPS the numbers and the holes; `'Renumber'` closes the holes.

### 14.5 Readers

| | list | open member n |
|---|---|---|
| MATLAB | `C = read_MI3D(f)`: `N`, `present`, `offset`/`length` (in the file), `tag` (from the comments), the summary `INFO`, `header`, `entries` | `I = read_MI3D(f, n, ...)` — the options of `read_I3D` (also `read_I3D(f, 'Member', n)`); `[]` for a hole |
| C | `mi3d.dll` (`mi3d_c.h`): `mi3d_open` / `mi3d_count` / `mi3d_present` / `mi3d_range` / `mi3d_tag` / `mi3d_entry_*` / `mi3d_header` (`i3d::Container` in C++) | `mi3d_range(m, n, &offset, &length)`, then `i3d_open_window(path, offset, length, nvars, names, values)` of `i3d.dll` → an `i3d_file`, as `i3d_open` |
| Python | `read_mi3d(path)` (`tests/read_i3d.py`), `MI3DFile` (`tests/i3d_ctypes.py`, over `mi3d.dll`) | `read_mi3d(path, n)` → as `read_i3d`, `None` for a hole |

A member is read through its WINDOW of the file: the C++ core opens the container, checks the member, and reads it as a file of `length` bytes that starts at `offset`. An `.mi3d` opened as an `.i3d` is `badMagic` (with a hint), and an `.i3d` opened as an `.mi3d` too.

Errors: `badMagic` (not `MI3D 0.1`), `badSubscript`, `badIndex`, `missingMember`, and those of the member itself.

MEASURED: `tests/check_mi3d.py` (both readers on hand-made containers: text, `<hidden>` and I3Db members, holes, `<missing>`, lines in any order, `@a+n`, `@a:EOF`, anything between members, crc, CRLF, a `<hidden>` part holding a member line, an empty container; and bad: the magic, every bad subscript, a repeated n, other descriptors, past the end, a member that is a `.mi3d`, a window that cuts the member's header or its binary, a bad crc; a Lazy member resolved from the container's folder) and `tests/check_mi3d.m` (the four MATLAB functions: members byte for byte, the summary, append and remove in place with the binary untouched, 12 members appended one by one through a full rewrite, compaction, `'Renumber'`, `lazyFolder`; and every container written, read by the DLL and by Python).

---

## Changes

| date | change |
|---|---|
| 2026-10-13 | first draft; converted from `SPEC.txt` to Markdown |
| 2026-10-13 | **I3Db: the inflated size N removed from the preamble.** It was `"I3Db" \| L \| N \| hidden`, binary at `20 + L`; it is now `"I3Db" \| L \| hidden`, binary at `12 + L`. The zlib stream must take exactly L bytes. N bought nothing that zlib's Adler-32 does not, and a reader had to trust it before checking anything. Files written before this change do not open; the ones in `tests/out_piechnik_mix` were converted |
| 2026-10-13 | open items 14–18 and section 13 added from the audit |
| 2026-10-13 | writer: `info.*` by default is EVERYTHING common to the stack (patient identifiers and every UID/ID included), in blocks like the DICOMstack display; person names as `"Family^Given"`; `info.PlaneName`; skipped attributes say why. The rotation comment of `transform` in prose, without the translation |
| 2026-10-13 | open item 19 |
| 2026-10-13 | audit fixes in the readers (section 13); JPEG-LS DICOM decoded by the bundled CharLS; new tests `check_invalid.py`, `check_dicom_fixtures.py` |
| 2026-10-13 | **the canonical form (section 9)**: readers keep the general grammar; writers must produce one form — complete subscripts, `transform` always 12 numbers, only `@a:b`, the encoding fixed by type (jpegls for 8/16-bit integers, zlib otherwise, dicom with Lazy), thumbnails as one grey PNG with the frames side by side. `<png>` is no longer reserved: decoded by the bundled lodepng. `write_I3D` loses its encoding argument |
| 2026-10-13 | the string-list literal; `info.series.*` and `info.planes.*` (open item 19 decided); section 10 regenerated with the final writer |
| 2026-10-13 | **`order` removed from the format** (readers too): the bytes of a block are always column-major `i j k t c`; an `order` option is `badDescriptor` |
| 2026-10-13 | canonical PNG thumbnails carry only IHDR, IDAT, IEND (imwrite's tIME made two writes of the same image differ) |
| 2026-10-13 | **the header is UTF-8** (open item 1); **one rescale per stack**, the per-block `rescale` option removed (a writer refuses a stack whose rescale varies); **the first frame** as the one partial read (5.7: C API, MATLAB, Python); per-series and per-plane lists ONE VALUE PER ROW, each with its series / its block of data in a comment |
| 2026-10-14 | **the `crc` is of the DECODED bytes**, no longer of the bytes in the file (section 4); a `<dicom>` block carries one (open item 4 decided); `<missing>` takes none; **the canonical form has a crc on every block and every aux**, and `write_I3D` loses its `'CRC'` option. Files written before this change with a crc on a compressed block (zlib, jpegls, png) now fail with `badCRC`: the ones in `tests/` were rewritten |
| 2026-10-30 | **the writer hides per entry, nothing else**: `i3d_add_info_*( … , visible , … )` with 1 (visible) or 0 (hidden part); the options `Visible` and `HideKeys` of the C API, and `write_I3D 'HideKeys'`, are gone. What reading data needs is always visible, `$DICOMDIR$` always hidden; the titles and comments of the info section go with the entry that follows them. `i3d_add_comment( w , text )`: the line above the next piece given, or with a leading backspace at the end of the line of the last one. `i3d_set_Xgrid` … `i3d_set_Tgrid` replace `i3d_set_grid` |
| 2026-10-25 | **one writer, in C++** (`cpp/i3d_write.cpp`, `i3d::Writer`, its C API in `i3d_c.h`): what `write_I3D.m` did -- the canonical form, the hidden part, Lazy references with their verification, I3Db, hide/show (`i3d_rewrite`) -- is now in `i3d.dll`; the container's writing (`mi3d_write`, `mi3d_append`, `mi3d_remove`, `mi3d_compact`) and reading, in a second DLL, `mi3d.dll`; `i3d.dll` opens a member by its window (`i3d_open_window`). **No MEX**: MATLAB loads the two DLLs with `loadlibrary` and calls them with `calllib`; its `.m` only translate an `@I3D` and its DICOMstack. MEASURED (233 files written both ways from the same `@I3D`, synthetic and the 9 series of `exampleDICOMS`, every option): the same header up to the offsets, the data blocks (zlib, jpegls) byte for byte, the same decoded content; only the thumbnails' PNG bytes differ (lodepng, not imwrite). The DLLs are built with `/DNDEBUG` (without it CharLS was 1.6× slower) |
| 2026-10-24 | **section 14: the container `.mi3d`**: `i3d(n) = <i3d @a:b>`, members by number with holes, a summary `info.*` (an I3Db member hides all its own), its `<hidden>` block always last, a reserve in the header to add and remove members without rewriting the file. Implemented: `write_MI3D` / `append_MI3D` / `remove_MI3D` / `read_MI3D`, `i3d::Container` and its C API, `read_mi3d` in Python; the C++ core reads any file through a window. Tests `check_mi3d.py`, `check_mi3d.m`. The Python reader now checks that a `<png>` aux is inside the file (a PNG cut before its IEND decoded anyway) |
| 2026-10-24 | **by default, all the data blocks and the `aux.*` stay visible**: the hidden part holds the `info.*` that are not in `'Visible'` (with their titles and comments) and `$DICOMDIR$`. Section 10 regenerated |
| 2026-10-24 | **the obfuscation changes** (sections 1.1, 1.2): the zlib stream is REVERSED before the XOR, and Knuth's multiplier is gone. Each with its own constants: I3Db `0x5C2D8F1B` / `0x49334462` (`"I3Db"`), the `<hidden>` block `0x7A3F5C29` / `0x68696464` (`"hidd"`). Files written before do not open: the 26 I3Db files in `tests/` were converted (same zlib stream, re-obfuscated; binary untouched) |
| 2026-10-23 | **the default canonical file has a hidden part**: only what a viewer needs to start (grids, transform, rescale, window, the first instant) and 10 `info.*` stay visible (`write_I3D 'Visible'`, `'all'` to turn it off); the `<hidden>` block is FIRST in the binary section with a gap of 0–31 bytes. Layout for every file: the size of data in the first line's comment, the description of `transform` in comment lines below it, a blank line before `info.*` and one before `---`. Section 10 regenerated from a real cine |
| 2026-10-23 | **a hidden PART of the header** (section 1.2): `header = <hidden @a:b>`, encoded like I3Db, read as if written in its place; it combines with I3Db, and the dump of the header does not show it. `write_I3D 'HideKeys'` |
| 2026-10-23 | **a literal `$` in a path is `$$`**; a lone `$` is `badVariable`; a variable's value is literal (section 2). **The file starts with exactly `I3D 0.1` / `I3Db`** (section 1). Subscripts are digits only and never empty; `frames` is dicom only, 1 ≤ a ≤ b. The two readers now agree on the 16 cases where they diverged (`check_invalid.py`): the DLL no longer accepts `1:-1`, `data()`, `frames 0:0`, `<png>` as data or invalid UTF-8 (surrogates, overlong); the Python reader no longer misreads `{…}` inside a path, accepts a non-finite grid, a repeated key, two types, a bad `rescale`/`window`, an aux raw of the wrong length or 257 copies of a block |
| 2026-10-23 | **`( )` on an UNKNOWN key is ignored** (section 2; on a known key other than data it is still `badHeader`): forward compatibility for arrays assigned in blocks. **A grid has at most 2^24 values** (3.1). Readers: a block, an I3Db header and a PNG are checked against the size of the file (and a zlib block against 1032:1) BEFORE any allocation; `i3d_open(NULL)` is `badInput`, not a crash |
| 2026-10-14 | **a `<jpegls>` block holds whole i,j planes** (any k, t and component range), stacked in ONE image of ni × (nj·planes), at most 65535 rows (open item 6, its jpegls part, decided); the canonical form blocks jpegls like zlib — the first instant in one block, the rest in the fewest. Old files (one plane per block) stay valid. The files in `tests/` were rewritten |
