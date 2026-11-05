# Ficheros MALOS (y unos pocos raros pero validos), escritos a mano, leidos por
# los DOS lectores: la DLL de C++ (por ctypes) y el de referencia en Python.
#
#   python check_invalid.py
#
# Un lector estricto se prueba con ficheros malos, no solo con buenos. Cada caso
# dice lo que TIENE que pasar:
#   ('err', ID, frase)   la DLL lanza con ese identificador, y Python con un
#                        mensaje que contiene la frase
#   ('ok',  array)       los dos leen exactamente ese array (bits)
# Todo en un directorio temporal que se borra al terminar.
import sys, os, struct, zlib, tempfile, shutil
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import i3d_ctypes
from read_i3d import read_i3d, _unhide, SEED_HIDDEN, SEED_I3DB, MULT_HIDDEN, MULT_I3DB

P = np.arange(12, dtype='<u2').reshape(4, 3, order='F')        # ni = 4, nj = 3
RAW = P.tobytes(order='F')                                       # 24 bytes
G1 = ['X = 0.0 : 1.0 : 3.0', 'Y = 0.0 : 1.0 : 2.0', 'Z = 0.0', 'T = 0.0']
G2 = ['X = 0.0 : 1.0 : 3.0', 'Y = 0.0 : 1.0 : 2.0', 'Z = 0.0 1.0', 'T = 0.0']

def text(lines, magic='I3D', end=True):
    return ('\n'.join([magic] + lines) + ('\n---\n' if end else '\n')).encode('utf-8')   # SPEC 1

def hidden(lines, binary, trim=0, extra=b'', old=False):
    # SPEC 1.1: "I3Db" | L | NOT(flujo al reves) XOR k ; _unhide es su propia
    # inversa. old: el esquema de antes del 2026-10-24 (sin invertir, el
    # multiplicador de Knuth), que ya no se lee
    z = zlib.compress(('\n'.join(['I3D'] + lines) + '\n').encode('ascii'), 9)
    z = z[:len(z) - trim] + extra
    h = _unhide(z, SEED_I3DB, 2654435761) if old else _unhide(z[::-1])
    return b'I3Db' + struct.pack('<Q', len(z)) + h + binary

def hidepart(lines, extra=b'', i3db=False):
    # SPEC 1.2: el bloque <hidden>: las lineas en zlib, el flujo AL REVES, y el
    # XOR con SUS constantes (_unhide es su propia inversa). i3db: con las
    # constantes de la cabecera I3Db, que en un <hidden> no valen
    z = zlib.compress(('\n'.join(lines) + '\n').encode('utf-8'), 9) + extra
    return _unhide(z[::-1], SEED_I3DB, MULT_I3DB) if i3db else _unhide(z[::-1], SEED_HIDDEN, MULT_HIDDEN)

HP = hidepart(['Z = 0.0', 'T = 0.0', 'data = <raw uint16 @0:23>'])        # media cabecera, data incluido
HPc = zlib.crc32(('\n'.join(['Z = 0.0', 'T = 0.0', 'data = <raw uint16 @0:23>']) + '\n').encode()) & 0xffffffff
G2v = ['X = 0.0 : 1.0 : 3.0', 'Y = 0.0 : 1.0 : 2.0']                      # lo que queda a la vista
def hline(n=len(HP), at=24, more=''): return 'header = <hidden @%d:%d%s>' % (at, at + n - 1, more)

def hidden_first():
    # el bloque <hidden> PRIMERO en el binario y data detras: el texto oculto lleva
    # el offset de data, que es el tamano del propio bloque -> hasta que cuadre
    n = 0
    for _ in range(8):
        hp = hidepart(['Z = 0.0', 'T = 0.0', 'data = <raw uint16 @%d:%d>' % (n, n + 23)])
        if len(hp) == n: return text(G2v + ['header = <hidden @0:%d>' % (n - 1)]) + hp + RAW
        n = len(hp)
    raise RuntimeError('hidden_first: the offset does not settle')

two = np.stack([P, np.full_like(P, 7)], axis=2)                  # el plano 2 = fill 7
fnan = np.stack([P.astype('<f8'), np.full(P.shape, np.nan)], axis=2)
# los lectores devuelven SIEMPRE i j k t (4-D), tambien con nk = nt = 1
P4, two, fnan = (a.reshape(a.shape[:2] + (a.shape[2] if a.ndim > 2 else 1, 1), order='F') for a in (P, two, fnan))

