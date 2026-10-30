function exportStackToI3Dfile( DS , f , modo )
%EXPORTSTACKTOI3DFILE   el @I3D de un stack (DS.IMAGE) a un .i3d, con calllib a i3d.dll
%
%   exportStackToI3Dfile( DS(d) , 'serie.i3d' , modo )    modo: 'full' | 'lazy' | 't1'
%
% Parte del ejemplo export_to_i3d.m (en fichero propio para que el script se
% pueda ejecutar por secciones). Necesita enableI3Dlibrary antes.
  I = DS.IMAGE;
  C = DS.commonINFO;                 % lo comun a todos los planos del stack
  D = I.data;
  T = I.T;
  U = DS.uids;                       % el SOPInstanceUID de cada plano (k,t)
  if strcmp( modo , 't1' )           % solo el primer instante
    D = D(:,:,:,1,:);  T = T(1);  U = U(:,1);
  end

  w = calllib( 'i3d' , 'i3d_new' );
  CW = onCleanup( @() calllib( 'i3d' , 'i3d_free' , w ) );
  chk = @( rc ) chk_( rc , w , f );

  % ---- la primera linea
  chk( calllib( 'i3d' , 'i3d_set_option' , w , 'Comment' , sprintf( 'export_to_i3d %s (%s)' , datestr( now , 'yyyy-mm-dd HH:MM:SS' ) , modo ) ) );

  % ---- data, rejillas y transform
  chk( calllib( 'i3d' , 'i3d_set_data' , w , D , class( D ) , ndims( D ) , int64( size( D ) ) ) );
  chk( calllib( 'i3d' , 'i3d_set_Xgrid' , w , double( I.X ) , numel( I.X ) ) );
  chk( calllib( 'i3d' , 'i3d_set_Ygrid' , w , double( I.Y ) , numel( I.Y ) ) );
  chk( calllib( 'i3d' , 'i3d_set_Zgrid' , w , double( I.Z ) , numel( I.Z ) ) );
  chk( calllib( 'i3d' , 'i3d_set_Tgrid' , w , double( T )   , numel( T ) ) );
  chk( calllib( 'i3d' , 'i3d_set_transform' , w , reshape( double( I.SpatialTransform ).' , 1 , [] ) ) );   % POR FILAS

  % ---- rescale y window, si son comunes al stack
  if all( isfield( C , { 'RescaleSlope' , 'RescaleIntercept' } ) )
    chk( calllib( 'i3d' , 'i3d_set_rescale' , w , double( C.RescaleSlope(1) ) , double( C.RescaleIntercept(1) ) , 'DICOM' ) );
  end
  if all( isfield( C , { 'WindowCenter' , 'WindowWidth' } ) ) && isnumeric( C.WindowCenter ) && ~isempty( C.WindowCenter )
    chk( calllib( 'i3d' , 'i3d_set_window' , w , double( C.WindowCenter(1) ) , double( C.WindowWidth(1) ) , 'DICOM' ) );
  end

  % ---- el thumbnail (uint8 gris), como aux.thumbnailK (PNG)
  if isfield( I.INFO , 'thumbnailK' ) && isa( I.INFO.thumbnailK , 'uint8' )
    th = I.INFO.thumbnailK;
    chk( calllib( 'i3d' , 'i3d_add_aux' , w , 'thumbnailK' , th , 'uint8' , ndims( th ) , int64( size( th ) ) ) );
  end

  % ---- info.*: a la vista (true) o en la parte oculta (false)
  VIS = true;  HID = false;
  chk( calllib( 'i3d' , 'i3d_add_comment' , w , '-- Series' ) );
  info_( w , chk , 'SeriesNumber'      , DS.SeriesNumber      , VIS );
  info_( w , chk , 'SeriesDescription' , DS.SeriesDescription , VIS );
  info_( w , chk , 'PlaneName'         , DS.PlaneName         , VIS );
  for a = { 'Modality' , 'StudyDate' , 'StudyTime' , 'StudyDescription' , 'Manufacturer' , 'ManufacturerModelName' }
    if isfield( C , a{1} ), info_( w , chk , a{1} , C.( a{1} ) , VIS ); end
  end
  chk( calllib( 'i3d' , 'i3d_add_comment' , w , '-- Patient and UIDs' ) );
  for a = { 'PatientName' , 'PatientID' , 'PatientBirthDate' , 'PatientSex' , 'StudyInstanceUID' , 'SeriesInstanceUID' }
    if isfield( C , a{1} ), info_( w , chk , a{1} , C.( a{1} ) , HID ); end
  end
  % una fila por plano (k la mas rapida); comments NULL: el comentario de cada
  % fila lo pone la DLL (el bloque de data del plano)
  sop = cellfun( @char , U(:).' , 'un' , 0 );
  chk( calllib( 'i3d' , 'i3d_add_info_rows_text' , w , 'planes.SOPInstanceUID' , numel( sop ) , sop , libpointer( 'stringPtrPtr' ) , HID ) );

  % ---- 'lazy': cada plano, una referencia a su .dcm
  if strcmp( modo , 'lazy' )
    chk( calllib( 'i3d' , 'i3d_set_option' , w , 'Lazy' , '1' ) );
    % 'Verify' 1 (el default): la DLL lee cada .dcm y solo lo referencia si da
    % EXACTAMENTE su plano de data; si no, ese plano se guarda dentro
    chk( calllib( 'i3d' , 'i3d_set_option' , w , 'Verify' , '1' ) );
    F = DS.ffiles;                   % F{k,t}: el .dcm del plano data(:,:,k,t)
    for t = 1:size( F , 2 )
      for k = 1:size( F , 1 )
        chk( calllib( 'i3d' , 'i3d_set_plane_ref' , w , k , t , strrep( char( F{k,t} ) , '\' , '/' ) ) );
      end
    end
  end

  chk( calllib( 'i3d' , 'i3d_write' , w , f ) );       % todo o nada
end

function chk_( rc , w , f )
%CHK_  cada funcion de la DLL devuelve 0 si va bien; si no, el mensaje lo da i3d_wlast_error
  if rc ~= 0
    error( 'exportStackToI3Dfile:i3d' , '%s: %s' , f , calllib( 'i3d' , 'i3d_wlast_error' , w ) );
  end
end

function info_( w , chk , key , v , vis )
%INFO_  info.key = v: texto o numeros
  if isstruct( v )                     % nombre DICOM (PN): Familia^Nombre
    c = struct2cell( v );  v = strjoin( c( cellfun( @ischar , c ) ).' , '^' );
  end
  if iscell( v ), v = v{1}; end
  if ischar( v )
    chk( calllib( 'i3d' , 'i3d_add_info_text' , w , key , strtrim( v ) , vis , '' ) );
  elseif isnumeric( v ) && ~isempty( v ) && all( isfinite( v(:) ) )
    chk( calllib( 'i3d' , 'i3d_add_info_numbers' , w , key , double( v(:).' ) , numel( v ) , vis , '' ) );
  end
end
