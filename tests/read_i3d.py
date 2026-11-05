# Lector de REFERENCIA del formato .i3d (SPEC.md), en Python + numpy.
#
# No es la libreria: es una segunda implementacion, independiente de la de
# MATLAB, para que lo que escribe write_I3D se compruebe con algo que no es
# MATLAB. Sigue la especificacion al pie de la letra y es estricta: ante
# cualquier cosa que SPEC declare invalida, lanza.
#
#   I = read_i3d('serie.i3d')
#   I['X'], I['Y'], I['Z'], I['T']   -> float64, exactos
#   I['transform']                   -> 4x4
#   I['data']                        -> ndarray (i,j,k,t[,c...]), order='F'
#   I['entries']                     -> todas las entradas, crudas
#   I['info']                        -> los info.* interpretados, por su nombre sin
#                                       'info.': numeros -> lista de float; textos ->
#                                       str (uno) o lista de str, con las $VARIABLES$
#                                       sustituidas; otra cosa -> el texto crudo
#   I['info_errors']                 -> los info.* que no se pueden leer (un $ suelto,
#                                       una variable que no existe): nombre -> motivo
#
#   C = read_mi3d('estudio.mi3d')      un contenedor (SPEC 14): C['N'], C['members']
#   I = read_mi3d('estudio.mi3d', 2)   su miembro 2, como read_i3d; None si es un hueco
import re, zlib, sys, os, struct, mmap
import numpy as np

TYPES = {'int8': '<i1', 'uint8': '<u1', 'int16': '<i2', 'uint16': '<u2',
         'int32': '<i4', 'uint32': '<u4', 'int64': '<i8', 'uint64': '<u8',
         'single': '<f4', 'double': '<f8'}

class I3DError(Exception): pass

def _is_escape(s, i):
    # los UNICOS escapes de una cadena (SPEC 2): \" y \\ ; otra '\' es literal
    return s[i] == '\\' and i + 1 < len(s) and s[i + 1] in '"\\'

def _strip_comment(line):
    out, q, i = [], False, 0
    while i < len(line):
        ch = line[i]
        if q and _is_escape(line, i):
            out.append(line[i:i + 2]); i += 2; continue
        if ch == '"': q = not q
        if ch == '#' and not q: break
        out.append(ch); i += 1
    return ''.join(out).rstrip()

def _string_tokens(body):
    # fichas de un descriptor: "cadena" (escapes resueltos) -> ('"', texto);
    # {forma} -> ('{', texto); o palabra. Las { } solo cuentan FUERA de una
    # cadena: una ruta puede llevarlas ("{6 5}/a.dcm", carpetas GUID)
    T, i = [], 0
    while i < len(body):
        if body[i] in ' \t': i += 1; continue
        if body[i] == '"':
            out, i = [], i + 1
            while i < len(body) and body[i] != '"':
                if _is_escape(body, i): i += 1
                out.append(body[i]); i += 1
            if i >= len(body): raise I3DError('unterminated string in a descriptor')
            T.append(('"', ''.join(out))); i += 1
        elif body[i] == '{':
            j = body.find('}', i)
            if j < 0: raise I3DError('badDescriptor: unterminated {shape}')
            T.append(('{', body[i + 1:j])); i = j + 1
        else:
            j = i
            while j < len(body) and body[j] not in ' \t': j += 1
            T.append(body[i:j]); i = j
    return T

# las constantes de las dos ofuscaciones (multiplicador, semilla): la de la
# cabecera I3Db (SPEC 1.1) y la de un bloque <hidden> (SPEC 1.2). Las dos con el
# mismo procedimiento: zlib, el flujo AL REVES, y el XOR con su k
MULT_I3DB, SEED_I3DB = 0x5C2D8F1B, 0x49334462          # "I3Db"
MULT_HIDDEN, SEED_HIDDEN = 0x7A3F5C29, 0x68696464      # "hidd"

def _unhide(h, seed=SEED_I3DB, mult=MULT_I3DB):
    # r(i) = NOT( hidden(i) XOR k(i) ), k(i) = ((i*mult + seed) mod 2^32 >> 8) & 0xFF
    # (es su propia inversa: sirve tambien para ocultar). La inversion del flujo
    # la hace quien llama: _split_header, _expand_hidden
    i = np.arange(len(h), dtype=np.uint64)
    k = (((i * np.uint64(mult) + np.uint64(seed)) % np.uint64(2**32)) >> np.uint64(8)) & np.uint64(0xFF)
    return (~(np.frombuffer(h, np.uint8) ^ k.astype(np.uint8))).astype(np.uint8).tobytes()

def _utf8(b):
    # SPEC 1: la cabecera es UTF-8 (las claves, ASCII); una secuencia invalida es error
    try: return b.decode('utf-8')
    except UnicodeDecodeError as e: raise I3DError('badHeader: the header is not valid UTF-8 (%s)' % e)