# near-lossless: una codestream JPEG-LS con NEAR = 3
import imagecodecs
NEAR = imagecodecs.jpegls_encode(np.ascontiguousarray(P.T), level=3)
crc = zlib.crc32(RAW) & 0xffffffff
# el crc es del DATO DECODIFICADO (SPEC 4, 2026-10-14): en raw coincide con el de
# los bytes del fichero; en zlib NO, y es lo que distingue los dos significados
Z = zlib.compress(RAW, 9)
crcZ = zlib.crc32(Z) & 0xffffffff                                # el de los bytes comprimidos: el MALO

# un <jpegls> de DOS planos (SPEC 4, 2026-10-14): apilados en una imagen de
# ni x (nj*2); en orden C (filas, columnas) eso es la traspuesta del bloque en
# orden columna visto como ni x (nj*2)
two_j = np.stack([P, P + 100], axis=2)                           # 4 x 3 x 2
JLS2 = imagecodecs.jpegls_encode(np.ascontiguousarray(two_j.reshape(4, 6, order='F').T))
crc2 = zlib.crc32(two_j.tobytes(order='F')) & 0xffffffff
two_j4 = two_j.reshape(4, 3, 2, 1, order='F')
JLS1 = imagecodecs.jpegls_encode(np.ascontiguousarray(P[:2].T))  # media fila i: no es un plano entero

