# Banco de compresion SIN PERDIDA para el formato .i3d: que codec deja el
# fichero mas pequeno sobre series reales de d:\DICOMS.
#
# Criterio principal: bytes comprimidos (relacion raw/comprimido).
# Secundario: tiempo de descompresion, un solo hilo.
# Cada codec se valida IDA Y VUELTA BIT A BIT: uno que no la cumpla no cuenta.
#
# El volumen se carga con pydicom tal cual esta almacenado (sin rescale),
# ordenado por InstanceNumber, como array (n, rows, cols): en orden C eso es
# columna mas rapida, que es la i de @I3D -- los mismos bytes que escribiria
# writeI3D para order i j k t c.
import os, sys, time, zlib, json
import numpy as np
import pydicom

def load_series(folder):
    hs = []
    for f in os.listdir(folder):
        p = os.path.join(folder, f)
        if not os.path.isfile(p): continue
        try:
            h = pydicom.dcmread(p)
            a = h.pixel_array
        except Exception:
            continue
        hs.append((int(getattr(h, 'InstanceNumber', 0)), a, h))
    hs.sort(key=lambda x: x[0])
    shapes = collections_mode([x[1].shape for x in hs])
    hs = [x for x in hs if x[1].shape == shapes]       # descartar localizadores sueltos
    V = np.stack([x[1] for x in hs])
    return V, hs[0][2]

def collections_mode(L):
    import collections
    return collections.Counter(L).most_common(1)[0][0]

# ---------------------------------------------------------------- codecs
# cada codec: (nombre, encode(bloque ndarray) -> bytes, decode(bytes, shape, dtype) -> ndarray)

def c_zlib(level):
    enc = lambda A: zlib.compress(A.tobytes(), level)
    dec = lambda b, sh, dt: np.frombuffer(zlib.decompress(b), dtype=dt).reshape(sh)
    return (f'zlib{level}', enc, dec)

# ---------------------------------------------------------------- filtros
# Exactos por construccion: la delta se hace en aritmetica modular del tipo sin
# signo del mismo ancho (uint16 para int16/uint16), y se deshace con un cumsum
# que tambien envuelve. El banco lo COMPRUEBA igualmente con el bit a bit.

def _u(A):  return A.view(np.dtype(f'u{A.dtype.itemsize}'))

def delta_fwd(A, axis):
    U = _u(A).copy()
    sl = [slice(None)] * U.ndim
    hi = sl.copy(); hi[axis] = slice(1, None)
    lo = sl.copy(); lo[axis] = slice(None, -1)
    U[tuple(hi)] = _u(A)[tuple(hi)] - _u(A)[tuple(lo)]
    return U

def delta_inv(U, axis, dt):
    return np.cumsum(U, axis=axis, dtype=U.dtype).view(dt)

def shuffle_fwd(b, itemsize):
    return np.frombuffer(b, np.uint8).reshape(-1, itemsize).T.tobytes()

def shuffle_inv(b, itemsize):
    return np.frombuffer(b, np.uint8).reshape(itemsize, -1).T.tobytes()

def with_filters(codec, delta_axis=None, shuffle=True):
    # delta_axis: -1 a lo largo de i (columnas); 0 entre cortes (solo volumen)
    name, enc, dec = codec
    tag = name + ('+d' + {-1: 'i', 0: 'k'}[delta_axis] if delta_axis is not None else '') + ('+sh' if shuffle else '')
    def E(A):
        U = delta_fwd(A, delta_axis) if delta_axis is not None else _u(A)
        b = U.tobytes()
        if shuffle: b = shuffle_fwd(b, A.dtype.itemsize)
        return enc(np.frombuffer(b, np.uint8))
    def D(b, sh, dt):
        isz = np.dtype(dt).itemsize
        r = dec(b, (np.prod(sh) * isz,), np.uint8).tobytes()
        if shuffle: r = shuffle_inv(r, isz)
        U = np.frombuffer(r, np.dtype(f'u{isz}')).reshape(sh)
        return delta_inv(U, delta_axis, dt) if delta_axis is not None else U.view(dt)
    return (tag, E, D)

import imagecodecs as ic, lzma

def c_bytes(name, enc_b, dec_b):
    enc = lambda A: enc_b(A.tobytes())
    dec = lambda b, sh, dt: np.frombuffer(dec_b(b), dtype=dt).reshape(sh)
    return (name, enc, dec)