def _split_header(raw):
    # la variante OCULTA (SPEC 1.1): "I3Db" | L (uint64 LE) | cabecera ofuscada | binario
    if raw[:4] == b'I3Db':
        L, = struct.unpack('<Q', raw[4:12])
        if len(raw) < 12 + L: raise I3DError('truncated: the file ends inside the hidden header')
        # el flujo zlib tiene que ocupar EXACTAMENTE los L bytes
        d = zlib.decompressobj()
        # SPEC 1.1: deshacer el XOR y dar la vuelta al flujo
        try: text = d.decompress(_unhide(raw[12:12 + L])[::-1])
        except zlib.error as e: raise I3DError('badHeader: the hidden header does not inflate (%s)' % e)
        if not d.eof: raise I3DError('the hidden header does not inflate (truncated zlib stream)')
        if d.unused_data: raise I3DError('the hidden header has bytes after its zlib stream')
        return _utf8(text).replace('\r\n', '\n'), 12 + L
    # la cabecera acaba en la PRIMERA linea que es exactamente '---' (CR opcional)
    pos = 0
    while True:
        nl = raw.find(b'\n', pos)
        if nl < 0: raise I3DError('no terminator line ---')
        line = raw[pos:nl].rstrip(b'\r')
        if line == b'---':
            return _utf8(raw[:pos]), nl + 1
        pos = nl + 1

# key [anotacion, que se SALTA] (subindices) = valor ;  o  $VARIABLE$ = "valor"
ENTRY = re.compile(r'^([A-Za-z0-9_.]+|\$[A-Za-z0-9_]+\$)(?:\[[^\]]*\])?(\([^)]*\))?\s*=\s*(.*)$')

def _known(k):
    # las claves que v0 interpreta (SPEC 2-7); el resto son desconocidas
    return k in ('X', 'Y', 'Z', 'T', 'transform', 'fill', 'data', 'header', 'thumbnail') or \
           k.startswith(('$', 'info.'))

def _entries(text, magic='I3D'):
    # magic: la primera linea de la cabecera, 'I3D' (o 'MI3D', SPEC 14);
    # None, el texto de una parte <hidden> (SPEC 1.2), que no la lleva
    lines = text.split('\n')
    if magic:
        # ES 'I3D', sin nada delante ni version (SPEC 1), y puede seguir un
        # comentario: 'I3D  # ...'. 'I3D 0.1', 'I3D 2'... son badMagic
        l0 = lines[0].rstrip('\r')
        rest = l0[len(magic):]
        if not l0.startswith(magic) or (rest and not rest[0].isspace()) or _strip_comment(rest).strip(): raise I3DError('badMagic: bad magic: %r' % lines[0])
        lines = lines[1:]
    E = []
    for ln in lines:
        ln = ln.rstrip('\r')
        s = _strip_comment(ln)
        if not s.strip(): continue
        if ln[0] in ' \t':
            if not E: raise I3DError('continuation without entry')
            E[-1][2] += ' ' + s.strip()
            continue
        m = ENTRY.match(s)
        if not m: raise I3DError('bad line: %r' % ln)
        # ( ) (SPEC 2): en una clave conocida que no es data, error; en una
        # DESCONOCIDA se ignora, como toda clave desconocida
        if m.group(2) is not None and m.group(1) != 'data' and _known(m.group(1)):
            raise I3DError('badHeader: only data takes a ( ) subscript, not %r' % m.group(1))
        E.append([m.group(1), m.group(2), m.group(3).strip()])
    return E

def _expand_hidden(E, raw, b0):
    # SPEC 1.2: 'header = <hidden @a:b>', una PARTE de la cabecera oculta como
    # I3Db (zlib, NOT, XOR k(i)) en la seccion binaria. Sus lineas cuentan como
    # escritas en el sitio de esa entrada; un solo nivel
    at = [q for q, e in enumerate(E) if e[0] == 'header']
    if not at: return E
    if len(at) > 1: raise I3DError('badHeader: repeated key header')
    q = at[0]
    d = _descriptor(E[q][2])
    if d['encoding'] != 'hidden': raise I3DError('badDescriptor: header takes a <hidden @a:b> descriptor')
    if set(d) - {'encoding', 'offset', 'length', 'crc'} or 'offset' not in d or d['length'] is None:
        raise I3DError('badDescriptor: <hidden> is <hidden @a:b>: where its bytes are, nothing else')
    L = d['length']
    if L == 'EOF': L = len(raw) - (b0 + d['offset'])
    if L <= 0 or b0 + d['offset'] + L > len(raw): raise I3DError('truncated: the file ends inside the <hidden> part of the header')
    z = zlib.decompressobj()
    # SPEC 1.2: deshacer el XOR con SUS constantes, y dar la vuelta al flujo
    try: text = z.decompress(_unhide(raw[b0 + d['offset']: b0 + d['offset'] + L], SEED_HIDDEN, MULT_HIDDEN)[::-1])
    except zlib.error as e: raise I3DError('badHeader: the <hidden> part of the header does not inflate (%s)' % e)
    if not z.eof: raise I3DError('badHeader: the <hidden> part of the header does not inflate')
    if z.unused_data: raise I3DError('badHeader: the <hidden> part of the header has bytes after its zlib stream')
    # el crc, opcional: de los bytes inflados tal cual
    if 'crc' in d and (zlib.crc32(text) & 0xffffffff) != d['crc']: raise I3DError('badCRC: the <hidden> part of the header fails its crc')
    H = _entries(_utf8(text).replace('\r\n', '\n'), magic=None)
    if any(e[0] == 'header' for e in H): raise I3DError("badHeader: a <hidden> part of the header cannot hold another 'header'")
    return E[:q + 1] + H + E[q + 1:]

