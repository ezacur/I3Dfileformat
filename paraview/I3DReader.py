"""I3DReader.py -- ParaView reader for .i3d and .mi3d (SPEC.md), over i3d.dll / mi3d.dll.

Load it once: Tools > Manage Plugins > Load New... > this file (tick "Auto Load"), or
in Python  LoadPlugin(r'...\\I3DReader.py', ns=globals()).  Then File > Open reads
.i3d and .mi3d. All the format logic is in the DLLs (ctypes, the C API of
cpp/i3d_c.h and cpp/mi3d_c.h); this file only turns what they give into VTK.

  .i3d   one dataset:
           vtkImageData       when the grids X Y Z are uniform and the transform has
                              orthogonal columns (a rotation, a scale per axis, a
                              reflection): origin, spacing and direction matrix. Uniform
                              to 1/1000 of the step (UNIFORM_TOL: DICOM slice positions
                              carry nanometres of rounding), orthogonal to 1e-5
           vtkStructuredGrid  otherwise (a non-uniform grid, a shear): the world
                              coordinates of every voxel, A * [X(i); Y(j); Z(k); 1], exact
         point data 'data' (the components c... as components), T as time steps,
         info.* as field data (numbers -> double arrays, texts -> string arrays)
  .mi3d  a vtkMultiBlockDataSet, one block per member ("n: tag"), holes skipped;
         time steps: the union of the members' T, each member at its nearest instant

Properties: DICOMDIR (overrides $DICOMDIR$ of a Lazy file, SPEC 2) and FirstFrameOnly
(reads only data(:,:,:,1): fast, little memory).

The DLLs are looked for in: $I3D_DLL_DIR, the folder of this file, ..\\cpp\\build and
..\\matlab (the repository layout).
"""
import ctypes as C
import os

import numpy as np
from paraview.util.vtkAlgorithm import VTKPythonAlgorithmBase, smproxy, smproperty, smdomain, smhint
from vtkmodules.vtkCommonCore import vtkDoubleArray, vtkStringArray, vtkPoints
from vtkmodules.vtkCommonDataModel import vtkImageData, vtkStructuredGrid, vtkMultiBlockDataSet, vtkDataObject
from vtkmodules.vtkCommonExecutionModel import vtkStreamingDemandDrivenPipeline
from vtkmodules.util import numpy_support

# ------------------------------------------------------------------ the DLLs
_HERE = os.path.dirname(os.path.abspath(globals().get('__file__', os.getcwd())))
_DIRS = [os.environ.get('I3D_DLL_DIR', ''), _HERE,
         os.path.join(_HERE, '..', 'cpp', 'build'), os.path.join(_HERE, '..', 'matlab')]
_L = None
_M = None
_P = C.POINTER


class I3DError(RuntimeError):
    def __init__(self, ident, msg):
        super().__init__('[%s] %s' % (ident, msg))
        self.ident = ident


def _find(name):
    for d in _DIRS:
        p = os.path.join(d, name)
        if d and os.path.isfile(p):
            return os.path.abspath(p)
    raise I3DError('cannotOpen', '%s not found in %s (set I3D_DLL_DIR)' % (name, [d for d in _DIRS if d]))


def _libs():
    global _L, _M
    if _L is not None:
        return _L, _M
    L = C.CDLL(_find('i3d.dll'))
    V = C.c_void_p
    for f, r, a in [
            ('i3d_open', V, [C.c_char_p]),
            ('i3d_open_vars', V, [C.c_char_p, C.c_int, _P(C.c_char_p), _P(C.c_char_p)]),
            ('i3d_open_window', V, [C.c_char_p, C.c_int64, C.c_int64, C.c_int, _P(C.c_char_p), _P(C.c_char_p)]),
            ('i3d_close', None, [V]),
            ('i3d_last_error', C.c_char_p, [V]), ('i3d_last_error_id', C.c_char_p, [V]),
            ('i3d_grid', C.c_int, [V, C.c_char, _P(_P(C.c_double)), _P(C.c_size_t)]),
            ('i3d_transform', C.c_int, [V, _P(C.c_double)]),
            ('i3d_data_shape', C.c_int, [V, _P(C.c_int), _P(C.c_int64)]),
            ('i3d_data_type', C.c_char_p, [V]),
            ('i3d_data_bytes', C.c_size_t, [V]), ('i3d_read_data', C.c_int, [V, V, C.c_size_t]),
            ('i3d_first_frame_bytes', C.c_size_t, [V]), ('i3d_read_first_frame', C.c_int, [V, V, C.c_size_t]),
            ('i3d_info_count', C.c_int, [V]),
            ('i3d_info_key', C.c_char_p, [V, C.c_int]), ('i3d_info_type', C.c_char_p, [V, C.c_int]),
            ('i3d_info_length', C.c_int64, [V, C.c_int]),
            ('i3d_info_numbers', C.c_int, [V, C.c_int, _P(C.c_double), C.c_int64]),
            ('i3d_info_text', C.c_char_p, [V, C.c_int, C.c_int64])]:
        g = getattr(L, f)
        g.restype = r
        g.argtypes = a
    M = C.CDLL(_find('mi3d.dll'))
    for f, r, a in [
            ('mi3d_open', V, [C.c_char_p]), ('mi3d_close', None, [V]),
            ('mi3d_last_error', C.c_char_p, [V]), ('mi3d_last_error_id', C.c_char_p, [V]),
            ('mi3d_count', C.c_int, [V]), ('mi3d_present', C.c_int, [V, C.c_int]),
            ('mi3d_range', C.c_int, [V, C.c_int, _P(C.c_int64), _P(C.c_int64)]),
            ('mi3d_tag', C.c_char_p, [V, C.c_int])]:
        g = getattr(M, f)
        g.restype = r
        g.argtypes = a
    _L, _M = L, M
    return L, M


