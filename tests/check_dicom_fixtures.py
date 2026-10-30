# <dicom> sin depender de d:\DICOMS: .dcm SINTETICOS con valores conocidos,
# referenciados desde .i3d hechos a mano, leidos por los DOS lectores (DLL con
# DCMTK, Python con pydicom) y comparados con lo que se escribio.
#
#   python check_dicom_fixtures.py
#
# Cada .dcm es de 6 columnas x 5 filas (Columns = 6 = ni, Rows = 5 = nj: SPEC 4,
# la columna es la i). Los casos:
#   native12   uint16 nativo, BitsStored 12
#   signed12   int16, BitsStored 12, HighBit 11, PixelRepresentation 1: lo
#              almacenado son 12 bits en complemento a 2 con los 4 altos a 0; el
#              lector TIENE que extender el signo (-5 se guarda 0x0FFB)
#   rle        native12 en RLE Lossless
#   jpls       uint16 en JPEG-LS lossless (1.2.840.10008.1.2.4.80)
#   mf3        uint16, 3 frames
# y en .i3d: las tres codificaciones en un volumen, el signo, frames a:b, una
# $VARIABLE$ que se sobrescribe al abrir, una ruta con '\' y una carpeta "año".
# Todo en un directorio temporal que se borra al terminar.
import sys, os, tempfile, shutil, zlib
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import i3d_ctypes
from read_i3d import read_i3d
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, RLELossless, JPEGLSLossless, generate_uid
from pydicom.encaps import encapsulate
import imagecodecs

NI, NJ = 6, 5
rng = np.random.default_rng(11)

def dcm(path, frames, bits_stored=16, signed=False, ts=ExplicitVRLittleEndian):
    # frames: (nf, NJ, NI) en el orden de pydicom (fila, columna); lo almacenado tal cual
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.4'
    meta.MediaStorageSOPInstanceUID = generate_uid()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = Dataset(); ds.file_meta = meta
    ds.SOPClassUID = meta.MediaStorageSOPClassUID; ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.Modality = 'MR'; ds.Rows = NJ; ds.Columns = NI
    ds.SamplesPerPixel = 1; ds.PhotometricInterpretation = 'MONOCHROME2'
    ds.BitsAllocated = 16; ds.BitsStored = bits_stored; ds.HighBit = bits_stored - 1
    ds.PixelRepresentation = 1 if signed else 0
    if frames.shape[0] > 1: ds.NumberOfFrames = frames.shape[0]
    stored = frames.astype('<u2' if not signed else '<i2')
    ds.PixelData = stored.tobytes()
    if ts == RLELossless:
        ds.compress(RLELossless)
    elif ts == JPEGLSLossless:
        ds.file_meta.TransferSyntaxUID = JPEGLSLossless
        ds.PixelData = encapsulate([imagecodecs.jpegls_encode(np.ascontiguousarray(f.astype(np.uint16))) for f in frames])
        ds['PixelData'].VR = 'OB'
    ds.save_as(path, enforce_file_format=True)

def i3d(path, lines):
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(['I3D 0.1'] + lines) + '\n---\n')

def grids(nk):
    return ['X = 0.0 : 1.0 : %d.0' % (NI - 1), 'Y = 0.0 : 1.0 : %d.0' % (NJ - 1),
            'Z = ' + ('0.0' if nk == 1 else '0.0 : 1.0 : %d.0' % (nk - 1)), 'T = 0.0']

def as_i3d(frames, dtype):
    # (nf, NJ, NI) de pydicom -> data(i,j,k,1) de @I3D: la columna es la i
    return np.ascontiguousarray(np.transpose(frames, (2, 1, 0))).astype(dtype)[:, :, :, None]

def crc(a):
    # el crc de un bloque (SPEC 4): de sus bytes DECODIFICADOS, en orden columna
    return '%08x' % (zlib.crc32(np.asfortranarray(a).tobytes(order='F')) & 0xffffffff)