def _subs(sub):
    if sub is None: return None
    S = [p.strip() for p in sub[1:-1].split(',')]
    # ni data() ni data(:,:,1,): un subindice vacio no es ':'
    if any(not p for p in S): raise I3DError('badSubscript: an empty subscript in data%s' % sub)
    return S

def _index(t, p):
    # un indice: cifras y nada mas, >= 1 (ni '+1', ni '-1', ni '1_0')
    if not re.fullmatch(r'[0-9]+', t) or int(t) < 1: raise I3DError('badSubscript: a subscript is a positive integer, not %r' % p)
    return int(t)

def _range_of(p, n):
    # un subindice de SPEC 2 sobre una dimension de extension n -> (lo, hi) 0-based, hi exclusivo
    if p == ':': return 0, n
    if ':' in p:
        a, b = p.split(':', 1)
        if ':' in b: raise I3DError('badSubscript: no steps in a subscript: %r' % p)
        a, b = a.strip(), b.strip()
        lo = _index(a, p) if a else 1
        hi = _index(b, p) if b else n
    else:
        lo = hi = _index(p, p)
    if not (1 <= lo <= hi <= n): raise I3DError('subscript %s out of 1..%d' % (p, n))
    return lo - 1, hi

def _numbers(tokens, what='a number'):
    try: return [float(t) for t in tokens]
    except ValueError: raise I3DError('badNumber: bad number in %s: %r' % (what, ' '.join(tokens)))

MAX_GRID = 2 ** 24                               # valores por rejilla (SPEC 3.1)

def _grid(name, sub, val):
    tok = val.split()
    if ':' in tok:
        if len(tok) != 5 or tok[1] != ':' or tok[3] != ':': raise I3DError('bad range in ' + name)
        a, s, b = float(tok[0]), float(tok[2]), float(tok[4])
        if not s > 0: raise I3DError('range step must be > 0 in ' + name)
        nn = round((b - a) / s) + 1
        # tope (SPEC 3.1): como mucho 2^24 valores; y que cierre antes de reservar
        if not 1 <= nn <= MAX_GRID: raise I3DError('badGrid: bad range in %s (%s values; at most 2^24)' % (name, nn))
        n = int(nn)
        if a + float(n - 1) * s != b: raise I3DError('range of %s does not end exactly at b' % name)
        v = np.array([a + float(k) * s for k in range(n)])   # k*s y la suma: dos operaciones
        if v[-1] != b: raise I3DError('range of %s does not end exactly at b' % name)
    else:
        if len(tok) > MAX_GRID: raise I3DError('badGrid: %s has more than 2^24 values' % name)
        v = np.array(_numbers(tok))
    # una rejilla se asigna entera: X(...) no tiene sentido. El [n] ni se mira
    if sub is not None: raise I3DError('a grid takes no ( ) subscript: ' + name + sub)
    if v.size == 0: raise I3DError('badGrid: %s is empty' % name)
    if not np.all(np.isfinite(v)): raise I3DError('badGrid: %s is not finite' % name)
    if v.size > 1 and np.any(np.diff(v) <= 0): raise I3DError(name + ' not strictly increasing')
    return v

DESC = re.compile(r'^<(.*)>$')

def _descriptor(val):
    m = DESC.match(val)
    if not m: raise I3DError('not a descriptor: ' + val)
    # fichas: "cadena con espacios" (una ruta DICOM los lleva; escapes \" y \\
    # resueltos, el resto de '\' literales), {forma} o palabra
    tok = _string_tokens(m.group(1))
    if not tok or isinstance(tok[0], tuple): raise I3DError('badDescriptor: a descriptor starts with its encoding: ' + val)
    d = {'encoding': tok[0]}
    i = 1
    while i < len(tok):
        t = tok[i]
        if isinstance(t, tuple) and t[0] == '{':
            if 'shape' in d: raise I3DError('badDescriptor: two {shape} in a descriptor')
            try: d['shape'] = [int(x) for x in t[1].split()]
            except ValueError: raise I3DError('badDescriptor: bad {shape} in ' + val)
        elif isinstance(t, tuple):
            if 'path' in d: raise I3DError('two paths in a descriptor')
            d['path'] = t[1]
        elif t in TYPES:
            # uno solo: con dos, quedarse con el ultimo REINTERPRETABA los datos
            if 'type' in d: raise I3DError('badDescriptor: two types in ' + val)
            d['type'] = t
        elif t.startswith('@'):
            # @a | @a+n | @a+Inf | @a:b ([a,b], INCLUSIVO) | @a:EOF
            m2 = re.match(r'^@(\d+)(?:([+:])(\w+))?$', t)
            if not m2: raise I3DError('bad offset %r' % t)
            d['offset'] = int(m2.group(1)); d['length'] = None
            if m2.group(2) == '+':
                d['length'] = 'EOF' if m2.group(3) == 'Inf' else int(m2.group(3))
            elif m2.group(2) == ':':
                d['length'] = 'EOF' if m2.group(3) == 'EOF' else int(m2.group(3)) - d['offset'] + 1
                if d['length'] != 'EOF' and d['length'] < 1: raise I3DError('@a:b with b < a')
        elif t == 'crc':
            d['crc'] = int(tok[i+1], 16); i += 1
        elif t == 'frames':
            # a:b, 1-based, 1 <= a <= b: un 0 o un negativo no es "todos"
            f = tok[i+1] if i + 1 < len(tok) and isinstance(tok[i+1], str) else ''
            mf = re.fullmatch(r'([0-9]+)(?::([0-9]+))?', f)
            if not mf: raise I3DError('badDescriptor: frames is a:b, 1-based, not %r' % f)
            a = int(mf.group(1)); b = int(mf.group(2) or a)
            if not 1 <= a <= b: raise I3DError('badDescriptor: frames is a:b with 1 <= a <= b, not %r' % f)
            d['frames'] = (a, b); i += 1
        # (no hay 'order': los bytes van SIEMPRE en i j k t c -- SPEC 5.3)
        else: raise I3DError('unknown descriptor token %r' % (t,))
        i += 1
    if 'frames' in d and d['encoding'] != 'dicom': raise I3DError('badDescriptor: frames is for <dicom> only: ' + val)
    return d

