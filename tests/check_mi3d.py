# El contenedor .mi3d (SPEC 14), leido por los DOS lectores: la DLL de C++ (por
# ctypes) y el de referencia en Python. Contenedores hechos a mano con ficheros
# de out_roundtrip como miembros (en texto, con parte <hidden>, I3Db), buenos y
# malos.
#
#   python check_mi3d.py
#
# Un miembro bueno se compara con su .i3d ORIGINAL leido por el mismo lector:
# data, rejillas, entradas y cabecera. Un caso malo dice el identificador que
# tiene que dar la DLL y una frase del mensaje de Python.
# Todo en un directorio temporal que se borra al terminar.
import sys, os, re, zlib, tempfile, shutil
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import i3d_ctypes
from read_i3d import read_i3d, read_mi3d, _unhide, SEED_HIDDEN, MULT_HIDDEN

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'out_roundtrip')
# un .i3d en texto, uno con parte <hidden> y uno I3Db
FILES = ['int16_rot_canon.i3d', 'double_tensor_hidden.i3d', 'single_rgb_chunked.i3d', 'int16_rot_hidden.i3d']
RAW = {f: open(os.path.join(SRC, f), 'rb').read() for f in FILES}
assert RAW['int16_rot_hidden.i3d'][:4] == b'I3Db'

def hidepart(lines):
    # SPEC 1.2: zlib, el flujo AL REVES, XOR con las constantes de <hidden>
    z = zlib.compress(('\n'.join(lines) + '\n').encode('utf-8'), 9)
    return _unhide(z[::-1], SEED_HIDDEN, MULT_HIDDEN)

def mi3d(members, lines=(), hidden=None, sep=True, fill=b'', magic='MI3D', order=None, form='ab', crc=None, cut=0):
    # members: [(n, bytes)] (bytes None: 'i3d(n) = <missing>'); lines: mas lineas
    # de cabecera; hidden: lineas de la parte <hidden>, su bloque el ULTIMO (SPEC
    # 14.3); sep: los separadores del escritor amable; fill: bytes entre miembros
    # (el lector no los mira); order: el orden de las lineas i3d; form: 'ab',
    # 'plus' (@a+n) o 'eof' (el ultimo @a:EOF); crc: {n: crc}; cut: bytes de menos
    # en la longitud declarada del miembro 1
    B, L = b'', {}
    for n, b in members:
        if b is None: L[n] = 'i3d(%d) = <missing>' % n; continue
        if sep: B += b'****** # member %d\n' % n
        B += fill
        a = len(B); B += b; B += b'\n++++++\n' if sep else fill
        ln = len(b) - (cut if n == members[0][0] else 0)
        d = '@%d:%d' % (a, a + ln - 1) if form == 'ab' else '@%d+%d' % (a, ln)
        if form == 'eof' and n == members[-1][0] and not sep and not fill: d = '@%d:EOF' % a
        if crc and n in crc: d += ' crc %08x' % crc[n]
        L[n] = 'i3d(%d) = <i3d %s>' % (n, d)
    keys = order or list(L)
    H = [L[k] for k in keys] + list(lines)
    if hidden is not None:
        # '{n}' en hidden: la linea i3d(n), que va DENTRO de la parte oculta
        hp = hidepart([L[int(h[1:-1])] if h.startswith('{') else h for h in hidden])
        H.append('header = <hidden @%d:%d>' % (len(B), len(B) + len(hp) - 1))
        B += hp
    return ('\n'.join([magic] + H) + '\n---\n').encode('utf-8') + B

def agree(dn):
    # python check_mi3d.py DIR: cada .mi3d de DIR (los de tests/check_mi3d.m),
    # por la DLL y por Python, miembro a miembro, iguales entre si
    bad = 0
    for f in sorted(os.listdir(dn)):
        if not f.endswith('.mi3d'): continue
        p = os.path.join(dn, f)
        try:
            M, C = i3d_ctypes.MI3DFile(p), read_mi3d(p)
            assert M.count() == C['N'], 'N'
            assert [e[0] for e in M.entries()] == [e[0] for e in C['entries']], 'entries'
            for n in range(1, C['N'] + 1):
                if n not in C['members']:
                    assert M.present(n) == 0 and read_mi3d(p, n) is None, 'hole %d' % n
                    continue
                assert M.range(n) == C['members'][n][:2], 'range %d' % n
                I, J = read_mi3d(p, n), M.member(n)
                assert I['data'].dtype == J.dtype() and np.array_equal(I['data'], J.data(), equal_nan=True), 'data %d' % n
                for g in 'XYZT': assert np.array_equal(I[g], J.grid(g)), '%s %d' % (g, n)
                assert [e[0] for e in I['entries']] == [e[0] for e in J.entries()], 'entries %d' % n
            print('  ok   %s: %d members' % (f, C['N']))
        except Exception as e:
            print('  FAIL %s: %s' % (f, e)); bad += 1
    print('%d failed' % bad)
    return bad