CASES = [
  # --- validos: lo que el lector TIENE que aceptar
  ('ok basic',            text(G1 + ['data = <raw uint16 @0:23>']) + RAW,                         ('ok', P4)),
  ('ok unknown key',      text(G1 + ['futurekey = 3', 'data = <raw uint16 @0:23>']) + RAW,        ('ok', P4)),
  ('ok CRLF',             text(G1 + ['data = <raw uint16 @0:23>']).replace(b'\n', b'\r\n') + RAW, ('ok', P4)),
  ('ok crc',              text(G1 + ['data = <raw uint16 @0:23 crc %08x>' % crc]) + RAW,          ('ok', P4)),
  ('ok fill int',         text(G2 + ['fill = 7', 'data(:,:,1) = <raw uint16 @0:23>', 'data(:,:,2) = <missing>']) + RAW, ('ok', two)),
  ('ok fill NaN default', text(G2 + ['data(:,:,1) = <raw double @0:95>', 'data(:,:,2) = <missing>']) + P.astype('<f8').tobytes(order='F'), ('ok', fnan)),
  ('ok hidden',           hidden(G1 + ['data = <raw uint16 @0:23>'], RAW),                       ('ok', P4)),
  # --- la cabecera
  ('bad magic',           text(G1 + ['data = <raw uint16 @0:23>'], magic='I3D 0.2') + RAW,        ('err', 'badMagic', 'bad magic')),
  ('no terminator',       text(G1 + ['data = <raw uint16 @0:23>'], end=False),                    ('err', 'badHeader', 'no terminator')),
  ('repeated key',        text(G1 + ['X = 0.0 : 1.0 : 3.0', 'data = <raw uint16 @0:23>']) + RAW,  ('err', 'badHeader', 'repeated key')),
  ('( ) outside data',    text(G1 + ['thumbnail(1:2) = <raw uint8 {2 1} @24:25>', 'data = <raw uint16 @0:23>']) + RAW + b'\0\0', ('err', 'badHeader', 'only data takes')),
  ('fill out of range',   text(G2 + ['fill = 70000', 'data(:,:,1) = <raw uint16 @0:23>', 'data(:,:,2) = <missing>']) + RAW, ('err', 'badHeader', 'does not fit')),
  ('hidden: stream cut',  hidden(G1 + ['data = <raw uint16 @0:23>'], RAW, trim=1),               ('err', 'badHeader', 'does not inflate')),
  ('hidden: extra byte',  hidden(G1 + ['data = <raw uint16 @0:23>'], RAW, extra=b'\x00'),        ('err', 'badHeader', 'after its zlib stream')),
  # --- las rejillas
  ('range not closing',   text(['X = 0.0 : 0.3 : 1.0'] + G1[1:] + ['data = <raw uint16 @0:23>']) + RAW, ('err', 'badGrid', 'does not end exactly')),
  ('grid not increasing', text(['X = 0.0 2.0 1.0 3.0'] + G1[1:] + ['data = <raw uint16 @0:23>']) + RAW, ('err', 'badGrid', 'not strictly increasing')),
  # --- la cobertura
  ('overlap',             text(G1 + ['data = <raw uint16 @0:23>', 'data(:,:,1) = <missing>']) + RAW, ('err', 'coverage', 'coverage')),
  ('gap',                 text(G2 + ['data(:,:,1) = <raw uint16 @0:23>']) + RAW,                  ('err', 'coverage', 'coverage')),
  # --- los descriptores y los bloques
  ('unknown option',      text(G1 + ['data = <raw uint16 @0:23 future 1>']) + RAW,                ('err', 'badDescriptor', 'unknown descriptor token')),
  # 'order' ya no existe (2026-10-13): un bloque es siempre i j k t c
  ('order option',        text(G1 + ['data = <raw uint16 @0:23 order j i k t c>']) + RAW,         ('err', 'badDescriptor', 'unknown descriptor token')),
  # ni rescale (2026-11-03: el formato no tiene rescale ni window)
  ('rescale option',      text(G1 + ['data = <raw uint16 @0:23 rescale 2.0 -1000.0>']) + RAW,     ('err', 'badDescriptor', 'unknown descriptor token')),
  # la cabecera es UTF-8 (2026-10-13): con tildes vale; en Latin-1 no
  ('ok UTF-8 header',     text(G1 + ['info.PatientName = "Muñoz^José"', 'data = <raw uint16 @0:23>']) + RAW, ('ok', P4)),
  ('Latin-1 header',      text(G1 + ['data = <raw uint16 @0:23>']).replace(b'I3D\n', b'I3D\ninfo.PatientName = "Mu\xf1oz"\n') + RAW, ('err', 'badHeader', 'not valid UTF-8')),
  ('raw wrong length',    text(G1 + ['data = <raw uint16 @0:21>']) + RAW,                         ('err', 'badBlock', 'raw length mismatch')),
  ('truncated',           text(G1 + ['data = <raw uint16 @0:23>']) + RAW[:20],                   ('err', 'truncated', 'ends inside the block')),
  # NADA se reserva por lo que diga el fichero sin compararlo antes con lo que
  # el fichero tiene (2026-10-23): un bloque de 1.5 GB en 100 bytes, una cabecera
  # I3Db de 2^29, un zlib que no puede inflar a tanto, una rejilla de 10^8
  ('block past the end',  text(G1 + ['data = <zlib uint16 @0:1500000000>']) + RAW,                ('err', 'truncated', 'ends inside the block')),
  ('hidden L past the end', b'I3Db' + struct.pack('<Q', 2 ** 29) + b'\0' * 8,                     ('err', 'truncated', 'ends inside the hidden header')),
  ('zlib over 1032:1',    text(['X = 0.0 : 1.0 : 3999.0', 'Y = 0.0 : 1.0 : 3999.0', 'Z = 0.0', 'T = 0.0', 'data = <zlib uint16 @0:%d>' % (len(Z) - 1)]) + Z, ('err', 'badBlock', 'bytes, expected')),
  ('grid over 2^24',      text(['X = 0.0 : 1e-8 : 1.0'] + G1[1:] + ['data = <missing>']),          ('err', 'badGrid', 'at most 2^24')),
  # ( ) en una clave DESCONOCIDA se ignora (2026-10-23): un v0 abre un fichero
  # con arrays futuros asignados por bloques; en una conocida sigue siendo error
  ('ok unknown key ( )',  text(G1 + ['labels(:,:,:,1) = <raw uint8 @24:35>', 'data = <raw uint16 @0:23>']) + RAW + b'\0' * 12, ('ok', P4)),
  ('( ) on info.*',       text(G1 + ['info.x(1) = 1.0', 'data = <raw uint16 @0:23>']) + RAW,     ('err', 'badHeader', 'only data takes')),
  # --- donde los dos lectores DIVERGIAN (sonda del 2026-10-23): uno aceptaba, el
  # otro no. Ahora los dos dicen lo mismo, y lo que dice la SPEC
  ('magic after a space', text(G1 + ['data = <raw uint16 @0:23>'], magic=' I3D') + RAW,           ('err', 'badMagic', 'bad magic')),
  # sin version (2026-11-03): 'I3D 0.1' o 'I3D 2' es badMagic, 'I3D  # ...' vale
  ('magic with version',  text(G1 + ['data = <raw uint16 @0:23>'], magic='I3D 0.1') + RAW,        ('err', 'badMagic', 'bad magic')),
  ('magic I3D#x',         text(G1 + ['data = <raw uint16 @0:23>'], magic='I3D#x') + RAW,          ('err', 'badMagic', 'bad magic')),
  ('ok magic + comment',  text(G1 + ['data = <raw uint16 @0:23>'], magic='I3D  # c') + RAW,       ('ok', P4)),
  ('subscript 1:-1',      text(G1 + ['data(:,:,:,1:-1) = <raw uint16 @0:23>']) + RAW,             ('err', 'badSubscript', 'positive integer')),
  ('data() empty',        text(G1 + ['data() = <raw uint16 @0:23>']) + RAW,                       ('err', 'badSubscript', 'empty subscript')),
  ('data(..,) stray ,',   text(G1 + ['data(:,:,1,) = <raw uint16 @0:23>']) + RAW,                 ('err', 'badSubscript', 'empty subscript')),
  ('frames 0:0',          text(G1 + ['data = <dicom uint16 "x.dcm" frames 0:0>']),                ('err', 'badDescriptor', '1 <= a <= b')),
  ('frames on raw',       text(G1 + ['data = <raw uint16 @0:23 frames 1:1>']) + RAW,              ('err', 'badDescriptor', 'for <dicom> only')),
  ('<png> as data',       text(G1 + ['data = <png uint8 {4 3} @0:9>']) + b'\0' * 10,              ('err', 'badDescriptor', 'thumbnail only')),
  ('UTF-8 surrogate',     text(G1 + ['data = <raw uint16 @0:23>']).replace(b'---', b'info.s = "\xed\xa0\x80"\n---') + RAW, ('err', 'badHeader', 'not valid UTF-8')),
  ('UTF-8 overlong',      text(G1 + ['data = <raw uint16 @0:23>']).replace(b'---', b'info.s = "\xe0\x80\xaf"\n---') + RAW, ('err', 'badHeader', 'not valid UTF-8')),
  ('grid X = nan',        text(['X = nan', 'Y = 0.0 : 1.0 : 2.0', 'Z = 0.0', 'T = 0.0', 'data = <raw uint16 @0:5>']) + RAW[:6], ('err', 'badGrid', 'not finite')),
  ('257 copies of a block', text(G1 + ['data = <raw uint16 @0:23>'] * 257) + RAW,                 ('err', 'coverage', 'overlap')),
  ('info.* repeated',     text(G1 + ['info.A = 1.0', 'info.A = 2.0', 'data = <raw uint16 @0:23>']) + RAW, ('err', 'badHeader', 'repeated key')),
  ('two types',           text(G1 + ['data = <raw uint16 int16 @0:23>']) + RAW,                   ('err', 'badDescriptor', 'two types')),
  # rescale y window ya no existen (2026-11-03): son claves desconocidas, se ignoran
  ('ok rescale ignored',  text(G1 + ['rescale = "abc"', 'window = 1.0 2.0 3.0', 'data = <raw uint16 @0:23>']) + RAW, ('ok', P4)),
  ('thumbnail raw wrong length', text(G1 + ['data = <raw uint16 @0:23>', 'thumbnail = <raw uint8 {2 1} @0:9>']) + RAW, ('err', 'badBlock', '<raw> has', 'thumbnail')),
  ('thumbnail not uint8',  text(G1 + ['data = <raw uint16 @0:23>', 'thumbnail = <raw uint16 {2 1} @0:3>']) + RAW, ('err', 'badDescriptor', 'uint8', 'thumbnail')),
  ('ok aux. is unknown',   text(G1 + ['data = <raw uint16 @0:23>', 'aux.thumbnail = <raw uint8 {2 1} @0:1>']) + RAW, ('ok', P4)),
  # --- la PARTE OCULTA de la cabecera (SPEC 1.2, 2026-10-23): 'header = <hidden @a:b>'
  ('ok <hidden> part',    text(G2v + [hline()]) + RAW + HP,                                       ('ok', P4)),
  ('ok <hidden> first',   hidden_first(),                                                         ('ok', P4)),
  ('ok <hidden> with crc', text(G2v + [hline(more=' crc %08x' % HPc)]) + RAW + HP,               ('ok', P4)),
  ('ok <hidden> in I3Db', hidden(G2v + [hline()], RAW + HP),                                      ('ok', P4)),
  ('<hidden> bad crc',    text(G2v + [hline(more=' crc %08x' % (HPc ^ 1))]) + RAW + HP,          ('err', 'badCRC', 'fails its crc')),
  ('two header entries',  text(G2v + [hline(), hline()]) + RAW + HP,                              ('err', 'badHeader', 'repeated key')),
  ('header in <hidden>',  text(G2v + [hline(len(hidepart(['header = <hidden @0:1>'])))]) + RAW + hidepart(['header = <hidden @0:1>']), ('err', 'badHeader', 'cannot hold another')),
  ('header( )',           text(G1 + ['header(1) = <hidden @0:1>', 'data = <raw uint16 @0:23>']) + RAW, ('err', 'badHeader', 'only data takes')),
  ('header not <hidden>', text(G2v + ['header = <zlib @24:30>']) + RAW + HP,                      ('err', 'badDescriptor', 'takes a <hidden')),
  ('<hidden> with a type', text(G2v + [hline(more=' uint8')]) + RAW + HP,                         ('err', 'badDescriptor', 'nothing else')),
  ('<hidden> past the end', text(G2v + [hline(n=len(HP) + 100)]) + RAW + HP,                      ('err', 'truncated', 'ends inside the <hidden> part')),
  ('<hidden> extra byte', text(G2v + [hline(n=len(HP) + 1)]) + RAW + hidepart(['Z = 0.0', 'T = 0.0', 'data = <raw uint16 @0:23>'], b'\0'), ('err', 'badHeader', 'after its zlib stream')),
  ('<hidden> as data',    text(G1 + ['data = <hidden @0:23>']) + RAW,                             ('err', 'badDescriptor', 'for the key header only')),
  # cada ocultacion con SUS constantes (2026-10-24): un bloque <hidden> ofuscado
  # como la cabecera I3Db no se lee
  ('<hidden> done like I3Db', text(G2v + [hline()]) + RAW + hidepart(['Z = 0.0', 'T = 0.0', 'data = <raw uint16 @0:23>'], i3db=True), ('err', 'badHeader', 'does not inflate')),
  ('I3Db of before 10-24', hidden(G1 + ['data = <raw uint16 @0:23>'], RAW, old=True),                ('err', 'badHeader', 'does not inflate')),
  ('bad crc',             text(G1 + ['data = <raw uint16 @0:23 crc %08x>' % (crc ^ 1)]) + RAW,    ('err', 'badCRC', 'badCRC')),
  ('ok crc of the data',  text(G1 + ['data = <zlib uint16 @0:%d crc %08x>' % (len(Z) - 1, crc)]) + Z,  ('ok', P4)),
  ('crc of the file bytes', text(G1 + ['data = <zlib uint16 @0:%d crc %08x>' % (len(Z) - 1, crcZ)]) + Z, ('err', 'badCRC', 'badCRC')),
  ('crc on <missing>',    text(G2 + ['data(:,:,1) = <raw uint16 @0:23>', 'data(:,:,2) = <missing crc %08x>' % crc]) + RAW, ('err', 'badDescriptor', 'takes no crc')),
  ('undefined variable',  text(G1 + ['data = <dicom uint16 "$NOPE$/x.dcm">']),                    ('err', 'badVariable', 'undefined variable')),
  ('jpegls near-lossless', text(G1 + ['data = <jpegls uint16 @0:%d>' % (len(NEAR) - 1)]) + NEAR,  ('err', 'badBlock', 'near-lossless')),
  # varios planos por <jpegls> (2026-10-14): planos i,j ENTEROS, y la imagen
  # como mucho 65535 x 65535 (el CharLS del navegador y el de imagecodecs no leen
  # la extension de dimensiones grandes)
  ('ok jpegls 2 planes',  text(G2 + ['data(:,:,1:2) = <jpegls uint16 @0:%d crc %08x>' % (len(JLS2) - 1, crc2)]) + JLS2, ('ok', two_j4)),
  ('jpegls not whole planes', text(G1 + ['data(1:2,:,1) = <jpegls uint16 @0:%d>' % (len(JLS1) - 1), 'data(3:4,:,1) = <raw uint16 @%d:%d>' % (len(JLS1), len(JLS1) + 11)]) + JLS1 + RAW[:12], ('err', 'badData', 'whole i,j planes')),
  ('jpegls over 65535 rows', text(['X = 0.0', 'Y = 0.0 : 1.0 : 65535.0', 'Z = 0.0', 'T = 0.0', 'data = <jpegls uint8 @0:3>']) + b'\0' * 4, ('err', 'badData', 'at most 65535')),
]

