# Envoltorio minimo de las DLL (cpp/build/i3d.dll y mi3d.dll) por ctypes, sobre
# las API en C de cpp/i3d_c.h y cpp/mi3d_c.h. Es el embrion del wrapper de
# Python, y aqui sirve para probar las DLL contra los mismos originales que el
# lector de referencia.
import ctypes as C, os
import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))
DLL = os.path.join(_here, '..', 'cpp', 'build', 'i3d.dll')
MDLL = os.path.join(_here, '..', 'cpp', 'build', 'mi3d.dll')

NP = {'int8': np.int8, 'uint8': np.uint8, 'int16': np.int16, 'uint16': np.uint16,
      'int32': np.int32, 'uint32': np.uint32, 'int64': np.int64, 'uint64': np.uint64,
      'single': np.float32, 'double': np.float64}

class I3DCError(Exception):
    def __init__(self, ident, msg): super().__init__(f'[{ident}] {msg}'); self.ident = ident

def _lib():
    L = C.CDLL(DLL)
    L.i3d_open.restype = C.c_void_p;            L.i3d_open.argtypes = [C.c_char_p]
    L.i3d_open_vars.restype = C.c_void_p
    L.i3d_open_vars.argtypes = [C.c_char_p, C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_char_p)]
    L.i3d_close.argtypes = [C.c_void_p]
    L.i3d_last_error.restype = C.c_char_p;      L.i3d_last_error.argtypes = [C.c_void_p]
    L.i3d_last_error_id.restype = C.c_char_p;   L.i3d_last_error_id.argtypes = [C.c_void_p]
    L.i3d_grid.argtypes = [C.c_void_p, C.c_char, C.POINTER(C.POINTER(C.c_double)), C.POINTER(C.c_size_t)]
    L.i3d_transform.argtypes = [C.c_void_p, C.POINTER(C.c_double)]
    L.i3d_data_shape.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int64)]
    L.i3d_data_type.restype = C.c_char_p;       L.i3d_data_type.argtypes = [C.c_void_p]
    L.i3d_data_bytes.restype = C.c_size_t;      L.i3d_data_bytes.argtypes = [C.c_void_p]
    L.i3d_read_data.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
    L.i3d_first_frame_bytes.restype = C.c_size_t;  L.i3d_first_frame_bytes.argtypes = [C.c_void_p]
    L.i3d_read_first_frame.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
    L.i3d_missing_count.argtypes = [C.c_void_p]
    L.i3d_thumbnail_shape.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int64)]
    L.i3d_thumbnail_read.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
    P3 = [C.POINTER(C.c_char_p)] * 3
    L.i3d_entry_count.argtypes = [C.c_void_p]
    L.i3d_entry.argtypes = [C.c_void_p, C.c_int] + P3
    L.i3d_header.restype = C.c_char_p;          L.i3d_header.argtypes = [C.c_void_p]
    # los info.* interpretados por la DLL (SPEC 7)
    L.i3d_info_count.argtypes = [C.c_void_p]
    for f in ('key', 'type'):
        g = getattr(L, 'i3d_info_' + f);  g.restype = C.c_char_p;  g.argtypes = [C.c_void_p, C.c_int]
    L.i3d_info_length.restype = C.c_int64;      L.i3d_info_length.argtypes = [C.c_void_p, C.c_int]
    L.i3d_info_numbers.argtypes = [C.c_void_p, C.c_int, C.POINTER(C.c_double), C.c_int64]
    L.i3d_info_text.restype = C.c_char_p;       L.i3d_info_text.argtypes = [C.c_void_p, C.c_int, C.c_int64]
    # un miembro de un .mi3d: los bytes [offset, offset+length) del fichero
    L.i3d_open_window.restype = C.c_void_p
    L.i3d_open_window.argtypes = [C.c_char_p, C.c_int64, C.c_int64, C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_char_p)]
    return L

