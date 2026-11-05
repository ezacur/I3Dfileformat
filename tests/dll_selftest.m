function ok = dll_selftest()
%DLL_SELFTEST   i3d.dll through calllib: a hand-made .i3d, read back exactly
%
%   ok = dll_selftest()
%
% No usa write_I3D: solo read_I3D (que carga la DLL) y calllib. Escribe
% a mano un .i3d pequeno, con lo que mas facil es romper -- un
% rango, una lista no uniforme, una matriz no trivial, int16 con negativos, dos
% bloques, un <missing> con fill y un [n] que MIENTE (no se lee) --, y comprueba
% cada cosa bit a bit. Lanza si algo no cuadra.

  f = fullfile( tempdir , sprintf( 'i3d_dll_selftest_%d.i3d' , feature('getpid') ) );
  CLEAN = onCleanup( @() delete_( f ) );

  D = int16( reshape( -6:5 , [3 2 2 1] ) );            % i j k t
  H = { 'I3D'
        '# dll_selftest'
        'X[999] = 0.0 : 0.5 : 1.0'                     % el [999] no se lee
        'Y[2]   = -1.0 2.5'
        'Z[2]   = 0.0 0.1'
        'T[1]   = 7.0'
        'transform ='
        '    0.0  -1.0   0.0   10.5'
        '    1.0   0.0   0.0  -20.0'
        '    0.0   0.0   1.0    3.0'
        'fill    = -7'
        sprintf( 'data(:,:,1) = <raw int16 @0+%d>' , 6*2 )
        'data(:,:,2) = <missing>   # unreadable'
        '---' };
  fid = fopen( f , 'w' );
  fwrite( fid , [ strjoin( H.' , newline ) , newline ] , 'char' );
  fwrite( fid , D(:,:,1) , 'int16' );
  fclose( fid );

  addpath( fullfile( fileparts( mfilename( 'fullpath' ) ) , '..' , 'matlab' ) );
  S = read_I3D( f );
  bits = @(x) typecast( double( x(:) ).' , 'uint64' );
  assert( isequal( bits( S.X ) , bits( [0 0.5 1] ) ) , 'dll_selftest:X' , 'X' );
  assert( isequal( bits( S.Y ) , bits( [-1 2.5] ) ) , 'dll_selftest:Y' , 'Y' );
  assert( isequal( bits( S.Z ) , bits( [0 0.1] ) ) , 'dll_selftest:Z' , 'Z' );
  assert( isequal( S.T , 7 ) , 'dll_selftest:T' , 'T' );
  assert( isequal( S.SpatialTransform , [0 -1 0 10.5; 1 0 0 -20; 0 0 1 3; 0 0 0 1] ) , 'dll_selftest:A' , 'transform' );
  assert( isa( S.data , 'int16' ) && isequal( size( S.data ) , [3 2 2] ) , 'dll_selftest:size' , 'data class/size' );
  E = D;  E(:,:,2) = -7;                               % el plano que falta, con fill
  assert( isequal( S.data , E ) , 'dll_selftest:data' , 'data values' );
  assert( ~isfield( S , 'rescale' ) && ~isfield( S , 'window' ) , 'dll_selftest:rw' , 'no rescale/window' );
  % el bloque <missing>, por la API (0-based, hi exclusivo)
  h = calllib( 'i3d' , 'i3d_open' , f );
  [ rc , ~ , nd , lo , hi ] = calllib( 'i3d' , 'i3d_missing_box' , h , 0 , 0 , zeros( 1 , 16 , 'int64' ) , zeros( 1 , 16 , 'int64' ) );
  nm = calllib( 'i3d' , 'i3d_missing_count' , h );  calllib( 'i3d' , 'i3d_close' , h );  clear h
  assert( rc == 0 && nm == 1 && isequal( double( lo(1:nd) ) , [0 0 1 0] ) && isequal( double( hi(1:nd) ) , [3 2 2 1] ) , 'dll_selftest:missing' , 'missing' );

  % y un fichero invalido tiene que dar SU identificador
  fid = fopen( f , 'w' );
  fwrite( fid , [ strjoin( strrep( H.' , 'data(:,:,2) = <missing>' , 'data(:,:,1:2) = <missing>' ) , newline ) , newline ] , 'char' );
  fwrite( fid , D(:,:,1) , 'int16' );  fclose( fid );
  try
    read_I3D( f );  error( 'dll_selftest:noError' , 'an overlapping block was accepted' );
  catch LE
    assert( strcmp( LE.identifier , 'read_I3D:coverage' ) , 'dll_selftest:id' , 'expected read_I3D:coverage, got %s' , LE.identifier );
  end

  % el escritor: en una lista, un comentario vacio no escribe nada (ni el '#')
  w = calllib( 'i3d' , 'i3d_new' );
  WCLEAN = onCleanup( @() calllib( 'i3d' , 'i3d_free' , w ) );
  chk = @( rc ) assert( rc == 0 , 'dll_selftest:write' , '%s' , calllib( 'i3d' , 'i3d_wlast_error' , w ) );
  chk( calllib( 'i3d' , 'i3d_set_data' , w , D , 'int16' , 4 , int64( size( D , 1:4 ) ) ) );
  chk( calllib( 'i3d' , 'i3d_add_info_rows_text' , w , 'some' , 2 , { 'v1' , 'v2' } , { 'c1' , '' } , 1 ) );
  chk( calllib( 'i3d' , 'i3d_add_info_rows_text' , w , 'none' , 2 , { 'n1' , 'n2' } , { '' , '' } , 1 ) );
  chk( calllib( 'i3d' , 'i3d_write' , w , f ) );
  L = strsplit( fileread( f ) , newline );
  row = @( v ) L{ find( contains( L , [ '"' , v , '"' ] ) , 1 ) };
  assert( endsWith( row( 'v1' ) , '"v1"  # c1' ) , 'dll_selftest:rowc' , 'a row comment: %s' , row( 'v1' ) );
  for v = { 'v2' , 'n1' , 'n2' }
    assert( endsWith( strtrim( row( v{1} ) ) , [ '"' , v{1} , '"' ] ) , 'dll_selftest:rowc' , 'an empty row comment wrote something: %s' , row( v{1} ) );
  end
  I = read_I3D( f );
  assert( iscell( I.INFO.some ) && isequal( I.INFO.some(:) , { 'v1' ; 'v2' } ) , 'dll_selftest:rows' , 'info.some does not read back' );
  ok = true;
end

function delete_( f )
  if exist( f , 'file' ), delete( f ); end
end