def run(path, want):
    res = {}
    for who in ('cpp', 'py'):
        try:
            a = i3d_ctypes.I3DFile(path).data() if who == 'cpp' else read_i3d(path)['data']
            # un caso del thumbnail: la DLL lo lee solo si se le pide (Python, siempre)
            if who == 'cpp' and len(want) > 3: i3d_ctypes.I3DFile(path).thumbnail()
            got = ('ok', a)
        except i3d_ctypes.I3DCError as e: got = ('err', e.ident, str(e))
        except Exception as e:            got = ('err', '', f'{type(e).__name__}: {e}')
        if want[0] == 'ok':
            exp = np.asarray(want[1])
            good = got[0] == 'ok' and got[1].dtype == exp.dtype and got[1].shape == exp.shape and got[1].tobytes(order='F') == exp.tobytes(order='F')
            res[who] = 'ok' if good else 'FAIL(' + (got[2][:90] if got[0] == 'err' else 'different data') + ')'
        else:
            if got[0] == 'ok': res[who] = 'FAIL(accepted)'
            elif who == 'cpp': res[who] = 'ok' if got[1] == want[1] else f'FAIL([{got[1]}] {got[2][:80]})'
            else:              res[who] = 'ok' if want[2] in got[2] else f'FAIL({got[2][:90]})'
    return res