def _jpegls_near(b):
    # el NEAR del primer SOS (FFDA) de una codestream JPEG-LS (ISO 14495-1 C.2.3):
    # FFDA | Ls(2) | Ns(1) | Ns x (Ci, Tmi) | NEAR(1) | ILV(1) | ...
    # Se recorren los segmentos desde SOI, cada uno con su longitud
    if b[:2] != b'\xff\xd8': raise I3DError('badBlock: <jpegls> does not start with SOI')
    p = 2
    while p + 4 <= len(b):
        if b[p] != 0xFF: raise I3DError('badBlock: <jpegls> marker expected at %d' % p)
        m = b[p + 1]
        L = (b[p + 2] << 8) | b[p + 3]
        if m == 0xDA:
            ns = b[p + 4]
            return b[p + 5 + 2 * ns]
        p += 2 + L
    raise I3DError('badBlock: <jpegls> has no SOS')

def _substitute(p, variables, what='path'):
    # $NOMBRE$ -> su valor (los del fichero, o los que se pasan al abrir, que
    # mandan), que entra TAL CUAL; $$ -> un $ literal; un $ sin pareja, error
    # (SPEC 2). En las rutas de los descriptores y en los textos de info.*
    out, i = [], 0
    while i < len(p):
        if p[i] != '$': out.append(p[i]); i += 1; continue
        if p[i + 1:i + 2] == '$': out.append('$'); i += 2; continue
        j = p.find('$', i + 1)
        if j < 0: raise I3DError('badVariable: unclosed $ in %s %r (a literal $ is $$)' % (what, p))
        name = p[i:j + 1]
        if name not in variables: raise I3DError('badVariable: undefined variable %s in %s %r' % (name, what, p))
        out.append(variables[name]); i = j + 1
    return ''.join(out)

def _info(v, variables, key):
    # un info.* (SPEC 7): SOLO cadenas -> sus textos, con las variables
    # sustituidas (str si es una, lista si son varias); SOLO numeros -> lista de
    # float; otra cosa -> el texto crudo. Como la DLL (i3d_info_*)
    v = v.strip()
    try: T = _string_tokens(v)
    except I3DError: T = None
    if T and all(isinstance(t, tuple) and t[0] == '"' for t in T):
        s = [_substitute(t[1], variables, key) for t in T]
        return s[0] if len(s) == 1 else s
    toks = v.split()
    if toks and not any('_' in t for t in toks):        # float() acepta '1_000'; la DLL, no
        try: return [float(t) for t in toks]
        except ValueError: pass
    return v

def _resolve(p, variables, i3dpath):
    # las variables, y una ruta relativa, respecto al directorio del .i3d
    p = _substitute(p, variables).replace('\\', '/')
    if not (re.match(r'^[A-Za-z]:/', p) or p.startswith('/')):
        p = os.path.join(os.path.dirname(os.path.abspath(i3dpath)), p)
    return os.path.normpath(p)