def _mlib():
    # el contenedor .mi3d (SPEC 14): mi3d.dll
    M = C.CDLL(MDLL)
    M.mi3d_open.restype = C.c_void_p;           M.mi3d_open.argtypes = [C.c_char_p]
    M.mi3d_close.argtypes = [C.c_void_p]
    M.mi3d_last_error.restype = C.c_char_p;     M.mi3d_last_error.argtypes = [C.c_void_p]
    M.mi3d_last_error_id.restype = C.c_char_p;  M.mi3d_last_error_id.argtypes = [C.c_void_p]
    M.mi3d_count.argtypes = [C.c_void_p]
    M.mi3d_present.argtypes = [C.c_void_p, C.c_int]
    M.mi3d_range.argtypes = [C.c_void_p, C.c_int, C.POINTER(C.c_int64), C.POINTER(C.c_int64)]
    M.mi3d_tag.restype = C.c_char_p;            M.mi3d_tag.argtypes = [C.c_void_p, C.c_int]
    M.mi3d_entry_count.argtypes = [C.c_void_p]
    for f in ('key', 'subs', 'value'):
        g = getattr(M, 'mi3d_entry_' + f);  g.restype = C.c_char_p;  g.argtypes = [C.c_void_p, C.c_int]
    M.mi3d_header.restype = C.c_char_p;         M.mi3d_header.argtypes = [C.c_void_p]
    return M

def _entries(count, entry, h):
    out = []
    for e in range(count(h)):
        k, s, v = C.c_char_p(), C.c_char_p(), C.c_char_p()
        entry(h, e, C.byref(k), C.byref(s), C.byref(v))
        out.append((k.value.decode(), s.value.decode(), v.value.decode()))
    return out

_L = None
_M = None

