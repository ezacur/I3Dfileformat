function write_MI3D( S , fname , varargin )
%WRITE_MI3D   escribe un contenedor .mi3d (SPEC 14) con mi3d.dll (calllib), SIN PASAR POR DISCO
%
%   write_MI3D( DS(1:10) , fname )            un array de DICOMstacks: un miembro por pila
%   write_MI3D( { R1 , R2 , R3 } , fname )    structs como la de read_I3D
%   write_MI3D( { I1 , I2 , I3 } , fname )    I3D con su DICOMstack en I.INFO.DICOMstack
%   write_MI3D( ... , 'Comment' , c )         la primera linea (sin darla: "mi3d_write <fecha>, K stacks")
%
% Cada miembro es EXACTAMENTE el .i3d que escribiria write_I3D (la misma
% conversion a R y las mismas llamadas, sobre el escritor de mi3d.dll), pero se
% codifica en memoria y se copia al contenedor: ningun .i3d intermedio toca el
% disco. El resultado es el mismo .mi3d que escribir cada uno con write_I3D y
% juntarlos con mi3d_write_files, con las mismas etiquetas.
%
% En la cabecera del .mi3d, bajo las lineas i3d(n), una NOTA de cada miembro (SPEC
% 14.7): sus series, de su involvedSeries, una por linea, numero, descripcion y hora
% (y fecha si no son todas del mismo dia), alineadas, con '~' donde la descripcion
% o la fecha repiten la de la linea de arriba del mismo miembro:
%   # -- series of each stack: number, description, time
%   #  i3d(1)   1  loc        10:02:11
%   #  i3d(2)   5  SA cine    10:14:40
%   #           6  ~          10:19:30
%
% El cell puede mezclar DICOMstacks, I3D y Rs. La etiqueta de cada miembro (el
% comentario de su linea i3d(n)) es NNN.descripcion (plano), la del comentario
% de su cabecera. En memoria quedan solo los miembros ya comprimidos (y la pila
% que se esta escribiendo).
%
% ERROR IDENTIFIERS
%   write_MI3D:input     S no es un array de DICOMstacks ni un cell; una opcion mala
%   write_MI3D:charset   MATLAB no pasa las cadenas en UTF-8
%   write_MI3D:<id>      lo que dice mi3d.dll (badData, badGrid, cannotOpen...)
%
% See also write_I3D, read_I3D, read_MI3D.

  if isa( S , 'DICOMstack' )
    S = arrayfun( @( d ) S( d ) , 1:numel( S ) , 'un' , 0 );   % un cell, una pila por celda
  elseif ~iscell( S )
    error( 'write_MI3D:input' , 'An array of DICOMstacks, or a cell of DICOMstacks, I3D or structs like the one of read_I3D, was expected.' );
  end
  if isempty( S ), error( 'write_MI3D:input' , 'No stacks to write.' ); end
  if mod( numel( varargin ) , 2 ), error( 'write_MI3D:input' , 'Options go in pairs: ''Comment'' , c.' ); end
  COMMENT = '';
  for o = 1:2:numel( varargin )
    switch lower( varargin{o} )
      case 'comment', COMMENT = varargin{o+1};
      otherwise,      error( 'write_MI3D:input' , 'Unknown option ''%s'' (Comment).' , varargin{o} );
    end
  end

  loadMI3Dlibrary();
  mi3dnew = calllib( 'mi3d' , 'mi3d_new' );  CLEAN = onCleanup( @() calllib( 'mi3d' , 'mi3d_free' , mi3dnew ) );
  callmi3d = @(api,varargin) chk_( calllib( 'mi3d' , ['mi3d_',api] , mi3dnew , varargin{:} ) , mi3dnew , api );   % un rc ~= 0: error (add_*: aviso)

  if ~isempty( COMMENT ), callmi3d( 'set_option' , 'Comment' , COMMENT ); end
  rows = cell( 1 , numel( S ) );
  for s = 1:numel( S )
    R = write_I3D( S{s} , callmi3d );                     % mi3d_add_stack y las mismas llamadas que un .i3d
    rows{s} = series_( R );  clear R                      % sus series, para su nota
  end
  [ head , notes ] = notes_( rows );                      % las notas: las series de cada miembro
  callmi3d( 'set_note' , int32( 0 ) , head );
  for s = 1:numel( S ), callmi3d( 'set_note' , int32( s ) , notes{s} ); end
  callmi3d( 'write' , fname );
  clearvars('CLEAN');
end