def _png_thumb(raw, b0, d, name):
    # SPEC 7: un thumbnail uint8 {r c} o {r c 1 f} es UNA imagen PNG gris de 8 bits de
    # r filas y c*f columnas, los frames uno al lado de otro; en orden columna es
    # el array {r c 1 f}. {r c 3 f}: una PNG RGB de 8 bits igual. Se decodifica con
    # imagecodecs (otra implementacion que lodepng)
    import imagecodecs
    s = d['shape']
    if d.get('type') != 'uint8' or len(s) < 2 or (len(s) > 2 and s[2] not in (1, 3)) or any(v != 1 for v in s[4:]):
        raise I3DError('badDescriptor: <png> holds uint8 {rows cols}, {rows cols 1 frames} or {rows cols 3 frames}: ' + name)
    nch = s[2] if len(s) > 2 else 1;  nf = s[3] if len(s) > 3 else 1
    L = d['length']
    if L is None: raise I3DError('png needs a length: ' + name)
    if L == 'EOF': L = len(raw) - (b0 + d['offset'])
    # dentro del fichero: un slice corto no avisa, y una PNG sin su IEND se
    # decodifica igual
    if L <= 0 or b0 + d['offset'] + L > len(raw): raise I3DError('truncated: the file ends inside ' + name)
    fb = raw[b0 + d['offset']: b0 + d['offset'] + L]
    # gris de 8 bits y nada mas: la cabecera IHDR (bit depth, colour type) a mano
    if fb[:8] != b'\x89PNG\r\n\x1a\n' or fb[12:16] != b'IHDR': raise I3DError('badBlock: not a PNG: ' + name)
    w, h = struct.unpack('>II', fb[16:24]);  bit, ct = fb[24], fb[25]
    want = 2 if nch == 3 else 0                         # colour type PNG: 0 gris, 2 RGB
    if bit != 8 or ct != want: raise I3DError('badBlock: <png> must be 8-bit %s, not colour type %d at %d bits: %s' % ('RGB' if nch == 3 else 'grey', ct, bit, name))
    img = imagecodecs.png_decode(fb)
    W = s[1] * nf
    if img.shape != ((s[0], W, 3) if nch == 3 else (s[0], W)): raise I3DError('badBlock: <png> is %s, {shape} needs %dx%d: %s' % (img.shape, s[0], W, name))
    if nch == 3:   # (r, f*c+x, ch) -> {r c 3 f}
        a = img.reshape(s[0], nf, s[1], 3).transpose(0, 2, 3, 1).reshape(s)
    else:
        a = np.reshape(img, s, order='F')
    _crc(d, a.tobytes(order='F'), name)                 # de los pixeles, en orden columna
    return a

def _crc(d, decoded, what):
    # SPEC 4 (2026-10-14): el crc es el CRC-32 de zlib de los bytes DECODIFICADOS
    # del bloque -- en su tipo, little-endian, orden columna --, no de los del
    # fichero: protege el dato, tambien el de un <dicom>
    if 'crc' in d and (zlib.crc32(decoded) & 0xffffffff) != d['crc']:
        raise I3DError('badCRC: %s decodes to data that fails its crc' % what)

def _jpegls_dicom(ds, nf):
    # pydicom 3 no trae decodificador JPEG-LS: los frames encapsulados con
    # pydicom.encaps y cada uno con imagecodecs (que por dentro tambien es
    # CharLS: el decodificador NO es independiente; los fragmentos, la mascara y
    # el signo si). Lo almacenado: los BitsStored que acaban en HighBit, y el signo
    # extendido si PixelRepresentation = 1 -- lo mismo que pixel_array
    from pydicom.encaps import generate_frames
    import imagecodecs
    F = [imagecodecs.jpegls_decode(f) for f in generate_frames(ds.PixelData, number_of_frames=nf)]
    a = np.stack(F).astype(np.int64)
    bs, hb = int(ds.BitsStored), int(ds.HighBit)
    a = (a >> (hb + 1 - bs)) & ((1 << bs) - 1)
    if int(ds.PixelRepresentation) == 1:
        a = np.where(a >= (1 << (bs - 1)), a - (1 << bs), a)
    a = a.astype('%sint%d' % ('' if int(ds.PixelRepresentation) else 'u', int(ds.BitsAllocated)))
    return a[0] if nf == 1 else a                  # como pixel_array: sin eje de frames si es uno

def _dicom_planes(fn, dt, ni, nj, nplanes, frames):
    # los pixeles ALMACENADOS de un .dcm, con pydicom (OTRA implementacion que
    # DCMTK): sin rescale. Plano = Columns x Rows, columna mas rapida (la i)
    import pydicom
    ds = pydicom.dcmread(fn)
    nf = int(getattr(ds, 'NumberOfFrames', 1) or 1)
    if str(ds.file_meta.TransferSyntaxUID) in ('1.2.840.10008.1.2.4.80', '1.2.840.10008.1.2.4.81'):
        a = _jpegls_dicom(ds, nf)
    else:
        a = ds.pixel_array
    if nf == 1: a = a[None]
    if a.shape[1:] != (nj, ni): raise I3DError('dicom %s is %s, expected %dx%d' % (fn, a.shape, nj, ni))
    f0, f1 = frames if frames else (1, nf)
    if f1 - f0 + 1 != nplanes: raise I3DError('dicom %s: %d frames for %d planes' % (fn, f1 - f0 + 1, nplanes))
    a = a[f0 - 1:f1]
    if a.dtype != dt: raise I3DError('dicom %s holds %s, the descriptor says %s' % (fn, a.dtype, dt))
    return np.ascontiguousarray(a).astype(dt.newbyteorder('<')).tobytes()

def read_i3d(path, variables=None):
    return _read(open(path, 'rb').read(), path, variables)

