function matlab_proto( dst , lib )
%MATLAB_PROTO   genera <lib>_proto.m para calllib (SIN thunk) y lo copia a dst
%
%   matlab_proto( dst )          i3d_proto.m  (i3d.dll, i3d_c.h)
%   matlab_proto( dst , 'mi3d' ) mi3d_proto.m (mi3d.dll, mi3d_c.h)
%
% Lo llama cpp\build.bat despues de compilar, con dst = ..\matlab.
%
% loadlibrary necesita los tipos de cada funcion (una DLL de C solo exporta los
% nombres). Con el prototipo ya hecho, matlab\ carga la DLL SIN la cabecera y
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
% Sin thunk, calllib admite 6 argumentos como mucho: una funcion con mas no se
% puede llamar desde MATLAB. En i3d.dll no hay ninguna (falla si aparece); en
% mi3d.dll, solo las de escribir por ruta, mi3d_write_files y mi3d_append, que
% MATLAB no usa (escribe con mi3d_new ... mi3d_write).
%
% Aqui SI hace falta un compilador de C (mex -setup C): loadlibrary analiza
% la cabecera y compila su thunk, que se tira. Se genera en una carpeta
% temporal, con la DLL recien compilada (build\<lib>.dll), para no tocar la que
% un MATLAB tenga cargada en dst; luego se copia el prototipo (la DLL la copia
% build.bat).

  if nargin < 2, lib = 'i3d'; end
  switch lib
    case 'i3d',  hdr = 'i3d_c.h';   MORE6 = {};
    case 'mi3d', hdr = 'mi3d_c.h';  MORE6 = { 'mi3d_write_files' , 'mi3d_append' };
    otherwise,   error( 'matlab_proto:lib' , 'lib is ''i3d'' or ''mi3d''' );
  end
  dll   = [ lib '.dll' ];
  proto = [ lib '_proto' ];

  here = fileparts( mfilename( 'fullpath' ) );
  tmp  = tempname;  mkdir( tmp );
  copyfile( fullfile( here , 'build' , dll ) , tmp );
  copyfile( fullfile( here , hdr ) , tmp );
  old = cd( tmp );  C = onCleanup( @() cleanup_( old , tmp , lib ) );
  % las definiciones de la CRT de Windows que el analizador no conoce salen como
  % avisos (voidPtr): no son de la API
  [ ~ , ~ ] = loadlibrary( dll , hdr , 'alias' , lib , 'mfilename' , proto );
  n = numel( libfunctions( lib ) );
  unloadlibrary( lib );

  % el prototipo, sin thunk
  txt = fileread( [ proto '.m' ] );
  TH  = 'fcns.calltype{fcnNum}=''Thunk''';
  nT  = numel( strfind( txt , TH ) );
  txt = strrep( txt , TH , 'fcns.calltype{fcnNum}=''cdecl''' );
  txt = regexprep( txt , 'fcns\.thunkname\{fcnNum\}=''\w*'';' , '' );
  txt = regexprep( txt , '(?m)^ThunkLibName=[^\n]*' , 'ThunkLibName=[];   % sin thunk: calltype cdecl (cpp\\matlab_proto.m)' );
  assert( nT == n && ~contains( txt , 'thunkname{fcnNum}=' ) , 'matlab_proto:format' , ...
          'matlab_proto: unexpected prototype (%d Thunk calls for %d functions)' , nT , n );
  delete( [ proto '.m' ] );
  fid = fopen( [ proto '.m' ] , 'w' );  fwrite( fid , txt );  fclose( fid );
  clear( proto );

  % la prueba: cargarlo sin thunk y llamar (cadenas, punteros, int64)
  loadlibrary( dll , str2func( proto ) , 'alias' , lib );
  % sin thunk, calllib admite 6 argumentos como mucho ('Too many inputs passed to
  % SimpleFunctionThunk'): una funcion de la API con mas no se podria llamar
  sig  = libfunctions( lib , '-full' );
  na   = cellfun( @( s ) numel( strsplit( regexprep( s , '.*\((.*)\)\s*$' , '$1' ) , ',' ) ) , sig );
  name = regexprep( sig , '^.*?(\w+)\s*\(.*$' , '$1' );
  bad  = na > 6 & ~ismember( name , MORE6 );
  assert( ~any( bad ) , 'matlab_proto:args' , 'matlab_proto: without thunk calllib takes at most 6 arguments: %s' , strjoin( sig( bad ) , ' | ' ) );
  switch lib
    case 'i3d'
      h = calllib( 'i3d' , 'i3d_open' , 'no_such_file.i3d' );
      ok = isNull( h ) && ~isempty( calllib( 'i3d' , 'i3d_last_error' , [] ) ) ...
        && strcmp( calllib( 'i3d' , 'i3d_num2str' , 0.5 ) , '0.5' );
      w = calllib( 'i3d' , 'i3d_new' );
      ok = ok && calllib( 'i3d' , 'i3d_set_Xgrid' , w , [ 0 1 2 ] , int64( 3 ) ) == 0 ...
              && calllib( 'i3d' , 'i3d_write' , w , fullfile( tmp , 'incomplete.i3d' ) ) ~= 0 ...   % sin data: debe fallar
              && ~isempty( calllib( 'i3d' , 'i3d_wlast_error' , w ) );
      calllib( 'i3d' , 'i3d_free' , w );
    case 'mi3d'
      h = calllib( 'mi3d' , 'mi3d_open' , 'no_such_file.mi3d' );
      ok = isNull( h ) && ~isempty( calllib( 'mi3d' , 'mi3d_last_error' , [] ) );
      w = calllib( 'mi3d' , 'mi3d_new' );
      ok = ok && calllib( 'mi3d' , 'mi3d_set_Xgrid' , w , [ 0 1 2 ] , int64( 3 ) ) ~= 0 ...      % sin mi3d_add_stack: debe fallar
              && calllib( 'mi3d' , 'mi3d_add_stack' , w , 'x' ) == 0 ...
              && calllib( 'mi3d' , 'mi3d_set_Xgrid' , w , [ 0 1 2 ] , int64( 3 ) ) == 0 ...
              && calllib( 'mi3d' , 'mi3d_write' , w , fullfile( tmp , 'incomplete.mi3d' ) ) ~= 0 ...   % sin data: debe fallar
              && ~isempty( calllib( 'mi3d' , 'mi3d_wlast_error' , w ) );
      calllib( 'mi3d' , 'mi3d_free' , w );
  end
  clear h w                                               % los lib.pointer, o no se descarga
  unloadlibrary( lib );
  assert( ok , 'matlab_proto:nothunk' , 'matlab_proto: %s does not work without thunk in this MATLAB' , dll );

  copyfile( [ proto '.m' ] , dst );
  T = fullfile( dst , [ lib '_thunk_pcwin64.dll' ] );     % el de antes, si lo hay
  if isfile( T ), delete( T ); end
  fprintf( 'matlab_proto: %s.m, without thunk (%d functions) -> %s\n' , proto , n , dst );
end

function cleanup_( old , tmp , lib )
% primero salir de tmp, luego borrarlo (con la libreria ya descargada)
  if libisloaded( lib ), unloadlibrary( lib ); end
  cd( old );
  rmdir( tmp , 's' );
end
