function write_I3D( S , fname )

ATTS_VISIBLES = {...
  'PatientID';'AcquisitionContrast';'AcquisitionDate';'AcquisitionDateTime';...
  'AcquisitionDuration';'AcquisitionGroupLength';'AcquisitionMatrix';'AcquisitionNumber';...
  'AcquisitionTime';'AcquisitionType';'AcquisitionsInSeries';...
  'AnatomicRegionSequence';'AnatomicalOrientationType';'AngioFlag';...
  'BodyPartExamined';'CardiacNumberOfImages';'CardiacSignalSource';...
  'CardiacSynchronizationTechnique';'ColorType';'Columns';'CommentsOnThePerformedProcedureStep';...
  'ComplexImageComponent';'ConfidentialityConstraintOnPatientDataDescription';...
  'ContentDate';'ContentQualification';...
  'ContentTime';'ConversionType';'DataSetType';'DeidentificationMethod';...
  'DeidentificationMethodCodeSequence';'DeviceSerialNumber';'Format';'FormatVersion';'FrameTime';...
  'FrameType';'HeartRate';'Height';'ImageComments';'ImageFormat';'ImageGeometryType';'ImageLocation';...
  'ImageOrientation';'ImageOrientationPatient';'ImagePositionPatient';'ImageType';'InStackPositionNumber';...
  'InstanceCreationDate';'InstanceCreationTime';'InstanceCreatorUID';'InstanceNumber';...
  'InstitutionName';'InstitutionalDepartmentName';'Laterality';'LossyImageCompression';...
  'LowRRValue';'MagneticFieldStrength';'Manufacturer';'ManufacturerModelName';'MaskingImage';...
  'MediaStorageSOPClassUID';'MediaStorageSOPInstanceUID';...
  'ModalitiesInStudy';'Modality';'NominalInterval';...
  'NominalPercentageOfCardiacPhase';'NominalRespiratoryTriggerDelayTime';'NumberOfAverages';...
  'NumberOfFrames';'NumberOfFramesInOverlay_0';'NumberOfTemporalPositions';...
  'PatientAge';'PatientBreedCodeSequence';'PatientBreedDescription';...
  'PatientIdentityRemoved';'PatientOrientation';'PatientPosition';'PatientSex';...
  'PatientSize';'PatientSpeciesDescription';'PatientState';'PatientWeight';'PhaseContrast';...
  'PhotometricInterpretation';'PixelPaddingValue';...
  'PixelPresentation';'PixelRepresentation';'PixelSpacing';'PlanarConfiguration';...
  'ProtocolName';'ReferencedImageSequence';'ReferencedPatientSequence';'ReferencedPerformedProcedureStepSequence';...
  'ReferencedRawDataSequence';'ReferencedStudySequence';...
  'RequestAttributesSequence';'RequestedContrastAgent';'RequestedProcedureCodeSequence';...
  'RequestedProcedureDescription';'RequestedProcedureID';'RequestingService';...
  'RescaleIntercept';'RescaleSlope';'RescaleType';'RespiratoryIntervalTime';...
  'RespiratoryMotionCompensationTechnique';'RespiratorySignalSource';'ResponsibleOrganization';...
  'RevolutionTime';'RotationDirection';'Rows';'SOPClassUID';...
  'SOPInstanceUID';'SamplesPerPixel';'SaturationRecovery';'ScanOptions';'ScanningSequence';...
  'ScheduledProcedureStepEndDate';'ScheduledProcedureStepEndTime';...
  'ScheduledProcedureStepID';'ScheduledProcedureStepStartDate';'ScheduledProcedureStepStartTime';...
  'ScheduledStudyStartDate';'ScheduledStudyStartTime';'SequenceName';'SequenceVariant';...
  'SeriesDate';'SeriesDescription';'SeriesInstanceUID';'SeriesNumber';'SeriesTime';'SliceLocation';...
  'SliceThickness';'SmallestImagePixelValue';'SmallestPixelValueInSeries';'SoftwareVersions';...
  'SourceApplicationEntityTitle';'SourceImageSequence';'SpacingBetweenSlices';'SpatialPresaturation';...
  'SpatialResolution';'SpecialNeeds';'SpecificCharacterSet';'StackID';'StationName';'SteadyStatePulseSequence';...
  'StorageGroupLength';'StorageMediaFileSetUID';'StudyDate';'StudyDescription';...
  'StudyGroupLength';'StudyID';'StudyInstanceUID';'StudyPriorityID';'StudyStatusID';'StudyTime';...
  'TableHeight';'TableSpeed';'TagThickness';'Tagging';'TemporalPositionIdentifier';'TemporalPositionIndex';...
  'TemporalResolution';'TimeOfFlightContrast';'TimeOfLastCalibration';'TimezoneOffsetFromUTC';...
  'TotalCollimationWidth';'TransferSyntaxUID';'TransmitCoilName';'TransmitCoilType';'TriggerTime';...
  'TriggerWindow';'TypeOfPatientID';'Units';'VolumeBasedCalculationTechnique';...
  'VolumetricProperties';'Width';'WindowCenter';'WindowCenterWidthExplanation';'WindowWidth';'ZoomCenter';...
  'ZoomFactor';'xAcquisitionDatenum';'xContentDatenum';'xFrame';'xInstanceCreationDatenum';...
  'xPerformedProcedureStepEndDatenum';'xPerformedProcedureStepStartDatenum';'xPersonCount';'xR';...
  'xScheduledProcedureStepEndDatenum';'xScheduledProcedureStepStartDatenum';'xScheduledStudyStartDatenum';...
  'xSegmentNumber';'xSeriesDatenum';'xStudyDatenum';'xZ'
  };

  loadlibrary_();
  
  if isa( S ,'I3D') && isfield( S.INFO ,'DICOMstack')
    I = S;
    S = S.INFO.DICOMstack;
  elseif isa( S ,'DICOMstack') && numel( S ) == 1
    I = S.IMAGE;
  elseif isa( S ,'DICOMstack') && numel( S ) > 1
    error( 'A single stack was expected.' );
  else
    error( 'A single DICOMstack or an I3D was expected.');
  end
  

  i3dnew = calllib( 'i3d' , 'i3d_new' ); CLEAN = onCleanup( @() calllib( 'i3d' , 'i3d_free' , i3dnew ) );

  calli3d = @(api,varargin) chk_( calllib( 'i3d' , ['i3d_',api] , i3dnew , varargin{:} ) , i3dnew , api );   % un rc ~= 0: error (add_*: aviso)
  dollar  = @(s) strrep( s , '$' , '$$' );   % un texto de info.*: el lector sustituye $VARIABLES$, y un $ literal es $$ (SPEC 2)

  calli3d( 'add_comment' ,   sprintf( '\b%03d.%s (%s)   [ %s ]' , S.SeriesNumber , S.SeriesDescription , S.PlaneName , strjoin( arrayfun(@num2str,size(S),'un',0) , ' x ' ) ) );

  calli3d( 'set_Xgrid' ,     double( I.X ) , numel( I.X ) );
  calli3d( 'set_Ygrid' ,     double( I.Y ) , numel( I.Y ) );
  calli3d( 'set_Zgrid' ,     double( I.Z ) , numel( I.Z ) );
  calli3d( 'set_Tgrid' ,     double( I.T ) , numel( I.T ) );
  calli3d( 'set_transform' , reshape( double( I.SpatialTransform ).' , 1 , [] ) );   % POR FILAS
  calli3d( 'set_data' ,      I.data , class( I.data ) , ndims( I.data ) , size( I.data ) );

  if isfield( I.INFO , 'thumbnail' )
    th = I.INFO.thumbnail;
    calli3d( 'set_thumbnail' , th , class(th) , ndims( th ) , size( th ) );
  end

  if true %write the Involved Series
    [~,is] = S.allInvolvedSeries;
    is = tidyColumns( is , 'Ditto' , '~' );   % ASCII: el '·' por defecto es UTF-8 de dos bytes, y un editor que no lo detecta muestra 'Â·'
    calli3d( 'add_info_rows_text' ,    'involvedSeries' , numel( is ) , dollar( is ) , repmat( {''} , numel(is) ,1) , 1 );
  end

  if true %write the common info
    C = S.commonINFO;
    C = rmfields( C , 'SeriesNumber','SeriesDescription','SeriesInstanceUID','SeriesDate','SeriesTime','xSeriesDatenum','Filename');   % Filename: una ruta absoluta (las rutas van en planes.Filename, relativas a $DICOMDIR$)
    f = fieldnames( C );
    w = fun( 'UID$'                   , f ); f = [ f( w) ; f(~w) ];
    w = fun( 'Date$|Time$|Datenum$'   , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^DeviceSerialNumber'    , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^ManufacturerModelName' , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^Manufacturer'          , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^InstitutionName'       , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^AcquisitionTime'       , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^AcquisitionDate'       , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^PixelSpacing'          , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^ImageType'             , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^ProtocolName'          , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^SequenceName'          , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^BodyPartExamined'      , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^xStudy.*'              , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^Study.*'               , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^xPatient.*'            , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^Patient.*'             , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^Modality'              , f ); f = [ f( w) ; f(~w) ];
    w = fun( '^Private_'              , f ); f = [ f(~w) ; f( w) ];
    C = reorderstructure( C , f{:} );
    for attr = fieldnames( C ).', attr = attr{1};
      value = C.(attr); %C = rmfields( C ,attr);
      if isnumeric( value ) && ~isempty( value ) && all( isnan( value(:) ) ), continue; end
      humanReadable = ismember( attr , ATTS_VISIBLES );
      if 0
      elseif isnumeric( value ) && ~isempty( value ) && isvector( value) && numel( value ) < 20 && all( isfinite( value(:) ) )
        calli3d( 'add_info_numbers' , attr , double( value(:).' ) , numel( value ) , humanReadable , '' );
      elseif ischar( value )
        calli3d( 'add_info_text' ,    attr , dollar( strtrim( regexprep( value , '[\x00-\x1F\x7F]+' , ' | ' ) ) ) , humanReadable , '' );
      elseif numel( value ) >= 200      % p.ej. los privados CSA de Siemens: uneval, caro y sin utilidad como texto
        continue;
      else
        calli3d( 'add_info_text' ,    attr , dollar( strtrim( uneval(value) ) ) , humanReadable , '' );
      end
    end
  end

  if true, try  %write the plane-by-plane dicom reference
      C = S.commonINFO;
      Suid  = repmat( {''} , size(S,3:4) );     % '' (no NaN ni []): un plano sin DICOM
      Sn    = zeros( size(S,3:4) );
      Sd    = repmat( {''} , size(S,3:4) );
      Iuid  = repmat( {''} , size(S,3:4) );
      Ifn   = repmat( {''} , size(S,3:4) );
      slice = cell( size(S,3:4) );

      DICOMDIR = S.commonFolder;  DICOMDIR = DICOMDIR(1:end-1);   % la carpeta comun del stack, sin su filesep final; todos sus DICOM cuelgan de ella
      calli3d( 'set_variable' , 'DICOMDIR' , DICOMDIR );
      for k = 1:size( S ,3)
        for f = 1:size( S ,4)
          slice{k,f} = sprintf( 'data(:,:,%d,%d)' , k , f );
          Q = S.infos{k,f};  if ~isstruct( Q ), Q = struct(); end      % un plano sin DICOM: sin infos

          if     isfield( C , 'SeriesInstanceUID' ),  Suid{k,f} = C.SeriesInstanceUID;
          elseif isfield( Q , 'SeriesInstanceUID' ),  Suid{k,f} = Q.SeriesInstanceUID;
          end

          if     isfield( C , 'SeriesNumber' ),       Sn(k,f) = C.SeriesNumber;
          elseif isfield( Q , 'SeriesNumber' ),       Sn(k,f) = Q.SeriesNumber;
          end

          if     isfield( C , 'SeriesDescription' ),  Sd{k,f} = C.SeriesDescription;
          elseif isfield( Q , 'SeriesDescription' ),  Sd{k,f} = Q.SeriesDescription;
          end

          if     isfield( C , 'SOPInstanceUID' ),     Iuid{k,f} = C.SOPInstanceUID;
          elseif isfield( Q , 'MediaStorageSOPInstanceUID' ), Iuid{k,f} = Q.MediaStorageSOPInstanceUID;
          end

          fn = char( S.ffiles{k,f} );               % '$DICOMDIR$\sub\fichero'; un '$' de la ruta es '$$' (SPEC 2)
          if ~isempty( fn ), Ifn{k,f} = [ '$DICOMDIR$' , strrep( fn( numel( DICOMDIR )+1:end ) , '$' , '$$' ) ]; end
        end
      end

      calli3d( 'add_comment' ,           '-- Series and planes (planes: k fastest, then t)' );
      calli3d( 'add_info_rows_numbers' , 'series.SeriesNumber'               , numel( Sn )   , Sn   , slice , 1 );   % enteros: se escriben como enteros
      calli3d( 'add_info_rows_text' ,    'series.SeriesDescription'          , numel( Sd )   , dollar( Sd ) , slice , 1 );
      calli3d( 'add_info_rows_text' ,    'series.SeriesInstanceUID'          , numel( Suid ) , dollar( Suid ) , slice , 1 );
      calli3d( 'add_info_rows_text' ,    'planes.Filename'                   , numel( Ifn )  , Ifn      , slice , 1 );   % ya con $DICOMDIR$ y sus $$
      calli3d( 'add_info_rows_text' ,    'planes.MediaStorageSOPInstanceUID' , numel( Iuid ) , dollar( Iuid ) , slice , 1 );
    catch E
      warning( 'write_I3D:planes' , 'info.series / info.planes not written: %s' , E.message );
  end; end

  calli3d( 'write' , fname );
  clearvars('CLEAN');
 
end


function loadlibrary_()
%LOADLIBRARY_  i3d.dll de esta carpeta, una vez (lo mismo en read_I3D)
  if libisloaded( 'i3d' ), return; end
  if ~strcmpi( feature( 'DefaultCharacterSet' ) , 'UTF-8' )
    error( 'write_I3D:charset' , 'MATLAB passes strings to the DLL in %s, and it takes UTF-8: set feature(''DefaultCharacterSet'',''UTF-8'').' , feature( 'DefaultCharacterSet' ) );
  end
  old = cd( fileparts( mfilename( 'fullpath' ) ) );  C = onCleanup( @() cd( old ) );
  loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' );
end


function chk_( rc , w , api )
%CHK_  lo que devuelve una funcion de i3d.dll: 0 bien; si no, su mensaje. Un info.* que
% no se puede escribir es un aviso (el fichero sale sin el); lo demas, un error
  if rc == 0, return; end
  msg = calllib( 'i3d' , 'i3d_wlast_error' , w );
  if strncmp( api , 'add_' , 4 )
    warning( 'write_I3D:skipped' , 'i3d_%s: %s' , api , msg );
  else
    error( [ 'write_I3D:' calllib( 'i3d' , 'i3d_wlast_error_id' , w ) ] , 'i3d_%s: %s' , api , msg );
  end
end


function L = tidyColumns( L , varargin )
%TIDYCOLUMNS  Tidy a column-aligned listing: squeeze the blank columns, and ditto
% the fields that repeat the line above.
%
%   T = tidyColumns( L )                  L: a cell of lines, or a char matrix
%   T = tidyColumns( L , 'Ditto' , c )    the ditto character (default char(183),
%                                         the middle dot '·')
%   T = tidyColumns( L , 'Gap' , n )      the widest separation kept (default 2)
%   T = tidyColumns( L , 'Prefix' , m )   the common start and end of a field that
%                                         changes: 'delimiter' (default) cut at a
%                                         separator, 'char' all of it, 'none'
%                                         left alone
%   T = tidyColumns( L , 'Keep' , s )     the characters that are never dittoed
%                                         (default '.:"()-'; the blank, always), so
%                                         a dittoed UID, date or time keeps its
%                                         shape
%   T = tidyColumns( L , 'Ref' , r )      what a line is compared with:
%                                         'previous' (default) the line above,
%                                         like a ditto mark; 'first' the first
%                                         line, the same for all
%
% 1. A run of columns that are blank on EVERY line is cut down to 'Gap' columns
%    (a shorter run, like the blank between two words, stays as it is); the
%    leading run goes, and every line loses its trailing blanks.
% 2. The FIELDS are then the stretches between those blank columns. Each line is
%    compared, field by field, with the line above ('Ref'): a field that is the
%    same is dittoed -- each of its characters becomes the ditto character,
%    except those of 'Keep' -- so the eye goes to what changes, and a dot means
%    "as above". With 'Ref','first' every line is compared with the first, and a
%    field is dittoed only where it is the same on ALL lines, so a column is
%    dittoed alike on every line. A field that changes gets the same on its
%    COMMON START and its COMMON END: a UID 1.2.276.0.723.1104.1449135919 over
%    1.2.276.0.723.1104.1449135917 shows ·.·.···.·.···.····.1449135917, and 15.SA
%    under 14.SA shows 15.··. By default the start is cut back to its last
%    separator ('.', ':', '-'...) and the end begins after its first one, which
%    stays visible: 14 over 15, or 12:08 over 12:10, are not split in the middle
%    of a number ('Prefix').
%
%   T = tidyColumns( { '  14.SA cine rest     2008-04-11 12:08:56   1.2.3.45   (14 files)'
%                      '  15.SA cine rest     2008-04-11 12:09:02   1.2.3.47   (14 files)' } )
%     '14.SA cine rest  2008-04-11 12:08:56  1.2.3.45  (14 files)'
%     '15.·· ···· ····  ····-··-·· ··:09:02  ·.·.·.47  (·· ·····)'
%
% When the hour goes from 12 to 13 halfway down, 'previous' shows it where it
% changes; 'first' shows it on every line, since 1 is all the lines share:
%
%   'previous'                     'first'
%     '14.SA 12:58:56'               '14.SA 12:58:56'
%     '15.·· ··:59:02'               '15.·· 12:59:02'
%     '16.·· 13:01:31'               '16.·· 13:01:31'
%     '17.·· ··:02:10'               '17.·· 13:02:10'
%
% A field is cut ONLY at a column that is blank on every line: '14.SA' is one
% field, and its common end is what goes.
%
% T is of the type of L: a cell column (each line without trailing blanks) or a
% char matrix.
%
% ERROR IDENTIFIERS
%   tidyColumns:input   L is not a cell of char rows nor a char matrix
%   tidyColumns:ditto   'Ditto' is not a single character
%   tidyColumns:gap     'Gap' is not a positive integer
%   tidyColumns:prefix  'Prefix' is not 'delimiter', 'char' or 'none'
%   tidyColumns:keep    'Keep' is not char
%   tidyColumns:ref     'Ref' is not 'previous' or 'first'
%
% See also deblank, strjust

  DITTO = char( 183 );
  GAP   = 3;
  if ~isempty( varargin ), [ varargin , ~ , DITTO ] = parseargs( varargin , 'Ditto' , '$DEFS$' , DITTO ); end
  if ~isempty( varargin ), [ varargin , ~ , GAP   ] = parseargs( varargin , 'Gap'   , '$DEFS$' , GAP   ); end
  KEEP = '.:"()-''';
  if ~isempty( varargin ), [ varargin , ~ , KEEP ] = parseargs( varargin , 'Keep' , '$DEFS$' , KEEP ); end
  PREFIX = 'delimiter';
  if ~isempty( varargin ), [ varargin , ~ , PREFIX ] = parseargs( varargin , 'Prefix' , '$DEFS$' , PREFIX ); end
  if ~ischar( PREFIX ) || ~any( strcmp( PREFIX , { 'delimiter' , 'char' , 'none' } ) )
    error( 'tidyColumns:prefix' , 'Prefix must be ''delimiter'', ''char'' or ''none''.' );
  end
  REF = 'previous';
  if ~isempty( varargin ), [ varargin , ~ , REF ] = parseargs( varargin , 'Ref' , '$DEFS$' , REF ); end
  if ~ischar( REF ) || ~any( strcmp( REF , { 'previous' , 'first' } ) )
    error( 'tidyColumns:ref' , 'Ref must be ''previous'' or ''first''.' );
  end
  if ~isempty( varargin ), error( 'tidyColumns:input' , 'unrecognised arguments.' ); end
  if ~ischar( DITTO ) || ~isscalar( DITTO ), error( 'tidyColumns:ditto' , 'Ditto must be a single character.' ); end
  if ~ischar( KEEP ), error( 'tidyColumns:keep' , 'Keep must be a char row of characters.' ); end
  KEEP = [ KEEP(:).' , ' ' ];                            % el blanco, siempre
  if ~isnumeric( GAP ) || ~isscalar( GAP ) || GAP < 1 || GAP ~= round( GAP ), error( 'tidyColumns:gap' , 'Gap must be a positive integer.' ); end

  isCell = iscell( L );
  if isCell
    if ~all( cellfun( @(s) ischar( s ) && size( s , 1 ) <= 1 , L(:) ) )
      error( 'tidyColumns:input' , 'L must be a cell of char rows or a char matrix.' );
    end
    shape = size( L );
    M = char( L(:) );                    % char() pads with blanks; {} gives ''
  elseif ischar( L )
    M = L;
  else
    error( 'tidyColumns:input' , 'L must be a cell of char rows or a char matrix.' );
  end
  if isempty( M ), return; end

  % 1. un tramo de columnas en blanco en TODAS las lineas -> GAP (o las que tenga,
  % si son menos: el blanco entre palabras se queda); fuera el inicial
  blank = all( M == ' ' , 1 );
  ix    = 1:numel( blank );
  run   = blank .* ( ix - cummax( ~blank .* ix ) );       % el puesto de cada blanco en su tramo
  keep  = ~blank | ( run >= 1 & run <= GAP );
  keep( 1:find( ~blank , 1 ) - 1 ) = false;
  M = M( : , keep );

  % 2. los campos: los tramos entre columnas en blanco
  if size( M , 1 ) > 1
    blank = all( M == ' ' , 1 );
    d = diff( [ true , blank , true ] );
    a = find( d == -1 );  b = find( d == 1 ) - 1;
    M0 = M;                              % 'previous' compara con la de arriba SIN puntos
    for f = 1:numel( a )
      c = a(f):b(f);
      if strcmp( REF , 'first' )         % lo mismo en todas: lo comun a TODAS con la primera
        w = c( dittoed_( M0( 2:end , c ) ~= M0( 1 , c ) , M0( 1 , c ) , PREFIX ) );
        if ~isempty( w ), M( 2:end , w ) = ditto_( M( 2:end , w ) , KEEP , DITTO ); end
      else                               % cada linea con la de arriba, como un idem
        for i = 2:size( M , 1 )
          w = c( dittoed_( M0( i , c ) ~= M0( i-1 , c ) , M0( i-1 , c ) , PREFIX ) );
          if ~isempty( w ), M( i , w ) = ditto_( M( i , w ) , KEEP , DITTO ); end
        end
      end
    end
  end

  if isCell
    L = reshape( deblank( cellstr( M ) ) , shape );
  else
    L = M;
  end
end

function w = dittoed_( D , R , PREFIX )
% las posiciones del campo que se tapan: D, que columnas cambian (una fila por
% linea comparada); R, la linea de referencia, donde se buscan los separadores
  n = numel( R );
  p = find( any( D , 1 ) , 1 ) - 1;                       % lo comun al principio
  if isempty( p ), w = 1:n; return; end                   % el campo entero
  if strcmp( PREFIX , 'none' ), w = []; return; end
  if strcmp( PREFIX , 'delimiter' )
    p = find( ~isstrprop( R(1:p) , 'alphanum' ) , 1 , 'last' );     % hasta un separador
    if isempty( p ), p = 0; end
  end
  % y lo comun al FINAL (14.SA sobre 15.SA: el SA), que empieza despues de un
  % separador, que queda a la vista
  e = n - find( any( D , 1 ) , 1 , 'last' );
  if strcmp( PREFIX , 'delimiter' ) && e > 0
    k = find( ~isstrprop( R(end-e+1:end) , 'alphanum' ) , 1 );
    if isempty( k ), e = 0; else, e = e - k; end
  end
  w = [ 1:p , n-e+1:n ];
end

function S = ditto_( S , KEEP , DITTO )
  S( ~ismember( S , KEEP ) ) = DITTO;
end