_NP = {'int8': np.int8, 'uint8': np.uint8, 'int16': np.int16, 'uint16': np.uint16, 'int32': np.int32,
       'uint32': np.uint32, 'int64': np.int64, 'uint64': np.uint64, 'single': np.float32, 'double': np.float64}


def _s(b):
    return b.decode('utf-8') if b else ''


class _File:
    """An .i3d opened by i3d.dll: the whole file, or a window of a .mi3d (a member)."""

    def __init__(self, path, variables=None, window=None):
        L, _ = _libs()
        self.L = L
        variables = {k.strip('$'): v for k, v in (variables or {}).items() if v}
        n = len(variables)
        names = (C.c_char_p * max(n, 1))(*[k.encode('utf-8') for k in variables])
        values = (C.c_char_p * max(n, 1))(*[v.encode('utf-8') for v in variables.values()])
        p = path.encode('utf-8')
        if window is not None:
            self.h = L.i3d_open_window(p, window[0], window[1], n, names, values)
        elif n:
            self.h = L.i3d_open_vars(p, n, names, values)
        else:
            self.h = L.i3d_open(p)
        if not self.h:
            raise I3DError(_s(L.i3d_last_error_id(None)), _s(L.i3d_last_error(None)))

    def _check(self, rc):
        if rc:
            raise I3DError(_s(self.L.i3d_last_error_id(self.h)), _s(self.L.i3d_last_error(self.h)))

    def grid(self, a):
        p, n = _P(C.c_double)(), C.c_size_t()
        self._check(self.L.i3d_grid(self.h, a.encode(), C.byref(p), C.byref(n)))
        return np.ctypeslib.as_array(p, (n.value,)).copy() if n.value else np.zeros(0)

    def transform(self):
        a = (C.c_double * 16)()
        self._check(self.L.i3d_transform(self.h, a))
        return np.array(a[:]).reshape(4, 4)                         # by rows

    def shape(self):
        nd, d = C.c_int(), (C.c_int64 * 16)()
        self._check(self.L.i3d_data_shape(self.h, C.byref(nd), d))
        return tuple(d[:nd.value])

    def data(self, first=False):
        s = list(self.shape())
        if first:
            s[3] = 1
        a = np.empty(int(np.prod(s)), dtype=_NP[_s(self.L.i3d_data_type(self.h))])
        nb = self.L.i3d_first_frame_bytes(self.h) if first else self.L.i3d_data_bytes(self.h)
        rd = self.L.i3d_read_first_frame if first else self.L.i3d_read_data
        self._check(rd(self.h, a.ctypes.data_as(C.c_void_p), nb))
        return a.reshape(s, order='F')

    def info(self):
        out = {}
        for i in range(self.L.i3d_info_count(self.h)):
            k, t, n = _s(self.L.i3d_info_key(self.h, i)), _s(self.L.i3d_info_type(self.h, i)), self.L.i3d_info_length(self.h, i)
            if t == 'numbers':
                v = (C.c_double * max(n, 1))()
                if self.L.i3d_info_numbers(self.h, i, v, n) == 0:
                    out[k] = np.array(v[:n])
            elif t == 'text':
                out[k] = [_s(self.L.i3d_info_text(self.h, i, j)) for j in range(n)]
            elif t == 'other':
                out[k] = [_s(self.L.i3d_info_text(self.h, i, 0))]
        return out

    def close(self):
        if self.h:
            self.L.i3d_close(self.h)
            self.h = None


