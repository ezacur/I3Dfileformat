# Verifica lo que escribe num2strI3D.m contra Python, cuyo float() redondea
# correctamente (como strtod) y cuyo repr() es la forma mas corta exacta.
#
# Entrada: un fichero con una linea por caso:  <16 hex de los bits>\t<cadena>
# Comprueba, para cada linea:
#   EXACT    float(cadena) tiene exactamente esos bits
#   SHORTEST la cadena no tiene mas digitos significativos que repr()
#   DOT      un double con valor entero lleva '.0' (o exponente), cero incluido
import sys, struct, re

def bits2float(h):
    return struct.unpack('<d', struct.pack('<Q', int(h, 16)))[0]

def sigdigits(s):
    # digitos significativos de una forma decimal: sin signo, sin exponente,
    # sin punto, sin ceros a la izquierda ni a la derecha
    m = re.match(r'^-?([0-9.]+)(e[+-]?\d+)?$', s)
    if not m: return None
    d = m.group(1).replace('.', '').lstrip('0').rstrip('0')
    return max(len(d), 1)

n = bad_exact = bad_short = bad_dot = 0
examples = []
for line in open(sys.argv[1]):
    h, s = line.rstrip('\n').split('\t')
    x = bits2float(h)
    n += 1
    y = float(s)
    # un NaN en texto no conserva signo ni carga util (SPEC [OPEN]): basta isnan
    same = (x != x and y != y) or struct.pack('<d', x) == struct.pack('<d', y)
    if not same:
        bad_exact += 1
        if len(examples) < 10: examples.append(('EXACT', h, s, repr(x)))
        continue
    if s in ('nan', 'inf', '-inf'): continue
    if sigdigits(s) > sigdigits(repr(x).replace('-', '')):
        bad_short += 1
        if len(examples) < 10: examples.append(('SHORTEST', h, s, repr(x)))
    if x == int(x) and abs(x) < 1e300 and ('.' not in s and 'e' not in s):
        bad_dot += 1
        if len(examples) < 10: examples.append(('DOT', h, s, repr(x)))

print(f'{n} cases   not exact: {bad_exact}   not shortest: {bad_short}   missing .0: {bad_dot}')
for e in examples: print('  ', *e)
sys.exit(0 if (bad_exact == 0 and bad_short == 0 and bad_dot == 0) else 1)
