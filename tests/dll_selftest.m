function ok = dll_selftest()
%DLL_SELFTEST   i3d.dll through calllib: a hand-made .i3d, read back exactly
%
%   ok = dll_selftest()
%
% No usa @I3D ni write_I3D: solo read_I3D (y con el, enableI3Dlibrary y la DLL). Escribe
% a mano un .i3d pequeno, con lo que mas facil es romper -- un
% rango, una lista no uniforme, una matriz no trivial, int16 con negativos, dos
% bloques, un <missing> con fill y un [n] que MIENTE (no se lee) --, y comprueba
% cada cosa bit a bit. Lanza si algo no cuadra.

  f = fullfile( tempdir , sprintf( 'i3d_dll_selftest_%d.i3d' , feature('getpid') ) );
  CLEAN = onCleanup( @() delete_( f ) );

  D = int16( reshape( -6:5 , [3 2 2 1] ) );            % i j k t
  H = { 'I3D 0.1'
        '# dll_selftest'
        'X[999] = 0.0 : 0.5 : 1.0'                     % el [999] no se lee
        'Y[2]   = -1.0 2.5'
        'Z[2]   = 0.0 0.1'
        'T[1]   = 7.0'
        'transform ='
        '    0.0  -1.0   0.0   10.5'
        '    1.0   0.0   0.0  -20.0'
        '    0.0   0.0   1.0    3.0'
        'rescale = 2.0 -1024.0'
        'window  = 40.0 400.0'
        'fill    = -7'
        sprintf( 'data(:,:,1) = <raw int16 @0+%d>' , 6*2 )
        'data(:,:,2) = <missing>   # unreadable'
        '---' };
  fid = fopen( f , 'w' );
  fwrite( fid , [ strjoin( H.' , newline ) , newline ] , 'char' );
  fwrite( fid , D(:,:,1) , 'int16' );
  fclose( fid );

  addpath( fullfile( fileparts( mfilename( 'fullpath' ) ) , '..' , 'matlab' ) );
  [ ~ , S ] = read_I3D( f );
  bits = @(x) typecast( double( x(:) ).' , 'uint64' );
  assert( isequal( bits( S.X ) , bits( [0 0.5 1] ) ) , 'dll_selftest:X' , 'X' );
  assert( isequal( bits( S.Y ) , bits( [-1 2.5] ) ) , 'dll_selftest:Y' , 'Y' );
  assert( isequal( bits( S.Z ) , bits( [0 0.1] ) ) , 'dll_selftest:Z' , 'Z' );
  assert( isequal( S.T , 7 ) , 'dll_selftest:T' , 'T' );
  assert( isequal( S.SpatialTransform , [0 -1 0 10.5; 1 0 0 -20; 0 0 1 3; 0 0 0 1] ) , 'dll_selftest:A' , 'transform' );
  assert( isa( S.data , 'int16' ) && isequal( size( S.data ) , [3 2 2] ) , 'dll_selftest:size' , 'data class/size' );
  E = D;  E(:,:,2) = -7;                               % el plano que falta, con fill
  assert( isequal( S.data , E ) , 'dll_selftest:data' , 'data values' );
  assert( isequal( S.rescale , [2 -1024] ) && isequal( S.window , [40 400] ) , 'dll_selftest:rw' , 'rescale/window' );
  assert( numel( S.missing ) == 1 && isequal( S.missing.lo , [1 1 2 1] ) && isequal( S.missing.hi , [3 2 2 1] ) , 'dll_selftest:missing' , 'missing' );

  % y un fichero invalido tiene que dar SU identificador
  fid = fopen( f , 'w' );
  fwrite( fid , [ strjoin( strrep( H.' , 'data(:,:,2) = <missing>' , 'data(:,:,1:2) = <missing>' ) , newline ) , newline ] , 'char' );
  fwrite( fid , D(:,:,1) , 'int16' );  fclose( fid );
  try
    read_I3D( f );  error( 'dll_selftest:noError' , 'an overlapping block was accepted' );
  catch LE
    assert( strcmp( LE.identifier , 'read_I3D:coverage' ) , 'dll_selftest:id' , 'expected read_I3D:coverage, got %s' , LE.identifier );
  end
  ok = true;
end

function delete_( f )
  if exist( f , 'file' ), delete( f ); end
end