if len(sys.argv) > 1: sys.exit(1 if agree(sys.argv[1]) else 0)

TMP = tempfile.mkdtemp(prefix='mi3d_')
fails = []

def put(name, b):
    p = os.path.join(TMP, re.sub(r'[^A-Za-z0-9_.]', '_', name)); open(p, 'wb').write(b); return p

def same(I, J, what):
    # dos lecturas iguales (las de Python: dicts; las de la DLL: I3DFile)
    if isinstance(I, dict):
        assert I['data'].dtype == J['data'].dtype and np.array_equal(I['data'], J['data'], equal_nan=True), what + ': data'
        for g in 'XYZT': assert np.array_equal(I[g], J[g]), what + ': ' + g
        assert I['entries'] == J['entries'], what + ': entries'
    else:
        assert np.array_equal(I.data(), J.data(), equal_nan=True), what + ': data'
        for g in 'XYZT': assert np.array_equal(I.grid(g), J.grid(g)), what + ': ' + g
        assert I.entries() == J.entries(), what + ': entries'
        assert I.header() == J.header(), what + ': header'

def check_members(p, want):
    # want: {n: fichero de out_roundtrip | None (hueco)}; N = max(want)
    N = max(want, default=0)
    M = i3d_ctypes.MI3DFile(p)
    assert M.count() == N, 'cpp: N = %d, not %d' % (M.count(), N)
    C = read_mi3d(p)
    assert C['N'] == N, 'py: N = %d, not %d' % (C['N'], N)
    for n in range(1, N + 1):
        f = want.get(n)
        assert M.present(n) == (f is not None), 'cpp: present(%d)' % n
        if f is None:
            assert read_mi3d(p, n) is None, 'py: a hole is None'
            try: M.member(n); raise AssertionError('cpp: a hole opened')
            except i3d_ctypes.I3DCError as e: assert e.ident == 'missingMember', 'cpp: a hole gives ' + e.ident
            continue
        # el miembro, byte a byte el original
        a, L = M.range(n)
        assert open(p, 'rb').read()[a:a + L] == RAW[f], 'member %d is not byte for byte %s' % (n, f)
        assert C['members'][n][:2] == (a, L), 'py and cpp disagree on the range of %d' % n
        same(read_mi3d(p, n), read_i3d(os.path.join(SRC, f)), 'py member %d' % n)
        same(M.member(n), i3d_ctypes.I3DFile(os.path.join(SRC, f)), 'cpp member %d' % n)
    for n in (0, N + 1):
        assert M.present(n) == -1, 'cpp: present(%d) out of range' % n
        try: read_mi3d(p, n); raise AssertionError('py: member %d opened' % n)
        except Exception as e: assert 'badIndex' in str(e), 'py: %s' % e
        try: M.member(n); raise AssertionError('cpp: member %d opened' % n)
        except i3d_ctypes.I3DCError as e: assert e.ident == 'badIndex', 'cpp: %d gives %s' % (n, e.ident)
    M.close()
    return C

def ok(name, b, want, extra=None):
    try:
        p = put(name + '.mi3d', b)
        C = check_members(p, want)
        if extra: extra(p, C)
        print('  ok   ' + name)
    except Exception as e:
        print('  FAIL ' + name + ': ' + str(e)); fails.append(name)

def bad(name, b, ident, phrase, n=None):
    # n None: falla el CONTENEDOR al abrir; n: abre, y falla el miembro n
    p = put(name + '.mi3d', b)
    got = []
    try:
        M = i3d_ctypes.MI3DFile(p)
        if n is not None:
            F = M.member(n); F.data(); F.thumbnail()
        got.append('cpp: opened')
    except i3d_ctypes.I3DCError as e:
        got.append('cpp: ok' if e.ident == ident else 'cpp: ' + str(e))
    try:
        C = read_mi3d(p, n)
        if n is not None: C['data']
        got.append('py: opened')
    except Exception as e:
        got.append('py: ok' if phrase in str(e) else 'py: ' + str(e))
    good = got == ['cpp: ok', 'py: ok']
    print(('  ok   ' if good else '  FAIL ') + name + ('' if good else '  ' + '  '.join(got)))
    if not good: fails.append(name)

R = [RAW[f] for f in FILES]
W3 = {1: FILES[0], 2: FILES[1], 3: FILES[3]}