def _members(path):
    """[(n, tag, (offset, length))] of the members of a .mi3d (holes skipped)."""
    _, M = _libs()
    m = M.mi3d_open(path.encode('utf-8'))
    if not m:
        raise I3DError(_s(M.mi3d_last_error_id(None)), _s(M.mi3d_last_error(None)))
    try:
        out = []
        for n in range(1, M.mi3d_count(m) + 1):
            if M.mi3d_present(m, n) != 1:
                continue
            a, L = C.c_int64(), C.c_int64()
            if M.mi3d_range(m, n, C.byref(a), C.byref(L)):
                raise I3DError(_s(M.mi3d_last_error_id(m)), _s(M.mi3d_last_error(m)))
            out.append((n, _s(M.mi3d_tag(m, n)), (a.value, L.value)))
        return out
    finally:
        M.mi3d_close(m)


# ------------------------------------------------------------------ to VTK
UNIFORM_TOL = 1e-3       # a grid is uniform if no value is further than this * step from the
                         # line between its first and last value (DICOM slice positions carry
                         # rounding of 1e-7..1e-5 of the spacing: nanometres)
ORTHO_TOL = 1e-5         # the columns of the transform, orthogonal to this (DICOM cosines)


def _uniform(g):
    """(first, step) if the grid is uniform to UNIFORM_TOL, else None. One value: step 1."""
    if len(g) == 1:
        return g[0], 1.0
    s = (g[-1] - g[0]) / (len(g) - 1)
    err = np.max(np.abs(g - (g[0] + s * np.arange(len(g)))))
    return (g[0], s) if err <= UNIFORM_TOL * abs(s) else None


class _Stack:
    """One stack read: its geometry, its data (all instants, or the first) and its info."""

    def __init__(self, f, first):
        self.X, self.Y, self.Z, self.T = f.grid('X'), f.grid('Y'), f.grid('Z'), f.grid('T')
        self.A = f.transform()
        self.D = f.data(first)                                        # (i, j, k, t, c...), order F
        self.info = f.info()
        if first:
            self.T = self.T[:1]
        # vtkImageData if the grids are uniform and the columns of A orthogonal
        A3 = self.A[:3, :3]
        self.u = (_uniform(self.X), _uniform(self.Y), _uniform(self.Z))
        self.cols = np.linalg.norm(A3, axis=0)
        self.U = A3 / np.where(self.cols > 0, self.cols, 1)
        rigid = bool(np.all(self.cols > 0) and np.allclose(self.U.T @ self.U, np.eye(3), atol=ORTHO_TOL))
        self.image = rigid and all(self.u)

    def dataset(self, t):
        """The VTK dataset at instant index t."""
        ni, nj, nk = len(self.X), len(self.Y), len(self.Z)
        A3, b = self.A[:3, :3], self.A[:3, 3]
        (ux, uy, uz), cols, U = self.u, self.cols, self.U
        if self.image:
            ds = vtkImageData()
            ds.SetDimensions(ni, nj, nk)
            ds.SetOrigin(*(A3 @ np.array([ux[0], uy[0], uz[0]]) + b))
            ds.SetSpacing(ux[1] * cols[0], uy[1] * cols[1], uz[1] * cols[2])
            ds.SetDirectionMatrix(U.flatten().tolist())
        else:
            I, J, K = np.meshgrid(self.X, self.Y, self.Z, indexing='ij')
            P = np.stack([I.ravel(order='F'), J.ravel(order='F'), K.ravel(order='F')], axis=1) @ A3.T + b
            pts = vtkPoints()
            pts.SetData(numpy_support.numpy_to_vtk(np.ascontiguousarray(P), deep=1))
            ds = vtkStructuredGrid()
            ds.SetDimensions(ni, nj, nk)
            ds.SetPoints(pts)
        v = self.D[:, :, :, min(t, self.D.shape[3] - 1), ...]
        nc = int(np.prod(v.shape[3:])) if v.ndim > 3 else 1
        a = numpy_support.numpy_to_vtk(np.ascontiguousarray(v.reshape(ni * nj * nk, nc, order='F')), deep=1)
        a.SetName('data')
        ds.GetPointData().AddArray(a)
        ds.GetPointData().SetActiveScalars('data')
        for k, val in self.info.items():
            if isinstance(val, np.ndarray):
                fa = vtkDoubleArray()
                for x in val:
                    fa.InsertNextValue(float(x))
            else:
                fa = vtkStringArray()
                for x in val:
                    fa.InsertNextValue(x)
            fa.SetName(k)
            ds.GetFieldData().AddArray(fa)
        return ds


def _nearest(T, t):
    return int(np.argmin(np.abs(np.asarray(T) - t))) if len(T) else 0