d = tempfile.mkdtemp(prefix='i3d_dcm_')
nbad = 0
try:
    u12 = rng.integers(0, 4096, (1, NJ, NI))
    u16 = rng.integers(0, 65536, (1, NJ, NI))
    s12 = rng.integers(-2048, 2048, (1, NJ, NI))
    s12[0, 0, :4] = [-2048, -5, -1, 2047]                      # los extremos y el -1
    mf = rng.integers(0, 4096, (3, NJ, NI))
    os.makedirs(os.path.join(d, 'fx'));  os.makedirs(os.path.join(d, 'año'))
    dcm(os.path.join(d, 'fx', 'native12.dcm'), u12, bits_stored=12)
    dcm(os.path.join(d, 'fx', 'rle.dcm'), u12, bits_stored=12, ts=RLELossless)
    dcm(os.path.join(d, 'fx', 'jpls.dcm'), u16, ts=JPEGLSLossless)
    # signed12: lo ALMACENADO son los 12 bits bajos (4 altos a 0)
    dcm(os.path.join(d, 'fx', 'signed12.dcm'), (s12 & 0x0FFF).astype(np.int16), bits_stored=12, signed=True)
    dcm(os.path.join(d, 'fx', 'mf3.dcm'), mf, bits_stored=12)
    shutil.copy(os.path.join(d, 'fx', 'native12.dcm'), os.path.join(d, 'año', 'native12.dcm'))
    # carpetas con '$' (\\srv\C$\...) y con llaves (GUIDs): rutas validas
    for sub in ('C$x', '{6 5}'):
        os.makedirs(os.path.join(d, sub)); shutil.copy(os.path.join(d, 'fx', 'native12.dcm'), os.path.join(d, sub, 'native12.dcm'))

    CASES = [
      # nombre, fichero .i3d (relativo a d), cabecera, esperado, variables al abrir
      ('three encodings', 'three.i3d', grids(3) + ['$FX$ = "fx"',
          'data(:,:,1) = <dicom uint16 "$FX$/native12.dcm">',
          'data(:,:,2) = <dicom uint16 "$FX$/rle.dcm">',
          'data(:,:,3) = <dicom uint16 "$FX$/jpls.dcm">'],
          np.concatenate([as_i3d(u12, '<u2'), as_i3d(u12, '<u2'), as_i3d(u16, '<u2')], axis=2), None),
      ('sign extension', 'signed.i3d', grids(1) + ['data = <dicom int16 "fx/signed12.dcm">'],
          as_i3d(s12, '<i2'), None),
      ('multiframe all', 'mf.i3d', grids(3) + ['data = <dicom uint16 "fx/mf3.dcm">'],
          as_i3d(mf, '<u2'), None),
      ('frames 2:3', 'mf23.i3d', grids(3) + ['data(:,:,1:2) = <dicom uint16 "fx/mf3.dcm" frames 2:3>',
          'data(:,:,3) = <dicom uint16 "fx/native12.dcm">'],
          np.concatenate([as_i3d(mf[1:3], '<u2'), as_i3d(u12, '<u2')], axis=2), None),
      ('variable override', 'over.i3d', grids(1) + ['$FX$ = "nowhere"', 'data = <dicom uint16 "$FX$/native12.dcm">'],
          as_i3d(u12, '<u2'), {'FX': 'fx'}),
      ('backslash path', 'bs.i3d', grids(1) + [r'data = <dicom uint16 "fx\native12.dcm">'],
          as_i3d(u12, '<u2'), None),
      # una ruta NO ASCII escrita EN LA CABECERA (UTF-8, SPEC 1)
      ('non-ASCII in header', 'nonascii.i3d', grids(1) + ['data = <dicom uint16 "año/native12.dcm">'],
          as_i3d(u12, '<u2'), None),
      ('i3d in non-ASCII', os.path.join('año', 'inside.i3d'), grids(1) + ['data = <dicom uint16 "native12.dcm">'],
          as_i3d(u12, '<u2'), None),
      # el crc de un <dicom> (2026-10-14): el de los pixeles decodificados. Los tres
      # codecs, el signo y frames a:b
      ('crc on <dicom>', 'crc.i3d', grids(3) + [
          'data(:,:,1) = <dicom uint16 "fx/rle.dcm" crc %s>' % crc(as_i3d(u12, '<u2')),
          'data(:,:,2) = <dicom uint16 "fx/jpls.dcm" crc %s>' % crc(as_i3d(u16, '<u2')),
          'data(:,:,3) = <dicom uint16 "fx/mf3.dcm" frames 2:2 crc %s>' % crc(as_i3d(mf[1:2], '<u2'))],
          np.concatenate([as_i3d(u12, '<u2'), as_i3d(u16, '<u2'), as_i3d(mf[1:2], '<u2')], axis=2), None),
      ('crc on signed', 'crcs.i3d', grids(1) + ['data = <dicom int16 "fx/signed12.dcm" crc %s>' % crc(as_i3d(s12, '<i2'))],
          as_i3d(s12, '<i2'), None),
      # el .dcm ya no da lo que se escribio (aqui: el crc de OTRO plano): badCRC
      ('crc: the .dcm changed', 'crcbad.i3d', grids(1) + ['data = <dicom uint16 "fx/native12.dcm" crc %s>' % crc(as_i3d(u16, '<u2'))],
          'badCRC', None),
      # un '$' literal se escribe $$ (SPEC 2, 2026-10-23); uno suelto es un error;
      # el valor de una variable entra tal cual, con su '$'
      ('literal $ as $$', 'dollar.i3d', grids(1) + ['data = <dicom uint16 "C$$x/native12.dcm">'], as_i3d(u12, '<u2'), None),
      ('lone $ is an error', 'lone.i3d', grids(1) + ['data = <dicom uint16 "C$x/native12.dcm">'], 'badVariable', None),
      ('$ in a variable value', 'dvar.i3d', grids(1) + ['$FX$ = "C$x"', 'data = <dicom uint16 "$FX$/native12.dcm">'], as_i3d(u12, '<u2'), None),
      # unas { } dentro de la ruta no son un {shape}
      ('braces in a path', 'brace.i3d', grids(1) + ['data = <dicom uint16 "{6 5}/native12.dcm">'], as_i3d(u12, '<u2'), None),
    ]
    for name, rel, lines, exp, var in CASES:
        p = os.path.join(d, rel); i3d(p, lines)
        res = {}
        for who in ('cpp', 'py'):
            try:
                a = i3d_ctypes.I3DFile(p, var).data() if who == 'cpp' else read_i3d(p, var)['data']
                if isinstance(exp, str):
                    res[who] = 'FAIL(accepted)'                  # TENIA que lanzar exp
                    continue
                good = a.dtype == exp.dtype and a.shape == exp.shape and a.tobytes(order='F') == np.asfortranarray(exp).tobytes(order='F')
                res[who] = 'ok' if good else f'FAIL(different: {a.dtype}{a.shape})'
            except Exception as e:
                res[who] = 'ok' if isinstance(exp, str) and exp in str(e) else f'FAIL({str(e)[:100]})'
        bad = any(v.startswith('FAIL') for v in res.values())
        if name.startswith('OPEN1'):
            print(f'  open {name:18s} cpp: {res["cpp"]:10s} py: {res["py"][:60]}')
            continue
        nbad += bad
        print(f'  {"FAIL" if bad else "ok  "} {name:18s} cpp: {res["cpp"]:10s} py: {res["py"]}')
finally:
    shutil.rmtree(d, ignore_errors=True)
print(f'{len(CASES)} cases, {nbad} failed')
sys.exit(1 if nbad else 0)