print('-- good')
ok('three', mi3d([(1, R[0]), (2, R[1]), (3, R[3])]), W3)
ok('no separators', mi3d([(1, R[0]), (2, R[1]), (3, R[3])], sep=False), W3)
ok('anything between', mi3d([(1, R[0]), (2, R[1]), (3, R[3])], fill=b'\x00\xffMI3D I3D\n---\n' * 3), W3)
ok('lines in any order', mi3d([(1, R[0]), (2, R[1]), (3, R[3])], order=[3, 1, 2]), W3)
ok('@a+n', mi3d([(1, R[0]), (2, R[1]), (3, R[3])], form='plus'), W3)
ok('@a:EOF', mi3d([(1, R[0]), (2, R[3])], sep=False, form='eof'), {1: FILES[0], 2: FILES[3]})
ok('holes', mi3d([(1, R[0]), (3, R[2]), (5, None)]), {1: FILES[0], 2: None, 3: FILES[2], 4: None, 5: None})
ok('one member, first is a hole', mi3d([(2, R[1])]), {1: None, 2: FILES[1]})
ok('crc', mi3d([(1, R[0]), (2, R[1])], crc={1: zlib.crc32(R[0]), 2: zlib.crc32(R[1])}), {1: FILES[0], 2: FILES[1]})
ok('empty container', b'MI3D  # nothing yet\n---\n', {})

def summary(p, C):
    # la parte <hidden> se lee en su sitio; el resumen es solo entradas
    keys = [e[0] for e in C['entries']]
    assert keys == ['i3d', 'i3d', 'info.StudyDate', 'header', 'i3d', 'info.PatientName'], keys
    Mk = [e[0] for e in i3d_ctypes.MI3DFile(p).entries()]
    assert Mk == keys, 'cpp entries %s' % Mk
    # el volcado no muestra la parte oculta
    assert 'PatientName' not in i3d_ctypes.MI3DFile(p).header() and 'PatientName' not in C['header']
ok('hidden part, with a member in it', mi3d([(1, R[0]), (2, R[1]), (3, R[3])], order=[1, 2],
   lines=['', '# -- common to every stack', 'info.StudyDate = "20250308"'],
   hidden=['{3}', 'info.PatientName = "A^B"']), W3, summary)

def crlf():
    b = mi3d([(1, R[0]), (2, R[1])])
    h, rest = b.split(b'\n---\n', 1)
    return h.replace(b'\n', b'\r\n') + b'\r\n---\r\n' + rest
ok('CRLF header', crlf(), {1: FILES[0], 2: FILES[1]})

print('-- bad container')
G = [(1, R[0]), (2, R[1])]
bad('magic MI3D 0.1', mi3d(G, magic='MI3D 0.1'), 'badMagic', 'badMagic')
bad('a space before MI3D', b' ' + mi3d(G), 'badMagic', 'badMagic')
bad('an .i3d opened as .mi3d', R[0], 'badMagic', 'badMagic')
bad('an I3Db opened as .mi3d', R[3], 'badMagic', 'badMagic')
bad('no terminator', b'MI3D\ni3d(1) = <missing>\n--\n', 'badHeader', 'terminator')
for sub in ['', '()', '(0)', '(1:2)', '(end)', '(+1)', '(1,1)', '( )', '(1234567890)']:
    b = mi3d(G).replace(b'i3d(1)', b'i3d' + sub.encode(), 1)
    bad('i3d%s' % (sub or ' without ( )'), b, 'badSubscript', 'badSubscript')
bad('repeated i3d(1)', mi3d(G).replace(b'i3d(2)', b'i3d(1)', 1), 'badHeader', 'repeated')
bad('i3d(1) and a <missing> 1', mi3d(G, lines=['i3d(1) = <missing>']), 'badHeader', 'repeated')
bad('<zlib> as a member', mi3d(G).replace(b'<i3d @', b'<zlib @', 1), 'badDescriptor', 'badDescriptor')
bad('a type', mi3d(G).replace(b'<i3d @', b'<i3d uint8 @', 1), 'badDescriptor', 'badDescriptor')
bad('a path', mi3d(G).replace(b'<i3d @', b'<i3d "x.i3d" @', 1), 'badDescriptor', 'badDescriptor')
bad('no length', mi3d([(1, R[0])], lines=['i3d(2) = <i3d @0>']), 'badDescriptor', 'badDescriptor')
bad('no offset', mi3d([(1, R[0])], lines=['i3d(2) = <i3d>']), 'badDescriptor', 'badDescriptor')
bad('<missing @0:3>', mi3d([(1, R[0])], lines=['i3d(2) = <missing @0:3>']), 'badDescriptor', 'badDescriptor')
bad('<missing crc>', mi3d([(1, R[0])], lines=['i3d(2) = <missing crc 00000000>']), 'badDescriptor', 'badDescriptor')
bad('past the end', mi3d([(1, R[0])], lines=['i3d(2) = <i3d @0:99999999>']), 'truncated', 'truncated')
bad('repeated info key', mi3d(G, lines=['info.a = 1', 'info.a = 2']), 'badHeader', 'repeated')
bad('info.a(1)', mi3d(G, lines=['info.a(1) = 1']), 'badHeader', 'only data')
bad('two header', mi3d(G, lines=['header = <hidden @0:3>'], hidden=['info.a = 1']), 'badHeader', 'repeated')

