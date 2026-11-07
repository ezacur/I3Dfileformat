# I3D — user guide

I3D is a file format for **one medical image stack per file**: a 3D or 4D volume (a cine, a stack of slices, a 3D acquisition…) with its exact geometry and its metadata. Its companion, **`.mi3d`**, is a container that holds several `.i3d` files — typically all the series of one study — in a single file.

This guide explains what the format is, what it is good for, and how to use it from the command line, MATLAB, C#, Python and C/C++. The normative text, with every rule and every decision, is [`SPEC.md`](SPEC.md); this guide links to it where it matters.

---

## 1. What a file looks like

An `.i3d` file is a **text header** followed by a **binary section** (values illustrative):

```
I3D  # 021.SA cine rest (SA)  [ 256 x 208 x 12 x 25 x 1 ]
X[256] = 0.0 : 1.40625 : 358.59375
Y[208] = 0.0 : 1.40625 : 291.09375
Z[12] = 0.0 : 8.0 : 88.0
T[25] = 0.0 : 1.0 : 24.0
transform = 0.6113   -0.3010   -0.7319   -71.71
            0.7854    0.3098    0.5358  -201.45
            0.0654   -0.9019    0.4270   156.23
# rot 128.5 deg about [-0.86 -0.48 0.18]
header = <hidden @0:1186>  # the rest of the header
data(:,:,:,1)    = <jpegls uint16 @1216:1015383 crc 3f9c0a12>
data(:,:,:,2:25) = <jpegls uint16 @1015384:24521130 crc 77a1e4c0>
thumbnail = <png uint8 {136 132 1 25} @24521131:24680412 crc 0b8de131>

info.StudyDescription = "Cardiac MR"
info.SeriesDescription = "SA cine rest"
...
---
<binary: the hidden block, the data blocks, the thumbnail>
```

You can open it in a text editor and read it. The first line is the magic `I3D` (a program recognises the format by its first four bytes) with an optional comment; the header ends at the line `---`.

---

## 2. What the format defines

