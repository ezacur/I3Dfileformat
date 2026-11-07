function [ files , failed ] = convert_to_MI3D( folder , outdir , varargin )
%CONVERT_TO_MI3D   todos los DICOM de un folder, a un .mi3d por paciente y estudio
%
%   convert_to_MI3D( folder )                   los .mi3d, en folder
%   convert_to_MI3D( folder , outdir )          en outdir
%   convert_to_MI3D( ... , 'Threads' , n )      los de DICOMstackCollect (12)
%   convert_to_MI3D( ... , 'T1' , true )        solo el primer instante de cada pila; el thumbnail, animado
%   convert_to_MI3D( ... , 'T01' , true )       lo mismo, y el thumbnail solo de ese instante
%   convert_to_MI3D( ... , 'Info' , true )      la cabecera entera de cada fichero (DS.dicominfo)
%   [ files , failed ] = convert_to_MI3D( ... ) los .mi3d escritos, y cuantos estudios no
%
% Las pilas de DICOMstackCollect( folder ) se agrupan por StudyInstanceUID (igual, no
% byStudyInstanceUID: con un UID corto, este se lleva pilas de otro estudio), y cada
% estudio va a un <Person>.<StudyDescription>.mi3d (write_MI3D), sus series
% ordenadas por SeriesNumber (las que no lo tienen, al final). El nombre:
%   / \ :                       '-' (fixfilename los tomaria por separadores de ruta)
%   sin Person                  unknownPerson
%   sin StudyDescription        unknownStudy_<StudyDate>, la fecha como yyyy-mm-dd
%                               (unknownDate si no la hay)
%   si ya existe ese .mi3d      (en disco, o de otro estudio de esta llamada) se le
%                               añade _<StudyDate>; y si aun existe, '_' hasta que no
%
% 'T1': de cada pila, data(:,:,:,1,...), T(1), y de series.* / planes.* la columna
% t = 1; de involvedSeries, las series que quedan. El thumbnail sigue animado (todos
% los instantes, como sin 'T1'). 'T01': lo mismo, y el thumbnail, solo el de t = 1.
% 'Info': antes de escribir, DS.dicominfo (todas las pilas en una llamada): las
% info.* del .i3d son entonces la cabecera ENTERA de los ficheros, no solo lo que
% lee DICOMstackCollect. Lento (12-72 ms por fichero).
%
% Un estudio que no se puede escribir es un aviso (convert_to_MI3D:failed), y se sigue
% con los demas. Como write_MI3D, sin ningun .i3d intermedio en disco.
%
% See also write_MI3D, read_MI3D, DICOMstackCollect, convert_to_MI3D_cli.

  if nargin < 2 || isempty( outdir ), outdir = folder; end
  THREADS = 12;  T1 = false;  T01 = false;  INFO = false;
  if mod( numel( varargin ) , 2 ), error( 'convert_to_MI3D:input' , 'Options go in pairs: ''Threads'' , n.' ); end
  for o = 1:2:numel( varargin )
    switch lower( varargin{o} )
      case 'threads', THREADS = varargin{o+1};
      case 't1',      T1   = logical( varargin{o+1} );
      case 't01',     T01  = logical( varargin{o+1} );
      case 'info',    INFO = logical( varargin{o+1} );
      otherwise,      error( 'convert_to_MI3D:input' , 'Unknown option ''%s'' (Threads, T1, T01, Info).' , varargin{o} );
    end
  end
  T1 = T1 || T01;
  if ~isfolder( folder ), error( 'convert_to_MI3D:input' , 'No folder %s.' , folder ); end
  if ~isfolder( outdir ), mkdir( outdir ); end

  DS = DICOMstackCollect( folder , 'Threads' , THREADS );
  files = {};  failed = 0;
  if isempty( DS ), return; end
  if INFO, DS = DS.dicominfo; end

  U = DS.StudyInstanceUID_;
  for TS = unique( U ).'
    try
      T = DS( strcmp( U , TS{1} ) );                   % EXACTO: byStudyInstanceUID no lo es (un UID corto se lleva pilas de otro)

      sn = NaN( 1 , numel( T ) );                       % por SeriesNumber; sin el, al final
      for k = 1:numel( T ), try, x = double( T(k).SeriesNumber ); if ~isempty( x ), sn(k) = x(1); end; end; end
      [ ~ , o ] = sort( sn );  T = T( o );

      [ name , date ] = name_( T(1) );
      f = fullfile( outdir , [ name '.mi3d' ] );
      if isfile( f ) || ismember( f , files ), f = fullfile( outdir , [ name '_' date '.mi3d' ] ); end
      while isfile( f ) || ismember( f , files ), f = regexprep( f , '\.mi3d$' , '_.mi3d' ); end

      if T1
        X = cell( 1 , numel( T ) );
        for k = 1:numel( T ), X{k} = firstFrame_( write_I3D( T(k) ) , T01 ); end     % write_I3D( S ): solo la R
        write_MI3D( X , f );
      else
        write_MI3D( T , f );
      end
      files{end+1} = f; %#ok<AGROW>
    catch E
      failed = failed + 1;
      warning( 'convert_to_MI3D:failed' , 'study %s not written: %s' , TS{1} , E.message );
    end
  end
  files = files(:);