print('-- bad member')
bad('member is a .mi3d', mi3d([(1, R[0]), (2, mi3d([(1, R[0])]))]), 'badBlock', 'one level', n=2)
bad('member is garbage', mi3d([(1, R[0]), (2, b'hello\n---\n')]), 'badMagic', 'badMagic', n=2)
bad('member window cuts the header', mi3d([(1, R[0][:R[0].index(b'\n---\n') + 2])]), 'badHeader', 'terminator', n=1)
bad('member window cuts the binary', mi3d([(1, R[0])], cut=7), 'truncated', 'truncated', n=1)
bad('I3Db member cut', mi3d([(1, R[3])], cut=len(R[3]) - 20), 'truncated', 'truncated', n=1)
bad('bad crc', mi3d(G, crc={2: zlib.crc32(R[1]) ^ 1}), 'badCRC', 'badCRC', n=2)

def mi3d_as_i3d():
    p = put('as_i3d.mi3d', mi3d(G)); got = []
    try: i3d_ctypes.I3DFile(p); got.append('cpp: opened')
    except i3d_ctypes.I3DCError as e: got.append('cpp: ok' if e.ident == 'badMagic' else 'cpp: ' + str(e))
    try: read_i3d(p); got.append('py: opened')
    except Exception as e: got.append('py: ok' if 'badMagic' in str(e) else 'py: ' + str(e))
    good = got == ['cpp: ok', 'py: ok']
    print(('  ok   ' if good else '  FAIL ') + 'a .mi3d opened as .i3d' + ('' if good else '  ' + '  '.join(got)))
    if not good: fails.append('mi3d as i3d')
mi3d_as_i3d()

# un miembro Lazy: su ruta relativa es del directorio del CONTENEDOR (SPEC 14.2)
def lazy():
    import pydicom
    from pydicom.dataset import Dataset, FileMetaDataset
    from pydicom.uid import ExplicitVRLittleEndian, generate_uid
    ni, nj = 6, 5
    v = (np.arange(ni * nj, dtype='<u2') * 7).reshape(nj, ni)
    meta = FileMetaDataset(); meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.4'
    meta.MediaStorageSOPInstanceUID = generate_uid(); meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = Dataset(); ds.file_meta = meta; ds.SOPClassUID = meta.MediaStorageSOPClassUID
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID; ds.Modality = 'MR'; ds.Rows = nj; ds.Columns = ni
    ds.SamplesPerPixel = 1; ds.PhotometricInterpretation = 'MONOCHROME2'
    ds.BitsAllocated = 16; ds.BitsStored = 16; ds.HighBit = 15; ds.PixelRepresentation = 0
    ds.PixelData = v.tobytes()
    os.makedirs(os.path.join(TMP, 'dcm'), exist_ok=True)
    ds.save_as(os.path.join(TMP, 'dcm', 'a.dcm'), enforce_file_format=True)
    m = ('I3D\nX = 0.0 : 1.0 : 5.0\nY = 0.0 : 1.0 : 4.0\nZ = 0.0\nT = 0.0\n'
         'data = <dicom uint16 "dcm/a.dcm">\n---\n').encode()
    p = put('lazy.mi3d', mi3d([(1, R[0]), (2, m)]))
    want = v.T.reshape(ni, nj, 1, 1)
    got = []
    try: got.append(np.array_equal(i3d_ctypes.MI3DFile(p).member(2).data(), want))
    except Exception as e: got.append('cpp: %s' % e)
    try: got.append(np.array_equal(read_mi3d(p, 2)['data'], want))
    except Exception as e: got.append('py: %s' % e)
    good = got == [True, True]
    print(('  ok   ' if good else '  FAIL ') + 'Lazy member, path relative to the container' + ('' if good else '  %s' % got))
    if not good: fails.append('lazy')
lazy()

shutil.rmtree(TMP, ignore_errors=True)
print('%d failed' % len(fails))
sys.exit(1 if fails else 0)
