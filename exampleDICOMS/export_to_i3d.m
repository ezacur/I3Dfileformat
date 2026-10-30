%EXPORT_TO_I3D   ejemplo completo: de una carpeta de DICOM a .i3d y .mi3d, con calllib
%
% 1. DICOMstackCollect lee exampleDICOMS\ y devuelve los stacks (un DICOMstack
%    por serie/plano, cada uno con su @I3D en .IMAGE).
% 2. Cada stack se exporta a tres carpetas, llamando a i3d.dll con calllib:
%      exported_i3d\        los pixeles dentro del fichero (jpegls/zlib)
%      exported_i3d_lazy\   cada plano, una REFERENCIA a su .dcm (sin copiar pixeles)
%      exported_i3d_t1\     solo el primer instante (t = 1)
%    con el nombre  {%03d SeriesNumber}.{%s SeriesDescription}.i3d
% 3. Por cada StudyInstanceUID, un contenedor exported_mi3d\{StudyInstanceUID}.mi3d
%    con todos los stacks de ese estudio, NO lazy y con todos los instantes. Se
%    hace desde los stacks (no desde los .i3d de 2.): cada uno se escribe a un
%    .i3d temporal y mi3d.dll los junta.
%
% Nada de write_I3D / write_MI3D: solo las dos DLL (matlab\lib\i3d_c.h y
% matlab\lib\mi3d_c.h tienen la API completa). Cada calllib devuelve 0 si va
% bien; si no, el mensaje esta en i3d_wlast_error(w) / mi3d_last_error(NULL).
%
% Usa dos funciones de esta carpeta: exportStackToI3Dfile (las llamadas a
% i3d.dll para un stack) y stackI3Dfilenames (los nombres de los ficheros).

%% ---------------------------------------------------------------- rutas
ROOT = 'C:\repos\I3Dfileformat\exampleDICOMS\';
cd( ROOT )
addpath( 'C:\Dropbox\mTools' );  mTools_SETUP;                    % I3D, parseargs...
addpath( 'C:\Dropbox\mTools\libraries\scratch\DICOM' );           % DICOMstackCollect
addpath( 'C:\repos\I3Dfileformat\matlab' );                       % enableI3Dlibrary (y lib\)

OUT_I3D  = fullfile( ROOT , 'exported_i3d' );
OUT_LAZY = fullfile( ROOT , 'exported_i3d_lazy' );
OUT_T1   = fullfile( ROOT , 'exported_i3d_t1' );
OUT_MI3D = fullfile( ROOT , 'exported_mi3d' );
for d = { OUT_I3D , OUT_LAZY , OUT_T1 , OUT_MI3D }
  if ~exist( d{1} , 'dir' ), mkdir( d{1} ); end
end

%% ---------------------------------------------------------------- los stacks
% 'onlyK': solo el thumbnail del corte (las vistas rotadas son lo caro)
DS = DICOMstackCollect( ROOT , 'onlyK' );
fprintf( '%d stacks\n' , numel( DS ) );

%% ---------------------------------------------------------------- cargar las DLL
enableI3Dlibrary;                    % loadlibrary de i3d.dll y mi3d.dll, como 'i3d' y 'mi3d'