d = tempfile.mkdtemp(prefix='i3d_invalid_')
nbad = 0
try:
    for k, (name, content, want) in enumerate(CASES):
        p = os.path.join(d, 'c%02d.i3d' % k)
        open(p, 'wb').write(content)
        r = run(p, want)
        bad = any(v.startswith('FAIL') for v in r.values())
        nbad += bad
        print(f'  {"FAIL" if bad else "ok  "} {name:22s} cpp: {r["cpp"]:30s} py: {r["py"]}')
    # el VOLCADO (SPEC 1.2): i3d_header -- lo que muestran i3dinfo --header e
    # showI3Dfile -- no despliega la parte <hidden>, tampoco de un I3Db; las
    # entradas (i3d_entry), si: el lector las necesita
    L0 = i3d_ctypes._lib()
    L0.i3d_header.restype = i3d_ctypes.C.c_char_p;  L0.i3d_header.argtypes = [i3d_ctypes.C.c_void_p]
    L0.i3d_entry_count.argtypes = [i3d_ctypes.C.c_void_p]
    L0.i3d_entry.argtypes = [i3d_ctypes.C.c_void_p, i3d_ctypes.C.c_int] + [i3d_ctypes.C.POINTER(i3d_ctypes.C.c_char_p)] * 3
    for name, content in (('dump of a <hidden> part', text(G2v + [hline()]) + RAW + HP), ('dump of I3Db + <hidden>', hidden(G2v + [hline()], RAW + HP))):
        p = os.path.join(d, 'dump.i3d'); open(p, 'wb').write(content)
        h = L0.i3d_open(p.encode()); head = L0.i3d_header(h).decode()
        keys = []
        for e in range(L0.i3d_entry_count(h)):
            k, s, v = (i3d_ctypes.C.c_char_p(), i3d_ctypes.C.c_char_p(), i3d_ctypes.C.c_char_p())
            L0.i3d_entry(h, e, i3d_ctypes.C.byref(k), i3d_ctypes.C.byref(s), i3d_ctypes.C.byref(v)); keys.append(k.value.decode())
        L0.i3d_close(h)
        bad = 'data' in head or 'Z =' in head or 'header = <hidden' not in head or keys != ['X', 'Y', 'header', 'Z', 'T', 'data']
        nbad += bad
        print(f'  {"FAIL" if bad else "ok  "} {name:22s} cpp: {"ok" if not bad else "FAIL(" + repr(keys) + ")"}')
    # la frontera C: un NULL es un error con su identificador, no un access
    # violation que tumba el proceso del wrapper (2026-10-23)
    L = i3d_ctypes._lib()
    names = (i3d_ctypes.C.c_char_p * 1)(None); values = (i3d_ctypes.C.c_char_p * 1)(b'x')
    for name, call in (('C API: i3d_open(NULL)', lambda: L.i3d_open(None)),
                       ('C API: NULL var name', lambda: L.i3d_open_vars(p.encode(), 1, names, values))):
        h = call(); ident = L.i3d_last_error_id(None).decode()
        bad = h is not None or ident != 'badInput'
        nbad += bad
        print(f'  {"FAIL" if bad else "ok  "} {name:22s} cpp: {"ok" if not bad else f"FAIL(handle {h}, [{ident}])"}')
finally:
    shutil.rmtree(d, ignore_errors=True)
print(f'{len(CASES) + 4} cases, {nbad} failed')
sys.exit(1 if nbad else 0)
