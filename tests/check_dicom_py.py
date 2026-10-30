# Los .i3d perezosos de un directorio, leidos por DOS lectores independientes:
#   py   tests/read_i3d.py, que decodifica <dicom> con pydicom
#   cpp  la DLL (cpp/build/i3d.dll), que decodifica con DCMTK
# y comparados bit a bit entre si. Lo que dicomread daba ya lo comprobo el
# escritor (verificacion con el lector C++) y try_study.m.
#   python check_dicom_py.py <dir>
import sys, os, glob
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_i3d import read_i3d
import i3d_ctypes

nbad = 0
files = sorted(glob.glob(os.path.join(sys.argv[1], '*.i3d')))
for f in files:
    try:
        a = read_i3d(f)['data']
    except Exception as e:
        print(f'  FAIL {os.path.basename(f)}  py: {type(e).__name__}: {str(e)[:120]}'); nbad += 1; continue
    try:
        b = i3d_ctypes.I3DFile(f).data()
    except Exception as e:
        print(f'  FAIL {os.path.basename(f)}  cpp: {e}'); nbad += 1; continue
    same = a.dtype == b.dtype and a.shape == b.shape and a.tobytes(order='F') == b.tobytes(order='F')
    nbad += not same
    if not same:
        print(f'  FAIL {os.path.basename(f)}  {a.dtype}{a.shape} vs {b.dtype}{b.shape}')
print(f'{len(files)} files, {nbad} failed  (pydicom vs DCMTK, bit for bit)')
sys.exit(1 if nbad else 0)
