# Inventario de series en unas pocas carpetas de d:\DICOMS, para elegir
# volumenes de prueba variados. Solo cabeceras (stop_before_pixels).
import os, sys, collections
import pydicom

ROOTS = sys.argv[1:]
MAXFILES = 4000          # por carpeta: no barrer el corpus entero

for root in ROOTS:
    series = collections.defaultdict(list)
    n = 0
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if n >= MAXFILES: break
            p = os.path.join(dp, f)
            try:
                h = pydicom.dcmread(p, stop_before_pixels=True)
                uid = h.SeriesInstanceUID
            except Exception:
                continue
            n += 1
            series[uid].append((p, h))
        if n >= MAXFILES: break
    print(f'== {root}: {n} files, {len(series)} series')
    for uid, L in sorted(series.items(), key=lambda kv: -len(kv[1]))[:6]:
        h = L[0][1]
        ts = str(getattr(h.file_meta, 'TransferSyntaxUID', '?'))
        print(f'  {len(L):5d}  {getattr(h,"Modality","?"):3s} {h.Rows}x{h.Columns} '
              f'bits {getattr(h,"BitsStored","?")} pr {getattr(h,"PixelRepresentation","?")} '
              f'ts {ts}  "{getattr(h,"SeriesDescription","")}"')
        print(f'         {os.path.dirname(L[0][0])}')
