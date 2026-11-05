# Las referencias de las pruebas de C# (csharp/I3D.Tests), con el lector de
# REFERENCIA (read_i3d.py): las pruebas leen lo mismo con la DLL a traves de
# I3DFile y lo comparan bit a bit.
#
#   python make_cs_refs.py <dir de .i3d> <dir de referencias> <dir de especiales>
#
# <dir de .i3d>: los ficheros a comparar (los de check_roundtrip( outdir )). Por
# cada uno, en <dir de referencias>:
#   <tag>.json            fichero, variables, tipo, forma, rejillas y transform en
#                         hex, thumbnail (su forma), info (los valores CRUDOS de la
#                         cabecera), infoParsed (I['info']) e infoErrors
#   <tag>.data.bin        data, en orden columna
#   <tag>.first.bin       el primer instante, data(:,:,:,1,c...)
#   <tag>.thumbnail.bin   el thumbnail, si hay
# Y en <dir de especiales>, los ficheros de las pruebas especificas: utf8.i3d,
# hidden.i3d (I3Db, por i3d_rewrite), png.i3d, vars.i3d (una ruta $DICOMDIR$ que
# no existe), invalid_coverage.i3d, invalid_rawlen.i3d.
import sys, os, glob, json
import ctypes as C
import numpy as np
import imagecodecs
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_i3d import read_i3d
import i3d_ctypes

src, refdir, special = sys.argv[1:4]
os.makedirs(refdir, exist_ok=True)
os.makedirs(special, exist_ok=True)

def hexd(x): return np.ascontiguousarray(x, dtype='<f8').tobytes().hex()

n = 0
for f in sorted(glob.glob(os.path.join(src, '*.i3d'))):
    tag = os.path.basename(f)[:-4]
    if tag.endswith(('_corrupt', '_crcbad')): continue        # controles negativos: no se leen
    I = read_i3d(f)
    D = I['data']
    th = I.get('thumbnail')
    raw = {k: v for k, _, v in I['entries'] if k.startswith('info.')}
    R = {'file': os.path.abspath(f), 'variables': {}, 'dtype': D.dtype.name, 'shape': list(D.shape),
         'X': hexd(I['X']), 'Y': hexd(I['Y']), 'Z': hexd(I['Z']), 'T': hexd(I['T']),
         'transform': hexd(I['transform']),
         'thumbnail': None if th is None else {'shape': list(th.shape)},
         'info': raw, 'infoParsed': I['info'], 'infoErrors': sorted(I['info_errors'])}
    with open(os.path.join(refdir, tag + '.json'), 'w', encoding='utf-8') as o:
        json.dump(R, o, ensure_ascii=False)
    open(os.path.join(refdir, tag + '.data.bin'), 'wb').write(D.tobytes(order='F'))
    open(os.path.join(refdir, tag + '.first.bin'), 'wb').write(np.asfortranarray(D[:, :, :, :1]).tobytes(order='F'))
    if th is not None: open(os.path.join(refdir, tag + '.thumbnail.bin'), 'wb').write(th.tobytes(order='F'))
    n += 1

# ---- los especiales, a mano
def write(name, header, binary=b''):
    with open(os.path.join(special, name), 'wb') as o:
        o.write(('\n'.join(header) + '\n---\n').encode('utf-8'))
        o.write(binary)

G = ['I3D', 'X = 0.0 1.0', 'Y = 0.0 1.0 2.0', 'Z = 0.0 1.0 2.0 3.0', 'T = 0.0']
d = np.arange(24, dtype='<u2')                                  # {2 3 4 1}: 24 uint16
write('utf8.i3d', G + ['data(:,:,:,1) = <raw uint16 @0:47>', 'info.PatientName = "Muñoz^José"'], d.tobytes())
# la variante oculta (I3Db), por la DLL
L = i3d_ctypes._lib()
L.i3d_rewrite.argtypes = [C.c_char_p, C.c_char_p, C.c_int]
if L.i3d_rewrite(os.path.join(special, 'utf8.i3d').encode(), os.path.join(special, 'hidden.i3d').encode(), 1):
    raise SystemExit('i3d_rewrite failed')
# un thumbnail PNG {5 4 1 2} = arange(40)*3 en orden columna: UNA imagen gris de
# 5 x (4*2), los frames uno al lado del otro (SPEC 7)
TH = (np.arange(40, dtype=np.uint8) * 3).reshape((5, 4, 1, 2), order='F')
png = imagecodecs.png_encode(np.ascontiguousarray(np.concatenate([TH[:, :, 0, f] for f in range(2)], axis=1)))
write('png.i3d', G + ['data(:,:,:,1) = <raw uint16 @0:47>',
                      'thumbnail = <png uint8 {5 4 1 2} @48:%d>' % (48 + len(png) - 1)], d.tobytes() + png)
# una ruta con $DICOMDIR$ que no existe: abre, y leer data da cannotOpen
write('vars.i3d', ['I3D', 'X = 0.0 1.0', 'Y = 0.0 1.0', 'Z = 0.0', 'T = 0.0',
                   '$DICOMDIR$ = "C:/no/such/folder"',
                   'data(:,:,1,1) = <dicom uint16 "$DICOMDIR$/x.dcm">'])
# un plano sin asignar: coverage al abrir
write('invalid_coverage.i3d', G[:3] + ['Z = 0.0 1.0', 'T = 0.0', 'data(:,:,1,1) = <raw uint16 @0:11>'], np.zeros(6, '<u2').tobytes())
# un raw con menos bytes de los que pide su forma: badBlock al leer
write('invalid_rawlen.i3d', G + ['data(:,:,:,1) = <raw uint16 @0:45>'], d.tobytes()[:46])
print(f'{n} references in {refdir}; specials in {special}')
