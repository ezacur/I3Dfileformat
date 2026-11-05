function R = read_I3D( fname , varargin )
%READ_I3D   lee un fichero .i3d con i3d.dll (calllib)
%
%   R = read_I3D( fname )
%   R = read_I3D( fname , 'Data' , 'first' )                       solo data(:,:,:,1,...)
%   R = read_I3D( fname , 'Data' , 'none' )                        sin data: lo demas
%   R = read_I3D( fname , 'Variables' , { 'DICOMDIR' , 'E:\x' } )  mandan sobre las del fichero
%
%   R.filename            el fichero
%   R.X R.Y R.Z R.T       las rejillas, columnas
%   R.SpatialTransform    la 4x4
%   R.data                el volumen, en su clase: [ I J K T canales... ]
%   R.thumbnail           uint8 {filas cols 1 frames} gris o {filas cols 3 frames} RGB; [] si no hay
%   R.INFO                info.a.b = ... -> R.INFO.a.b, visibles y ocultas:
%                           numeros -> fila double;  textos -> char (uno) o cell (varios)
%                           planes.* y series.* con una fila por plano -> [nK nT]
%                           las $VARIABLES$ ($DICOMDIR$...) ya sustituidas
%
% Un info.* que no se puede leer (cita una variable que no existe, o un $ suelto
% de un fichero antiguo) es un aviso, y no se devuelve.
%
% See also write_I3D.

  [ VARS , DATA ] = options_( varargin{:} );
  loadlibrary_();

  % abrir
  if isempty( VARS ), h = calllib( 'i3d' , 'i3d_open' , fname );
  else,               h = calllib( 'i3d' , 'i3d_open_vars' , fname , int32( size( VARS , 2 ) ) , VARS(1,:) , VARS(2,:) );
  end
  if isNull( h )
    error( [ 'read_I3D:' calllib( 'i3d' , 'i3d_last_error_id' , [] ) ] , '%s' , calllib( 'i3d' , 'i3d_last_error' , [] ) );
  end
  CLEAN = onCleanup( @() calllib( 'i3d' , 'i3d_close' , h ) );

  calli3d = @( api , varargin ) calllib( 'i3d' , [ 'i3d_' , api ] , h , varargin{:} );   % todas llevan el fichero delante
  chk     = @( rc ) chk_( rc , h );

  R = struct( 'filename' , fname );

  % rejillas y transform
  n = calli3d( 'Xgrid_length' );
  [ rc , ~ , R.X ] = calli3d( 'Xgrid_copy' , zeros( n , 1 ) , n );  chk( rc );

  n = calli3d( 'Ygrid_length' );
  [ rc , ~ , R.Y ] = calli3d( 'Ygrid_copy' , zeros( n , 1 ) , n );  chk( rc );

  n = calli3d( 'Zgrid_length' );
  [ rc , ~ , R.Z ] = calli3d( 'Zgrid_copy' , zeros( n , 1 ) , n );  chk( rc );

  n = calli3d( 'Tgrid_length' );
  [ rc , ~ , R.T ] = calli3d( 'Tgrid_copy' , zeros( n , 1 ) , n );  chk( rc );

  [ rc , ~ , M ] = calli3d( 'transform' , zeros( 1 , 16 ) );  chk( rc );
  R.SpatialTransform = reshape( M , 4 , 4 ).';                     % viene POR FILAS

  % data. calllib devuelve un buffer [filas, resto]: se le da la forma con reshape
  [ rc , ~ , nd , siz ] = calli3d( 'data_shape' , 0 , zeros( 1 , 16 , 'int64' ) );  chk( rc );
  siz = double( siz(1:nd) );  siz(end+1:4) = 1;                    % [ I J K T canales... ]
  type = calli3d( 'data_type' );
  switch DATA
    case 'all'
      [ rc , ~ , R.data ] = calli3d( 'read_data' , zeros( prod( siz ) , 1 , type ) , calli3d( 'data_bytes' ) );  chk( rc );
      R.data = reshape( R.data , [ siz , 1 ] );
    case 'first'
      siz(4) = 1;
      [ rc , ~ , R.data ] = calli3d( 'read_first_frame' , zeros( prod( siz ) , 1 , type ) , calli3d( 'first_frame_bytes' ) );  chk( rc );
      R.data = reshape( R.data , [ siz , 1 ] );
    case 'none'
      R.data = [];
  end
  nK = siz(3);  nT = numel( R.T );

  % thumbnail
  R.thumbnail = [];
  [ rc , ~ , nd , tsiz ] = calli3d( 'thumbnail_shape' , 0 , zeros( 1 , 16 , 'int64' ) );  chk( rc );
  if nd > 0
    tsiz = double( tsiz(1:nd) );
    [ rc , ~ , R.thumbnail ] = calli3d( 'thumbnail_read' , zeros( prod( tsiz ) , 1 , 'uint8' ) , prod( tsiz ) );  chk( rc );
    R.thumbnail = reshape( R.thumbnail , [ tsiz , 1 ] );
  end

  % info.*
  R.INFO = struct();
  for i = 0:calli3d( 'info_count' )-1
    key = calli3d( 'info_key'    , i );
    n   = calli3d( 'info_length' , i );
    switch calli3d( 'info_type' , i )
      case 'numbers', [ rc , ~ , v ] = calli3d( 'info_numbers' , i , zeros( 1 , n ) , n );  chk( rc );
      case 'text',    v = arrayfun( @( j ) calli3d( 'info_text' , i , j ) , 0:n-1 , 'un' , 0 );  if n == 1, v = v{1}; end
      case 'other',   v = calli3d( 'info_text' , i , 0 );
      case 'error',   warning( 'read_I3D:info' , 'info.%s not read: %s' , key , calli3d( 'last_error' ) );  continue;
    end
    if startsWith( key , { 'planes.' , 'series.' } ) && n > 1 && n == nK*nT     % una fila por plano, k la mas rapida
      v = reshape( v , nK , nT );
    end
    p = strsplit( key , '.' );
    R.INFO = setfield( R.INFO , p{:} , v );
  end

  clearvars('CLEAN');
