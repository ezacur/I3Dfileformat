# Compara cada <caso>_<enc>.i3d contra el original que MATLAB guardo en ref.mat,
# leido con DOS lectores independientes:
#   py   el lector de referencia (tests/read_i3d.py)
#   cpp  la DLL de C++ (cpp/build/i3d.dll) por su API en C (tests/i3d_ctypes.py)
# Bit a bit: rejillas, transform, data (NaN y -0 incluidos: se comparan BYTES) y
# el thumbnail, que TIENE que estar en todos menos en los hechos a mano (rawhand,
# crcbad). zlib, CharLS y DCMTK estan dentro de la DLL: un unsupportedEncoding
# es un fallo, no una tolerancia.
import sys, os, glob
import numpy as np
import scipy.io
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_i3d import read_i3d
import i3d_ctypes

dn = sys.argv[1]
ref = scipy.io.loadmat(os.path.join(dn, 'ref.mat'))
have_dll = os.path.isfile(i3d_ctypes.DLL)

def compare(get, R, want_thumb):
    """get(campo) -> array leido; devuelve la lista de lo que NO coincide"""
    msgs = []
    for g in 'XYZT':
        if get(g).astype('<f8').tobytes() != np.ascontiguousarray(R[g].ravel(), dtype='<f8').tobytes():
            msgs.append(g)
    if get('transform').astype('<f8').tobytes() != np.ascontiguousarray(R['A'], dtype='<f8').tobytes():
        msgs.append('transform')
    D = R['D']
    if D.dtype == bool: D = D.astype(np.uint8)          # logical se escribe como uint8 0/1
    d = get('data')
    if d.dtype.str.lstrip('<|=') != D.dtype.str.lstrip('<|='):
        msgs.append(f'type {d.dtype} vs {D.dtype}')
    elif d.size != D.size or d.tobytes(order='F') != np.reshape(D, d.shape, order='F').tobytes(order='F'):
        msgs.append('data')
    # el PRIMER INSTANTE (SPEC 5.7), solo leyendo los bloques que lo cortan: tiene
    # que ser data(:,:,:,1,c...) bit a bit. Solo la DLL lo ofrece (py: None)
    ff = get('first')
    if ff is not None and d.size == D.size:
        want = np.asfortranarray(np.reshape(D, d.shape, order='F')[:, :, :, :1])
        if ff.shape != want.shape or ff.tobytes(order='F') != want.tobytes(order='F'):
            msgs.append('first frame')
    th = get('thumbnailK')
    if want_thumb and th is None:
        msgs.append('thumbnail missing')
    elif th is not None and (th.dtype != np.uint8 or th.tobytes(order='F') != np.reshape(R['TH'], th.shape, order='F').tobytes(order='F')):
        msgs.append('thumbnail')
    return msgs

def via_py(f):
    I = read_i3d(f)
    return lambda k: I['aux'].get(k) if k.startswith('thumbnail') else None if k == 'first' else I[k]

def via_cpp(f):
    F = i3d_ctypes.I3DFile(f)
    def get(k):
        if k in 'XYZT': return F.grid(k)
        if k == 'transform': return F.transform()
        if k.startswith('thumbnail'): return F.aux(k)
        if k == 'first': return F.first_frame()
        return F.data()
    return get

nbad = ncase = 0
for f in sorted(glob.glob(os.path.join(dn, '*.i3d'))):
    name, enc = os.path.basename(f)[:-4].rsplit('_', 1)
    R = ref[name][0, 0]
    ncase += 1
    want = enc not in ('rawhand', 'crcbad')         # los hechos a mano no llevan thumbnail
    res = {}
    for who, via in (('py', via_py), ('cpp', via_cpp)):
        if who == 'cpp' and not have_dll: res[who] = 'FAIL(no dll)'; continue
        if enc == 'crcbad':
            # un byte alterado bajo un crc: el lector TIENE que lanzar badCRC
            try:
                compare(via(f), R, want)
                res[who] = 'FAIL(no badCRC raised)'
            except Exception as e:
                res[who] = 'ok(badCRC)' if 'badCRC' in str(e) else f'FAIL({e})'
            continue
        try:
            m = compare(via(f), R, want)
            if enc == 'corrupt':
                # el control negativo: TIENE que fallar, y solo en data (y en el
                # primer instante, si el byte cae en su bloque)
                res[who] = 'ok' if 'data' in m and set(m) <= {'data', 'first frame'} else 'FAIL(detected: ' + (','.join(m) or 'NOTHING') + ')'
            else:
                res[who] = 'ok' if not m else 'FAIL(' + ','.join(m) + ')'
        except Exception as e:
            # con el byte corrupto, que el lector LANCE tambien es detectarlo
            res[who] = 'ok(raised)' if enc == 'corrupt' else f'FAIL({type(e).__name__}: {e})'
    bad = any(v.startswith('FAIL') for v in res.values())
    nbad += bad
    print(f'  {"FAIL" if bad else "ok  "} {name:16s} {enc:7s}  py: {res["py"]:10s}  cpp: {res["cpp"]}')
print(f'{ncase} files, {nbad} failed')
sys.exit(1 if nbad else 0)
