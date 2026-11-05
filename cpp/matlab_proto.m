function matlab_proto( dst )
%MATLAB_PROTO   genera i3d_proto.m para calllib (SIN thunk) y lo copia a dst
%
%   matlab_proto( dst )          lo llama cpp\build.bat despues de compilar: dst = ..\matlab
%
% loadlibrary necesita los tipos de cada funcion (una DLL de C solo exporta los
% nombres). Con el prototipo ya hecho, matlab\ carga i3d.dll SIN la cabecera y
% SIN compilador:
%
%   loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' )
%
% SIN THUNK (decidido 2026-11-05): loadlibrary escribe un prototipo que llama
% por un thunk compilado (i3d_thunk_pcwin64.dll), que es lo que documenta
% MathWorks en 64 bits. Aqui se reescribe con calltype 'cdecl' y
% ThunkLibName = []: MATLAB llama a la DLL directamente (en Windows x64 hay una
% sola convencion de llamada). No esta documentado; MEDIDO en R2022a: el import y
% la escritura dan lo mismo que con thunk. Al final se carga el prototipo sin
% thunk y se prueba (cadenas, punteros, int64): si una version de MATLAB lo
% rompe, falla aqui y no en el usuario.
%
% Aqui SI hace falta un compilador de C (mex -setup C): loadlibrary analiza
% cpp\i3d_c.h y compila su thunk, que se tira. Se genera en una carpeta
% temporal, con la DLL recien compilada (build\i3d.dll), para no tocar la que un
% MATLAB tenga cargada en dst; luego se copia el prototipo (la DLL la copia
% build.bat).

  here = fileparts( mfilename( 'fullpath' ) );
  tmp  = tempname;  mkdir( tmp );
  copyfile( fullfile( here , 'build' , 'i3d.dll' ) , tmp );
  copyfile( fullfile( here , 'i3d_c.h' ) , tmp );
  old = cd( tmp );  C = onCleanup( @() cleanup_( old , tmp ) );
  % las definiciones de la CRT de Windows que el analizador no conoce salen como
  % avisos (voidPtr): no son de la API
  [ ~ , ~ ] = loadlibrary( 'i3d.dll' , 'i3d_c.h' , 'alias' , 'i3d' , 'mfilename' , 'i3d_proto' );
  n = numel( libfunctions( 'i3d' ) );
  unloadlibrary( 'i3d' );

  % el prototipo, sin thunk
  txt = fileread( 'i3d_proto.m' );
  TH  = 'fcns.calltype{fcnNum}=''Thunk''';
  nT  = numel( strfind( txt , TH ) );
  txt = strrep( txt , TH , 'fcns.calltype{fcnNum}=''cdecl''' );
  txt = regexprep( txt , 'fcns\.thunkname\{fcnNum\}=''\w*'';' , '' );
  txt = regexprep( txt , '(?m)^ThunkLibName=[^\n]*' , 'ThunkLibName=[];   % sin thunk: calltype cdecl (cpp\\matlab_proto.m)' );
  assert( nT == n && ~contains( txt , 'thunkname{fcnNum}=' ) , 'matlab_proto:format' , ...
          'matlab_proto: unexpected prototype (%d Thunk calls for %d functions)' , nT , n );
  delete( 'i3d_proto.m' );
  fid = fopen( 'i3d_proto.m' , 'w' );  fwrite( fid , txt );  fclose( fid );
  clear i3d_proto

  % la prueba: cargarlo sin thunk y llamar (cadenas, punteros, int64)
  loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' );
  % sin thunk, calllib admite 6 argumentos como mucho ('Too many inputs passed to
  % SimpleFunctionThunk'): una funcion de la API con mas no se podria llamar
  sig = libfunctions( 'i3d' , '-full' );
  na  = cellfun( @( s ) numel( strsplit( regexprep( s , '.*\((.*)\)\s*$' , '$1' ) , ',' ) ) , sig );
  assert( all( na <= 6 ) , 'matlab_proto:args' , 'matlab_proto: without thunk calllib takes at most 6 arguments: %s' , strjoin( sig( na > 6 ) , ' | ' ) );
  h = calllib( 'i3d' , 'i3d_open' , 'no_such_file.i3d' );
  ok = isNull( h ) && ~isempty( calllib( 'i3d' , 'i3d_last_error' , [] ) ) ...
    && strcmp( calllib( 'i3d' , 'i3d_num2str' , 0.5 ) , '0.5' );
  w = calllib( 'i3d' , 'i3d_new' );
  ok = ok && calllib( 'i3d' , 'i3d_set_Xgrid' , w , [ 0 1 2 ] , int64( 3 ) ) == 0 ...
          && calllib( 'i3d' , 'i3d_write' , w , fullfile( tmp , 'incomplete.i3d' ) ) ~= 0 ...   % sin data: debe fallar
          && ~isempty( calllib( 'i3d' , 'i3d_wlast_error' , w ) );
  calllib( 'i3d' , 'i3d_free' , w );
  clear h w                                               % los lib.pointer, o no se descarga
  unloadlibrary( 'i3d' );
  assert( ok , 'matlab_proto:nothunk' , 'matlab_proto: i3d.dll does not work without thunk in this MATLAB' );

  copyfile( 'i3d_proto.m' , dst );
  T = fullfile( dst , 'i3d_thunk_pcwin64.dll' );          % el de antes, si lo hay
  if isfile( T ), delete( T ); end
  fprintf( 'matlab_proto: i3d_proto.m, without thunk (%d functions) -> %s\n' , n , dst );
end

function cleanup_( old , tmp )
% primero salir de tmp, luego borrarlo (con la libreria ya descargada)
  if libisloaded( 'i3d' ), unloadlibrary( 'i3d' ); end
  cd( old );
  rmdir( tmp , 's' );
end
