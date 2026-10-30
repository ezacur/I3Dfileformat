function S = i3d_read_( f , mode , vars , win )
%I3D_READ_  everything the DLL reader gives of an .i3d, as one struct (read_I3D)
%
%   S = i3d_read_( f , mode , vars , win )
%
%   mode  true: todo; false: solo la cabecera (ni data ni los aux);
%         'firstFrame': data(:,:,:,1,c...)
%   vars  { 'NOMBRE' , valor , ... }: variables $NOMBRE$ que mandan sobre las del
%         fichero ({} ninguna)
%   win   [] el fichero entero, o [offset length]: los bytes de un miembro de un
%         .mi3d (mi3d_range)
%
%   S     X Y Z T SpatialTransform data rescale window missing (lo/hi 1-based,
%         inclusivos) entries ({key subs value}) header file hidden binstart aux
%         (name data error)
%
% ERROR IDENTIFIERS: read_I3D:<id>, el identificador del lector.
  enableI3Dlibrary;
  names = vars(1:2:end);  values = vars(2:2:end);
  if isempty( names ), names = libpointer( 'stringPtrPtr' );  values = libpointer( 'stringPtrPtr' ); end
  if isempty( win )
    h = calllib( 'i3d' , 'i3d_open_vars' , f , numel( vars ) / 2 , names , values );
  else
    h = calllib( 'i3d' , 'i3d_open_window' , f , win(1) , win(2) , numel( vars ) / 2 , names , values );
  end
  if isNull( h ), i3d_err_( 'read_I3D' , 'f' , [] ); end
  C = onCleanup( @() calllib( 'i3d' , 'i3d_close' , h ) );
  chk = @( rc ) rc == 0 || i3d_err_( 'read_I3D' , 'f' , h );

  S = struct();
  for a = 'XYZT'
    n = double( calllib( 'i3d' , 'i3d_grid_length' , h , int8( a ) ) );
    [ rc , ~ , g ] = calllib( 'i3d' , 'i3d_grid_copy' , h , int8( a ) , zeros( 1 , n ) , n );  chk( rc );
    S.( a ) = reshape( g , 1 , [] );
  end
  [ rc , ~ , A ] = calllib( 'i3d' , 'i3d_transform' , h , zeros( 1 , 16 ) );  chk( rc );
  S.SpatialTransform = reshape( A , 4 , 4 ).';                     % POR FILAS
  [ rc , ~ , nd , dims ] = calllib( 'i3d' , 'i3d_data_shape' , h , 0 , zeros( 1 , 16 , 'int64' ) );  chk( rc );
  dims = double( dims( 1:nd ) );
  type = calllib( 'i3d' , 'i3d_data_type' , h );
  S.data = [];
  if ischar( mode ), dims(4) = 1;  fn = 'i3d_read_first_frame';  nb = calllib( 'i3d' , 'i3d_first_frame_bytes' , h );
  else,                            fn = 'i3d_read_data';         nb = calllib( 'i3d' , 'i3d_data_bytes' , h );
  end
  if ischar( mode ) || mode
    [ rc , ~ , D ] = calllib( 'i3d' , fn , h , zeros( dims , type ) , nb );  chk( rc );
    S.data = reshape( D , dims );
  end
  [ rc , ~ , s , i ] = calllib( 'i3d' , 'i3d_rescale' , h , 0 , 0 );  chk( rc );
  S.rescale = [ s i ];
  [ rc , ~ , hw , c , w ] = calllib( 'i3d' , 'i3d_window' , h , 0 , 0 , 0 );  chk( rc );
  if hw, S.window = [ c w ]; else, S.window = []; end
  S.missing = struct( 'lo' , {} , 'hi' , {} );
  for m = 1:calllib( 'i3d' , 'i3d_missing_count' , h )
    [ rc , ~ , nd , lo , hi ] = calllib( 'i3d' , 'i3d_missing_box' , h , m - 1 , 0 , zeros( 1 , 16 , 'int64' ) , zeros( 1 , 16 , 'int64' ) );  chk( rc );
    S.missing(m,1).lo = double( lo( 1:nd ) ) + 1;                  % 1-based, inclusivo
    S.missing(m,1).hi = double( hi( 1:nd ) );
  end
  ne = calllib( 'i3d' , 'i3d_entry_count' , h );
  S.entries = cell( ne , 3 );
  for e = 1:ne
    S.entries(e,:) = { calllib( 'i3d' , 'i3d_entry_key' , h , e - 1 ) , calllib( 'i3d' , 'i3d_entry_subs' , h , e - 1 ) , calllib( 'i3d' , 'i3d_entry_value' , h , e - 1 ) };
  end
  S.header = calllib( 'i3d' , 'i3d_header' , h );
  S.file = f;
  S.hidden = calllib( 'i3d' , 'i3d_is_hidden' , h ) == 1;
  S.binstart = double( calllib( 'i3d' , 'i3d_binary_start' , h ) );
  % aux.NAME: uno que el lector no decodifica no se calla: data [] y su error
  na = calllib( 'i3d' , 'i3d_aux_count' , h );
  S.aux = struct( 'name' , cell( na , 1 ) , 'data' , [] , 'error' , '' );
  for a = 1:na
    n = calllib( 'i3d' , 'i3d_aux_name' , h , a - 1 );
    S.aux(a).name = n;
    if ~( ischar( mode ) || mode ), S.aux(a).error = 'notRead: readdata is false';  continue; end
    [ rc , ~ , ~ , nd , ad ] = calllib( 'i3d' , 'i3d_aux_shape' , h , n , 0 , zeros( 1 , 16 , 'int64' ) , libpointer( 'stringPtrPtr' ) );
    if rc == 0
      ad = double( ad( 1:nd ) );  if isscalar( ad ), ad(2) = 1; end
      [ rc , ~ , ~ , v ] = calllib( 'i3d' , 'i3d_aux_read' , h , n , zeros( ad , calllib( 'i3d' , 'i3d_aux_type' , h , n ) ) , prod( ad ) * numel( typecast( zeros( 1 , calllib( 'i3d' , 'i3d_aux_type' , h , n ) ) , 'uint8' ) ) );
    end
    if rc == 0
      S.aux(a).data = reshape( v , ad );
    else
      S.aux(a).error = sprintf( '%s: %s' , calllib( 'i3d' , 'i3d_last_error_id' , h ) , calllib( 'i3d' , 'i3d_last_error' , h ) );
    end
  end
end
