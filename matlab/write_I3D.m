function R0 = write_I3D( S , fname )
%WRITE_I3D   escribe un .i3d con i3d.dll (calllib)
%
%   write_I3D( DS , fname )     un DICOMstack (una pila)
%   write_I3D( I , fname )      un I3D con su DICOMstack en I.INFO.DICOMstack
%   write_I3D( R , fname )      una struct como la de read_I3D:
%                                 R.X R.Y R.Z R.T, R.SpatialTransform, R.data,
%                                 R.thumbnail (opcional), R.INFO
%
% Un DICOMstack o un I3D se convierte primero en una R, y se escribe esa R:
% write_I3D( read_I3D( f ) , g ) reescribe f.
%
% R.INFO: un numero o una fila de numeros, un char, o un cell de char (una
% fila por texto); un struct anida (INFO.a.b es info.a.b). A la vista van
% involvedSeries, series.*, planes.* y las de ATTS_VISIBLES; las demas, en la
% parte oculta. series.* y planes.* con un valor por plano [nK nT] van al final,
% una fila por plano; planes.Filename lleva rutas absolutas, que se escriben
% relativas a $DICOMDIR$, la carpeta comun de todas.
%
% write_I3D( S , callmi3d ) es lo que usa write_MI3D: S, un miembro NUEVO de su
% escritor (mi3d.dll), con las mismas llamadas, sin pasar por disco.
% R = write_I3D( ... ) da ademas la R que escribe (la de un DICOMstack o un I3D,
% convertida). R = write_I3D( S ), sin fichero: solo la convierte, no escribe nada.
%
% See also read_I3D, write_MI3D.