def _read(raw, path, variables):
    # raw: los bytes del fichero, o los de un miembro de un .mi3d (SPEC 14): sus
    # offsets son de SU binario, y su tamano es el suyo. path: de donde salen las
    # rutas relativas (la del contenedor, para un miembro)
    if raw[:4] == b'MI3D': raise I3DError('badMagic: a .mi3d container, not an .i3d: open one of its members (SPEC 14)')
    text, b0 = _split_header(raw)
    E = _expand_hidden(_entries(text), raw, b0)
    I = {'entries': E}
    # una clave sin ( ) aparece UNA vez (SPEC 2): no hay "gana la ultima"
    once = set()
    for k, sub, _ in E:
        if k == 'data' or sub is not None: continue
        if k in once: raise I3DError('badHeader: repeated key %r' % k)
        once.add(k)
    V = {}
    for k, _, v in E:
        if not k.startswith('$'): continue
        t = _string_tokens(v.strip())
        if len(t) != 1 or not (isinstance(t[0], tuple) and t[0][0] == '"'): raise I3DError('%s must be a quoted string' % k)
        V[k] = t[0][1]
    V.update({('$%s$' % k.strip('$')): v for k, v in (variables or {}).items()})
    I['info'], I['info_errors'] = {}, {}
    for k, _, v in E:
        if not k.startswith('info.'): continue
        try: I['info'][k[5:]] = _info(v, V, k)
        except I3DError as e: I['info_errors'][k[5:]] = str(e)
    for g in 'XYZT':
        e = [x for x in E if x[0] == g]
        if len(e) != 1: raise I3DError('need exactly one %s' % g)
        I[g] = _grid(g, e[0][1], e[0][2])
    # transform: ausente = identidad; 3 numeros = traslacion; 12 = las tres filas
    e = [x for x in E if x[0] == 'transform']
    A = np.eye(4)
    if e:
        v = _numbers(e[0][2].split(), 'transform')
        if len(v) == 3: A[:3, 3] = v
        elif len(v) == 12: A[:3, :] = np.array(v).reshape(3, 4)
        else: raise I3DError('transform needs 3 or 12 numbers, not %d' % len(v))
    I['transform'] = A

    ext = [I['X'].size, I['Y'].size, I['Z'].size, I['T'].size]
    blocks = []
    for name, sub, val in E:
        if name != 'data': continue
        ss = _subs(sub) or []
        d = _descriptor(val)
        # <png> y <gif> son del thumbnail (SPEC 4); <hidden>, de la clave header (SPEC 1.2)
        if d['encoding'] in ('png', 'gif'): raise I3DError('badDescriptor: <%s> is for the thumbnail only, not for a data block' % d['encoding'])
        if d['encoding'] == 'hidden': raise I3DError('badDescriptor: <hidden> is for the key header only')
        # SPEC 5.2: si falta i, j o k vale ':'; si falta t vale 1; un componente
        # que falta tambien vale 1. Asi  data = <...>  es data(:,:,:,1)
        sp = ss[:3] + [':'] * (3 - len(ss[:3]))
        sp = sp + [ss[3] if len(ss) > 3 else '1']
        cp = ss[4:]
        blocks.append((sp, cp, d))
    if not blocks: raise I3DError('no data')
    # extension de cada dimension de componente: el mayor indice usado
    ncd = max(len(b[1]) for b in blocks)
    cext = []
    for c in range(ncd):
        m = 1
        for _, cp, _ in blocks:
            if c < len(cp):
                # el mayor indice ESCRITO (a o b), como el C++; si no es un
                # indice valido, _range_of lo rechaza abajo
                for x in cp[c].split(':'):
                    if re.fullmatch(r'\s*[0-9]+\s*', x): m = max(m, int(x))
        cext.append(m)
    shape = ext + cext
    types = sorted({b[2]['type'] for b in blocks if 'type' in b[2]})
    if len(types) != 1: raise I3DError('mixed block types %s: promotion not implemented here' % types)
    dt = np.dtype(TYPES[types[0]])
    # fill (SPEC 5.5): lo que vale un <missing>. Default 0 en enteros, NaN en
    # float; y tiene que CABER en el tipo
    e = [x for x in E if x[0] == 'fill']
    if dt.kind == 'f':
        fill = float(e[0][2]) if e else float('nan')
    else:
        fill = int(e[0][2]) if e else 0
        info = np.iinfo(dt)
        if not (info.min <= fill <= info.max): raise I3DError('badHeader: fill %d does not fit in %s' % (fill, types[0]))
    # COBERTURA (SPEC 5.5), como el C++: ningun par de cajas se solapa y sus
    # volumenes suman el total. (Antes un contador uint8 por elemento, que daba
    # la vuelta: 257 copias del mismo bloque pasaban por "asignado una vez")
    boxes = []
    for sp, cp, d in blocks:
        rr = [_range_of(p, n) for p, n in zip(sp, ext)]
        cc = [_range_of(cp[c] if c < len(cp) else '1', cext[c]) for c in range(ncd)]
        boxes.append(rr + cc)
    Bx = np.array(boxes, dtype=np.int64)                 # bloques x dims x (lo, hi)
    lo, hi = Bx[:, :, 0], Bx[:, :, 1]
    for a in range(len(boxes) - 1):
        over = np.all((lo[a] < hi[a + 1:]) & (lo[a + 1:] < hi[a]), axis=1)
        if over.any(): raise I3DError('coverage: data blocks %d and %d overlap' % (a + 1, a + 2 + int(np.argmax(over))))
    total, covered = int(np.prod(shape)), sum(int(np.prod([h - l for l, h in b])) for b in boxes)
    if covered != total: raise I3DError('coverage: the blocks cover %d of %d elements' % (covered, total))
    data = np.zeros(shape, dtype=dt, order='F')
    for (sp, cp, d), box in zip(blocks, boxes):
        bshape = [h - l for l, h in box]
        if 'shape' in d and [n for n in d['shape']] != bshape[:len(d['shape'])]:
            raise I3DError('{shape} %s does not match the subscript %s' % (d['shape'], bshape))
        nbytes = int(np.prod(bshape)) * dt.itemsize
        if d['encoding'] == 'dicom':
            if not (bshape[0] == ext[0] and bshape[1] == ext[1]): raise I3DError('a dicom block is whole i,j planes')
            fn = _resolve(d['path'], V, path)
            buf = _dicom_planes(fn, dt, ext[0], ext[1], int(np.prod(bshape[2:])), d.get('frames'))
            _crc(d, buf, 'a <dicom> block')
            blk = np.frombuffer(buf, dtype=dt).reshape(bshape, order='F')
            sl = tuple(slice(l, h) for l, h in box)
            data[sl] = blk
            continue
        if d['encoding'] == 'missing':
            # sin dato que proteger: un crc ahi no se comprobaria nunca
            if 'crc' in d: raise I3DError('badDescriptor: <missing> takes no crc')
            sl = tuple(slice(l, h) for l, h in box)
            data[sl] = fill
            continue
        L = d['length']
        if L == 'EOF': L = len(raw) - (b0 + d['offset'])
        # el bloque, DENTRO del fichero: un slice de Python lo cortaria en silencio
        need = nbytes if d['encoding'] == 'raw' else L
        if need is not None and b0 + d['offset'] + need > len(raw):
            raise I3DError('truncated: the file ends inside the block ' + val)
        if d['encoding'] == 'raw':
            if L is not None and L != nbytes: raise I3DError('raw length mismatch')
            filebytes = raw[b0 + d['offset']: b0 + d['offset'] + nbytes]
        elif d['encoding'] in ('zlib', 'jpegls'):
            if L is None: raise I3DError(d['encoding'] + ' needs a length')
            filebytes = raw[b0 + d['offset']: b0 + d['offset'] + L]
        else:
            raise I3DError('encoding %s not implemented in the reference reader' % d['encoding'])
        if d['encoding'] == 'raw':
            buf = filebytes
        elif d['encoding'] == 'zlib':
            buf = zlib.decompress(filebytes)
        elif d['encoding'] == 'jpegls':
            # SPEC 4: los planos i,j ENTEROS del bloque apilados en UNA imagen
            # (ancho = ni, alto = nj * planos: la x es la i, y los planos en orden
            # k, t, c, asi que la imagen es el bloque en orden columna), a los
            # bits del tipo; un tipo con signo va desplazado 2^(bits-1). Se
            # decodifica con imagecodecs: OTRA implementacion que CharLS, para
            # que la comparacion pruebe algo
            import imagecodecs
            if not (bshape[0] == ext[0] and bshape[1] == ext[1]):
                raise I3DError('a jpegls block is made of whole i,j planes')
            # como mucho 65535 x 65535: mas grande necesita la extension LSE de
            # dimensiones grandes, que imagecodecs no lee
            rows = int(np.prod(bshape[1:]))
            if ext[0] > 65535 or rows > 65535:
                raise I3DError('badData: a jpegls image is %d x %d; at most 65535 x 65535' % (ext[0], rows))
            # NEAR = 0: un flujo near-lossless decodifica a OTROS valores sin queja
            near = _jpegls_near(filebytes)
            if near != 0: raise I3DError('badBlock: <jpegls> is near-lossless (NEAR = %d)' % near)
            img = imagecodecs.jpegls_decode(filebytes)
            height = nbytes // (dt.itemsize * ext[0])
            if img.shape != (height, ext[0]): raise I3DError('jpegls frame %s, expected %s' % (img.shape, (height, ext[0])))
            u = img.astype(np.dtype('<u%d' % dt.itemsize), copy=False)
            if dt.kind == 'i': u = u ^ np.array(1 << (8 * dt.itemsize - 1), dtype=u.dtype)
            buf = u.tobytes()
        else:
            raise I3DError('encoding %s not implemented in the reference reader' % d['encoding'])
        if len(buf) != nbytes: raise I3DError('block has %d bytes, expected %d' % (len(buf), nbytes))
        _crc(d, buf, 'a data block')
        # los bytes, en orden columna i j k t c (SPEC 5.3: no hay otro)
        blk = np.frombuffer(buf, dtype=dt).reshape(bshape, order='F')
        sl = tuple(slice(l, h) for l, h in box)
        data[sl] = blk
    if ncd == 0: data = data.reshape(ext, order='F')
    I['data'] = data

    # el thumbnail en raw/zlib/png: uint8 {r c}, {r c 1 f} o {r c 3 f}, en orden columna
    # (SPEC 7); None si no hay
    I['thumbnail'] = None
    for name, sub, val in E:
        if name != 'thumbnail': continue
        d = _descriptor(val)
        if d['encoding'] not in ('raw', 'zlib', 'png') or 'shape' not in d: continue
        s = d['shape']
        if d['type'] != 'uint8' or not (2 <= len(s) <= 4) or (len(s) >= 3 and s[2] not in (1, 3)):
            raise I3DError('badDescriptor: the thumbnail is uint8 {rows cols}, {rows cols 1 frames} or {rows cols 3 frames}, not ' + val)
        if d['encoding'] == 'png':
            I['thumbnail'] = _png_thumb(raw, b0, d, name)
            continue
        adt = np.dtype(TYPES[d['type']])
        n = int(np.prod(d['shape'])) * adt.itemsize
        L = d['length']
        if L == 'EOF': L = len(raw) - (b0 + d['offset'])
        # un raw con longitud: la de su {shape}, o el fichero miente (antes se
        # leian n bytes sin mirar la que decia)
        if d['encoding'] == 'raw' and L is not None and L != n:
            raise I3DError('badBlock: %s: <raw> has %d bytes but its {shape} needs %d' % (name, L, n))
        need = n if d['encoding'] == 'raw' else L
        if need is None or b0 + d['offset'] + need > len(raw):
            raise I3DError('truncated: the file ends inside ' + name)
        fb = raw[b0 + d['offset']: b0 + d['offset'] + need]
        buf = fb if d['encoding'] == 'raw' else zlib.decompress(fb)
        if len(buf) != n: raise I3DError('%s has %d bytes, expected %d' % (name, len(buf), n))
        _crc(d, buf, name)
        I['thumbnail'] = np.frombuffer(buf, dtype=adt).reshape(d['shape'], order='F')
    return I

