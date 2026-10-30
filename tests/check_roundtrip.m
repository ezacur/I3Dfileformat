function check_roundtrip( outdir )
%CHECK_ROUNDTRIP   write_I3D -> three readers, compared BYTE FOR BYTE against the original
%
%   check_roundtrip
%   check_roundtrip( outdir )   the same, and the files STAY in outdir (to open
%                               them elsewhere: a viewer, another reader)
%
% Escribe una bateria de @I3D con write_I3D -- que escribe SOLO la forma
% canonica (SPEC 9): el encoding lo fija el tipo, jpegls para (u)int8/(u)int16 y
% zlib para el resto --, con cada una de sus opciones; guarda los originales en
% un .mat (-v7) y los lee con TRES lectores: la DLL desde MATLAB (aqui, calllib), y la DLL y el de
% referencia en Python (tests/check_roundtrip.py). Rejillas, transform, data y
% el thumbnail (PNG) bit a bit. Ademas:
%   - cada fichero que escribe write_I3D se comprueba que ES canonico
%     (canon_): subindices completos, transform de 12 numeros, solo @a:b,
%     encodings del perfil. Un atajo que se cuele en el escritor se ve aqui;
%   - ficheros hechos o editados a mano, que NO son canonicos y los lectores
%     tienen que aceptar igual (la gramatica general): cabecera editada, offsets
%     @a+n / @a+Inf / @a:EOF, un bloque raw;
%   - controles negativos: un byte corrupto, un crc que no casa con el dato.
% Lanza si algun caso falla.

  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  if nargin
    % a directory of its own: the python half globs EVERY .i3d in it
    if exist( outdir , 'dir' ) && ~isempty( dir( fullfile( outdir , '*.i3d' ) ) )
      error('check_roundtrip:outdirNotEmpty','%s already has .i3d files: give an empty or new directory.', outdir );
    end
    if ~exist( outdir , 'dir' ), mkdir( outdir ); end
    dn = outdir;
  else
    [ dn , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>
  end

  rng( 7 );
  c = cosd(30); s = sind(30);
  C = {};
  % nombre, data, X, Y, Z, T, SpatialTransform
  C(end+1,:) = { 'int16_rot'     , int16( randi([-1024 3000],[5 4 3 2]) ) , (0:4)*0.703125 , (0:3)*0.1 , [0 8 16.000000000000004] , (0:1)*38.5 , [c 0 -s -180.1; 0 1 0 -95.3; s 0 c 41; 0 0 0 1] };
  C(end+1,:) = { 'uint16_1slice' , uint16( randi([0 65535],[7 6]) )        , (0:6)*1.40625  , (0:5)*1.40625 , 0 , 0 , eye(4) };
  F = single( randn( [4 3 2 2 3] ) );  F(1) = NaN;  F(2) = -0;  F(3) = Inf;  F(4) = -Inf;
  C(end+1,:) = { 'single_rgb'    , F                                        , 0:3 , 0:2 , [0 2] , [0 1] , diag([2 2 2 1]) };
  C(end+1,:) = { 'double_tensor' , randn( [3 3 2 2 3 3] )                   , [0 1 3] , [0 0.5 1] , [-1 1] , [0 10] , [1 0.2 0 5; 0 1 0 6; 0 0 -1 7; 0 0 0 1] };
  C(end+1,:) = { 'logical'       , rand( [4 4 4] ) > 0.5                    , 0:3 , 0:3 , 0:3 , 0 , eye(4) };
  C(end+1,:) = { 'uint8_nonunif' , uint8( randi([0 255],[4 3 2]) )          , [0 1 3 6] , [0 1 2] , [0 1] , 0 , eye(4) };
  C(end+1,:) = { 'int64_ext'     , int64( [intmin('int64') intmax('int64'); -1 0] ) , [0 1] , [0 1] , 0 , 0 , eye(4) };
  C(end+1,:) = { 'uint64_max'    , uint64( [intmax('uint64') 0 1] )         , 0 , [0 1 2] , 0 , 0 , eye(4) };
  C(end+1,:) = { 'translation'   , int16( randi([-9 9],[3 3 2 3]) )        , [0 1 2] , [0 1 2] , [0 1] , [0 5 10] , [1 0 0 -12.5; 0 1 0 7; 0 0 1 0.1; 0 0 0 1] };
  z = cumsum( repmat( 0.1 , 1 , 10 ) ) - 0.1;          % "casi" uniforme: tiene que ir como LISTA
  C(end+1,:) = { 'almost_uniform', int8( randi([-128 127],[2 2 10]) )       , [0 1] , [0 1] , z , 0 , eye(4) };
  % uint8 con 3 componentes: lleva COMPONENTES a jpegls (un bloque por plano Y
  % por componente, data(:,:,k,t,c))
  C(end+1,:) = { 'uint8_rgb'     , uint8( randi([0 255],[4 3 2 2 3]) )      , 0:3 , 0:2 , [0 2] , [0 1] , eye(4) };

  % los que escribe write_I3D (el crc ya no es una variante: va en todos)
  WRITTEN = { 'canon' , 'visall' , 'volume' , 'tblocks' , 'chunked' , 'hidden' , 'hidekeys' , 'hidekeysb' };
  names = C(:,1);
  for i = 1:size( C , 1 )
    I = I3D( C{i,2} , 'X',C{i,3} , 'Y',C{i,4} , 'Z',C{i,5} , 'T',C{i,6} );
    I.SpatialTransform = C{i,7};
    % un thumbnail en I.INFO: tiene que viajar como aux (PNG) y volver identico
    TH = uint8( randi( [0 255] , [ 7 5 1 2 ] ) );
    I.INFO = struct( 'thumbnailK' , TH );
    % y un DICOMstack minimo, para que haya info.*: StudyDate (de los visibles
    % por defecto) y PatientName (que va a la parte oculta)
    nk = size( C{i,2} , 3 );  nt = size( C{i,2} , 4 );
    I.INFO.DICOMstack = struct( 'ffiles' , { repmat( {''} , nk , nt ) } , 'uids' , { repmat( {''} , nk , nt ) } , ...
                                'infos' , { repmat( { struct() } , nk , nt ) } , ...
                                'commonINFO' , struct( 'StudyDate' , '20261024' , 'PatientName' , 'Test^Name' ) );
    write_I3D( I , fullfile( dn , [ names{i} '_canon.i3d' ] ) );
    % por defecto (SPEC 1.2, 9) se ve todo lo que hace falta para leer data --
    % TODOS los bloques de data y los aux -- y los info.* de 'Visible'
    % (StudyDate); el resto de info.* (PatientName) va a la parte oculta, que el
    % lector despliega
    fc = fullfile( dn , [ names{i} '_canon.i3d' ] );
    hc = fileread( fc );  hc = hc( 1:strfind( hc , [ newline '---' newline ] ) );
    Sc = hdr_( fc );
    nvis = numel( regexp( hc , '\ndata\(' , 'start' ) );  nall = nnz( strcmp( Sc.entries(:,1) , 'data' ) );
    if isempty( strfind( hc , 'header = <hidden @0:' ) ) || nvis ~= nall || isempty( strfind( hc , 'aux.thumbnailK' ) ) || ...
       isempty( strfind( hc , 'info.StudyDate' ) ) || ~isempty( strfind( hc , 'PatientName' ) ) || ...
       ~any( strcmp( Sc.entries(:,1) , 'info.PatientName' ) )
      error('check_roundtrip:visible','%s: by default all data and aux and info.StudyDate are visible, info.PatientName hidden (%d of %d data lines visible):\n%s', names{i} , nvis , nall , hc );
    end
    % todo a la vista ('Visible','all'): la forma de antes, y la base de los
    % ficheros editados a mano de abajo
    write_I3D( I , fullfile( dn , [ names{i} '_visall.i3d' ] ) , 'Visible' , 'all' );
    % (zlib) todo data en UN bloque, y un comentario propio en la primera linea
    write_I3D( I , fullfile( dn , [ names{i} '_volume.i3d' ] ) , 'Blocks' , 'volume' , 'Comment' , 'check_roundtrip # with a hash' );
    % (zlib) un bloque por instante; y bloques DIMINUTOS, que obligan a trocear por k
    write_I3D( I , fullfile( dn , [ names{i} '_tblocks.i3d' ] ) , 'Blocks' , 't' );
    x1 = C{i,2}(1);  if islogical( x1 ), x1 = uint8( x1 ); end    % logical se escribe como uint8
    pl = numel( typecast( x1 , 'uint8' ) ) * size( C{i,2} , 1 ) * size( C{i,2} , 2 ) * prod( size( C{i,2} , 5:6 ) );
    write_I3D( I , fullfile( dn , [ names{i} '_chunked.i3d' ] ) , 'MaxBlockBytes' , pl );
    % OCULTA (I3Db): la misma escritura en texto y oculta, con un comentario
    % FIJO para que no las distinga la fecha; las dos direcciones del conversor
    % tienen que dar los mismos BYTES, y en la oculta no puede verse la cabecera
    fh = fullfile( dn , [ names{i} '_hidden.i3d' ] );
    write_I3D( I , fh , 'Hidden' , 'Comment' , 'check_roundtrip' );
    [ ftx , CLt ] = sandfile( '#_text_????.i3d' );  %#ok<ASGLU>
    write_I3D( I , ftx , 'Comment' , 'check_roundtrip' );
    [ fsh , CLs ] = sandfile( '#_show_????.i3d' );  %#ok<ASGLU>
    [ fhd , CLh ] = sandfile( '#_hide_????.i3d' );  %#ok<ASGLU>
    showI3Dfile( fh , fsh );  hideI3Dfile( ftx , fhd );
    by = @(f) fread_all_( f );
    if ~isequal( by( fsh ) , by( ftx ) ), error('check_roundtrip:show','%s: showI3Dfile(hidden) is not the text file byte for byte.', names{i} ); end
    if ~isequal( by( fhd ) , by( fh ) ),  error('check_roundtrip:hide','%s: hideI3Dfile(text) is not the hidden file byte for byte.', names{i} ); end
    hb = char( by( fh ).' );
    for w = { 'I3D 0.1' , 'transform' , 'data' , 'X[' , 'aux.' }
      if ~isempty( strfind( hb , w{1} ) ), error('check_roundtrip:plain','%s: "%s" is visible in the hidden file.', names{i} , w{1} ); end
    end
    % la PARTE OCULTA de la cabecera (SPEC 1.2): TODOS los info.* a un bloque
    % <hidden> ('Visible',{}: i3d_add_info_* con visible 0), en texto y en I3Db.
    % Ni la cabecera en claro ni el VOLCADO de la I3Db (lo que da el lector como
    % header) pueden mostrarlos, y transform y data siguen a la vista; e
    % showI3Dfile de la I3Db tiene que dar, byte a byte, la de texto
    fk  = fullfile( dn , [ names{i} '_hidekeys.i3d' ] );
    fkb = fullfile( dn , [ names{i} '_hidekeysb.i3d' ] );
    write_I3D( I , fk  , 'Visible' , {} , 'Comment' , 'check_roundtrip' );
    write_I3D( I , fkb , 'Visible' , {} , 'Hidden' , 'Comment' , 'check_roundtrip' );
    hk = char( by( fk ).' );  hk = hk( 1:strfind( hk , [ newline '---' newline ] ) );
    Sd = hdr_( fkb );
    for t = { hk , Sd.header }
      if isempty( strfind( t{1} , 'header = <hidden @' ) ) || ~isempty( strfind( t{1} , [ newline 'info.' ] ) ) || isempty( strfind( t{1} , 'transform' ) ) || isempty( strfind( t{1} , [ newline 'data' ] ) )
        error('check_roundtrip:hideKeys','%s: the <hidden> part is missing, an info.* is visible, or transform/data are not:\n%s', names{i} , t{1} );
      end
    end
    if ~all( ismember( { 'info.StudyDate' , 'info.PatientName' } , Sd.entries(:,1) ) )
      error('check_roundtrip:hideKeys','%s: the reader does not return the hidden info.*.', names{i} );
    end
    [ fs2 , CLs2 ] = sandfile( '#_show2_????.i3d' );  %#ok<ASGLU>
    showI3Dfile( fkb , fs2 );
    if ~isequal( by( fs2 ) , by( fk ) ), error('check_roundtrip:hideKeys','%s: showI3Dfile(I3Db with a <hidden> part) is not the text file byte for byte.', names{i} ); end
    % FORMA CANONICA de todo lo que escribio write_I3D
    for v = WRITTEN
      canon_( fullfile( dn , [ names{i} '_' v{1} '.i3d' ] ) , ndims( C{i,2} ) );
    end
    REF.( names{i} ) = struct( 'X',I.X , 'Y',I.Y , 'Z',I.Z , 'T',I.T , 'A',I.SpatialTransform , 'D',C{i,2} , 'TH',TH );
  end
  save( fullfile( dn , 'ref.mat' ) , '-struct' , 'REF' , '-v7' );

  % la prueba tambien tiene que saber FALLAR: una copia con el PRIMER byte del
  % binario alterado (es de data: detras de los bloques van los aux). Tiene que
  % detectarse: o el dato sale distinto, o el lector lanza. De la escritura SIN
  % parte oculta: en la de por defecto el primer byte es del bloque <hidden>, y
  % las ediciones de abajo (@a+Inf en el ultimo @ de la cabecera) suponen que el
  % ultimo descriptor visible es el ultimo bloque
  fid = fopen( fullfile( dn , 'int16_rot_visall.i3d' ) , 'r' );  b = fread( fid , Inf , '*uint8' );  fclose( fid );
  ib = strfind( char( b(:).' ) , [ newline '---' newline ] ) + 5;
  b(ib) = bitxor( b(ib) , uint8(1) );
  fid = fopen( fullfile( dn , 'int16_rot_corrupt.i3d' ) , 'w' );  fwrite( fid , b , 'uint8' );  fclose( fid );

  % EDITADO A MANO: X[5] -> X[999] (la anotacion [..] no se lee) y una linea
  % de comentario de mas. La cabecera cambia de longitud y los offsets no se
  % tocan: valen porque son relativos al inicio del binario. Tiene que leerse
  % IGUAL que el original
  b = b(:).';  b(ib) = bitxor( b(ib) , uint8(1) );            % deshacer la corrupcion
  s = char( b );
  k = strfind( s , [ newline '---' newline ] );
  h = s( 1:k );
  h = strrep( h , 'X[5] = ' , 'X[999] = ' );
  h = strrep( h , [ newline 'transform =' ] , [ newline '# a comment added by hand' newline 'transform =' ] );
  % que la edicion se HIZO: si no, el caso pasaria sin probar nada
  if isempty( strfind( h , 'X[999] = ' ) ) || isempty( strfind( h , 'added by hand' ) )
    error('check_roundtrip:editNotApplied','the hand edit did not apply: the test would prove nothing.');
  end
  fid = fopen( fullfile( dn , 'int16_rot_edited.i3d' ) , 'w' );
  fwrite( fid , [ uint8( h ) , b( k+1:end ) ] , 'uint8' );  fclose( fid );

  % LAS OTRAS FORMAS DEL OFFSET (no canonicas, los lectores las aceptan): el
  % mismo fichero con  @a+n  y el ultimo  @a+Inf , y con el ultimo  @a:EOF
  % (detras del offset puede ir el crc: ' crc XXXXXXXX>')
  hp = regexprep( h , '@(\d+):(\d+)(?=( crc [0-9a-f]{8})?>)' , '@$1+${num2str(str2double($2)-str2double($1)+1)}' );   % @a:b inclusivo
  hp = regexprep( hp , '@(\d+)\+(\d+)(?=( crc [0-9a-f]{8})?>[^@]*$)' , '@$1+Inf' );
  he = regexprep( h , '@(\d+):(\d+)(?=( crc [0-9a-f]{8})?>[^@]*$)' , '@$1:EOF' );
  if isempty( strfind( hp , '+Inf' ) ) || isempty( strfind( he , ':EOF' ) )
    error('check_roundtrip:editNotApplied','the offset edits did not apply.');
  end
  fid = fopen( fullfile( dn , 'int16_rot_plus.i3d' ) , 'w' );  fwrite( fid , [ uint8( hp ) , b( k+1:end ) ] , 'uint8' );  fclose( fid );
  fid = fopen( fullfile( dn , 'int16_rot_eof.i3d' ) , 'w' );   fwrite( fid , [ uint8( he ) , b( k+1:end ) ] , 'uint8' );  fclose( fid );

  % RAW (no canonico): data entero en UN bloque raw, a mano, con la cabecera del
  % original. ('order' ya no existe: un bloque es siempre i j k t c)
  D0 = C{ strcmp( names , 'int16_rot' ) , 2 };
  hl = strsplit( h , newline );
  hl = hl( ~strncmp( hl , 'data' , 4 ) & ~strncmp( hl , 'aux.' , 4 ) & ~cellfun( 'isempty' , hl ) );   % su binario solo lleva data
  hl{end+1} = sprintf( 'data(:,:,:,:) = <raw int16 @0:%d>' , numel( D0 ) * 2 - 1 );   % @a:b inclusivo
  fid = fopen( fullfile( dn , 'int16_rot_rawhand.i3d' ) , 'w' );
  fwrite( fid , [ strjoin( hl , newline ) , newline , '---' , newline ] , 'char' );
  fwrite( fid , D0(:) , 'int16' );  fclose( fid );

  % CRC: el crc es de los bytes DECODIFICADOS (SPEC 4, 2026-10-14). Alterar un
  % byte comprimido haria fallar al DECODIFICADOR antes que al crc y no probaria
  % nada del crc; asi que el dato queda intacto y se altera UNA cifra del crc del
  % primer bloque: decodifica bien y no casa, y los tres lectores tienen que
  % RECHAZARLO con badCRC -- no basta con que el dato salga distinto
  I0 = I3D( D0 , 'X',REF.int16_rot.X , 'Y',REF.int16_rot.Y , 'Z',REF.int16_rot.Z , 'T',REF.int16_rot.T );
  I0.SpatialTransform = REF.int16_rot.A;
  fb = fullfile( dn , 'int16_rot_crcbad.i3d' );
  write_I3D( I0 , fb );
  fid = fopen( fb , 'r' );  b = fread( fid , Inf , '*uint8' );  fclose( fid );
  s = char( b(:).' );
  q = strfind( s , ' crc ' );
  if isempty( q ), error('check_roundtrip:editNotApplied','the canonical file has no crc: the crc test would prove nothing.'); end
  q = q(1) + 5 + 7;                                          % la ULTIMA cifra hex del primer crc
  b(q) = uint8( char( '0' + ( s(q) == '0' ) ) );             % otra cifra: '0' -> '1', cualquier otra -> '0'
  fid = fopen( fb , 'w' );  fwrite( fid , b , 'uint8' );  fclose( fid );

  % ---------------------------------------------------------------- la DLL desde MATLAB
  % la TERCERA lectura: la DLL dentro de MATLAB (read_I3D -> i3d.dll, calllib),
  % contra los originales, bit a bit. zlib, CharLS, lodepng y DCMTK estan
  % DENTRO: un unsupportedEncoding aqui es un fallo, no una tolerancia
  nbad = 0;
  bits = @(x) typecast( x(:).' , 'uint8' );
  for i = 1:size( C , 1 )
    R = REF.( names{i} );
    Dref = C{i,2};  if islogical( Dref ), Dref = uint8( Dref ); end
    for enc = [ WRITTEN , { 'corrupt' , 'edited' , 'plus' , 'eof' , 'rawhand' , 'crcbad' } ]
      f = fullfile( dn , [ names{i} '_' enc{1} '.i3d' ] );
      if ~exist( f , 'file' ), continue; end
      try
        [ J , S ] = read_I3D( f );
        same = isequal( bits( S.X ) , bits( R.X ) ) && isequal( bits( S.Y ) , bits( R.Y ) ) && ...
               isequal( bits( S.Z ) , bits( R.Z ) ) && isequal( bits( S.T ) , bits( R.T ) ) && ...
               isequal( bits( S.SpatialTransform ) , bits( R.A ) ) && ...
               strcmp( class( S.data ) , class( Dref ) ) && isequal( size( S.data ) , size( Dref ) ) && ...
               isequal( bits( S.data ) , bits( Dref ) ) && isequal( bits( J.DATA ) , bits( Dref ) );
        % el PRIMER INSTANTE (SPEC 5.7), leyendo solo sus bloques: data(:,:,:,1,c...)
        % bit a bit. Las dimensiones de componente, en una (si no, el indexado de
        % MATLAB las plegaria distinto)
        [ ~ , S1 ] = read_I3D( f , 'firstFrame' );
        sz = size( Dref );  sz(end+1:4) = 1;
        R1 = reshape( Dref , [ sz(1:4) , prod( sz(5:end) ) ] );  R1 = R1(:,:,:,1,:);
        same = same && strcmp( class( S1.data ) , class( Dref ) ) && numel( S1.data ) == numel( R1 ) && ...
               size( S1.data , 4 ) == 1 && isequal( bits( S1.data ) , bits( R1 ) ) && isequal( S1.T , S.T(1) );
        % el thumbnail (los ficheros hechos a mano -- rawhand, crcbad -- no lo llevan)
        if ~any( strcmp( enc{1} , { 'rawhand' , 'crcbad' } ) )
          same = same && isfield( J.INFO , 'thumbnailK' ) && isequal( J.INFO.thumbnailK , R.TH );
        end
        if strcmp( enc{1} , 'corrupt' ), good = ~same; else, good = same; end
        if strcmp( enc{1} , 'crcbad' ), good = false; end   % TENIA que lanzar badCRC
        what = 'read';
      catch LE
        % errores esperados: badCRC con el crc roto; cualquier error del
        % decodificador con el byte corrupto (tambien es detectarlo)
        good = ( strcmp( enc{1} , 'crcbad' ) && strcmp( LE.identifier , 'read_I3D:badCRC' ) ) || ...
               ( strcmp( enc{1} , 'corrupt' ) && strncmp( LE.identifier , 'read_I3D:' , 9 ) );
        what = LE.identifier;
      end
      nbad = nbad + ~good;
      fprintf( '  %s %-16s %-8s dll: %s\n' , repmat( 'ok  ' , 1 , good ) , names{i} , enc{1} , what );
      if ~good, fprintf( '  FAIL\n' ); end
    end
  end
  if nbad, error('check_roundtrip:dllFailed','%d file(s) failed through the DLL (calllib).', nbad ); end

  % las cabeceras, para MIRARLAS
  for g = { 'int16_rot_canon' , 'double_tensor_canon' , 'uint8_rgb_canon' }
    h = fileread( fullfile( dn , [ g{1} '.i3d' ] ) );
    h = h( 1:strfind( h , [ newline '---' newline ] ) + 4 );
    fprintf( '----- %s\n%s\n' , g{1} , h );
  end

  % sin la barra final: '...\"' escapa la comilla en la linea de comandos
  dq = regexprep( dn , '[\\/]+$' , '' );
  [ st , out ] = system( sprintf( '"%s" "%s" "%s"' , i3d_python() , fullfile( here , 'check_roundtrip.py' ) , dq ) );
  fprintf( '%s' , out );
  if st ~= 0, error('check_roundtrip:failed','round trip failed (see above).'); end
end

function canon_( f , nd )
%CANON_  que el fichero que escribio write_I3D sea CANONICO (SPEC 9). La cabecera
% la da el lector C++ en claro (tambien de un I3Db). nd: ndims de data
  S = hdr_( f );
  bad = @( why ) error( 'check_roundtrip:notCanonical' , '%s is not canonical: %s' , f , why );
  E = S.entries;
  % transform: siempre, y con sus 12 numeros
  t = E( strcmp( E(:,1) , 'transform' ) , 3 );
  if numel( t ) ~= 1 || numel( strsplit( strtrim( t{1} ) ) ) ~= 12, bad( 'transform is not 12 numbers' ); end
  for e = 1:size( E , 1 )
    k = E{e,1};  v = E{e,3};
    % offsets: solo @a:b
    at = regexp( v , '@[^\s>]+' , 'match' );
    if any( cellfun( 'isempty' , regexp( at , '^@\d+:\d+$' , 'once' ) ) ), bad( [ 'an offset that is not @a:b: ' , v ] ); end
    if strcmp( k , 'data' )
      sb = strsplit( E{e,2} , ',' );
      if isempty( E{e,2} ) || numel( sb ) < max( 4 , nd ), bad( [ 'data without its full subscript: data(' , E{e,2} , ')' ] ); end
      if ~all( strcmp( sb(1:2) , ':' ) ), bad( [ 'i or j is not '':'' : data(' , E{e,2} , ')' ] ); end
      if any( ~cellfun( 'isempty' , regexp( sb , '^\s*(\d+:|:\d+)\s*$' , 'once' ) ) ), bad( [ 'an open range: data(' , E{e,2} , ')' ] ); end
      if any( strcmp( sb(5:end) , ':' ) ), bad( [ 'a component dimension as '':'' : data(' , E{e,2} , ')' ] ); end
      enc = regexp( v , '^<(\w+)' , 'tokens' , 'once' );
      if isempty( enc ) || ~any( strcmp( enc{1} , { 'jpegls' , 'zlib' , 'dicom' , 'missing' } ) ), bad( [ 'a data encoding outside the profile: ' , v ] ); end
      % el crc: en todo bloque con datos, y en ningun <missing>
      hascrc = ~isempty( regexp( v , ' crc [0-9a-f]{8}>$' , 'once' ) );
      if strcmp( enc{1} , 'missing' ) == hascrc, bad( [ 'a block with no crc, or a <missing> with one: ' , v ] ); end
    elseif strcmp( k , 'header' )
      % la parte oculta (SPEC 1.2): <hidden @0:b>, el PRIMER bloque, y nada mas
      % (sin crc: el escritor no lo pone)
      if isempty( regexp( v , '^<hidden @0:\d+>$' , 'once' ) ), bad( [ 'a header that is not <hidden @0:b>: ' , v ] ); end
    elseif strncmp( k , 'aux.' , 4 )
      if isempty( regexp( v , '^<png uint8 \{[^}]*\} @\d+:\d+ crc [0-9a-f]{8}>$' , 'once' ) ), bad( [ 'an aux that is not <png uint8 {..} @a:b crc ..>: ' , v ] ); end
    end
  end
  % y detras del bloque <hidden>, un hueco de 0 a 31 bytes hasta el siguiente
  h = E( strcmp( E(:,1) , 'header' ) , 3 );
  if ~isempty( h )
    hend = str2double( regexp( h{1} , '@0:(\d+)' , 'tokens' , 'once' ) );
    st = regexp( strjoin( E( ~strcmp( E(:,1) , 'header' ) , 3 ).' , ' ' ) , '@(\d+):' , 'tokens' );
    if ~isempty( st )
      gap = min( cellfun( @(t) str2double( t{1} ) , st ) ) - ( hend + 1 );
      if gap < 0 || gap >= 32, bad( sprintf( 'the gap after the <hidden> block is %d bytes, not 0..31' , gap ) ); end
    end
  end
end

function S = hdr_( f )
%HDR_  la cabecera de f segun el lector (tambien de un I3Db), sin tocar el binario
  [ ~ , S ] = read_I3D( f , 'NOdata' );
end

function B = fread_all_( f )
%FREAD_ALL_  todos los bytes de un fichero, uint8 columna
  fid = fopen( f , 'r' );  B = fread( fid , Inf , '*uint8' );  fclose( fid );
end