| part | what it is | SPEC |
|---|---|---|
| **Layout** | a UTF-8 text header up to `---`, then a binary section. **Every offset is relative to the start of the binary section**, so the header can be edited by hand — fix a string, add a comment — without breaking anything. | [1](SPEC.md#1-file-layout) |
| **Grids `X Y Z T`** | the coordinates of each axis, strictly increasing; their lengths *are* the size of the volume. A uniform grid is written as a range `a : s : b` with an exact, bit-for-bit definition; a non-uniform one as the list of its values. | [3.1](SPEC.md#31-grids-x-y-z-t-all-four-required) |
| **`transform`** | a general 4×4 affine (rotation, scale, shear, reflection): `world = A · [X(i); Y(j); Z(k); 1]`. From DICOM, the world is the patient frame (LPS) in mm. | [3.2](SPEC.md#32-transform) |
| **`data`** | the array `data(i,j,k,t,c…)`, assigned in **rectangular blocks**, each with its own encoding: `jpegls` (lossless, for 8/16-bit integers), `zlib` (any type), `raw`, `dicom` (a reference to a `.dcm` file — the pixels stay in the DICOM) or `missing` (a part that could not be read). Ten types: `int8 … uint64, single, double`. | [4](SPEC.md#4-descriptors), [5](SPEC.md#5-data) |
| **`crc`** | the CRC-32 of each block's decoded bytes: a damaged block is detected, not read as wrong pixels. | [4](SPEC.md#4-descriptors) |
| **`thumbnail`** | one small preview image (grey or RGB, one frame per instant), stored as a PNG. | [7](SPEC.md#7-thumbnail-and-info) |
| **`info.*`** | the metadata: numbers or text, one key per DICOM attribute (`info.SeriesDescription`…), plus per-plane lists `info.series.*` and `info.planes.*`. | [7](SPEC.md#7-thumbnail-and-info) |
| **`$VARIABLES$`** | named strings, e.g. `$DICOMDIR$`, used in paths; a reader can override them when opening, so the referenced DICOM files can move without editing the `.i3d`. | [2](SPEC.md#2-header-grammar) |
| **hidden part, I3Db** | the less relevant lines of the header, or the whole header, stored compressed and obfuscated so that the casual reader does not see them. **It is not protection**: the SPEC says exactly how to undo it. | [1.1](SPEC.md#11-the-hidden-variant-i3db), [1.2](SPEC.md#12-a-hidden-part-of-the-header-decided-2026-10-23) |
| **canonical form** | readers accept files written by hand or by other tools; the writer produces **one** way of writing each thing — the same input gives the same bytes. | [9](SPEC.md#9-the-canonical-form-what-a-writer-must-produce) |

What it does **not** define (yet): the units and the meaning of `T` (today, from DICOM, `T` holds instant indices `0:nt-1`), and anything beyond one stack per file — that is what `.mi3d` is for.

### 2.1 The container `.mi3d`

```
MI3D  # mi3d_write 2026-11-07 10:12:31, 3 stacks
i3d(1) = <i3d @9:524296>             # 001.loc (AX) [ 256 x 256 x 3 x 1 ]
i3d(2) = <i3d @524340:25210981>      # 005.SA cine (SA) [ 256 x 208 x 12 x 25 ]
i3d(3) = <i3d @25211020:31002877>    # 012.4CH cine (4CH) [ 256 x 208 x 1 x 25 ]

# -- series of each stack: number, description, time
#  i3d(1)   1  loc       10:02:11
#  i3d(2)   5  SA cine   10:14:40
#           6  ~         10:19:30
#  i3d(3)  12  4CH cine  10:22:05

# -- common to every stack
info.StudyDescription = "Cardiac MR"
...
---
<each member, an .i3d byte for byte>
```

- Each member is a complete `.i3d`, **byte for byte**: any member can be opened without reading the others, and extracting it gives back exactly the original file.
- Members are numbered `1..N`; a number without a member is a **hole**, so numbers never change when a member is removed.
- The header holds a summary (the `info.*` common to all members), a **tag** per member, and **notes**: the series of each stack, with `~` where a line repeats the one above.
- Members can be appended or removed **in place**, without rewriting the file, thanks to a reserve at the end of the header.

[SPEC section 14](SPEC.md#14-the-container-mi3d-decided-2026-10-24).

---

## 3. Why use it

- **Readable and editable.** The header is text: `type`, `less`, a text editor or a diff show what is in the file. Dropping a damaged block is changing its line to `<missing>`.
- **Exact geometry.** The grids are exact (no rounding of the slice positions, non-uniform grids allowed), and the affine is general. What DICOM says about where each voxel is, is what the file says.
- **Lossless and compact.** 8/16-bit images go to JPEG-LS: 1.2–1.8× smaller than zlib and 5–16× faster to write, measured on real series (`bench/`). Nothing is lost: what you read is bit for bit what was written.
- **Fast partial reads.** The first instant of a cine is its own block, so a viewer that only needs a preview reads one block; the thumbnail is there without decoding anything.
- **Lazy files.** A block can point to the original `.dcm` instead of copying its pixels, with the folder in a variable you can change when opening.
- **Robust.** Every block carries a CRC; every error has a short identifier (`badHeader`, `badCRC`, `coverage`…) that is the same in every language.
- **One library, every language.** All the format logic lives in one C++ library with a C API (`i3d.dll`, `mi3d.dll`). MATLAB, C# and Python are thin wrappers over it, so they read the same files in the same way and fail with the same error. A separate reference reader in Python, written from the SPEC alone, checks the library bit for bit.
- **A study in one file.** `.mi3d` keeps every series of a study together, with a readable index, and is written **from memory**: no intermediate `.i3d` (with patient data) is left on disk.
- **UTF-8.** Names and descriptions with accents are written as they are.

---

## 4. Using it

### 4.1 Command line

**`convert_to_MI3D.exe`** (`dist/`, built with `matlab/build_convert.m`) turns a folder of DICOM files into one `.mi3d` per patient and study:

```
convert_to_MI3D.exe <folder> [outdir] [-t1|-t01] [-info] [-threads N]
```

| option | |
|---|---|
| `outdir` | where the `.mi3d` go (default: the folder itself) |
| `-t1` | only the first instant of each stack; the thumbnail stays animated |
| `-t01` | only the first instant, and a thumbnail of that instant |
| `-info` | read the whole DICOM header of every file (`dicominfo`; slower) |
| `-threads N` | reading threads (default 12) |

Files are named `<Person>.<StudyDescription>.mi3d` (`unknownPerson`, `unknownStudy_<date>` when missing). Exit code: 0 all written, 1 some study failed, 2 bad arguments. It needs the **MATLAB Runtime R2022a (9.12)**, free, on machines without MATLAB.

**`i3dinfo.exe`** (`cpp/build/`) shows what the library understands of a file:

```
i3dinfo serie.i3d             geometry, blocks, info
i3dinfo serie.i3d --header    the header as written
i3dinfo serie.i3d --sum       also reads data: sum, min, max
```

### 4.2 MATLAB

`matlab/` holds the DLLs, their prototypes and the functions; add it to the path. MATLAB must pass strings as UTF-8: `feature('DefaultCharacterSet','UTF-8')`.

```matlab
% one stack
write_I3D( DS(3) , 'serie.i3d' )              % a DICOMstack, an @I3D, or a struct R
R = read_I3D( 'serie.i3d' );                  % R.X R.Y R.Z R.T R.SpatialTransform R.data R.thumbnail R.INFO
R = read_I3D( 'serie.i3d' , 'Data' , 'first' );                    % only data(:,:,:,1)
R = read_I3D( 'lazy.i3d' , 'Variables' , { 'DICOMDIR' , 'E:\x' } ) % the DICOM moved
write_I3D( R , 'copy.i3d' )                   % an R rewrites the same bytes

% a study
write_MI3D( DS(1:10) , 'estudio.mi3d' )       % or { R1 , R2 } , or { I1 , I2 }, without temporary files
Rs = read_MI3D( 'estudio.mi3d' );             % a cell, one R per member ([] for a hole)
[ Rs , tags ] = read_MI3D( 'estudio.mi3d' , 'Data' , 'none' );

% a whole folder of DICOM
files = convert_to_MI3D( 'D:\DICOMS\patient' , 'E:\out' , 'T01' , true );
```

After changing the C++, `buildI3Dlibrary` unloads the libraries, rebuilds them and puts the new ones in `matlab/`.

### 4.3 C# (.NET 8)

`csharp/I3D` (`I3DFile.cs`, `MI3DFile.cs`); the project copies `i3d.dll` and `mi3d.dll` next to the assembly.

```csharp
using I3D;

using var f = I3DFile.Open( "serie.i3d" );
double[] X = f.X;                              // the grids, exact
double[,] A = f.Transform;
var ( data , shape ) = f.ReadData();           // a typed 1-D array, column-major (i fastest)
var ( first , s1 ) = f.ReadFirstFrame();       // data(:,:,:,1,c...) only
var thumb = f.ReadThumbnail();                 // null if there is none
var info = f.Info;                             // info.* by name: double[] / string[] / string

using var c = MI3DFile.Open( "estudio.mi3d" );
for( int n = 1 ; n <= c.Count ; n++ )
{
    using var m = c.Member( n );               // an I3DFile, read in place; null for a hole
    if( m is null ) continue;
    Console.WriteLine( $"{n}: {c.Tag( n )}  [{string.Join( " x " , m.Shape )}]" );
}
```

Errors are `I3DException`, with the library's identifier in `Id`.

### 4.4 Python

`tests/i3d_ctypes.py` is a thin ctypes wrapper of the DLLs (it looks for them in `cpp/build/`):

```python
from i3d_ctypes import I3DFile, MI3DFile

f = I3DFile('serie.i3d')
X = f.grid('X');  A = f.transform()
D = f.data()                     # numpy, shape (i, j, k, t[, c...]), order='F'
D1 = f.first_frame()
info = f.info()

c = MI3DFile('estudio.mi3d')
for n in range(1, c.count() + 1):
    if c.present(n) == 1:
        m = c.member(n)          # an I3DFile over the member, in place
        print(n, c.tag(n), m.shape())
```

`tests/read_i3d.py` is **not** a library: it is the independent reference reader that the tests compare the DLLs against (`read_i3d(f)`, `read_mi3d(f, n)`).

### 4.5 C and C++

The C API (`cpp/i3d_c.h`, `cpp/mi3d_c.h`) is the stable boundary; every function returns 0 on success, and the message and its identifier are asked for separately. All strings are UTF-8.

```c
#include "i3d_c.h"

i3d_file *f = i3d_open( "serie.i3d" );
if( !f ){ puts( i3d_last_error( NULL ) ); return 1; }
int nd;  int64_t dims[16];
i3d_data_shape( f , &nd , dims );                 /* i j k t c... */
size_t nb = i3d_data_bytes( f );
void *buf = malloc( nb );
if( i3d_read_data( f , buf , nb ) ) puts( i3d_last_error( f ) );
i3d_close( f );
```

Writing (the canonical form, SPEC 9):

```c
i3d_writer *w = i3d_new();
int64_t dims[4] = { 256 , 256 , 12 , 30 };
i3d_set_data( w , pixels , "int16" , 4 , dims );           /* copies the data */
i3d_set_Xgrid( w , x , 256 );   /* ... Y, Z, T; without them, 0 : 1 : n-1 */
i3d_add_info_text( w , "SeriesDescription" , "cine" , 1 , NULL );
if( i3d_write( w , "serie.i3d" ) ) puts( i3d_wlast_error( w ) );
i3d_free( w );
```

A `.mi3d` from memory has the same calls with `mi3d_` and an `mi3d_add_stack( m , tag )` before each member, then `mi3d_write( m , "estudio.mi3d" )`. A member of a container is opened with `mi3d_range` (from `mi3d.dll`) and `i3d_open_window` (from `i3d.dll`). In C++, `cpp/i3d.hpp` and `cpp/mi3d.hpp` give the same as classes.

### 4.6 ParaView

`paraview/I3DReader.py` is a reader plugin (ParaView 5.10 or later; tested on 6.2). Load it once with **Tools > Manage Plugins > Load New…** (tick *Auto Load*); then **File > Open** reads `.i3d` and `.mi3d`. It calls `i3d.dll` and `mi3d.dll` (looked for in `$I3D_DLL_DIR`, next to the plugin, in `cpp/build` and in `matlab/`), so a copy of the plugin and the two DLLs in one folder is enough.

| file | in ParaView |
|---|---|
| `.i3d` | a `vtkImageData` (origin, spacing and direction matrix) when the grids are uniform and the transform has orthogonal columns — DICOM stacks, to 1/1000 of the voxel spacing —; otherwise a `vtkStructuredGrid` with the exact world coordinates of every voxel (non-uniform grids, a shear) |
| `T` | time steps: a cine plays with the animation controls |
| components `c…` | the components of the point array `data` |
| `info.*` | field data |
| `.mi3d` | a multiblock, one block per member named `n: tag`, each in its own place in patient space; holes are skipped |

Properties: **DICOMDIR** (for Lazy files whose DICOM moved) and **First Frame Only** (reads only `data(:,:,:,1)`). In Python: `LoadPlugin(r'...\paraview\I3DReader.py', ns=globals())`, then `OpenDataFile('serie.i3d')`.

---

## 5. Reading a `.mi3d`

### 5.1 What is in it

| | where | how to get it |
|---|---|---|
| **N** | the largest `n` of the `i3d(n)` lines | MATLAB `numel( Rs )`; C# `c.Count`; Python `c.count()`; C `mi3d_count` |
| **member n** | the bytes `@a:b` of its `i3d(n)` line: a complete `.i3d` | read in place (below) |
| **hole** | an `n` in `1..N` without a member | MATLAB `[]`; C# `Member(n)` is `null`, `Present(n)` false; Python/C `present(n) == 0` |
| **tag** | the comment of the `i3d(n)` line, `NNN.description (plane)` (series number, series description, plane) | MATLAB 2nd output of `read_MI3D`; C# `c.Tag(n)`; Python `c.tag(n)`; C `mi3d_tag` |
| **notes** | the block `# -- series of each stack`: the series behind each member, with their times | the header as text: C# `c.Header`; Python `c.header()`; C `mi3d_header` |
| **summary** | the `info.*` of the container: what ALL members share (study, patient, device…) | its entries: C# `c.Entries`; Python `c.entries()`; C `mi3d_entry_*` |

Opening a `.mi3d` reads only its header. A member is not copied or extracted to be read: the library is given its byte range inside the container (`mi3d_range`) and reads it **in place** as an ordinary `.i3d` (`i3d_open_window`). Everything an `.i3d` offers — grids, transform, data, first frame, thumbnail, info — works on a member the same way, and errors keep their identifiers.

### 5.2 MATLAB

```matlab
% everything: one R per member, like read_I3D gives for an .i3d
[ Rs , tags ] = read_MI3D( 'estudio.mi3d' );
for n = 1:numel( Rs )
  if isempty( Rs{n} ), continue; end                  % a hole
  R = Rs{n};
  fprintf( '%d  %s  %s\n' , n , tags{n} , mat2str( size( R.data ) ) );
end

% only the index, without decoding any pixels (fast, little memory)
[ Rs , tags ] = read_MI3D( 'estudio.mi3d' , 'Data' , 'none' );

% a preview: the first instant of every member
Rs = read_MI3D( 'estudio.mi3d' , 'Data' , 'first' );

% the members of one series: by the tag, or by the per-plane info
n  = find( startsWith( tags , '005.' ) );                                       % NNN. = series number
has5 = @( R ) ~isempty( R ) && isfield( R.INFO , 'series' ) && ...                % numbers, or text when some plane has none
              any( str2double( string( R.INFO.series.SeriesNumber(:) ) ) == 5 );
n2 = find( cellfun( has5 , Rs ) );
```

`read_MI3D` reads every member. To read ONE member without the others, ask `mi3d.dll` for its range and give it to `read_I3D`:

```matlab
m = calllib( 'mi3d' , 'mi3d_open' , 'estudio.mi3d' );          % (read_MI3D has loaded the library)
[ rc , ~ , off , len ] = calllib( 'mi3d' , 'mi3d_range' , m , 3 , int64(0) , int64(0) );
calllib( 'mi3d' , 'mi3d_close' , m );
R3 = read_I3D( 'estudio.mi3d' , 'Window' , [ double( off ) , double( len ) ] );
```

### 5.3 C#

```csharp
using var c = MI3DFile.Open( "estudio.mi3d" );
Console.WriteLine( c.Header );                       // the index, the notes and the summary, as text
for( int n = 1 ; n <= c.Count ; n++ )
{
    if( !c.Present( n ) ) { Console.WriteLine( $"{n}: hole" ); continue; }
    using var f = c.Member( n )!;                    // an I3DFile, read in place
    Console.WriteLine( $"{n}: {c.Tag( n )}  [{string.Join( " x " , f.Shape )}] {f.DataType}" );
    var ( first , shape ) = f.ReadFirstFrame();      // only the first instant
}

// one member, by number; its info like any .i3d
using var m5 = c.Member( 5 );
var info = m5?.Info;
```

### 5.4 Python

```python
from i3d_ctypes import MI3DFile

c = MI3DFile('estudio.mi3d')
print(c.header())                                    # index, notes and summary
for n in range(1, c.count() + 1):
    if c.present(n) != 1: continue                   # 0: a hole
    f = c.member(n)                                  # an I3DFile, read in place
    print(n, c.tag(n), f.shape(), f.dtype())
    D = f.data()                                     # numpy (i, j, k, t[, c...]), order='F'
```

The reference reader, independent of the DLLs, does the same: `read_mi3d(path)` gives the index (`C['N']`, `C['members']`) and `read_mi3d(path, n)` member n as `read_i3d` would (`None` for a hole).

### 5.5 C

```c
#include "mi3d_c.h"
#include "i3d_c.h"

mi3d_file *m = mi3d_open( "estudio.mi3d" );
if( !m ){ puts( mi3d_last_error( NULL ) ); return 1; }
for( int n = 1 ; n <= mi3d_count( m ) ; n++ ){
  if( mi3d_present( m , n ) != 1 ) continue;               /* a hole */
  int64_t off , len;
  mi3d_range( m , n , &off , &len );                       /* from the start of the FILE */
  i3d_file *f = i3d_open_window( "estudio.mi3d" , off , len , 0 , NULL , NULL );
  if( !f ){ puts( i3d_last_error( NULL ) ); continue; }
  printf( "%d  %s\n" , n , mi3d_tag( m , n ) );
  /* ... i3d_data_shape, i3d_read_data, i3d_read_first_frame ... as for an .i3d */
  i3d_close( f );
}
mi3d_close( m );
```

### 5.6 Extracting a member as an `.i3d`

A member IS an `.i3d`, byte for byte, so extracting it is copying its range — no decoding, no re-encoding. The result is identical to the file the member was made from (its CRCs still check):

```python
a, L = MI3DFile('estudio.mi3d').range(3)
with open('estudio.mi3d', 'rb') as s, open('member3.i3d', 'wb') as o:
    s.seek(a); o.write(s.read(L))
```

(The same in any language with `mi3d_range` and a file copy. Note that this writes the member, with its patient data, to a new file: reading in place does not.)

### 5.7 Lazy members and variables

A member whose blocks reference `.dcm` files (`<dicom "$DICOMDIR$/…">`) resolves relative paths from the folder of the **container**. If the DICOM files moved, give the folder when opening the member, exactly as for an `.i3d`:

```matlab
Rs = read_MI3D( 'estudio.mi3d' , 'Variables' , { 'DICOMDIR' , 'E:\dicoms' } );
```
```csharp
using var f = c.Member( 2 , new Dictionary<string, string> { [ "DICOMDIR" ] = @"E:\dicoms" } );
```
```python
f = c.member(2, variables={'DICOMDIR': 'E:/dicoms'})
```

`write_MI3D` and `convert_to_MI3D` copy the pixels into the file, so their members are not Lazy and need nothing of this.

---

## 6. Building

| what | how |
|---|---|
| `i3d.dll`, `mi3d.dll`, `i3dinfo.exe` | `cpp\build.bat` (MSVC 2022). zlib, CharLS, lodepng and a subset of DCMTK are bundled in `third_party/` |
| the DLLs for MATLAB | `buildI3Dlibrary` in MATLAB: unloads, rebuilds, copies the DLLs and regenerates `i3d_proto.m` / `mi3d_proto.m` |
| `convert_to_MI3D.exe` | `build_convert` in MATLAB (MATLAB Compiler; DICOMstackCollect on the path): `dist\convert_to_MI3D.exe` |
| C# | `dotnet build csharp\I3D` |

The tests are listed in [SPEC section 12](SPEC.md#12-tests).

---

## 7. Errors

Every reader, in every language, reports the same short identifiers:

| id | meaning |
|---|---|
| `cannotOpen` | the file (or a referenced `.dcm`) cannot be opened |
| `badMagic` | not an `.i3d` (or an `.i3d` given where a `.mi3d` is expected, and the other way) |
| `badHeader` | the header breaks the grammar: a repeated key, invalid UTF-8… |
| `badGrid` | a grid that is not strictly increasing, or a range that is not exact |
| `badDescriptor` | a `< >` that does not make sense |
| `badSubscript` | a block subscript out of the volume |
| `coverage` | part of `data` assigned by no block, or by two (a part that could not be read is an explicit `<missing>` block, not a gap) |
| `badBlock` | a block whose bytes do not decode to its shape |
| `badCRC` | a block whose CRC does not match: the file is damaged |
| `badIndex`, `missingMember` | a `.mi3d` member out of `1..N`, or a hole |

---

## 8. Where to go next

- [`SPEC.md`](SPEC.md) — the specification: grammar, canonical form, container, decisions and their reasons, open items, changes.
- `cpp/i3d_c.h`, `cpp/mi3d_c.h` — the C API, with usage comments.
- `matlab/` — `help write_I3D`, `help read_I3D`, `help write_MI3D`, `help convert_to_MI3D`.
