function buildI3Dlibrary()
%BUILDI3DLIBRARY   recompila i3d.dll y mi3d.dll (cpp\build.bat) y las deja en esta carpeta
%
%   buildI3Dlibrary
%
% En este orden, y parando en el primer fallo:
%   1. unloadlibrary i3d y mi3d, si estan cargadas en ESTE MATLAB. Falla si
%      quedan lib.pointer vivos (un i3dfile abierto...): el error dice cuales del
%      workspace base son.
%   2. borra la i3d.dll y la mi3d.dll de esta carpeta. Si otro proceso tiene una
%      cargada (otro MATLAB, un Python, un C#...), Windows no deja: el error dice
%      que PID y que programa la tienen. Antes se guarda una copia, por si el
%      paso 3 falla.
%   3. cpp\build.bat: compila, copia build\i3d.dll y build\mi3d.dll aqui y
%      regenera i3d_proto.m y mi3d_proto.m (matlab_proto.m, en otro MATLAB). Si
%      falla, vuelven las DLL de antes.
%   4. comprueba que las de aqui son las recien compiladas.
%
% Las librerias quedan DESCARGADAS: la siguiente llamada a write_I3D, read_I3D o
% write_MI3D carga la nueva.
%
% See also write_I3D, read_I3D, write_MI3D.

  here = fileparts( mfilename( 'fullpath' ) );
  bat  = fullfile( fileparts( here ) , 'cpp' , 'build.bat' );
  assert( isfile( bat ) , 'buildI3Dlibrary:noBuild' , 'buildI3Dlibrary: %s not found' , bat );
  LIBS = { 'i3d' , 'mi3d' };
  dll  = cellfun( @( L ) fullfile( here , [ L '.dll' ] ) , LIBS , 'un' , 0 );
  new  = cellfun( @( L ) fullfile( fileparts( here ) , 'cpp' , 'build' , [ L '.dll' ] ) , LIBS , 'un' , 0 );

  % 1. descargarlas de este MATLAB
  for q = 1:numel( LIBS )
    if ~libisloaded( LIBS{q} ), continue; end
    try
      unloadlibrary( LIBS{q} );
    catch E
      P = basePointers_();
      if isempty( P ), P = '  (none in the base workspace: look in functions, globals, onCleanup objects...)';
      else,            P = sprintf( '  %s\n' , P{:} );  P = P(1:end-1);
      end
      error( 'buildI3Dlibrary:unload' , [ 'buildI3Dlibrary: cannot unload %s from this MATLAB (%s)\n' ...
             'Variables still holding objects of the library (clear them, close their files):\n%s\n' ...
             'Nothing was rebuilt.' ] , LIBS{q} , E.message , P );
    end
  end

  % 2. borrarlas de aqui (si otro proceso tiene una cargada, Windows no deja)
  bak = cell( size( LIBS ) );
  for q = 1:numel( LIBS )
    if ~isfile( dll{q} ), continue; end
    bak{q} = [ tempname , '_' , LIBS{q} , '.dll' ];
    copyfile( dll{q} , bak{q} );
    [ msg0 , id0 ] = lastwarn( '' );  ws = warning( 'off' , 'MATLAB:DELETE:Permission' );
    delete( dll{q} );
    warning( ws );  lastwarn( msg0 , id0 );
    if isfile( dll{q} )
      restore_( dll , bak );
      error( 'buildI3Dlibrary:locked' , [ 'buildI3Dlibrary: cannot delete %s: another process has it loaded.\n%s\n' ...
             'Close it there (in a MATLAB: clear the handles, then unloadlibrary %s). Nothing was rebuilt.' ] , dll{q} , holders_( dll{q} ) , LIBS{q} );
    end
  end

  % 3. compilar (build.bat copia build\*.dll aqui y regenera los prototipos)
  fprintf( 'buildI3Dlibrary: %s\n' , bat );
  st = system( [ '"' , bat , '"' ] , '-echo' );
  if st ~= 0
    restored = restore_( dll , bak );
    error( 'buildI3Dlibrary:build' , 'buildI3Dlibrary: cpp\build.bat failed (exit %d, its output is above).%s' , st , restored );
  end
  for q = 1:numel( LIBS ), if ~isempty( bak{q} ) && isfile( bak{q} ), delete( bak{q} ); end, end

  % 4. las de aqui son las recien compiladas
  for q = 1:numel( LIBS )
    assert( isfile( dll{q} ) && isequal( fileread_( dll{q} ) , fileread_( new{q} ) ) , 'buildI3Dlibrary:copy' , ...
            'buildI3Dlibrary: %s is not the freshly built %s' , dll{q} , new{q} );
  end
  clear i3d_proto mi3d_proto                             % los prototipos nuevos, no los que MATLAB tenia en memoria
  rehash
  for q = 1:numel( LIBS )
    d = dir( dll{q} );
    fprintf( 'buildI3Dlibrary: ok -- %s (%s, %d bytes); not loaded yet\n' , dll{q} , d.date , d.bytes );
  end
end

function txt = restore_( dll , bak )
% las DLL de antes, en su sitio (las que se borraron)
  txt = '';
  for q = 1:numel( dll )
    if ~isempty( bak{q} ) && isfile( bak{q} ) && ~isfile( dll{q} )
      movefile( bak{q} , dll{q} );  txt = [ txt , ' ' , dll{q} , ' is back in place.' ];   %#ok<AGROW>
    elseif ~isempty( bak{q} ) && isfile( bak{q} )
      delete( bak{q} );
    end
  end
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
