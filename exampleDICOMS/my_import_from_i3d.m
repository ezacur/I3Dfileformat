if ~libisloaded( 'i3d' )                                          % i3d.dll y su prototipo, de matlab\
  old = cd( 'C:\repos\I3Dfileformat\matlab' );  loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' );  cd( old );
end

%%

fname = 'C:\datos\estudio\serie.i3d';                            % el .i3d a leer

i3dfile = calllib( 'i3d' , 'i3d_open' , fname );
if isNull( i3dfile ), error( 'i3d_open: %s' , calllib( 'i3d' , 'i3d_last_error' , [] ) ); end
CLEAN = onCleanup( @() calllib( 'i3d' , 'i3d_close' , i3dfile ) );

calli3d = @( api , varargin ) calllib( 'i3d' , [ 'i3d_' , api ] , i3dfile , varargin{:} );   % todas llevan el fichero delante
chk     = @( rc ) assert( rc == 0 , 'i3d:read' , '%s' , calli3d( 'last_error' ) );
R = struct( 'filename' , fname );

%% las props: rejillas, transform, forma y clase de data (sin leer data)
n = calli3d( 'Xgrid_length' );
[~,~,R.X] = calli3d( 'Xgrid_copy' , zeros( n , 1 ) , n );

n = calli3d( 'Ygrid_length' );
[~,~,R.Y] = calli3d( 'Ygrid_copy' , zeros( n , 1 ) , n );

n = calli3d( 'Zgrid_length' );
[~,~,R.Z] = calli3d( 'Zgrid_copy' , zeros( n , 1 ) , n );

n = calli3d( 'Tgrid_length' );
[~,~,R.T] = calli3d( 'Tgrid_copy' , zeros( n , 1 ) , n );

[~,~,R.SpatialTransform] = calli3d( 'transform' , zeros( 1 , 16 ) );
R.SpatialTransform = reshape( R.SpatialTransform , 4 , 4 ).';

[~,~,nd,dims] = calli3d( 'data_shape' , 0 , zeros( 1 , 16 , 'int64' ) );
R.size  = double( dims( 1:nd ) );  R.size(end+1:4) = 1;

% el primer frame, data(:,:,:,1)
[~,~,R.first] = calli3d( 'read_first_frame' , zeros( prod( R.size([1:3,5:end]) ) , 1 , calli3d( 'data_type' ) ) , calli3d( 'first_frame_bytes' ) );
R.first = reshape( R.first , [ R.size(1:3) , 1 , R.size(5:end) ] );

% todo el volumen
[~,~,R.data] = calli3d( 'read_data' , zeros( prod(R.size) , 1 , calli3d( 'data_type' ) ) , calli3d( 'data_bytes' ) );
R.data = reshape( R.data , [ R.size , 1 ] );

%% el thumbnail (uint8 {filas cols 1 frames} gris o {filas cols 3 frames} color; [] si no hay)
[~,~,nd,siz] = calli3d( 'thumbnail_shape' , 0 , zeros( 1 , 16 , 'int64' ) );  siz = double( siz(1:nd) );
if nd > 0
  [~,~,R.thumbnail] = calli3d( 'thumbnail_read' , zeros( prod(siz) , 1 , 'uint8' ) , prod(siz) );
  R.thumbnail = reshape( R.thumbnail , [ siz(:).' , 1 ] );
end

%% las infos: info.a.b = ... -> R.INFO.a.b  (tambien las de la parte oculta)
%   numbers -> fila double      text  -> char (uno) o cell (varios), con $DICOMDIR$... ya sustituida
%   other   -> el texto crudo   error -> un texto que cita una variable que no existe
R.INFO = struct();
for i = 0:calli3d( 'info_count' )-1
  key = calli3d( 'info_key'    , i );
  n   = calli3d( 'info_length' , i );
  switch calli3d( 'info_type' , i )
    case 'numbers', [~,~,v] = calli3d( 'info_numbers' , i , zeros( 1 , n ) , n );
    case 'text',    v = arrayfun( @(j) calli3d( 'info_text' , i , j ) , 0:n-1 , 'un' , 0 );  if n == 1, v = v{1}; end
    case 'other',   v = calli3d( 'info_text' , i , 0 );
    case 'error',   error( 'i3d:info' , '%s' , calli3d( 'last_error' ) );
  end
  % planes.* y series.*: una fila por plano (k la mas rapida) -> [nK nT]
  if startsWith( key , {'planes.','series.'} ) && n > 1 && n == R.size(3)*R.size(4)
    v = reshape( v , R.size(3) , R.size(4) );
  end
  p = strsplit( key , '.' );
  R.INFO = setfield( R.INFO , p{:} , v );
end

%% una info en particular, si existe ([] si no)
% key = 'Modality'; try, val = getfield( R.INFO , curly( strsplit( key , '.' ) ).x ); end

% %% los bloques <missing>: los planos que el fichero no tiene (rellenos con 'fill'); lo/hi 1-based
% R.missing = struct( 'lo' , {} , 'hi' , {} );
% for m = 1:calli3d( 'missing_count' )
%   [ rc , ~ , nd , lo , hi ] = calli3d( 'missing_box' , m - 1 , 0 , zeros( 1 , 16 , 'int64' ) , zeros( 1 , 16 , 'int64' ) );  chk( rc );
%   R.missing(m,1).lo = double( lo( 1:nd ) ) + 1;
%   R.missing(m,1).hi = double( hi( 1:nd ) );
% end

%% cerrar
clear CLEAN