end


function [ VARS , DATA ] = options_( varargin )
%OPTIONS_  'Variables' { nombre , valor , ... } -> 2 x n;  'Data' 'all' | 'first' | 'none'
  VARS = cell( 2 , 0 );  DATA = 'all';
  if mod( numel( varargin ) , 2 ), error( 'read_I3D:options' , 'options go in pairs: ''Data'' , ''first''' ); end
  for o = 1:2:numel( varargin )
    switch lower( varargin{o} )
      case 'variables'
        v = varargin{o+1};
        if ~iscellstr( v ) || mod( numel( v ) , 2 ), error( 'read_I3D:options' , '''Variables'' is { name , value , ... }' ); end
        VARS = reshape( v , 2 , [] );
        VARS(1,:) = regexprep( VARS(1,:) , '^\$(.*)\$$' , '$1' );   % 'DICOMDIR' o '$DICOMDIR$'
      case 'data'
        DATA = validatestring( varargin{o+1} , { 'all' , 'first' , 'none' } );
      otherwise
        error( 'read_I3D:options' , 'unknown option ''%s'' (Data, Variables)' , varargin{o} );
    end
  end
end


function loadlibrary_()
%LOADLIBRARY_  i3d.dll de esta carpeta, una vez (lo mismo en write_I3D)
  if libisloaded( 'i3d' ), return; end
  if ~strcmpi( feature( 'DefaultCharacterSet' ) , 'UTF-8' )
    error( 'read_I3D:charset' , 'MATLAB passes strings to the DLL in %s, and it takes UTF-8: set feature(''DefaultCharacterSet'',''UTF-8'').' , feature( 'DefaultCharacterSet' ) );
  end
  old = cd( fileparts( mfilename( 'fullpath' ) ) );  C = onCleanup( @() cd( old ) );
  loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' );
end


function chk_( rc , h )
%CHK_  lo que devuelve una funcion de i3d.dll: 0 bien; si no, error con su mensaje
  if rc == 0, return; end
  error( [ 'read_I3D:' calllib( 'i3d' , 'i3d_last_error_id' , h ) ] , '%s' , calllib( 'i3d' , 'i3d_last_error' , h ) );
end