class I3DFile:
    def __init__(self, path, variables=None, member=None):
        # variables: {'DICOMDIR': 'D:/...'} -- MANDAN sobre las $NOMBRE$ del fichero
        # member: n, el miembro n del contenedor .mi3d path (SPEC 14)
        global _L
        if _L is None: _L = _lib()
        self.h = None
        variables = variables or {}
        n = len(variables)
        names = (C.c_char_p * max(n, 1))(*[k.strip('$').encode('utf-8') for k in variables])
        values = (C.c_char_p * max(n, 1))(*[v.encode('utf-8') for v in variables.values()])
        if member is not None:
            a, L = MI3DFile(path).range(member)
            self.h = _L.i3d_open_window(path.encode('utf-8'), a, L, n, names, values)
        elif n:
            self.h = _L.i3d_open_vars(path.encode('utf-8'), n, names, values)
        else:
            self.h = _L.i3d_open(path.encode('utf-8'))
        if not self.h:
            raise I3DCError(_L.i3d_last_error_id(None).decode(), _L.i3d_last_error(None).decode())
    def _check(self, rc):
        if rc: raise I3DCError(_L.i3d_last_error_id(self.h).decode(), _L.i3d_last_error(self.h).decode())
    def grid(self, a):
        p = C.POINTER(C.c_double)(); n = C.c_size_t()
        self._check(_L.i3d_grid(self.h, a.encode(), C.byref(p), C.byref(n)))
        return np.ctypeslib.as_array(p, shape=(n.value,)).copy()
    def transform(self):
        A = (C.c_double * 16)()
        self._check(_L.i3d_transform(self.h, A))
        return np.array(A[:]).reshape(4, 4)               # por filas
    def shape(self):
        nd = C.c_int(); d = (C.c_int64 * 16)()
        self._check(_L.i3d_data_shape(self.h, C.byref(nd), d))
        return tuple(d[:nd.value])
    def dtype(self): return NP[_L.i3d_data_type(self.h).decode()]
    def data(self):
        sh = self.shape()
        out = np.empty(sh, dtype=self.dtype(), order='F')
        self._check(_L.i3d_read_data(self.h, out.ctypes.data_as(C.c_void_p), out.nbytes))
        return out
    def first_frame(self):
        # data(:,:,:,1,c...): solo los bloques que cortan el primer instante
        sh = list(self.shape()); sh[3] = 1
        out = np.empty(tuple(sh), dtype=self.dtype(), order='F')
        self._check(_L.i3d_read_first_frame(self.h, out.ctypes.data_as(C.c_void_p), out.nbytes))
        return out
    def missing_count(self): return _L.i3d_missing_count(self.h)
    def thumbnail(self):
        # None si el fichero no tiene (como I.thumbnail -> null de la libreria)
        nd = C.c_int(); d = (C.c_int64 * 16)()
        self._check(_L.i3d_thumbnail_shape(self.h, C.byref(nd), d))
        if nd.value == 0: return None
        out = np.empty(tuple(d[:nd.value]), dtype=np.uint8, order='F')
        self._check(_L.i3d_thumbnail_read(self.h, out.ctypes.data_as(C.c_void_p), out.nbytes))
        return out
    def entries(self): return _entries(_L.i3d_entry_count, _L.i3d_entry, self.h)
    def info(self):
        # (info, errores), como read_i3d: info[nombre] -> lista de float, str o
        # lista de str; errores[nombre] -> el motivo
        I, err = {}, {}
        for i in range(_L.i3d_info_count(self.h)):
            k = _L.i3d_info_key(self.h, i).decode('utf-8')
            t = _L.i3d_info_type(self.h, i).decode()
            n = _L.i3d_info_length(self.h, i)
            if t == 'numbers':
                x = (C.c_double * n)()
                self._check(_L.i3d_info_numbers(self.h, i, x, n))
                I[k] = list(x)
            elif t == 'text':
                s = [_L.i3d_info_text(self.h, i, j).decode('utf-8') for j in range(n)]
                I[k] = s[0] if n == 1 else s
            elif t == 'other':
                I[k] = _L.i3d_info_text(self.h, i, 0).decode('utf-8')
            else:
                err[k] = _L.i3d_last_error(self.h).decode('utf-8')
        return I, err
    def header(self): return _L.i3d_header(self.h).decode('utf-8')
    def close(self):
        if self.h: _L.i3d_close(self.h); self.h = None
    def __del__(self): self.close()

class MI3DFile:
    # el contenedor .mi3d (SPEC 14): su cabecera. member(n) abre el miembro n
    def __init__(self, path):
        global _M
        if _M is None: _M = _mlib()
        self.path = path
        self.h = _M.mi3d_open(path.encode('utf-8'))
        if not self.h:
            raise I3DCError(_M.mi3d_last_error_id(None).decode(), _M.mi3d_last_error(None).decode())
    def count(self): return _M.mi3d_count(self.h)
    def present(self, n): return _M.mi3d_present(self.h, n)       # 1, 0 (hueco), -1 (fuera)
    def range(self, n):
        # los bytes del miembro n en el FICHERO; un hueco: missingMember
        a, L = C.c_int64(), C.c_int64()
        if _M.mi3d_range(self.h, n, C.byref(a), C.byref(L)):
            raise I3DCError(_M.mi3d_last_error_id(self.h).decode(), _M.mi3d_last_error(self.h).decode())
        return a.value, L.value
    def tag(self, n): return _M.mi3d_tag(self.h, n).decode('utf-8')
    def entries(self):
        return [tuple(getattr(_M, 'mi3d_entry_' + f)(self.h, e).decode('utf-8') for f in ('key', 'subs', 'value'))
                for e in range(_M.mi3d_entry_count(self.h))]
    def header(self): return _M.mi3d_header(self.h).decode('utf-8')
    def member(self, n, variables=None): return I3DFile(self.path, variables, member=n)
    def close(self):
        if self.h: _M.mi3d_close(self.h); self.h = None
    def __del__(self): self.close()