# ------------------------------------------------------------------ the reader
@smproxy.reader(name='I3DReader', label='I3D reader', extensions='i3d mi3d',
                file_description='I3D image stacks')
class I3DReader(VTKPythonAlgorithmBase):
    def __init__(self):
        VTKPythonAlgorithmBase.__init__(self, nInputPorts=0, nOutputPorts=1, outputType='vtkDataObject')
        self._file = None
        self._dicomdir = ''
        self._first = False
        self._stacks = None                  # [(name, _Stack)]
        self._times = None

    # -------- properties
    @smproperty.stringvector(name='FileName')
    @smdomain.filelist()
    @smhint.filechooser(extensions='i3d mi3d', file_description='I3D image stacks')
    def SetFileName(self, name):
        if name != self._file:
            self._file = name
            self._stacks = None
            self.Modified()

    @smproperty.stringvector(name='DICOMDIR', default_values='')
    def SetDICOMDIR(self, d):
        if d != self._dicomdir:
            self._dicomdir = d
            self._stacks = None
            self.Modified()

    @smproperty.xml("""<IntVectorProperty name="FirstFrameOnly" command="SetFirstFrameOnly"
                         number_of_elements="1" default_values="0">
                         <BooleanDomain name="bool"/>
                         <Documentation>Read only data(:,:,:,1): fast, little memory.</Documentation>
                       </IntVectorProperty>""")
    def SetFirstFrameOnly(self, v):
        if bool(v) != self._first:
            self._first = bool(v)
            self._stacks = None
            self.Modified()

    @smproperty.doublevector(name='TimestepValues', information_only='1', si_class='vtkSITimeStepsProperty')
    def GetTimestepValues(self):
        self._load()
        return self._times

    # -------- reading
    def _ismi3d(self):
        return self._file.lower().endswith('.mi3d')

    def _load(self):
        if self._stacks is not None or not self._file:
            return
        V = {'DICOMDIR': self._dicomdir} if self._dicomdir else None
        S = []
        if self._ismi3d():
            for n, tag, w in _members(self._file):
                f = _File(self._file, V, window=w)
                try:
                    S.append(('%d: %s' % (n, tag) if tag else str(n), _Stack(f, self._first)))
                finally:
                    f.close()
        else:
            f = _File(self._file, V)
            try:
                S.append((os.path.basename(self._file), _Stack(f, self._first)))
            finally:
                f.close()
        self._stacks = S
        self._times = sorted(set(float(t) for _, s in S for t in s.T))

    def RequestDataObject(self, request, inInfo, outInfo):
        self._load()
        cls = vtkMultiBlockDataSet if self._ismi3d() else (vtkImageData if self._stacks[0][1].image else vtkStructuredGrid)
        out = outInfo.GetInformationObject(0)
        cur = out.Get(vtkDataObject.DATA_OBJECT())
        if cur is None or not cur.IsA(cls.__name__):
            out.Set(vtkDataObject.DATA_OBJECT(), cls())
        return 1

    def RequestInformation(self, request, inInfo, outInfo):
        self._load()
        out = outInfo.GetInformationObject(0)
        k = vtkStreamingDemandDrivenPipeline
        out.Remove(k.TIME_STEPS())
        out.Remove(k.TIME_RANGE())
        if self._times and len(self._times) > 1:
            for t in self._times:
                out.Append(k.TIME_STEPS(), t)
            out.Append(k.TIME_RANGE(), self._times[0])
            out.Append(k.TIME_RANGE(), self._times[-1])
        if not self._ismi3d():
            s = self._stacks[0][1]
            out.Set(k.WHOLE_EXTENT(), 0, len(s.X) - 1, 0, len(s.Y) - 1, 0, len(s.Z) - 1)
        return 1

    def RequestData(self, request, inInfo, outInfo):
        self._load()
        out = outInfo.GetInformationObject(0)
        k = vtkStreamingDemandDrivenPipeline
        t = out.Get(k.UPDATE_TIME_STEP()) if out.Has(k.UPDATE_TIME_STEP()) else (self._times[0] if self._times else 0.0)
        dst = vtkDataObject.GetData(outInfo, 0)
        if self._ismi3d():
            for b, (name, s) in enumerate(self._stacks):
                dst.SetBlock(b, s.dataset(_nearest(s.T, t)))
                dst.GetMetaData(b).Set(vtkMultiBlockDataSet.NAME(), name)
        else:
            s = self._stacks[0][1]
            dst.ShallowCopy(s.dataset(_nearest(s.T, t)))
        if out.Has(k.UPDATE_TIME_STEP()):
            dst.GetInformation().Set(vtkDataObject.DATA_TIME_STEP(), t)
        return 1
