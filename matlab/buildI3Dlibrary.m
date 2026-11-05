function buildI3Dlibrary()
%BUILDI3DLIBRARY   recompila i3d.dll (cpp\build.bat) y la deja en esta carpeta
%
%   buildI3Dlibrary
%
% En este orden, y parando en el primer fallo:
%   1. unloadlibrary i3d, si esta cargada en ESTE MATLAB. Falla si quedan
%      lib.pointer vivos (un i3dfile abierto...): el error dice cuales del
%      workspace base son.
%   2. borra la i3d.dll de esta carpeta. Si otro proceso la tiene cargada (otro
%      MATLAB, un Python, un C#...), Windows no deja: el error dice que PID y que
%      programa la tienen. Antes se guarda una copia, por si el paso 3 falla.
%   3. cpp\build.bat: compila, copia build\i3d.dll aqui y regenera i3d_proto.m
%      (matlab_proto.m, en otro MATLAB). Si falla, vuelve la i3d.dll de antes.
%   4. comprueba que la i3d.dll de aqui es la recien compilada.
%
% La libreria queda DESCARGADA: la siguiente llamada a write_I3D o read_I3D
% carga la nueva.
%
% See also write_I3D, read_I3D.

  here = fileparts( mfilename( 'fullpath' ) );
  dll  = fullfile( here , 'i3d.dll' );
  bat  = fullfile( fileparts( here ) , 'cpp' , 'build.bat' );
  new  = fullfile( fileparts( here ) , 'cpp' , 'build' , 'i3d.dll' );
  assert( isfile( bat ) , 'buildI3Dlibrary:noBuild' , 'buildI3Dlibrary: %s not found' , bat );

  % 1. descargarla de este MATLAB
  if libisloaded( 'i3d' )
    try
      unloadlibrary( 'i3d' );
    catch E
      P = basePointers_();
      if isempty( P ), P = '  (none in the base workspace: look in functions, globals, onCleanup objects...)';
      else,            P = sprintf( '  %s\n' , P{:} );  P = P(1:end-1);
      end
      error( 'buildI3Dlibrary:unload' , [ 'buildI3Dlibrary: cannot unload i3d from this MATLAB (%s)\n' ...
             'Variables still holding objects of the library (clear them, close their files):\n%s\n' ...
             'Nothing was rebuilt.' ] , E.message , P );
    end
  end

  % 2. borrarla de aqui (si otro proceso la tiene cargada, Windows no deja)
  bak = '';
  if isfile( dll )
    bak = [ tempname , '_i3d.dll' ];
    copyfile( dll , bak );
    [ msg0 , id0 ] = lastwarn( '' );  ws = warning( 'off' , 'MATLAB:DELETE:Permission' );
    delete( dll );
    warning( ws );  lastwarn( msg0 , id0 );
    if isfile( dll )
      delete( bak );
      error( 'buildI3Dlibrary:locked' , [ 'buildI3Dlibrary: cannot delete %s: another process has it loaded.\n%s\n' ...
             'Close it there (in a MATLAB: clear the handles, then unloadlibrary i3d). Nothing was rebuilt.' ] , dll , holders_( dll ) );
    end
  end

  % 3. compilar (build.bat copia build\i3d.dll aqui y regenera i3d_proto.m)
  fprintf( 'buildI3Dlibrary: %s\n' , bat );
  st = system( [ '"' , bat , '"' ] , '-echo' );
  if st ~= 0
    if ~isempty( bak ) && ~isfile( dll ), movefile( bak , dll ); restored = ' The previous i3d.dll is back in place.';
    else, restored = ''; end
    error( 'buildI3Dlibrary:build' , 'buildI3Dlibrary: cpp\\build.bat failed (exit %d, its output is above).%s' , st , restored );
  end
  if ~isempty( bak ) && isfile( bak ), delete( bak ); end

  % 4. la de aqui es la recien compilada
  assert( isfile( dll ) && isequal( fileread_( dll ) , fileread_( new ) ) , 'buildI3Dlibrary:copy' , ...
          'buildI3Dlibrary: %s is not the freshly built %s' , dll , new );
  clear i3d_proto                                        % el prototipo nuevo, no el que MATLAB tenia en memoria
  rehash
  d = dir( dll );
  fprintf( 'buildI3Dlibrary: ok -- %s (%s, %d bytes); not loaded yet\n' , dll , d.date , d.bytes );
end

function P = basePointers_()
% las variables del workspace base que son objetos de una libreria (lib.pointer...)
  W = evalin( 'base' , 'whos' );
  W = W( startsWith( { W.class } , 'lib.' ) );
  P = arrayfun( @( w ) sprintf( '%s (%s)' , w.name , w.class ) , W , 'un' , 0 );
end

function txt = holders_( dll )
% que procesos tienen cargada ESTA dll (por su ruta completa), con PowerShell
  ps1 = [ tempname , '.ps1' ];
  fid = fopen( ps1 , 'w' );
  fprintf( fid , '%s\n' , ...
    '$dll = $args[0]' , ...
    'foreach( $p in Get-Process ){' , ...
    '  try { foreach( $m in $p.Modules ){ if( $m.FileName -ieq $dll ){ "{0}`t{1}`t{2}" -f $p.Id , $p.ProcessName , $p.Path; break } } } catch {}' , ...
    '}' );
  fclose( fid );
  [ ~ , out ] = system( sprintf( 'powershell -NoProfile -ExecutionPolicy Bypass -File "%s" "%s"' , ps1 , dll ) );
  delete( ps1 );
  L = strtrim( strsplit( strtrim( out ) , newline ) );  L = L( ~cellfun( 'isempty' , L ) );
  if isempty( L ), txt = 'Could not tell which process (none visible to this user; an elevated process, or one of another user?)';  return; end
  me = feature( 'getpid' );
  for q = 1:numel( L )
    t = strsplit( L{q} , sprintf( '\t' ) );
    L{q} = sprintf( '  PID %s  %s  %s' , t{1} , t{2} , strjoin( t(3:end) , ' ' ) );
    if str2double( t{1} ) == me, L{q} = [ L{q} , '   <- THIS MATLAB' ]; end
  end
  txt = sprintf( 'Loaded by:\n%s' , strjoin( L , newline ) );
end

function b = fileread_( f )
  fid = fopen( f , 'r' );  b = fread( fid , Inf , '*uint8' );  fclose( fid );
end
