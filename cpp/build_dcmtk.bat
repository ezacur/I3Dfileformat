@echo off
rem build_dcmtk.bat -- compila el SUBCONJUNTO de DCMTK de third_party/dcmtk-3.7.0
rem como librerias estaticas, y lo instala (cabeceras + .lib) en build\dcmtk-install.
rem Solo hace falta una vez; build.bat y la receta del MEX enlazan contra eso.
rem
rem   - solo los 7 modulos copiados (DCMTK_MODULES), sin apps
rem   - diccionario DICOM INTERNO (DCMTK_DEFAULT_DICT=builtin): ningun fichero
rem     dicom.dic al ejecutar
rem   - estatico, /MD (la misma CRT que el MEX y la DLL)
rem   - sin OpenSSL, PNG, TIFF, XML, zlib, iconv, ni conversion de juegos de
rem     caracteres: solo se decodifican PIXELES
rem   - CON rutas anchas (DCMTK_WIDE_CHAR_FILE_IO_FUNCTIONS): sin eso un .dcm en
rem     una carpeta con caracteres no ASCII ("Año") no abre en Windows
setlocal
cd /d "%~dp0"
set CM=C:\Win\CMake\bin\cmake.exe
set SRC=..\third_party\dcmtk-3.7.0
set BLD=build\dcmtk
set INS=build\dcmtk-install

"%CM%" -S %SRC% -B %BLD% -G "Visual Studio 17 2022" -A x64 ^
  -DDCMTK_MODULES="ofstd;oflog;dcmdata;dcmimgle;dcmimage;dcmjpeg;dcmjpls" ^
  -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DDCMTK_COMPILE_WIN32_MULTITHREADED_DLL=ON ^
  -DDCMTK_DEFAULT_DICT=builtin -DDCMTK_WIDE_CHAR_FILE_IO_FUNCTIONS=ON ^
  -DDCMTK_WITH_OPENSSL=OFF -DDCMTK_WITH_PNG=OFF -DDCMTK_WITH_TIFF=OFF -DDCMTK_WITH_XML=OFF ^
  -DDCMTK_WITH_ZLIB=OFF -DDCMTK_WITH_SNDFILE=OFF -DDCMTK_WITH_ICONV=OFF -DDCMTK_WITH_WRAP=OFF ^
  -DDCMTK_WITH_DOXYGEN=OFF -DDCMTK_ENABLE_CHARSET_CONVERSION="<disabled>" ^
  -DCMAKE_INSTALL_PREFIX=%INS% || exit /b 1
"%CM%" --build %BLD% --config Release --parallel 1 || exit /b 1
"%CM%" --install %BLD% --config Release || exit /b 1
echo build_dcmtk.bat: ok