end


function R = firstFrame_( R , still )
%FIRSTFRAME_  el primer instante de una R: data, T, series.* / planes.* y involvedSeries;
% y el thumbnail si still (si no, sigue animado)
  nT = numel( R.T );
  if nT <= 1, return; end
  ix = repmat( { ':' } , 1 , max( 4 , ndims( R.data ) ) );  ix{4} = 1;
  R.data = R.data( ix{:} );
  R.T = R.T(1);
  if still && ~isempty( R.thumbnail ) && size( R.thumbnail , 4 ) > 1, R.thumbnail = R.thumbnail( : , : , : , 1 ); end
  nK = size( R.data , 3 );
  for g = { 'series' , 'planes' }
    if ~isfield( R.INFO , g{1} ) || ~isstruct( R.INFO.( g{1} ) ), continue; end
    for f = fieldnames( R.INFO.( g{1} ) ).'
      v = R.INFO.( g{1} ).( f{1} );
      if size( v , 1 ) == nK && size( v , 2 ) == nT, R.INFO.( g{1} ).( f{1} ) = v( : , 1 ); end
    end
  end
  % involvedSeries: las series que quedan (su UID esta en la fila)
  if isfield( R.INFO , 'involvedSeries' ) && isfield( R.INFO , 'series' ) && isfield( R.INFO.series , 'SeriesInstanceUID' )
    is = R.INFO.involvedSeries;  if ischar( is ), is = cellstr( is ); end
    u = unique( R.INFO.series.SeriesInstanceUID( ~cellfun( 'isempty' , R.INFO.series.SeriesInstanceUID ) ) );
    if ~isempty( u ) && ~any( contains( is , '~' ) )        % con '~' (de un .i3d) no se puede saber: se dejan
      keep = cellfun( @( r ) any( cellfun( @( x ) contains( r , [ ' ' x ' ' ] ) , u ) ) , is );
      if any( keep ), R.INFO.involvedSeries = is( keep ); end
    end
  end
end


function [ name , date ] = name_( S )
%NAME_  <Person>.<StudyDescription>, como un nombre de fichero (fixfilename), y la fecha del estudio
  date = 'unknownDate';
  try
    d = char( S.StudyDate );
    if numel( d ) >= 8 && all( isstrprop( d(1:8) , 'digit' ) ), date = sprintf( '%s-%s-%s' , d(1:4) , d(5:6) , d(7:8) ); end
  end

  P = '';  try, P = strtrim( char( S.Person ) ); end
  if isempty( P ) || isempty( regexprep( P , '^Pid|[_\-\s]' , '' ) ), P = 'unknownPerson'; end     % 'Pid_-_-_': nada

  D = '';  try, D = strtrim( char( S.StudyDescription ) ); end
  if isempty( D ) || startsWith( D , 'unknown_' ), D = [ 'unknownStudy_' date ]; end

  P = regexprep( P , '[\\/:]' , '-' );  D = regexprep( D , '[\\/:]' , '-' );        % fixfilename los toma por separadores de ruta
  [ ~ , name ] = fileparts( fixfilename( sprintf( '%s.%s.mi3d' , P , D ) ) );     % fixfilename da una ruta completa; sin .mi3d
end
