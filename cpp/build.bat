@echo off
rem build.bat -- compila el lector .i3d con MSVC 2022 (el mismo que usa mex):
rem   i3d.dll + i3d.lib   la libreria, con la API en C (i3d_c.h)
rem   i3dinfo.exe         la herramienta de linea de comandos, cliente de la DLL
rem   mi3d.dll            el contenedor .mi3d, con la API en C (mi3d_c.h)
rem y copia las dos DLL y sus cabeceras a matlab\lib (loadlibrary)
rem
rem Dentro, compiladas desde third_party/ (copias verbatim, ver sus ORIGIN.txt):
rem   zlib 1.3.2     inflate para <zlib> y crc32 para el 'crc' de un bloque
rem   CharLS 2.4.5   JPEG-LS para <jpegls>, estatica (CHARLS_STATIC)
rem   lodepng        PNG para los <png> de aux (los thumbnails)
rem
rem /DNDEBUG en TODO: sin el, CharLS deja sus ASSERT en el bucle de cada pixel y
rem no fuerza el inline (MEDIDO 2026-10-25: JPEG-LS 1.6x mas lento que con mex,
rem que lo define siempre).
rem /fp:precise y SIN /fp:fast: el rango de SPEC 3.1 exige k*s y la suma como
rem dos operaciones; i3d.cpp ademas lo blinda con un volatile.
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "%~dp0"
if not exist build mkdir build

set Z=..\third_party\zlib-1.3.2
set ZSRC=%Z%\adler32.c %Z%\compress.c %Z%\crc32.c %Z%\deflate.c %Z%\infback.c %Z%\inffast.c %Z%\inflate.c %Z%\inftrees.c %Z%\trees.c %Z%\uncompr.c %Z%\zutil.c
set C=..\third_party\charls-2.4.5
set CSRC=%C%\src\charls_jpegls_decoder.cpp %C%\src\charls_jpegls_encoder.cpp %C%\src\jpeg_stream_reader.cpp %C%\src\jpeg_stream_writer.cpp %C%\src\jpegls.cpp %C%\src\jpegls_error.cpp %C%\src\validate_spiff_header.cpp %C%\src\version.cpp
set P=..\third_party\lodepng-20261006

rem codigo de otros, tal cual: sin avisos (/W0)
cl /nologo /c /O2 /DNDEBUG /W0 /MD %ZSRC% /Fobuild\ || exit /b 1
cl /nologo /c /O2 /DNDEBUG /W0 /MD /EHsc /std:c++17 /DCHARLS_STATIC /DCHARLS_LIBRARY_BUILD /I%C%\include %CSRC% /Fobuild\ || exit /b 1
cl /nologo /c /O2 /DNDEBUG /W0 /MD /EHsc /std:c++17 %P%\lodepng.cpp /Fobuild\ || exit /b 1
set ZOBJ=build\adler32.obj build\compress.obj build\crc32.obj build\deflate.obj build\infback.obj build\inffast.obj build\inflate.obj build\inftrees.obj build\trees.obj build\uncompr.obj build\zutil.obj
set COBJ=build\charls_jpegls_decoder.obj build\charls_jpegls_encoder.obj build\jpeg_stream_reader.obj build\jpeg_stream_writer.obj build\jpegls.obj build\jpegls_error.obj build\validate_spiff_header.obj build\version.obj

rem DCMTK (pixeles de <dicom>): estatica, de build_dcmtk.bat. Si no esta, se
rem compila sin ella y un <dicom> da error AL PEDIRLO (SPEC 4)
rem SIN dcmjpls ni dcmtkcharls: esa es una CharLS vieja con funciones del mismo
rem nombre que la 2.4.5 de aqui, y mezclarlas daba un access violation en todo
rem DICOM JPEG-LS. El JPEG-LS de un DICOM lo decodifica nuestra CharLS (i3d.cpp)
set DI=build\dcmtk-install
set DDEF=
set DLIB=
if exist %DI%\lib\dcmdata.lib (
  set DDEF=/DI3D_HAVE_DCMTK /I%DI%\include
  set DLIB=%DI%\lib\dcmjpeg.lib %DI%\lib\ijg8.lib %DI%\lib\ijg12.lib %DI%\lib\ijg16.lib %DI%\lib\dcmimage.lib %DI%\lib\dcmimgle.lib %DI%\lib\dcmdata.lib %DI%\lib\oflog.lib %DI%\lib\ofstd.lib ws2_32.lib netapi32.lib advapi32.lib iphlpapi.lib
) else (
  echo build.bat: no DCMTK in %DI% -- run build_dcmtk.bat first to read ^<dicom^> blocks
)

cl /nologo /std:c++17 /O2 /DNDEBUG /EHsc /W4 /fp:precise /MD /DI3D_BUILD_DLL /DI3D_HAVE_ZLIB /DI3D_HAVE_CHARLS /DCHARLS_STATIC /DI3D_HAVE_LODEPNG %DDEF% /I%Z% /I%C%\include /I%P% /LD i3d.cpp i3d_write.cpp i3d_c.cpp %ZOBJ% %COBJ% build\lodepng.obj %DLIB% /Fobuild\ /Febuild\i3d.dll || exit /b 1
cl /nologo /std:c++17 /O2 /DNDEBUG /EHsc /W4 /MD /DI3D_USE_DLL i3dinfo.cpp build\i3d.lib /Fobuild\ /Febuild\i3dinfo.exe || exit /b 1

rem mi3d.dll: el contenedor .mi3d (SPEC 14). El mismo nucleo, SIN DCMTK: solo
rem lee las cabeceras de los miembros, nunca sus pixeles. Sus objetos, a otro
rem directorio: el nucleo se compila con otras opciones
if not exist build\mi3d mkdir build\mi3d
cl /nologo /std:c++17 /O2 /DNDEBUG /EHsc /W4 /fp:precise /MD /DMI3D_BUILD_DLL /DI3D_HAVE_ZLIB /DI3D_HAVE_CHARLS /DCHARLS_STATIC /DI3D_HAVE_LODEPNG /I%Z% /I%C%\include /I%P% /LD i3d.cpp i3d_write.cpp mi3d.cpp mi3d_c.cpp %ZOBJ% %COBJ% build\lodepng.obj /Fobuild\mi3d\ /Febuild\mi3d.dll || exit /b 1

rem lo que usa MATLAB (loadlibrary): las DLL y sus cabeceras, en matlab\lib
if not exist ..\matlab\lib mkdir ..\matlab\lib
copy /y build\i3d.dll ..\matlab\lib\ >nul || exit /b 1
copy /y build\mi3d.dll ..\matlab\lib\ >nul || exit /b 1
copy /y i3d_c.h ..\matlab\lib\ >nul || exit /b 1
copy /y mi3d_c.h ..\matlab\lib\ >nul || exit /b 1
echo build.bat: ok