# ====================================================================== .mi3d
def read_mi3d(path, n=None, variables=None):
    # SPEC 14. Sin n: la cabecera del contenedor -> {'N', 'members': {n: (offset
    # en el FICHERO, longitud, crc)}, 'entries', 'header', 'binstart'}. Con n: el
    # miembro n como read_i3d, o None si es un hueco
    with open(path, 'rb') as fh:
        # mmap: un contenedor puede ser de GB, y solo se lee lo que se pide
        raw = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) if os.fstat(fh.fileno()).st_size else b''
        try:
            C = _container(raw)
            if n is None: return C
            if not isinstance(n, int) or not 1 <= n <= C['N']: raise I3DError('badIndex: no member %r: the container has 1..%d' % (n, C['N']))
            if n not in C['members']: return None
            a, L, crc = C['members'][n]
            m = raw[a:a + L]
        finally:
            if isinstance(raw, mmap.mmap): raw.close()
    if m[:4] == b'MI3D': raise I3DError('badBlock: member %d is a .mi3d (one level)' % n)
    # el crc de un miembro, opcional: de sus bytes tal cual
    if crc is not None and (zlib.crc32(m) & 0xffffffff) != crc: raise I3DError('badCRC: member %d fails its crc' % n)
    return _read(m, path, variables)

