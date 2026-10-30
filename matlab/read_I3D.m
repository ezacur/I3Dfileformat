function [ I , S ] = read_I3D( filename , varargin )
%READ_I3D   read an .i3d file into an @I3D, through i3d.dll
%
%   I = read_I3D( 'serie.i3d' )              un @I3D con data, rejillas y transform
%   [ I , S ] = read_I3D( 'serie.i3d' )      y la estructura cruda del lector
%   [ ~ , S ] = read_I3D( f , 'NOdata' )     solo la cabecera: no toca el binario
%                                            (ni data ni los aux)
%   I = read_I3D( f , 'firstFrame' )         solo el PRIMER INSTANTE, data(:,:,:,1,..),
%                                            y T = T(1): lee SOLO los bloques que lo
%                                            cortan (el escritor lo deja en los suyos).
%                                            MEDIDO: 335x mas rapido en un cine de
%                                            400 instantes (102x128x12x400)
%   I = read_I3D( f , ... , 'Member' , n )   el miembro n del contenedor .mi3d f
%                                            (SPEC 14). Mejor read_MI3D( f , n )
%   I = read_I3D( f , ... , 'Variables' , { 'DICOMDIR' , 'D:/x' } )
%                                            variables $NOMBRE$ que MANDAN sobre las
%                                            del fichero: los .dcm de un 'Lazy' se
%                                            pueden mover sin editar el .i3d
%
% Lee con i3d.dll (cpp/, por calllib: enableI3Dlibrary): es el MISMO codigo que usan la
% app y los wrappers de Python y JS, asi que lo que se ve aqui es lo que veran
% ellos.
%
% Lo que va a cada sitio del @I3D:
%   X Y Z T, SpatialTransform    tal cual, bit a bit
%   data                         los valores ALMACENADOS, en su clase (SPEC 6)
%   INFO.<nombre>                cada info.<nombre> de la cabecera: una cadena
%                                entre comillas como char, una lista de numeros
%                                como fila double, y cualquier otra cosa como
%                                el texto crudo
%   INFO.<aux>                   cada aux.NAME (raw/zlib) decodificado: los
%                                thumbnails vuelven a INFO.thumbnailK, ...
%   INFO.rescale , INFO.window   [slope intercept] y [center width] (o [])
%   INFO.missing                 los bloques <missing>: lo/hi 1-based
%   INFO.filename
%   ImageTransform               el window, si lo hay, llevado a valores
%                                ALMACENADOS: (c -/+ w/2 - intercept)/slope
%
% S es todo lo que da el lector: X Y Z T SpatialTransform data rescale window
% missing entries ({key subs value} de TODA la cabecera) header file hidden
% binstart aux.
%
% LIMITACIONES de este lector (SPEC 4: un encoding que no se sabe decodificar
% es un error AL PEDIR el bloque, no al abrir):
%   - <png>, <gif>: no se decodifican (un aux asi da un warning, no un error).
%   - lee data ENTERO: no hay lectura parcial todavia.
%   - no calcula values() ni image(), y no aplica el rescale por bloque
%     (SPEC [OPEN] 7).
%
% ERROR IDENTIFIERS
%   read_I3D:badInput, :cannotOpen, :badMagic, :badHeader, :badGrid,
%   :badTransform, :badNumber, :badDescriptor, :badSubscript, :badData,
%   :badType, :badVariable, :coverage, :truncated, :badBlock, :badCRC,
%   :unsupportedEncoding, :internal; de un 'Member': :missingMember (un hueco),
%   :badIndex (n fuera de 1..N)
%   -- el identificador es el del lector C++, prefijado con read_I3D:
%
% See also write_I3D, read_MI3D, I3D.

  % 'Member', n: el miembro n de un contenedor .mi3d (SPEC 14; mejor read_MI3D)
  MEMBER = 0;
  k = find( cellfun( @(a) ischar( a ) && strcmpi( a , 'Member' ) , varargin ) , 1 );
  if ~isempty( k )
    if k == numel( varargin ) || ~isnumeric( varargin{k+1} ) || ~isscalar( varargin{k+1} ) || varargin{k+1} < 1 || varargin{k+1} ~= round( varargin{k+1} )
      error('read_I3D:badInput','''Member'' takes an integer n >= 1.');
    end
    MEMBER = double( varargin{k+1} );  varargin(k:k+1) = [];
  end
  VARS = {};
  k = find( cellfun( @(a) ischar( a ) && strcmpi( a , 'Variables' ) , varargin ) , 1 );
  if ~isempty( k )
    if k == numel( varargin ) || ~iscellstr( varargin{k+1} ) || mod( numel( varargin{k+1} ) , 2 )
      error('read_I3D:badInput','''Variables'' takes { name , value , ... }.');
    end
    VARS = varargin{k+1}(:).';  varargin(k:k+1) = [];
  end
  NODATA = false;
  try, [ varargin , NODATA ] = parseargs( varargin , 'NOdata' , '$FORCE$' , { true , false } ); end
  FIRST = false;
  try, [ varargin , FIRST ] = parseargs( varargin , 'firstFrame' , '$FORCE$' , { true , false } ); end
  if ~isempty( varargin ), error('read_I3D:badInput','unrecognised arguments.'); end
  if NODATA && FIRST, error('read_I3D:badInput','''NOdata'' and ''firstFrame'' exclude each other.'); end
  if ~ischar( filename ) || isempty( filename ) || size( filename , 1 ) ~= 1
    error('read_I3D:badInput','filename must be a char row.');
  end

  if FIRST, MODE = 'firstFrame'; else, MODE = ~NODATA; end
  win = [];
  if MEMBER, win = i3d_member_( filename , MEMBER , 'read_I3D' ); end
  S = i3d_read_( filename , MODE , VARS , win );
  if FIRST, S.T = S.T(1); end                           % data es el instante 1
  if nargout < 1, return; end

  if isempty( S.data )
    I = I3D( 'X',S.X , 'Y',S.Y , 'Z',S.Z , 'T',S.T );
  else
    I = I3D( S.data , 'X',S.X , 'Y',S.Y , 'Z',S.Z , 'T',S.T );
  end
  I.SpatialTransform = S.SpatialTransform;

  INFO = struct();
  for e = 1:size( S.entries , 1 )
    k = S.entries{e,1};
    if ~strncmp( k , 'info.' , 5 ), continue; end
    f = strrep( k(6:end) , '.' , '_' );                % info.a.b -> a_b (SPEC [OPEN] 8)
    if ~isvarname( f ), f = matlab.lang.makeValidName( f ); end
    INFO.( f ) = i3d_value_( S.entries{e,3} );
  end
  % aux.NAME -> INFO.NAME (los thumbnails vuelven a donde DICOMstackCollect los
  % puso). Uno que el lector no sabe decodificar se dice, no se calla
  for a = 1:numel( S.aux )
    n = S.aux(a).name;  if ~isvarname( n ), n = matlab.lang.makeValidName( n ); end
    if isempty( S.aux(a).error )
      INFO.( n ) = S.aux(a).data;
    elseif NODATA
      % no se leyo a proposito: no es un aviso
    else
      warning('read_I3D:auxNotDecoded','aux.%s not decoded: %s', S.aux(a).name , S.aux(a).error );
    end
  end
  INFO.rescale  = S.rescale;
  INFO.window   = S.window;
  INFO.missing  = S.missing;
  INFO.filename = filename;
  if MEMBER, INFO.member = MEMBER; end
  I.INFO = INFO;

  if ~isempty( S.window ) && S.rescale(1) ~= 0
    c = S.window(1);  w = S.window(2);
    lo = ( c - w/2 - S.rescale(2) ) / S.rescale(1);
    hi = ( c + w/2 - S.rescale(2) ) / S.rescale(1);
    if lo > hi, [ lo , hi ] = deal( hi , lo ); end     % slope negativo
    if hi > lo, I.ImageTransform = [ lo 0 ; hi 1 ]; end
  end
end
