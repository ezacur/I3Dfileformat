#!/bin/sh
# Las cinco series del inventario, con el conjunto de codecs que importa.
# Un solo proceso a la vez: la maquina es compartida.
# el Python del entorno 'i3d' de Miniforge (tests/environment.yml), o I3D_PYTHON
PY="${I3D_PYTHON:-$USERPROFILE/miniforge3/envs/i3d/python.exe}"
SET="zlib9,zlib9+sh,zlib9+di+sh,zlib9+dk+sh,zstd19+sh,zstd22+sh,zstd22+dk+sh,xz9e+sh,xz9e+dk+sh,brotli11+sh,jpegls,jpeg2k-rev,png9"
for S in \
  "D:/DICOMS/RM_CT/Patient12_FOI_MPP25_mirar/FILESET/5224963/0/0" \
  "D:/DICOMS/RM_CT/Patient8_70220008_/FILESET/70720039/0/4" \
  "D:/DICOMS/MR 001/DICOM/000062D6/AA77D253/AA0655D4/0000CB02" \
  "D:/DICOMS/MR 001/DICOM/000062D6/AA77D253/AA0655D4/00007844" \
  "D:/DICOMS/RM_CT/Patient2_5189648/5189648/FILESET/5189648/0/0" ; do
  "$PY" bench_codecs.py "$S" "$SET"
done