def _container(raw):
    if raw[:3] == b'I3D' and raw[3:4] in (b'b', b' ', b'\t', b'\r', b'\n'): raise I3DError('badMagic: an .i3d, not a .mi3d container')
    # la cabecera, solo en texto: hasta la PRIMERA linea que es exactamente ---
    pos = 0
    while True:
        nl = raw.find(b'\n', pos)
        end = len(raw) if nl < 0 else nl
        if raw[pos:end].rstrip(b'\r') == b'---': break
        if nl < 0: raise I3DError('badHeader: no terminator line ---')
        pos = nl + 1
    text, b0 = _utf8(raw[:pos]), min(end + 1, len(raw))
    E = _expand_hidden(_entries(text, magic='MI3D'), raw, b0)
    once = set()
    for k, sub, _ in E:
        if k == 'i3d' or sub is not None: continue
        if k in once: raise I3DError('badHeader: repeated key %r' % k)
        once.add(k)
    N, members, seen = 0, {}, set()
    for k, sub, v in E:
        if k != 'i3d': continue
        # n: UN entero >= 1, solo cifras, como los subindices de data (SPEC 5.2)
        t = sub[1:-1].strip() if sub is not None else ''
        if not re.fullmatch(r'[0-9]{1,9}', t) or int(t) < 1: raise I3DError('badSubscript: a member is i3d(n), n one integer >= 1, not i3d%s' % (sub or ''))
        n = int(t)
        if n in seen: raise I3DError('badHeader: repeated i3d(%d)' % n)
        seen.add(n); N = max(N, n)
        d = _descriptor(v)
        if d['encoding'] == 'missing':            # un hueco declarado
            if set(d) - {'encoding'}: raise I3DError('badDescriptor: a hole is <missing>, nothing else')
            continue
        if d['encoding'] != 'i3d': raise I3DError('badDescriptor: i3d(n) takes <i3d @a:b> or <missing>, not ' + v)
        if set(d) - {'encoding', 'offset', 'length', 'crc'} or 'offset' not in d or d['length'] is None:
            raise I3DError('badDescriptor: a member is <i3d @a:b [crc X]>, nothing else: ' + v)
        L = d['length']
        if L == 'EOF': L = len(raw) - (b0 + d['offset'])
        if L <= 0 or b0 + d['offset'] + L > len(raw): raise I3DError('truncated: the file ends inside member %d' % n)
        members[n] = (b0 + d['offset'], L, d.get('crc'))
    return {'N': N, 'members': members, 'entries': E, 'header': text, 'binstart': b0}

if __name__ == '__main__':
    I = read_i3d(sys.argv[1])
    print({k: (v.shape if hasattr(v, 'shape') else len(v)) for k, v in I.items()}, I['data'].dtype)
