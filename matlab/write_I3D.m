function write_I3D( I , filename , varargin )
%WRITE_I3D   write an @I3D as an .i3d file in the CANONICAL form of SPEC 9
%
%   write_I3D( I , 'serie.i3d' )
%   write_I3D( I , f , 'Comment' , 'texto' )  el comentario de la 1a linea
%   write_I3D( I , f , 'Blocks' , 'volume' )  todo data en los menos bloques
%   write_I3D( I , f , 'Blocks' , 't' )       un bloque por instante
%   write_I3D( I , f , 'MaxBlockBytes' , n )  el mayor bloque (sin comprimir)
%   write_I3D( I , f , 'Hidden' )             cabecera comprimida y OFUSCADA (I3Db,
%                                             SPEC 1.1): aparta al curioso, NO protege
%   write_I3D( I , f , 'Lazy' )               de un DICOMstack: referencias a los .dcm
%   write_I3D( I , f , 'T1' )                 solo el PRIMER INSTANTE (tambien con 'Lazy')
%
% El formato esta en SPEC.md (raiz del repositorio). QUIEN ESCRIBE es el
% escritor de i3d.dll (cpp/i3d_write.cpp, por calllib: enableI3Dlibrary), que produce
% SOLO la forma canonica (SPEC 9): una sola manera de escribir cada cosa. Esta
% funcion solo le da lo que hay en el @I3D: data, rejillas, transform, y de un
% DICOMstack que atributos van a info.* y cuales a la vista, y que planos son
% referencias ('Lazy'). Los lectores aceptan la gramatica general; un fichero
% canonico no usa atajos. El ENCODING no se elige: lo fija el tipo de data.
%
%   LO QUE SE VE (por defecto): la primera linea, las rejillas, transform,
%               rescale, window, 'header = <hidden @0:b>', TODOS los bloques
%               de data y los aux, una linea en blanco, los info.* de 'Visible'
%               (con los titulos y comentarios que los preceden) y otra linea
%               en blanco. LOS DEMAS info.* y $DICOMDIR$ van a la parte oculta
%               de la cabecera (SPEC 1.2). 'Visible','all': todos los info.* a
%               la vista ($DICOMDIR$ sigue oculto).
%   I3D 0.1 # ...  la primera linea, con el comentario: el de 'Comment', o
%               por defecto "write_I3D <fecha>", y el tamano de data:
%               "write_I3D 2026-10-23 10:00:00, [ 192 x 156 x 14 x 30 ]".
%   X Y Z T     como rango  a : s : b  si la rejilla es uniforme BIT A BIT segun
%               la formula de SPEC 3.1 (a + k*s, dos operaciones), y si no como
%               lista, con el comentario de los pasos al final de su linea.
%               Nunca se redondea una rejilla casi uniforme a uniforme.
%   transform   SIEMPRE las tres filas (12 numeros), tambien si es eye(4) o
%               solo una traslacion; alineadas en el punto, la primera en la
%               misma linea que el '='. DEBAJO, en comentarios de linea: que
%               rotacion es (eje y angulo), y la misma rotacion como tres giros
%               sobre los ejes fijos ("turn a deg about x, then b about y, then
%               c about z"), SOLO si se comprobo que la reconstruye.
%   data        por TIPO: (u)int8, (u)int16 y logical (como uint8) en <jpegls>
%               -- los planos i,j del bloque apilados en UNA imagen de
%               ni x (nj*planos), como mucho 65535 filas (SPEC 4) --; cualquier
%               otro tipo en <zlib>. Los dos con
%               'Blocks','auto' (default): el PRIMER INSTANTE en su bloque y los
%               demas en los MENOS bloques que quepan ('MaxBlockBytes': 2^31-9,
%               el tope de los arrays de Java con los que se escribia antes, que
%               se conserva para que los ficheros no cambien); un instante que no cabe se parte
%               por k. Con 'Lazy', <dicom>: un bloque por .dcm.
%               SUBINDICES COMPLETOS, siempre: i, j, k, t y cada dimension de
%               componente; n si es un indice, ':' si es la dimension entera,
%               a:b si no (nunca a: ni :b); las de componente siempre n o 1:n:
%                 data(:,:,:,1)    = <zlib single @0:1830219>   # el 1er instante
%                 data(:,:,:,2:25) = <zlib single @1830220:42042096>
%                 data(:,:,:,1)    = <jpegls int16 @0:91234>    # (otro fichero, int16)
%               Offsets SIEMPRE  @a:b , INCLUSIVOS como en MATLAB: b es el
%               ultimo byte del bloque.
%   crc         SIEMPRE (forma canonica, 2026-10-14): cada bloque con datos --
%               jpegls, zlib, dicom -- y cada aux lleva  crc XXXXXXXX , el
%               CRC-32 de zlib de sus bytes DECODIFICADOS (el sub-array en su
%               tipo, little-endian, orden columna), no de los del fichero. En
%               un <dicom>, el de SU plano de I.data: si el .dcm cambia, o otro
%               lector lo decodifica distinto, sale badCRC. <missing>, ninguno.
%               Los bytes de un bloque, en orden columna i j k t c (el de
%               @I3D; el formato no admite otro). El tamano y la clase, en un
%               comentario al final de la primera linea de data.
%   [n]         el numero de elementos de cada rejilla, X[255]: anotacion para
%               humanos, el lector no la lee (SPEC 2).
%
%   aux.*       cada I.INFO.thumbnail* uint8 gris {filas cols 1 frames} como UNA
%               imagen <png> de filas x (cols*frames), los frames uno al lado de
%               otro (SPEC 7). Un thumbnail que no es uint8 gris no se escribe:
%               sale como comentario "skipped".
%   rescale, window   de un DICOMstack, si son COMUNES a toda la serie.
%   info.*      de un DICOMstack ('Info', abajo): por defecto TODO lo comun del
%               stack, en bloques comentados como el display de DICOMstack
%               (# -- Patient, Study, Series, Image, Device, Dates and times,
%               UIDs and IDs, Acquisition and others), cada Date con su Time.
%               Los nombres DICOM (PatientName...) en su forma de texto
%               "Familia^Nombre". info.PlaneName, el plano que DICOMstack ADIVINA
%               de ImageOrientationPatient, marcado como tal. Lo que no se puede
%               escribir (caracteres de control, secuencias) sale como
%               comentario "skipped". Y lo que NO es comun: la tabla de series
%               (info.series.*) y, por plano, su serie, su SOPInstanceUID y su
%               AcquisitionTime (info.planes.*), un valor por fila.
%
% Todavia NO escribe: fill.
%
% NUMEROS: los doubles, en la forma mas corta exacta, con ".0" (num2strI3D,
% de la DLL); MEDIDO contra Python en tests/check_num2str.m.
%
% ENTRADA
%   I         un @I3D con data numerico o logico, en memoria (ni vacio, ni
%             desreferenciado -- data como celda --, ni en GPU)
%   filename  char
%
% POR QUE jpegls para los enteros de 8/16 bits: MEDIDO en series reales
% (bench/real_jpegls_results.txt), 1.2-1.8x mas pequeno que zlib y 5-16x mas
% rapido de escribir. Los demas tipos no caben en JPEG-LS: zlib.
%
% LIMITACIONES
%   - logical se escribe como uint8 0/1 (SPEC 4, [OPEN]).
%   - complejos: no.
%   - los bloques se trocean a 'MaxBlockBytes' (2^31-9 por defecto). Un solo
%     plano i,j mayor que eso es un error.
%   - la DLL COPIA data (i3d_set_data): escribir pide el doble de memoria.
%
% OPCIONES (ademas de las de arriba)
%   'Verify' , tf     con 'Lazy' (default true): cada referencia se comprueba con
%                     el lector de la DLL; un plano que no da exactamente I.data se
%                     materializa. Con false, un @I3D modificado despues de leerlo
%                     referenciaria los pixeles ORIGINALES sin aviso.
%   'Visible' , L     los atributos info.* que quedan a la vista ('*' comodin);
%                     default: StudyDate StudyTime StudyDescription
%                     SeriesDescription DeviceSerialNumber Manufacturer
%                     ManufacturerModelName ImplementationVersionName
%                     InstitutionName InstitutionAddress. 'all': todos. Los
%                     demas van a la PARTE OCULTA de la cabecera (SPEC 1.2):
%                     ofuscados como I3Db en un bloque <hidden>, el PRIMERO del
%                     binario, y en su sitio 'header = <hidden @0:b>'. Se combina
%                     con 'Hidden': un volcado de la cabecera I3Db tampoco los
%                     muestra. Aparta al curioso; NO protege. (Es lo que hace
%                     i3d_add_info_* con visible 1 o 0: lo decide esta funcion)
%   'DicomDir' , p    el valor de $DICOMDIR$ (default: la raiz comun de los .dcm)
%   'Info' , L        'auto' (default) | lista de atributos | {} (ninguno)
%   'T1'              solo data(:,:,:,1,..) y T(1), como escribir I.t1, pero
%                     recortando TAMBIEN el DICOMstack de I.INFO (ffiles, uids,
%                     infos...) al primer instante: I.t1 solo recorta data, y
%                     con el stack entero 'Lazy' da lazyMismatch e info.planes
%                     se salta. El stack se recorta con DICOMstack.t(1), que
%                     recalcula commonINFO para ese instante; si eso quitara
%                     planos (t(1) descarta los que no tienen fichero), se
%                     recorta (:,1) tal cual. Los thumbnails (INFO.thumbnail*)
%                     NO se tocan: siguen siendo la animacion de toda la serie.
%
% ERROR IDENTIFIERS
%   write_I3D:notI3D        I no es un @I3D
%   write_I3D:badData       data vacio, desreferenciado, en GPU, complejo o de
%                           una clase no soportada
%   write_I3D:badGrid       una rejilla no es estrictamente creciente o no es
%                           finita
%   write_I3D:badTransform  la cuarta fila de SpatialTransform no es 0 0 0 1
%   write_I3D:badEncoding   se paso un encoding ('raw','zlib','jpegls'): ya no
%                           se elige, lo fija el tipo (forma canonica)
%   write_I3D:badOption     'Comment' no es una linea sin caracteres de control,
%                           'Blocks' no es 'auto', 'volume' ni 't',
%                           'MaxBlockBytes' no es positivo o es menor que un
%                           plano i,j, o se paso 'CRC' (ya no es una opcion: el
%                           crc va siempre)
%   write_I3D:cannotOpen    no se puede crear el fichero
%   write_I3D:notLazy       'Lazy' sin DICOMstack, o con mas de un componente
%   write_I3D:lazyMismatch  DICOMstack.ffiles no cuadra con el tamano de data
%   write_I3D:rescaleNotCommon  el rescale cambia de corte a corte: el formato
%                           tiene UNO para todo el stack (SPEC 6)
%   write_I3D:<id>          cualquier otro error de la DLL (badInput,
%                           internal...), con su identificador
%
% See also read_I3D, enableI3Dlibrary, num2strI3D, I3D.

  if ~isa( I , 'I3D' ), error('write_I3D:notI3D','I must be an I3D.'); end
  % la forma canonica fija el encoding por tipo: pasarlo es un error, no un
  % argumento que se ignora en silencio
  if ~isempty( varargin ) && ischar( varargin{1} ) && any( strcmpi( varargin{1} , {'raw','zlib','jpegls'} ) )
    error('write_I3D:badEncoding','the encoding is not chosen: the canonical form (SPEC 9) uses jpegls for (u)int8/(u)int16 and zlib otherwise.');
  end

  defCOMMENT = sprintf( 'write_I3D %s' , datestr( now , 'yyyy-mm-dd HH:MM:SS' ) );
  COMMENT = defCOMMENT;
  try, [ varargin , ~ , COMMENT ] = parseargs( varargin , 'Comment' , '$DEFS$' , defCOMMENT ); end
  defBLOCKS = 'auto';
  BLOCKS = defBLOCKS;
  try, [ varargin , ~ , BLOCKS ] = parseargs( varargin , 'Blocks' , '$DEFS$' , defBLOCKS ); end
  % el mayor bloque, sin comprimir. Es una opcion para poder PROBAR el troceado
  % con datos chicos
  defMAXB = [];
  MAXB = defMAXB;
  try, [ varargin , ~ , MAXB ] = parseargs( varargin , 'MaxBlockBytes' , '$DEFS$' , defMAXB ); end
  % el crc ya no es una opcion (2026-10-14): va SIEMPRE, de los bytes
  % decodificados. Pasar 'CRC' es un error, no algo que se ignora en silencio
  if any( cellfun( @(a) ischar( a ) && strcmpi( a , 'CRC' ) , varargin ) )
    error('write_I3D:badOption','''CRC'' is no longer an option: the canonical form (SPEC 9) has a crc on every block, always.');
  end
  % 'Lazy': si I viene de un DICOMstack, cada plano es una REFERENCIA a su .dcm
  defLAZY = false;
  LAZY = defLAZY;
  try, [ varargin , LAZY ] = parseargs( varargin , 'Lazy' , '$FORCE$' , { true , defLAZY } ); end
  % 'Verify' (default true): la DLL lee cada .dcm y lo referencia SOLO si da
  % exactamente ese plano de I.data
  defVERIFY = true;
  VERIFY = defVERIFY;
  try, [ varargin , ~ , VERIFY ] = parseargs( varargin , 'Verify' , '$DEFS$' , defVERIFY ); end
  % 'DicomDir': el valor de $DICOMDIR$ (default: la raiz comun de los .dcm)
  defDDIR = '';
  DDIR = defDDIR;
  try, [ varargin , ~ , DDIR ] = parseargs( varargin , 'DicomDir' , '$DEFS$' , defDDIR ); end
  % 'Hidden': la cabecera comprimida y OFUSCADA (I3Db, SPEC 1.1). No protege:
  % solo aparta al curioso con un editor de texto. El binario no cambia
  defHIDDEN = false;
  HIDDEN = defHIDDEN;
  try, [ varargin , HIDDEN ] = parseargs( varargin , 'Hidden' , '$FORCE$' , { true , defHIDDEN } ); end
  % 'Info': los atributos DICOM que van a info.* (si I viene de un DICOMstack).
  % Default 'auto': TODO lo comun del stack, por bloques como el display de
  % DICOMstack (info_); una lista = solo esos; {} = ninguno
  defINFO = 'auto';
  INFOL = defINFO;
  try, [ varargin , ~ , INFOL ] = parseargs( varargin , 'Info' , '$DEFS$' , defINFO ); end
  % 'T1': solo el primer instante, con su DICOMstack recortado igual (t1_)
  defT1 = false;
  T1 = defT1;
  try, [ varargin , T1 ] = parseargs( varargin , 'T1' , '$FORCE$' , { true , defT1 } ); end
  % 'Visible': los atributos info.* que quedan A LA VISTA; todo lo demas que no
  % necesita un visor va a la parte oculta (SPEC 1.2). 'all' = nada oculto por
  % defecto. El default, estos 10: que es, cuando, y con que maquina y donde
  defVIS = { 'StudyDate' 'StudyTime' 'StudyDescription' 'SeriesDescription' 'DeviceSerialNumber' ...
             'Manufacturer' 'ManufacturerModelName' 'ImplementationVersionName' 'InstitutionName' 'InstitutionAddress' };
  VIS = '$default$';
  try, [ varargin , ~ , VIS ] = parseargs( varargin , 'Visible' , '$DEFS$' , '$default$' ); end
  if ischar( VIS ) && strcmp( VIS , '$default$' ), VIS = defVIS; end
  if ischar( VIS ) && ~strcmp( VIS , 'all' ), VIS = { VIS }; end
  if ~( ( ischar( VIS ) && strcmp( VIS , 'all' ) ) || iscellstr( VIS ) )
    error('write_I3D:badOption','Visible must be ''all'' or a list of info.* names (''StudyDate'', ''Study*'').');
  end
  if ~isempty( varargin ), error('write_I3D:badOption','unrecognised arguments.'); end
  if T1, [ I , ntall ] = t1_( I ); end
  % la cabecera es UTF-8 (SPEC 1): cualquier caracter salvo los de control
  if ~ischar( COMMENT ) || ( ~isempty( COMMENT ) && size( COMMENT , 1 ) ~= 1 ) || any( COMMENT < 32 | COMMENT == 127 )
    error('write_I3D:badOption','Comment must be one line with no control characters.');
  end
  if ~ischar( BLOCKS ) || ~any( strcmp( BLOCKS , {'auto','volume','t'} ) )
    error('write_I3D:badOption','Blocks must be ''auto'', ''volume'' or ''t''.');
  end
  if isempty( MAXB ), MAXB = 2^31 - 1 - 8; end       % zlib y jpegls (Lazy: un bloque por .dcm)
  if ~isnumeric( MAXB ) || ~isscalar( MAXB ) || ~( MAXB >= 1 )
    error('write_I3D:badOption','MaxBlockBytes must be a positive number.');
  end

  % ---------------------------------------------------------------- data
  D = I.DATA;                            % .DATA y no .data: .data devuelve {} si
                                         % esta desreferenciado, y se veria vacio
  if iscell( D ),   error('write_I3D:badData','data is dereferenced (a POINTER recipe): materialise it first.'); end
  if isempty( D ),  error('write_I3D:badData','data is empty.'); end
  if isa( D , 'gpuArray' ), error('write_I3D:badData','data is on the GPU: bring it to the host first.'); end
  if ~isreal( D ),  error('write_I3D:badData','complex data is not supported.'); end
  if islogical( D ), D = uint8( D ); end
  types = { 'int8','uint8','int16','uint16','int32','uint32','int64','uint64','single','double' };
  if ~any( strcmp( class(D) , types ) )
    error('write_I3D:badData','data of class %s is not supported.', class(D) );
  end
  A = I.SpatialTransform;
  if ~isequal( size( A ) , [4 4] ), error('write_I3D:badTransform','SpatialTransform must be 4 x 4.'); end
  sz = size( D );  sz(end+1:5) = 1;

  % ---------------------------------------------------------------- i3d.dll
  % todo lo del formato lo decide el escritor de la DLL (SPEC 9); aqui solo se
  % le da lo que hay en el @I3D. Cada llamada devuelve 0, o el error
  enableI3Dlibrary;
  w = calllib( 'i3d' , 'i3d_new' );
  CW = onCleanup( @() calllib( 'i3d' , 'i3d_free' , w ) );
  chk = @( rc ) rc == 0 || i3d_err_( 'write_I3D' , 'w' , w );
  opt = @( n , v ) chk( calllib( 'i3d' , 'i3d_set_option' , w , n , v ) );
  opt( 'Comment' , COMMENT );
  opt( 'Blocks' , BLOCKS );
  opt( 'MaxBlockBytes' , sprintf( '%.17g' , MAXB ) );
  if HIDDEN, opt( 'Hidden' , '1' ); end
  % la visibilidad de un info.* (SPEC 1.2), el argumento visible de i3d_add_info_*:
  % 1, a la vista, si es de 'Visible' (o 'all'); 0, a la parte oculta
  visall = ischar( VIS ) && strcmp( VIS , 'all' );
  if visall, reV = {}; else, reV = cellfun( @(p) [ '^' , regexptranslate( 'wildcard' , [ 'info.' , p ] ) , '$' ] , VIS , 'un' , 0 ); end
  visf = @( k ) double( visall || any( ~cellfun( 'isempty' , regexp( k , reV , 'once' ) ) ) );

  chk( calllib( 'i3d' , 'i3d_set_data' , w , D , class( D ) , ndims( D ) , int64( size( D ) ) ) );
  for a = 'XYZT'
    v = double( I.( a ) );
    chk( calllib( 'i3d' , [ 'i3d_set_' , a , 'grid' ] , w , v(:).' , numel( v ) ) );     % i3d_set_Xgrid ...
  end
  % un comentario sale ENCIMA de lo siguiente que se da: este, detras de las
  % rejillas y encima de transform
  if T1 && ntall > 1
    chk( calllib( 'i3d' , 'i3d_add_comment' , w , sprintf( 'T1: only the first of %d instants (the thumbnails keep them all)' , ntall ) ) );
  end
  chk( calllib( 'i3d' , 'i3d_set_transform' , w , reshape( double( A ).' , 1 , [] ) ) );      % POR FILAS
  % lo que viene del DICOMstack y de I.INFO: rescale/window, thumbnails, info.*
  emit_( w , chk , meta_( I , INFOL , visf ) );
  % lo que NO es comun al stack: las series y, por plano, la serie, el UID de la
  % imagen y su hora (decidido 2026-10-13). Con 'Info' por defecto
  if ischar( INFOL ) && strcmp( INFOL , 'auto' ) && isstruct( I.INFO ) && isfield( I.INFO , 'DICOMstack' )
    emit_( w , chk , planes_( I.INFO.DICOMstack , sz(3) , sz(4) , visf ) );
  end

  % 'Lazy': cada plano, una REFERENCIA a su .dcm si se puede (lazy_); los que no
  % tienen fichero, <missing> o materializados (lo decide la DLL)
  if LAZY
    REF = lazy_( I , D , sz , prod( sz(5:end) ) );
    opt( 'Lazy' , '1' );
    opt( 'Verify' , sprintf( '%d' , logical( VERIFY ) ) );
    if ~isempty( DDIR ), opt( 'DicomDir' , DDIR ); end
    for t = 1:sz(4)
      for k = 1:sz(3)
        if ~isempty( REF{k,t} ) || isempty( I.INFO.DICOMstack.ffiles{k,t} )
          chk( calllib( 'i3d' , 'i3d_set_plane_ref' , w , k , t , REF{k,t} ) );
        end
      end
    end
  end

  % todo o nada: un fallo a mitad no deja un .i3d truncado
  chk( calllib( 'i3d' , 'i3d_write' , w , filename ) );
end

% ======================================================================
function emit_( w , chk , ops )
%EMIT_  las llamadas a la DLL de ops: cada una { funcion , argumentos... } (sin w)
  for q = 1:numel( ops )
    chk( calllib( 'i3d' , ops{q}{1} , w , ops{q}{2:end} ) );
  end
end

function c = cmt_( text )
%CMT_  una linea '# text' encima de lo siguiente que se da (aqui, un info.*)
  c = { 'i3d_add_comment' , text };
end

% ======================================================================
function ops = info_( DS , INFOL , visf )
%INFO_  las llamadas para los info.* de un DICOMstack
%
% FUENTES. Lo COMUN a todos los cortes del stack (commonINFO). Y solo para los
% bloques Patient, Study y Device -- que no cambian entre las series de un
% estudio, aunque el stack sea una fusion de varias --, si no estan ahi, el
% PRIMER fichero (marcado "# from the first file"). Nunca un atributo de corte
% (SOPInstanceUID, InstanceNumber, ImagePositionPatient...) como si fuera del
% stack: no son comunes, y no salen.
%
% 'auto' (default): todo lo comun, por bloques en el orden del display de
% DICOMstack -- Patient, Study, Series, Image, Device, fechas --, y detras los
% UIDs/IDs y el resto. Cada Date con su Time al lado. Fuera (group_ = 0): lo que
% no es un atributo DICOM (Private_*, los x* que calcula DICOMstack, lo que
% anade dicominfo: Filename, FileModDate, Width, BitDepth...), la geometria (esta
% en X Y Z y transform), la codificacion del pixel (la da el tipo de data) y
% rescale/window (son claves propias).
% Una lista: exactamente esos atributos, en ese orden, sin bloques.
  ops = {};
  C = struct();  try, C = DS.commonINFO; end
  if ~isstruct( C ), C = struct(); end
  H1 = struct();
  try
    F = DS.ffiles;  H1 = dicominfo( F{ find( ~cellfun( 'isempty' , F ) , 1 ) } );
  end

  if ischar( INFOL ) && strcmp( INFOL , 'auto' )
    names = fieldnames( C ).';
    extra = setdiff( fieldnames( H1 ).' , names , 'stable' );
    extra = extra( ismember( cellfun( @group_ , extra ) , [1 2 5] ) );
    names = [ names , extra ];
    g = cellfun( @group_ , names );
    TITLES = { 'Patient' , 'Study' , 'Series' , 'Image' , 'Device' , 'Dates and times' , 'UIDs and IDs' , 'Acquisition and others' };
    done = {};
    for b = 1:8
      lines = {};
      if b == 4, lines = plane_( DS , visf ); end
      for a = order_( names( g == b ) , b )
        if any( strcmp( a{1} , done ) ), continue; end
        [ lines , done ] = line_( lines , done , a{1} , C , H1 , visf );
        % la Time de una Date, justo detras (como en el display de DICOMstack)
        if endsWith( a{1} , 'Date' )
          t = [ a{1}(1:end-4) , 'Time' ];
          if any( strcmp( t , names ) ) && ~any( strcmp( t , done ) ), [ lines , done ] = line_( lines , done , t , C , H1 , visf ); end
        end
      end
      if ~isempty( lines ), ops = [ ops , { cmt_( sprintf( '-- %s' , TITLES{b} ) ) } , lines ]; end %#ok<AGROW>
    end
    return;
  end

  if isempty( INFOL ), return; end
  if ischar( INFOL ), INFOL = { INFOL }; end
  done = {};
  for a = INFOL(:).'
    if strcmp( a{1} , 'PlaneName' ), ops = [ ops , plane_( DS , visf ) ]; continue; end %#ok<AGROW>
    if isfield( C , a{1} ) || ( isfield( H1 , a{1} ) && any( group_( a{1} ) == [1 2 5] ) )
      [ ops , done ] = line_( ops , done , a{1} , C , H1 , visf );
    end
  end
end

function ops = planes_( DS , nk , nt , visf )
%PLANES_  las series del stack y, por plano, a cual pertenece, el UID de su
% imagen y su hora (SPEC 7). UN VALOR POR FILA; las de una serie dicen cual es,
% las de un plano dicen su bloque de data (lo pone la DLL):
%
%   # -- Series and planes (planes: k fastest, then t)
%   info.series.SeriesInstanceUID  = "1.3...503"   # series 1
%                                    "1.3...611"   # series 2
%   info.planes.series             = 1             # data(:,:,1,1)
%                                    1             # data(:,:,2,1)
%   info.planes.SOPInstanceUID     = "1.3...516"   # data(:,:,1,1)
%   ...
%   info.planes.AcquisitionTime    ...             (y AcquisitionDate SOLO si no
%                                                   es comun al stack)
% Indice de serie 0 y "" = plano sin fichero.
%
% El plano (k,t) es DS.uids{k,t} / DS.infos{k,t} (I3D de DICOMstack: la k es la z,
% la t es la t). Un atributo de un plano: el de su infos, o si no el comun
% (commonINFO: DICOMstack quita de infos lo que es comun). El UID de la imagen
% es el MediaStorageSOPInstanceUID con el que DICOMstack agrupa, que por la
% norma es el SOPInstanceUID. Si el stack ya no cuadra con data, nada y un
% comentario.
  ops = {};
  U = DS.uids;
  if ~iscell( U ) || size( U , 1 ) ~= nk || size( U , 2 ) ~= nt
    ops = { cmt_( sprintf( 'info.series / info.planes skipped: DICOMstack has %s planes, data %d x %d' , mat2str( size( U ) ) , nk , nt ) ) };
    return;
  end
  C = struct();  try, C = DS.commonINFO; end
  if ~isstruct( C ), C = struct(); end
  n = nk * nt;
  at = @( q , a ) att_( DS.infos , C , q , a );
  has = ~cellfun( 'isempty' , U(:) ).';                % los planos con fichero
  if ~any( has ), ops = { cmt_( 'info.series / info.planes skipped: no plane has a file' ) }; return; end

  % la tabla de series, por orden de aparicion; y el indice de cada plano
  suid = repmat( {''} , 1 , n );
  for q = find( has ), suid{q} = char( at( q ,'SeriesInstanceUID' ) ); end
  [ S , ~ , ix ] = unique( suid( has ) , 'stable' );
  idx = zeros( 1 , n );  idx( has ) = ix;
  first = arrayfun( @(s) find( idx == s , 1 ) , 1:numel( S ) );
  cs = arrayfun( @(s) sprintf( 'series %d' , s ) , 1:numel( S ) , 'un' , 0 );
  NOC = libpointer( 'stringPtrPtr' );                 % sin comentarios: los de cada plano, de la DLL

  ops{end+1} = cmt_( '-- Series and planes (planes: k fastest, then t)' );
  ops = [ ops , rows_( 'series.SeriesInstanceUID' , strs_( S ) , cs , visf ) ];
  sn = arrayfun( @(q) at( q ,'SeriesNumber' ) , first , 'un' , 0 );
  if all( cellfun( @(v) isnumeric( v ) && isscalar( v ) , sn ) )
    ops{end+1} = { 'i3d_add_info_rows_numbers' , 'series.SeriesNumber' , numel( sn ) , cellfun( @double , sn ) , 0 , cs , visf( 'info.series.SeriesNumber' ) };
  end
  sd = arrayfun( @(q) at( q ,'SeriesDescription' ) , first , 'un' , 0 );
  ops = [ ops , rows_( 'series.SeriesDescription' , strs_( sd ) , cs , visf ) ];
  ops{end+1} = { 'i3d_add_info_rows_numbers' , 'planes.series' , n , idx , 1 , NOC , visf( 'info.planes.series' ) };
  sop = U(:).';  sop( ~has ) = {''};
  ops = [ ops , rows_( 'planes.SOPInstanceUID' , strs_( sop ) , NOC , visf ) ];
  % las horas, y la fecha solo si NO es comun al stack (si lo es, ya esta en
  % info.AcquisitionDate)
  for a = { 'AcquisitionTime' , 'AcquisitionDate' }
    if strcmp( a{1} , 'AcquisitionDate' ) && isfield( C , 'AcquisitionDate' ), continue; end
    v = repmat( {''} , 1 , n );
    for q = find( has ), x = at( q ,a{1} ); if ischar( x ), v{q} = x; end, end
    if all( cellfun( 'isempty' , v ) ), continue; end   % nadie lo tiene
    ops = [ ops , rows_( [ 'planes.' , a{1} ] , strs_( v ) , NOC , visf ) ];
  end
end

function ops = rows_( key , T , Cm , visf )
%ROWS_  una lista de cadenas con UN VALOR POR FILA (Cm: un comentario por fila, o
% NULL: los de cada plano); o un comentario si no se puede escribir
  if isempty( T ), ops = { cmt_( sprintf( 'info.%s skipped: a value has control characters' , key ) ) }; return; end
  ops = { { 'i3d_add_info_rows_text' , key , numel( T ) , T , Cm , visf( [ 'info.' , key ] ) } };
end

function v = att_( infos , C , q , a )
%ATT_  el atributo a del plano q: el de su infos, o si no el comun; '' si ninguno
  v = '';
  P = infos{q};
  if isstruct( P ) && isfield( P , a ), v = P.(a);
  elseif isfield( C , a ),              v = C.(a);
  end
end

function T = strs_( c )
%STRS_  cadenas listas para la DLL (sin espacios a los lados); {} si alguna tiene
% caracteres de control
  T = cell( 1 , numel( c ) );
  for k = 1:numel( c )
    [ s , why ] = value_( char( c{k} ) );
    if ~isempty( why ), T = {};  return; end
    T{k} = s;
  end
end

function ops = plane_( DS , visf )
%PLANE_  info.PlaneName: el nombre del plano de adquisicion que da DICOMstack.
% NO es un atributo DICOM: DICOMstack lo calcula de ImageOrientationPatient --
% 'AX'/'COR'/'SAG' si el plano es cardinal a 1e-3 rad, y si no la vista
% cardiaca mas cercana ('hla','vla','lvot','sa') SIN umbral de distancia --, y
% el comentario lo dice para que nadie lo lea como un dato del escaner
  ops = {};
  try
    p = DS.PlaneName;  if iscell( p ), p = p{1}; end
    [ s , why , ~ , isnum ] = value_( p );
    if isempty( why ) && ~isnum
      ops = { { 'i3d_add_info_text' , 'PlaneName' , s , visf( 'info.PlaneName' ) , 'guessed by DICOMstack from ImageOrientationPatient' } };
    end
  end
end

function [ ops , done ] = line_( ops , done , a , C , H1 , visf )
%LINE_  la llamada para info.a , de commonINFO o si no del primer fichero
% (marcada); o un comentario que dice por que no sale
  done{end+1} = a;
  if isfield( C , a ), v = C.(a); src = '';
  else,                v = H1.(a); src = 'from the first file';
  end
  [ s , why , absent , isnum ] = value_( v );
  if absent,             return;                     % los ficheros no lo tienen: ni linea ni comentario
  elseif ~isempty( why ), ops{end+1} = cmt_( sprintf( 'info.%s skipped: %s' , a , why ) );
  elseif isnum,          ops{end+1} = { 'i3d_add_info_numbers' , a , s , numel( s ) , visf( [ 'info.' , a ] ) , src };
  else,                  ops{end+1} = { 'i3d_add_info_text' , a , s , visf( [ 'info.' , a ] ) , src };
  end
end

function [ IMG , DEV ] = display_lists_()
%DISPLAY_LISTS_  los bloques Image y Device del display de DICOMstack, en su orden
  IMG = { 'InstanceNumber' 'ImageType' 'SliceLocation' 'Modality' 'ProtocolName' 'MRAcquisitionType' 'SequenceName' ...
          'PerformedProcedureStepDescription' 'BodyPartExamined' 'RequestedProcedureDescription' 'AcquisitionNumber' ...
          'ScanningSequence' 'SequenceVariant' 'ScanOptions' 'ContrastBolusAgent' 'SliceThickness' };
  DEV = { 'DeviceSerialNumber' 'Manufacturer' 'ManufacturerModelName' 'ImplementationVersionName' 'InstitutionName' ...
          'InstitutionalDepartmentName' 'InstitutionAddress' 'StationName' 'RequestingPhysician' 'RequestingService' ...
          'ReferringPhysicianName' 'PerformingPhysicianName' 'NameOfPhysiciansReadingStudy' 'OperatorsName' ...
          'SoftwareVersions' 'DerivationDescription' 'SourceApplicationEntityTitle' };
end

function b = group_( a )
%GROUP_  el bloque de un atributo en info_ (0 = no va). Con los criterios del
% display de DICOMstack: lo que nombra Patient, Study o Series va a su bloque
% antes que a ningun otro, asi PatientID es de Patient y StudyInstanceUID de Study
  persistent OUT IMG DEV
  if isempty( OUT )
    OUT = { 'Filename' 'FileModDate' 'FileSize' 'Format' 'FormatVersion' 'Width' 'Height' 'BitDepth' 'ColorType' ...   % de dicominfo, no DICOM
            'FileMetaInformationGroupLength' 'FileMetaInformationVersion' ...
            'Rows' 'Columns' 'PixelSpacing' 'ImageOrientationPatient' 'ImagePositionPatient' ...                         % en X Y Z y transform
            'SamplesPerPixel' 'BitsAllocated' 'BitsStored' 'HighBit' 'PixelRepresentation' 'PlanarConfiguration' ...      % el tipo de data
            'RescaleSlope' 'RescaleIntercept' 'RescaleType' 'WindowCenter' 'WindowWidth' 'WindowCenterWidthExplanation' };  % claves propias
    % PhotometricInterpretation SI va: con MONOCHROME1 el blanco es 0
    [ IMG , DEV ] = display_lists_();
  end
  b = 0;
  if any( strcmp( a , OUT ) ) || strncmp( a , 'Private_' , 8 ) || ( numel( a ) > 1 && a(1) == 'x' && isstrprop( a(2) , 'upper' ) )
    return;
  end
  if     contains( a , 'Patient' ) || any( strcmp( a , { 'DeidentificationMethod' 'PregnancyStatus' 'AdmissionID' } ) ), b = 1;
  elseif contains( a , 'Study' ),   b = 2;
  elseif contains( a , 'Series' ),  b = 3;
  elseif any( strcmp( a , IMG ) ) || contains( a , 'Image' ), b = 4;
  elseif any( strcmp( a , DEV ) ),  b = 5;
  elseif endsWith( a , 'Date' ) || endsWith( a , 'DateTime' ), b = 6;
  elseif endsWith( a , 'UID' ) || endsWith( a , 'ID' ) || strcmp( a , 'AccessionNumber' ), b = 7;
  else,                             b = 8;
  end
end

function L = order_( L , b )
%ORDER_  dentro de un bloque: Image y Device, en el orden de la lista del display;
% los demas, las fechas primero (como el display) y luego el orden del fichero
  if b == 4 || b == 5
    [ IMG , DEV ] = display_lists_();
    if b == 4, R = IMG; else, R = DEV; end
    L = [ R( ismember( R , L ) ) , L( ~ismember( L , R ) ) ];
  else
    d = contains( L , 'Date' );
    L = [ L(d) , L(~d) ];
  end
end

% ======================================================================
function ops = meta_( I , INFOL , visf )
%META_  las llamadas para lo que viene de I.INFO: los thumbnails (cualquier
% INFO.thumbnail* numerico) como aux, rescale/window e info.* (si hay DICOMstack)
  ops = {};
  INFO = I.INFO;
  if ~isstruct( INFO ), return; end

  % thumbnails: tal cual los tiene MATLAB (dim 1 = filas, dim 2 = columnas, ...).
  % Uno que no es uint8 gris lo deja la DLL como un comentario "skipped"
  for f = fieldnames( INFO ).', f = f{1};
    v = INFO.(f);
    if strncmp( f , 'thumbnail' , 9 ) && ( isnumeric( v ) || islogical( v ) ) && ~isempty( v ) && isreal( v )
      if islogical( v ), v = uint8( v ); end
      ops{end+1} = { 'i3d_add_aux' , f , v , class( v ) , ndims( v ) , int64( size( v ) ) }; %#ok<AGROW>
    end
  end

  if ~isfield( INFO , 'DICOMstack' ), return; end
  DS = INFO.DICOMstack;
  C = struct();  try, C = DS.commonINFO; end
  if ~isstruct( C ), C = struct(); end

  % UN rescale para todo el stack (SPEC 6, decidido 2026-10-13). Si cambia de
  % corte a corte (PET, algunos TC), el formato no tiene donde ponerlo: escribir
  % sin el perderia los valores fisicos EN SILENCIO. Se niega
  vary = @( a ) any( cellfun( @(p) isstruct( p ) && isfield( p , a ) , DS.infos(:) ) );
  if vary( 'RescaleSlope' ) || vary( 'RescaleIntercept' )
    error('write_I3D:rescaleNotCommon','RescaleSlope/RescaleIntercept change between the slices of this stack, and the format holds one rescale for the whole stack (SPEC 6).');
  end
  % rescale / window: SOLO si son comunes a toda la serie (commonINFO). La
  % ventana de DICOM (SPEC 6) no es exactamente la lineal limpia: difiere en 0.5
  if all( isfield( C , { 'RescaleSlope' , 'RescaleIntercept' } ) ) && isnumeric( C.RescaleSlope ) && isnumeric( C.RescaleIntercept )
    ops{end+1} = { 'i3d_set_rescale' , double( C.RescaleSlope(1) ) , double( C.RescaleIntercept(1) ) , 'DICOM RescaleSlope / RescaleIntercept' };
  end
  if all( isfield( C , { 'WindowCenter' , 'WindowWidth' } ) ) && isnumeric( C.WindowCenter ) && isnumeric( C.WindowWidth ) && ~isempty( C.WindowCenter )
    note = '';  if numel( C.WindowCenter ) > 1, note = sprintf( ', the first of %d' , numel( C.WindowCenter ) ); end
    ops{end+1} = { 'i3d_set_window' , double( C.WindowCenter(1) ) , double( C.WindowWidth(1) ) , [ 'DICOM WindowCenter / WindowWidth' , note ] };
  end

  ops = [ ops , info_( DS , INFOL , visf ) ];
end

function [ s , why , absent , isnum ] = value_( v )
%VALUE_  un valor de info.* para la DLL -- s: la cadena (sin espacios a los
% lados) o la fila de numeros (isnum) --, y si no se puede escribir, por que
% (why ~= ''). absent: el valor es NaN entero, que es lo que DICOMstack pone a un
% atributo que los ficheros NO TIENEN (DICOM no puede codificar un NaN: DS e IS
% son cifras). No es un valor que no se pueda escribir: no hay valor, y no se
% dice nada, como de cualquier atributo que no esta
%   char                    una cadena (un vacio es "", que en DICOM es "esta y vacio");
%                           cualquier caracter salvo los de control: la cabecera
%                           es UTF-8 (SPEC 1)
%   numeros (<= 16, finitos) la lista
%   nombre DICOM (PN)       el struct de dicominfo (FamilyName, GivenName...) en la
%                           forma de texto de DICOM: "Familia^Nombre^Medio^Prefijo^Sufijo",
%                           sin los ^ de sobra al final
  s = '';  why = '';  absent = false;  isnum = false;
  if isstruct( v ) && isscalar( v ) && ~isempty( fieldnames( v ) ) && all( ismember( fieldnames( v ) , { 'FamilyName' 'GivenName' 'MiddleName' 'NamePrefix' 'NameSuffix' } ) )
    P = { 'FamilyName' 'GivenName' 'MiddleName' 'NamePrefix' 'NameSuffix' };
    c = cell( 1 , 5 );
    for k = 1:5, c{k} = ''; if isfield( v , P{k} ) && ischar( v.(P{k}) ), c{k} = strtrim( v.(P{k}) ); end, end
    n = find( ~cellfun( 'isempty' , c ) , 1 , 'last' );  if isempty( n ), n = 0; end
    v = strjoin( c(1:n) , '^' );
  end
  if ischar( v ) && size( v , 1 ) <= 1
    v = strtrim( v );
    if any( v < 32 | v == 127 ), why = 'control characters'; return; end   % la cabecera es UTF-8 (SPEC 1)
    s = v;
  elseif ( isnumeric( v ) || islogical( v ) ) && isreal( v ) && ~isempty( v ) && numel( v ) <= 16 && all( isfinite( double( v(:) ) ) )
    s = double( v(:).' );  isnum = true;
  elseif isnumeric( v ) && isreal( v ) && ~isempty( v ) && all( isnan( double( v(:) ) ) )
    absent = true;                               % lo que DICOMstack pone a lo que no esta
  elseif ( isnumeric( v ) || islogical( v ) ) && isempty( v )
    why = 'empty number';
  elseif isnumeric( v ) && ~isreal( v )
    why = 'complex numbers';
  elseif isnumeric( v ) && numel( v ) > 16
    why = sprintf( '%d numbers' , numel( v ) );
  elseif isnumeric( v )
    why = 'not finite (NaN or Inf)';             % alguno, no todos: NaN entero es absent
  elseif isstruct( v )
    why = 'a sequence (struct)';
  elseif ischar( v )
    why = sprintf( '%d lines of text' , size( v , 1 ) );
  else
    why = sprintf( 'a %s' , class( v ) );        % cell, objeto...: lo unico que se sabe es la clase
  end
end

% ======================================================================
function [ I , nt ] = t1_( I )
%T1_  I solo con su primer instante: data, T (y lo demas que recorta I.t1) y el
% DICOMstack de I.INFO, para que ffiles/uids/infos sigan cuadrando con data (lo
% necesitan lazy_ y planes_). INFO.thumbnail* no se toca. nt: los instantes que
% tenia
  nt = numel( I.T );
  if nt == 1, return; end
  nk = numel( I.Z );
  I = I.t1;
  if ~isstruct( I.INFO ) || ~isfield( I.INFO , 'DICOMstack' ), return; end
  DS = I.INFO.DICOMstack;
  % el metodo del stack, que recalcula commonINFO para ese instante. Pero quita
  % los planos sin fichero en t = 1, y data los conserva: entonces, a mano
  DS1 = [];
  try, DS1 = t( DS , 1 ); end
  if isempty( DS1 ) || size( DS1.ffiles , 1 ) ~= nk
    DS1 = DS;
    for p = { 'uids' , 'locations' , 'times' , 'ffiles' , 'files' , 'infos' }
      try
        v = DS1.( p{1} );
        if size( v , 2 ) == nt, DS1.( p{1} ) = v( : , 1 ); end
      end
    end
  end
  I.INFO.DICOMstack = DS1;
end

function REF = lazy_( I , D , sz , ncomp )
%LAZY_  para cada plano (k,t): la ruta de su .dcm (con '/'), o '' (no se puede
% referenciar, o no tiene fichero). El mapa (k,t) -> fichero es el de
% DICOMstackRead: DS.IMAGE(:,:,z,t) sale de DS.ffiles{z,t}, y el metodo I3D de
% DICOMstack hace permute([2 1]) -- la k de @I3D es la z, la t es la t.
%
% Se REFERENCIA solo si, para ese fichero:
%   - su sintaxis de transferencia es SIN PERDIDA y la decodifica el lector
%     (DCMTK): nativa LE/BE, RLE, JPEG lossless (.57/.70), JPEG-LS lossless (.80).
%     Una con perdida da pixeles distintos segun el decodificador;
%   - es un plano de un componente (no multiframe, SamplesPerPixel 1), aparece
%     una sola vez en ffiles (su ruta puede llevar cualquier caracter: la
%     cabecera es UTF-8, y el lector abre rutas UTF-8 tambien con DCMTK);
%   - su clase (BitsAllocated/PixelRepresentation) es la de I.data.
% Y ademas, con 'Verify' (default), la DLL LEE cada referencia y la materializa
% si no da EXACTAMENTE I.data(:,:,k,t): con el lector, y no con dicomread,
% porque lo que importa es lo que devolvera el fichero, y los dos discrepan
% (MEDIDO, tests/probe_jpll.m: dicomread de R2022a decodifica mal el JPEG
% lossless de 10 y 15 bits y no extiende el signo con BitsStored < BitsAllocated).
% Un plano sin fichero es <missing> si data es ENTERA y el plano es todo ceros
% (lo que deja DICOMstackRead), y si no se materializa: eso tambien lo decide la
% DLL. Un '$' de una ruta, la DLL lo escribe '$$'.
  INFO = I.INFO;
  if ~isstruct( INFO ) || ~isfield( INFO , 'DICOMstack' )
    error('write_I3D:notLazy','''Lazy'' needs an I3D that comes from a DICOMstack (I.INFO.DICOMstack).');
  end
  if ncomp > 1, error('write_I3D:notLazy','''Lazy'' with more than one component is not supported.'); end
  F = INFO.DICOMstack.ffiles;
  nk = sz(3);  nt = sz(4);
  if ~iscell( F ) || size( F , 1 ) ~= nk || size( F , 2 ) ~= nt
    error('write_I3D:lazyMismatch','DICOMstack.ffiles is %s but data has %d planes x %d instants: the I3D no longer matches its DICOMstack.', mat2str( size( F ) ) , nk , nt );
  end
  LOSSLESS = { '1.2.840.10008.1.2' , '1.2.840.10008.1.2.1' , '1.2.840.10008.1.2.2' , '1.2.840.10008.1.2.5' , ...
               '1.2.840.10008.1.2.4.57' , '1.2.840.10008.1.2.4.70' , '1.2.840.10008.1.2.4.80' };
  full = cellfun( @(f) strrep( char( f ) , '\' , '/' ) , F , 'un' , 0 );
  used = full( ~cellfun( 'isempty' , full ) );
  [ u , ~ , ix ] = unique( used );  dup = u( accumarray( ix(:) , 1 ) > 1 );

  REF = repmat( { '' } , nk , nt );
  for t = 1:nt
    for k = 1:nk
      fn = full{k,t};
      if isempty( fn ) || any( strcmp( fn , dup ) ) || any( fn < 32 | fn == 127 ), continue; end
      try
        h = dicominfo( fn );
        if ~any( strcmp( h.TransferSyntaxUID , LOSSLESS ) ), continue; end
        if isfield( h , 'NumberOfFrames' ) && ~isempty( h.NumberOfFrames ) && h.NumberOfFrames > 1, continue; end
        if isfield( h , 'SamplesPerPixel' ) && h.SamplesPerPixel ~= 1, continue; end
        pr = isfield( h , 'PixelRepresentation' ) && h.PixelRepresentation == 1;
        cls = sprintf( '%sint%d' , repmat( 'u' , 1 , ~pr ) , h.BitsAllocated );
        if ~strcmp( cls , class( D ) ), continue; end
        if double( h.Columns ) ~= sz(1) || double( h.Rows ) ~= sz(2), continue; end
        REF{k,t} = fn;
      end
    end
  end
end