ZSTD19 = c_bytes('zstd19', lambda b: ic.zstd_encode(b, level=19), ic.zstd_decode)
ZSTD22 = c_bytes('zstd22', lambda b: ic.zstd_encode(b, level=22), ic.zstd_decode)
XZ9E   = c_bytes('xz9e',   lambda b: lzma.compress(b, preset=9 | lzma.PRESET_EXTREME), lzma.decompress)
# el brotli_decode de imagecodecs falla (BROTLI_DECODER_RESULT_ERROR) si no se
# le da el tamano de salida; el modulo brotli no lo necesita
import brotli
BR11   = c_bytes('brotli11', lambda b: brotli.compress(b, quality=11), brotli.decompress)

Z9 = c_zlib(9)
CODECS = [ c_zlib(6), Z9,
           with_filters(Z9, None, True),
           with_filters(Z9, -1, False),
           with_filters(Z9, -1, True) ]
for G in (ZSTD19, ZSTD22, XZ9E, BR11):
    CODECS += [ G, with_filters(G, None, True), with_filters(G, -1, True) ]
CODECS_VOLUME_ONLY = [ with_filters(G, 0, True) for G in (Z9, ZSTD22, XZ9E) ]

# ---------------------------------------------------------------- codecs de imagen
# 2-D, corte a corte. Trabajan sobre enteros SIN signo: un int16 se lleva a
# uint16 con XOR 0x8000 (biyectivo: es sumar 32768 en modulo 2^16), y se
# deshace igual. Todos sin perdida, y el banco lo comprueba bit a bit.
def _to_u(A):
    if A.dtype.kind == 'i': return (A.view(np.dtype(f'u{A.dtype.itemsize}')) ^ (1 << (8*A.dtype.itemsize-1)))
    return A
def _from_u(U, dt):
    dt = np.dtype(dt)
    if dt.kind == 'i': return (U ^ (1 << (8*dt.itemsize-1))).view(dt)
    return U.astype(dt, copy=False)

def c_image(name, enc2d, dec2d):
    enc = lambda A: enc2d(np.ascontiguousarray(_to_u(A)))
    dec = lambda b, sh, dt: _from_u(np.asarray(dec2d(b)).reshape(sh), dt)
    return (name, enc, dec)

CODECS_SLICE_ONLY = [
    c_image('jpegls',  lambda A: ic.jpegls_encode(A, level=0), ic.jpegls_decode),
    c_image('jpeg2k-rev', lambda A: ic.jpeg2k_encode(A, level=0, reversible=True, numthreads=1),
                          lambda b: ic.jpeg2k_decode(b, numthreads=1)),
    c_image('png9',    lambda A: ic.png_encode(A, level=9), ic.png_decode),
]

# ---------------------------------------------------------------- banco
def run(V, codecs, per_slice):
    raw = V.nbytes
    out = []
    for name, enc, dec in codecs:
        blocks = [V[k] for k in range(V.shape[0])] if per_slice else [V]
        t0 = time.perf_counter()
        B = [enc(b) for b in blocks]
        te = time.perf_counter() - t0
        t0 = time.perf_counter()
        R = [dec(b, blk.shape, blk.dtype) for b, blk in zip(B, blocks)]
        td = time.perf_counter() - t0
        exact = all(np.array_equal(r, blk) for r, blk in zip(R, blocks))
        nb = sum(len(b) for b in B)
        out.append(dict(codec=name, block='slice' if per_slice else 'volume',
                        bytes=nb, ratio=raw/nb, enc_s=te, dec_s=td, exact=exact))
    return out

if __name__ == '__main__':
    folder = sys.argv[1]
    ONLY = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None
    V, h = load_series(folder)
    print(f'{folder}\n  {V.shape} {V.dtype}  raw {V.nbytes/2**20:.1f} MiB  '
          f'min {V.min()} max {V.max()}', flush=True)
    for per_slice in (False, True):
        cs = CODECS + (CODECS_SLICE_ONLY if per_slice else CODECS_VOLUME_ONLY)
        if ONLY: cs = [c for c in cs if c[0] in ONLY]
        for r in run(V, cs, per_slice):
            print(f"  {r['codec']:24s} {r['block']:6s} ratio {r['ratio']:6.3f}  "
                  f"dec {r['dec_s']*1e3:8.1f} ms  enc {r['enc_s']:7.2f} s  "
                  f"{'EXACT' if r['exact'] else 'NOT EXACT'}", flush=True)