function Q = series_( R )
%SERIES_  las series de una R: { numero , descripcion , fecha , hora }, una fila por
% serie, de su info.involvedSeries (las filas de allInvolvedSeries: 'N.''desc''
% fecha hora UID (n files)', con '~' donde repiten la de arriba si vienen de un
% .i3d); sin el, de series.* (sin fecha ni hora)
  Q = cell( 0 , 4 );
  if isfield( R.INFO , 'involvedSeries' )
    is = R.INFO.involvedSeries;  if ischar( is ), is = cellstr( is ); end
    is = is(:);
    for i = 2:numel( is )                                 % deshacer los '~': la columna de la de arriba
      a = is{i};  b = is{i-1};  w = find( a == '~' );  w = w( w <= numel( b ) );
      a( w ) = b( w );  is{i} = a;
    end
    for i = 1:numel( is )
      t = regexp( is{i} , '^\s*(\S*?)\.''(.*)''\s+(\d{4}-\d{2}-\d{2})?\s*(\d{2}:\d{2}:\d{2})?' , 'tokens' , 'once' );
      if isempty( t ), t = { strtrim( is{i} ) , '' , '' , '' }; end
      Q( end+1 , : ) = t; %#ok<AGROW>
    end
  elseif isfield( R.INFO , 'series' ) && isfield( R.INFO.series , 'SeriesNumber' )
    n = R.INFO.series.SeriesNumber(:);  if ~iscell( n ), n = arrayfun( @( x ) sprintf( '%g' , x ) , n , 'un' , 0 ); n( strcmp( n , 'NaN' ) ) = {''}; end
    d = repmat( {''} , numel( n ) , 1 );
    if isfield( R.INFO.series , 'SeriesDescription' ), d = cellstr( R.INFO.series.SeriesDescription(:) ); end
    [ ~ , u ] = unique( strcat( n , char( 1 ) , d ) , 'stable' );
    Q = [ n(u) , d(u) , repmat( {''} , numel( u ) , 2 ) ];
  end
end


function [ head , notes ] = notes_( rows )
%NOTES_  las notas del .mi3d: de cada miembro, una linea por serie, 'numero  descripcion
% hora' (y la fecha si no todas son del mismo dia), alineadas en TODO el contenedor;
% dentro de un miembro, '~' donde la descripcion o la fecha repiten la de arriba
  for s = 1:numel( rows )                                 % sin caracteres de control; una descripcion larga, cortada
    d = regexprep( rows{s}(:,2) , '[\x00-\x1F\x7F]+' , ' ' );
    long = cellfun( 'length' , d ) > 40;  d( long ) = cellfun( @( x ) [ x(1:39) , '…' ] , d( long ) , 'un' , 0 );
    rows{s}(:,2) = d;
  end
  A = vertcat( rows{:} );  if isempty( A ), A = cell( 0 , 4 ); end
  withDate = numel( unique( A( ~cellfun( 'isempty' , A(:,3) ) , 3 ) ) ) > 1;
  wn = max( [ 1 ; cellfun( 'length' , A(:,1) ) ] );  wd = max( [ 1 ; cellfun( 'length' , A(:,2) ) ] );
  head = 'series of each stack: number, description, time';  if withDate, head = 'series of each stack: number, description, date and time'; end
  notes = cell( 1 , numel( rows ) );
  for s = 1:numel( rows )
    Q = rows{s};  L = cell( size( Q , 1 ) , 1 );
    for i = 1:size( Q , 1 )
      d = Q{i,2};  f = Q{i,3};
      if i > 1 && strcmp( d , Q{i-1,2} ), d = '~'; end
      if i > 1 && strcmp( f , Q{i-1,3} ), f = '~'; end
      if isempty( d ), d = '''''';  end
      t = Q{i,4};  if withDate, t = strtrim( [ f , ' ' , t ] ); end
      L{i} = sprintf( '%*s  %-*s  %s' , wn , Q{i,1} , wd , d , t );
    end
    notes{s} = strjoin( L , newline );
  end
end


function loadMI3Dlibrary()
  % loadMI3Dlibrary  mi3d.dll de esta carpeta, una vez
  if libisloaded( 'mi3d' ), return; end
  if ~strcmpi( feature( 'DefaultCharacterSet' ) , 'UTF-8' )
    error( 'write_MI3D:charset' , 'MATLAB passes strings to the DLL in %s, and it takes UTF-8: set feature(''DefaultCharacterSet'',''UTF-8'').' , feature( 'DefaultCharacterSet' ) );
  end
  old = cd( fileparts( mfilename( 'fullpath' ) ) );  C = onCleanup( @() cd( old ) );
  loadlibrary( 'mi3d.dll' , @mi3d_proto , 'alias' , 'mi3d' );
end


function chk_( rc , m , api )
%CHK_  lo que devuelve una funcion de mi3d.dll: 0 bien; si no, su mensaje. Un info.* que
% no se puede escribir es un aviso (el miembro sale sin el); lo demas, un error
  if rc == 0, return; end
  msg = calllib( 'mi3d' , 'mi3d_wlast_error' , m );
  if strncmp( api , 'add_' , 4 ) && ~strcmp( api , 'add_stack' )
    warning( 'write_MI3D:skipped' , 'mi3d_%s: %s' , api , msg );
  else
    error( [ 'write_MI3D:' calllib( 'mi3d' , 'mi3d_wlast_error_id' , m ) ] , 'mi3d_%s: %s' , api , msg );
  end
end