ATTS_VISIBLES = {...
  'PlaneName' ;...
  'SeriesNumber';'SeriesDescription';'SeriesInstanceUID';'SeriesDate';'SeriesTime';'xSeriesDatenum' ;...
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

  if isstruct( S ) && isscalar( S ) && isfield( S , 'data' )
    R = S;                                                % una R, como la de read_I3D
  else
    R = toR_( S );                                        % un DICOMstack o un I3D
  end
  if nargout, R0 = R; end                                 % la R que se escribe (write_MI3D: sus notas)
  if nargin < 2, return; end                              % R = write_I3D( S ): solo convertir

  if isa( fname , 'function_handle' )                     % write_MI3D: un miembro nuevo de SU escritor
    calli3d = fname;
  else
    loadI3Dlibrary();
    i3dnew = calllib( 'i3d' , 'i3d_new' ); CLEAN = onCleanup( @() calllib( 'i3d' , 'i3d_free' , i3dnew ) );
    calli3d = @(api,varargin) chk_( calllib( 'i3d' , ['i3d_',api] , i3dnew , varargin{:} ) , i3dnew , api );   % un rc ~= 0: error (add_*: aviso)
  end
  dollar  = @(s) strrep( s , '$' , '$$' );   % un texto de info.*: el lector sustituye $VARIABLES$, y un $ literal es $$ (SPEC 2)
  clean   = @(s) regexprep( s , '[\x00-\x1F\x7F]+' , ' | ' );   % la DLL no acepta caracteres de control en un texto

  % el comentario de cabecera: NNN.descripcion (plano)  [ I x J x K x T x C ]
  szData = size( R.data );  szData(end+1:5) = 1;
  sn = NaN; try, v = R.INFO.series.SeriesNumber(:); if iscell( v ), v = str2double( v ); end; v = v( isfinite( v ) & v ~= 0 ); if ~isempty( v ), sn = min( v ); end; end   % sin los 0 de un plano vacio; texto si tenia huecos
  sd = 'unknown_SeriesDescription'; try, v = cellstr( R.INFO.series.SeriesDescription ); v = v( ~cellfun( 'isempty' , v ) ); if ~isempty( v ), sd = v{1}; end; end
  pn = ''; try, pn = [ ' (' , R.INFO.PlaneName , ')' ]; end                % una R sin PlaneName: sin el
  if isa( fname , 'function_handle' )
    calli3d( 'add_stack' ,   sprintf( '%03d.%s%s' , sn , clean( sd ) , clean( pn ) ) );   % la etiqueta del miembro: lo mismo que el comentario
  end
  calli3d( 'add_comment' ,   sprintf( '\b%03d.%s%s  [ %s ]' , sn , clean( sd ) , clean( pn ) , strjoin( arrayfun(@num2str,szData,'un',0) , ' x ' ) ) );

  calli3d( 'set_Xgrid' ,     double( R.X ) , numel( R.X ) );
  calli3d( 'set_Ygrid' ,     double( R.Y ) , numel( R.Y ) );
  calli3d( 'set_Zgrid' ,     double( R.Z ) , numel( R.Z ) );
  calli3d( 'set_Tgrid' ,     double( R.T ) , numel( R.T ) );
  calli3d( 'set_transform' , reshape( double( R.SpatialTransform ).' , 1 , [] ) );   % POR FILAS
  calli3d( 'set_data' ,      R.data , class( R.data ) , ndims( R.data ) , size( R.data ) );
  if isfield( R , 'thumbnail' ) && ~isempty( R.thumbnail )
  calli3d( 'set_thumbnail' , R.thumbnail , class( R.thumbnail ) , ndims( R.thumbnail ) , size( R.thumbnail ) );
  end

  if isfield( R.INFO , 'involvedSeries' ), try
  is = R.INFO.involvedSeries; R.INFO = rmfields( R.INFO , 'involvedSeries' );
  if ischar( is ), is = cellstr( is ); end                                 % una sola serie: read_I3D da un char
  is = tidyColumns( is , 'Ditto' , '~' );
  calli3d( 'add_info_rows_text' , 'involvedSeries' , numel( is ) , dollar( clean( is(:) ) ) , repmat( {''} , numel(is) ,1) , true );
  catch E, warning( 'write_I3D:involvedSeries' , 'info.involvedSeries not written: %s' , E.message );
  end; end

  % las infos, en su orden; series.* y planes.*, despues
  for key = fieldnames( R.INFO ).', key = key{1};
    if strcmp( key ,'series'), continue; end
    if strcmp( key ,'planes'), continue; end
    val = R.INFO.(key); R.INFO = rmfields( R.INFO , key );
    if isnumeric( val ) && ~isempty( val ) && all( isnan( val(:) ) ), continue; end
    humanReadable = ismember( key , ATTS_VISIBLES );

    if 0
    elseif iscellstr( val )
      calli3d( 'add_info_rows_text' , key , numel( val ) , dollar( clean( val(:) ) ) , repmat( {''} , numel( val ) , 1 ) , humanReadable );
    elseif ischar( val )
      calli3d( 'add_info_text' , key , dollar( strtrim( clean( val ) ) ) , humanReadable , '' );
    elseif ( isnumeric( val ) || islogical( val ) ) && ~isempty( val ) && isvector( val) && numel( val ) < 20 && all( isfinite( val(:) ) )
      calli3d( 'add_info_numbers' , key , double( val(:).' ) , numel( val ) , humanReadable , '' );
    elseif ( isnumeric( val ) || islogical( val ) ) && numel( val ) >= 200      % p.ej. los privados CSA de Siemens: uneval, caro y sin utilidad como texto
      continue;
    elseif isnumeric( val ) || islogical( val )
      calli3d( 'add_info_text' , key , uneval(val) , humanReadable , '' );
    elseif ( isstruct( val ) || iscell( val ) ) && bytes_( val ) < 1e4   % una secuencia DICOM, un nombre de persona...: uneval, si no es muy grande
      try,     calli3d( 'add_info_text' , key , dollar( strtrim( clean( uneval( val ) ) ) ) , humanReadable , '' );
      catch E, warning( 'write_I3D:skipped' , 'info.%s: uneval of a %s failed: %s' , key , class( val ) , E.message );
      end
    else, warning( 'write_I3D:skipped' , 'info.%s: a %s (%d bytes) is not written' , key , class( val ) , bytes_( val ) );
    end
  end

  if isfield( R.INFO ,'planes' ) && isfield( R.INFO.planes ,'Filename' ), try   % sin nombres de fichero (un I3D, una R): no hay $DICOMDIR$
    fn = R.INFO.planes.Filename;
    fn = cellstr( fn );
    DICOMDIR = commonFolder_( fn );
    if ~isempty( DICOMDIR ), calli3d( 'set_variable' , 'DICOMDIR' , DICOMDIR ); end
    for f = 1:numel(fn)
      if     isempty( fn{f} ),     continue;                                % un plano sin DICOM: ''
      elseif isempty( DICOMDIR ),  fn{f} = dollar( fn{f} );                  % sin carpeta comun (otra unidad): la ruta tal cual
      else,                        fn{f} = [ '$DICOMDIR$' , dollar( fn{f}( numel( DICOMDIR )+1:end ) ) ];
      end
    end
    R.INFO.planes.Filename = fn;
  catch E, warning( 'write_I3D:Filename' , 'info.planes.Filename: %s' , E.message );
  end; end

  if isfield( R.INFO ,'series' )
    Q = R.INFO.series;
    calli3d( 'add_comment' , ' Series (planes: k fastest, then t)' );
    if isfield( Q ,'SeriesNumber' ),      try, Q.SeriesNumber = seriesNumber_( Q.SeriesNumber );   % con huecos: texto, "" en los huecos
      if isnumeric( Q.SeriesNumber ),     calli3d( 'add_info_rows_numbers' , 'series.SeriesNumber'      , numel( Q.SeriesNumber      ) ,                double( Q.SeriesNumber )      , planeIdx_( Q , numel( Q.SeriesNumber      ) ) , 1 );
      elseif ~isempty( Q.SeriesNumber ),  calli3d( 'add_info_rows_text' ,    'series.SeriesNumber'      , numel( Q.SeriesNumber      ) , dollar( clean( Q.SeriesNumber ) )      , planeIdx_( Q , numel( Q.SeriesNumber      ) ) , 1 );
      end;                                                                                  catch E, warning( 'write_I3D:series' , 'info.series.SeriesNumber: %s'      , E.message ); end; end
    if isfield( Q ,'SeriesDescription' ), try, calli3d( 'add_info_rows_text' ,    'series.SeriesDescription' , numel( Q.SeriesDescription ) , dollar( clean( Q.SeriesDescription ) ) , planeIdx_( Q , numel( Q.SeriesDescription ) ) , 1 ); catch E, warning( 'write_I3D:series' , 'info.series.SeriesDescription: %s' , E.message ); end; end
    if isfield( Q ,'SeriesInstanceUID' ), try, calli3d( 'add_info_rows_text' ,    'series.SeriesInstanceUID' , numel( Q.SeriesInstanceUID ) , dollar( clean( Q.SeriesInstanceUID ) ) , planeIdx_( Q , numel( Q.SeriesInstanceUID ) ) , 1 ); catch E, warning( 'write_I3D:series' , 'info.series.SeriesInstanceUID: %s' , E.message ); end; end
    R.INFO = rmfields( R.INFO , 'series' );
  end
  if isfield( R.INFO ,'planes' )
    Q = R.INFO.planes;
    calli3d( 'add_comment' , ' Planes (planes: k fastest, then t)' );
    if isfield( Q ,'Filename' ),                   try, calli3d( 'add_info_rows_text' , 'planes.Filename'                   , numel( Q.Filename                   ) ,                Q.Filename                     , planeIdx_( Q , numel( Q.Filename                   ) ) , 1 ); catch E, warning( 'write_I3D:planes' , 'info.planes.Filename: %s'                   , E.message ); end; end   % ya con $DICOMDIR$ y sus $$
    if isfield( Q ,'MediaStorageSOPInstanceUID' ), try, calli3d( 'add_info_rows_text' , 'planes.MediaStorageSOPInstanceUID' , numel( Q.MediaStorageSOPInstanceUID ) , dollar( clean( Q.MediaStorageSOPInstanceUID ) ) , planeIdx_( Q , numel( Q.MediaStorageSOPInstanceUID ) ) , 1 ); catch E, warning( 'write_I3D:planes' , 'info.planes.MediaStorageSOPInstanceUID: %s' , E.message ); end; end
    R.INFO = rmfields( R.INFO , 'planes' );
  end

  if ~isa( fname , 'function_handle' ), calli3d( 'write' , fname ); end   % un miembro: lo escribe write_MI3D, con los demas
  clearvars('CLEAN');
end


function R = toR_( S )
%TOR_  un DICOMstack (o un I3D que lleva el suyo en INFO.DICOMstack) -> una R como
% la de read_I3D: X Y Z T SpatialTransform data thumbnail INFO. En INFO, los
% atributos comunes ya en su forma de escribir (fila de numeros o texto),
% series.* y planes.* [nK nT], y planes.Filename con las rutas absolutas
  if isa( S ,'I3D') && isfield( S.INFO ,'DICOMstack')
    I = S;
    S = S.INFO.DICOMstack;
  elseif isa( S ,'DICOMstack') && numel( S ) == 1
    I = S.IMAGE;
  elseif isa( S ,'DICOMstack') && numel( S ) > 1
    error( 'write_I3D:input' , 'A single stack was expected.' );
  else
    error( 'write_I3D:input' , 'A single DICOMstack, an I3D or a struct like the one of read_I3D was expected.');
  end

  R = struct();
  R.X = double( I.X(:) );
  R.Y = double( I.Y(:) );
  R.Z = double( I.Z(:) );
  R.T = double( I.T(:) );
  R.SpatialTransform = double( I.SpatialTransform );
  R.data = I.data;
  if isfield( I.INFO , 'thumbnail' ), R.thumbnail = I.INFO.thumbnail; end
  
  % la info comun
  R.INFO = S.commonINFO;
  R.INFO = rmfields( R.INFO ,'Filename');   % Filename: una ruta absoluta (las rutas van en planes.Filename)
  R.INFO.PlaneName = S.PlaneName;
  f = fieldnames( R.INFO );
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
  w = fun( '^xSeries.*'             , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^Series.*'              , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^xStudy.*'              , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^Study.*'               , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^xPatient.*'            , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^Patient.*'             , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^PlaneName'             , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^Modality'              , f ); f = [ f( w) ; f(~w) ];
  w = fun( '^Private_'              , f ); f = [ f(~w) ; f( w) ];
  R.INFO = reorderstructure( R.INFO , f{:} );

  % las series involucradas
  [~,R.INFO.involvedSeries] = S.allInvolvedSeries;
  
  % plano a plano: la serie y el DICOM de cada uno
  try
    C = S.commonINFO;
    Suid  = repmat( {''} , size(S,3:4) );     % '' (no NaN ni []): un plano sin DICOM
    Sn    = zeros( size(S,3:4) );
    Sd    = repmat( {''} , size(S,3:4) );
    Iuid  = repmat( {''} , size(S,3:4) );
    Ifn   = repmat( {''} , size(S,3:4) );
    planeIdx = repmat( {''} , size(S,3:4) );
    for k = 1:size( S ,3)
      for f = 1:size( S ,4)
        planeIdx{k,f} = sprintf( 'data(:,:,%d,%d)' , k , f );
        
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

        Ifn{k,f} = char( S.ffiles{k,f} );         % la ruta absoluta; el escritor la pone relativa a $DICOMDIR$
      end
    end
    R.INFO.series = struct( 'SeriesNumber' , Sn , 'SeriesDescription' , {Sd} , 'SeriesInstanceUID' , {Suid} , 'planeIdx' , {planeIdx} );
    R.INFO.planes = struct( 'Filename' , {Ifn} , 'MediaStorageSOPInstanceUID' , {Iuid} , 'planeIdx' , {planeIdx} );

  catch LE
    warning( 'write_I3D:planes' , 'info.series / info.planes not written: %s' , LE.message );
  end

end


function c = planeIdx_( Q , n )
%PLANEIDX_  los comentarios de las n filas de series.* / planes.*: Q.planeIdx
% ('data(:,:,k,t)'); vacios si Q no lo trae (o no son n)
  if isfield( Q , 'planeIdx' ) && iscellstr( Q.planeIdx ) && numel( Q.planeIdx ) == n
    c = Q.planeIdx(:);
  else
    c = repmat( {''} , n , 1 );
  end
end


function v = seriesNumber_( v )
%SERIESNUMBER_  series.SeriesNumber: numeros si son todos finitos; con huecos (un plano
% sin SeriesNumber, NaN), texto con "" en los huecos (los numeros por i3d_num2str, como
% los escribe la DLL); todos huecos: {} (no se escribe). Un cell (read_I3D de un
% fichero con huecos) ya es texto
  if iscell( v ), return; end
  v = double( v );
  if all( isfinite( v(:) ) ), return; end
  if ~any( isfinite( v(:) ) ), v = {}; return; end
  loadI3Dlibrary();                                  % write_MI3D no la carga
  t = repmat( {''} , size( v ) );
  for i = find( isfinite( v(:) ) ).', t{i} = calllib( 'i3d' , 'i3d_num2str' , v(i) ); end
  v = t;
end


function b = bytes_( v )
%BYTES_  lo que ocupa v en memoria
  w = whos( 'v' );  b = w.bytes;
end


function d = commonFolder_( files )
%COMMONFOLDER_  la carpeta comun de todos los ficheros (sin el separador final)
  files = files( ~cellfun( 'isempty' , files ) );
  if isempty( files ), d = ''; return; end
  M = char( files(:) );
  n = find( any( M ~= M(1,:) , 1 ) , 1 ) - 1;               % lo comun, caracter a caracter
  if isempty( n ), n = size( M , 2 ); end
  d = fileparts( M( 1 , 1:n ) );
end


function loadI3Dlibrary()
  % loadI3Dlibrary  i3d.dll de esta carpeta, una vez (lo mismo en read_I3D)
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
