# Un fichero de ejemplo por cada combinacion distinta de
#   (TransferSyntax, BitsAllocated, BitsStored, HighBit, PixelRepresentation,
#    SamplesPerPixel, frames>1)
# en d:\DICOMS, para probar el lector <dicom> contra dicomread en TODA la variedad
# del corpus. Solo cabeceras, y como mucho MAXPER ficheros por carpeta de primer
# nivel: barrer los ~600 000 ficheros del corpus no hace falta.
#   python dicom_variety.py D:/DICOMS out.txt
import os, sys
import pydicom

root, outf = sys.argv[1], sys.argv[2]
MAXPER = 200
seen = {}
for top in sorted(os.listdir(root)):
    tp = os.path.join(root, top)
    if not os.path.isdir(tp): continue
    n = 0
    for dp, dn, fn in os.walk(tp):
        for f in fn:
            if n >= MAXPER: break
            p = os.path.join(dp, f)
            try:
                h = pydicom.dcmread(p, stop_before_pixels=True)
                key = (str(h.file_meta.TransferSyntaxUID), int(h.BitsAllocated), int(h.BitsStored),
                       int(h.HighBit), int(h.PixelRepresentation), int(getattr(h, 'SamplesPerPixel', 1)),
                       int(getattr(h, 'NumberOfFrames', 1) or 1) > 1)
            except Exception:
                continue
            n += 1
            seen.setdefault(key, p)
        if n >= MAXPER: break
with open(outf, 'w', encoding='utf-8') as o:
    for k, p in sorted(seen.items()):
        o.write('%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n' % (k[0], k[1], k[2], k[3], k[4], k[5], int(k[6]), p))
print(len(seen), 'combinations')
for k, p in sorted(seen.items()): print(' ', k, '\n     ', p)