%% ---------------------------------------------------------------- un .i3d por stack, x3
names = stackI3Dfilenames( DS );
for d = 1:numel( DS )
  fname = filename( fixfilename( sprintf('%03d.%s(%s).i3d', DS(d).SeriesNumber , DS(d).SeriesDescription , DS(d).PlaneName{1} ) ) );

  while isfile( fullfile( OUT_I3D , fname ) ), fname = regexprep( fname , '\.i3d$','_.i3d'); end

  chk( calllib( 'i3d' , 'i3d_set_option' , i3dobj , 'Comment' , sprintf( 'export_to_i3d %s (%s)' , datestr( now , 'yyyy-mm-dd HH:MM:SS' ) , modo ) ) );

  I = DS(d).IMAGE;
  C = DS(d).commonINFO;                 % lo comun a todos los planos del stack
  U = DS(d).uids;                       % el SOPInstanceUID de cada plano (k,t)

  i3dobj = calllib( 'i3d' , 'i3d_new' ); CLEAN = onCleanup( @() calllib( 'i3d' , 'i3d_free' , i3dobj ) );

  callinb( 'i3d' , 'i3
  calllib( 'i3d' , 'i3d_set_Xgrid' , i3dobj , double( I.X ) , numel( I.X ) );
  calllib( 'i3d' , 'i3d_set_Ygrid' , i3dobj , double( I.Y ) , numel( I.Y ) );
  calllib( 'i3d' , 'i3d_set_Zgrid' , i3dobj , double( I.Z ) , numel( I.Z ) );
  calllib( 'i3d' , 'i3d_set_Ygrid' , i3dobj , double( I.Y ) , numel( I.T ) );
  calllib( 'i3d' , 'i3d_set_transform' , i3dobj , reshape( double( I.SpatialTransform ).' , 1 , [] ) );   % POR FILAS
  calllib( 'i3d' , 'i3d_set_data' , i3dobj , I.data , class( I.data ) , ndims( I.data ) , size( I.data ) );

  if isfield( I.INFO , 'thumbnailK' ) && isa( I.INFO.thumbnailK , 'uint8' )
    th = I.INFO.thumbnailK;
    chk( calllib( 'i3d' , 'i3d_add_aux' , w , 'thumbnailK' , th , 'uint8' , ndims( th ) , int64( size( th ) ) ) );
  end



  exportStackToI3Dfile( DS(d) , fullfile( OUT_I3D  , fname ) , 'full' );  fprintf( ' i3d' );



  exportStackToI3Dfile( DS(d) , fullfile( OUT_LAZY , names{d} ) , 'lazy' );  fprintf( ' lazy' );
  exportStackToI3Dfile( DS(d) , fullfile( OUT_T1   , names{d} ) , 't1'   );  fprintf( ' t1\n' );
end

%% ---------------------------------------------------------------- un .mi3d por estudio
suid = cell( 1 , numel( DS ) );                  % (arrayfun no sirve sobre un DICOMstack)
for d = 1:numel( DS ), suid{d} = char( DS(d).StudyInstanceUID ); end
TMP = tempname;  mkdir( TMP );                     % los .i3d temporales de los miembros
for S = unique( suid , 'stable' )
  ix = find( strcmp( suid , S{1} ) );
  % cada stack del estudio, a un .i3d temporal: el miembro es ese fichero tal cual
  files = cell( 1 , numel( ix ) );
  for j = 1:numel( ix )
    files{j} = fullfile( TMP , sprintf( 'm%03d.i3d' , j ) );
    exportStackToI3Dfile( DS( ix(j) ) , files{j} , 'full' );
  end
  tags = names( ix );                              % la etiqueta de cada miembro (un comentario)
  f = fullfile( OUT_MI3D , [ S{1} , '.mi3d' ] );
  %   mi3d_write( path , n , files , tags , reserve , comment , lazykeep )
  %   reserve 0: 8192 bytes para que append crezca sin reescribir; comment '': el de defecto
  rc = calllib( 'mi3d' , 'mi3d_write' , f , numel( files ) , files , tags , 0 , '' , 0 );
  if rc, error( 'export_to_i3d:mi3d' , '%s' , calllib( 'mi3d' , 'mi3d_last_error' , [] ) ); end
  delete( files{:} );
  fprintf( 'mi3d: %d stacks -> %s\n' , numel( ix ) , f );
end
rmdir( TMP , 's' );

%% ---------------------------------------------------------------- comprobacion (lectura, tambien por calllib)
% el ultimo .mi3d: cuantos miembros y el tamano de data del primero
m = calllib( 'mi3d' , 'mi3d_open' , f );
if isNull( m ), error( 'export_to_i3d:mi3d' , '%s' , calllib( 'mi3d' , 'mi3d_last_error' , [] ) ); end
N = calllib( 'mi3d' , 'mi3d_count' , m );
[ ~ , ~ , off , len ] = calllib( 'mi3d' , 'mi3d_range' , m , 1 , 0 , 0 );      % sus bytes en el fichero
calllib( 'mi3d' , 'mi3d_close' , m );
r = calllib( 'i3d' , 'i3d_open_window' , f , off , len , 0 , libpointer( 'stringPtrPtr' ) , libpointer( 'stringPtrPtr' ) );
[ ~ , ~ , nd , dims ] = calllib( 'i3d' , 'i3d_data_shape' , r , 0 , zeros( 1 , 16 , 'int64' ) );
calllib( 'i3d' , 'i3d_close' , r );
fprintf( '%s: %d miembros; el 1o es %s\n' , f , N , mat2str( double( dims(1:nd) ) ) );
