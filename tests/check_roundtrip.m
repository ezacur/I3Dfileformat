function check_roundtrip( outdir )
%CHECK_ROUNDTRIP   the writer of i3d.dll -> three readers, compared BYTE FOR BYTE against the original
%
%   check_roundtrip
%   check_roundtrip( outdir )   the same, and the files STAY in outdir (to open
%                               them elsewhere: a viewer, another reader, the C# tests)
%
% Escribe una bateria con el escritor de la DLL por calllib (la API de
% write_I3D: i3d_set_*, i3d_add_info_*, i3d_write), con cada una de sus
% opciones, guarda los originales en un .mat (-v7) y los lee con TRES lectores:
% read_I3D (la DLL desde MATLAB), y la DLL por ctypes y el lector de referencia
% en Python (tests/check_roundtrip.py). Rejillas, transform, data, primer
% instante, thumbnail (gris y RGB) e info.* bit a bit. Ademas:
%   - cada fichero que escribe la DLL ES canonico (SPEC 9) (canon_);
%   - es determinista: escrito dos veces, los mismos bytes;
%   - i3d_rewrite pasa de texto a oculto (I3Db) y vuelta, byte a byte;
%   - los info.*: un $ literal ($$), comillas y \, una ruta con $DICOMDIR$ (que
%     read_I3D devuelve resuelta), numeros, filas; uno ilegible ($ suelto) es un
%     aviso y el resto del fichero se lee;
%   - ficheros editados a mano (no canonicos): cabecera editada, offsets
%     @a+n / @a+Inf / @a:EOF, un bloque raw;
%   - controles negativos: un byte corrupto, un crc que no casa con el dato;
%   - una ruta de mas de 260 caracteres;
%   - ninguna funcion de la API pasa de 6 argumentos (calllib sin thunk).
% Lanza si algun caso falla.

  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  load_();
  if nargin
    % a directory of its own: the python half globs EVERY .i3d in it
    if exist( outdir , 'dir' ) && ~isempty( dir( fullfile( outdir , '*.i3d' ) ) )
      error('check_roundtrip:outdirNotEmpty','%s already has .i3d files: give an empty or new directory.', outdir );
    end
    if ~exist( outdir , 'dir' ), mkdir( outdir ); end
    dn = outdir;
  else
    dn = tempname;  mkdir( dn );  CLEAN = onCleanup( @() rmdir( dn , 's' ) );  %#ok<NASGU>
  end

  % calllib sin thunk admite 6 argumentos como mucho
  sig = libfunctions( 'i3d' , '-full' );
  na  = cellfun( @( s ) numel( strsplit( regexprep( s , '.*\((.*)\)\s*$' , '$1' ) , ',' ) ) , sig );
  if any( na > 6 ), error( 'check_roundtrip:args' , 'more than 6 arguments: %s' , strjoin( sig( na > 6 ) , ' | ' ) ); end

  rng( 7 );
  c = cosd(30); s = sind(30);
  C = {};
  % nombre, data, X, Y, Z, T, SpatialTransform, forma del thumbnail
  C(end+1,:) = { 'int16_rot'     , int16( randi([-1024 3000],[5 4 3 2]) ) , (0:4)*0.703125 , (0:3)*0.1 , [0 8 16.000000000000004] , (0:1)*38.5 , [c 0 -s -180.1; 0 1 0 -95.3; s 0 c 41; 0 0 0 1] , [7 5 1 2] };
  C(end+1,:) = { 'uint16_1slice' , uint16( randi([0 65535],[7 6]) )        , (0:6)*1.40625  , (0:5)*1.40625 , 0 , 0 , eye(4) , [7 5] };
  F = single( randn( [4 3 2 2 3] ) );  F(1) = NaN;  F(2) = -0;  F(3) = Inf;  F(4) = -Inf;
  C(end+1,:) = { 'single_rgb'    , F                                        , 0:3 , 0:2 , [0 2] , [0 1] , diag([2 2 2 1]) , [7 5 3 2] };
  C(end+1,:) = { 'double_tensor' , randn( [3 3 2 2 3 3] )                   , [0 1 3] , [0 0.5 1] , [-1 1] , [0 10] , [1 0.2 0 5; 0 1 0 6; 0 0 -1 7; 0 0 0 1] , [7 5 1 2] };
  C(end+1,:) = { 'uint8_nonunif' , uint8( randi([0 255],[4 3 2]) )          , [0 1 3 6] , [0 1 2] , [0 1] , 0 , eye(4) , [7 5 1 1] };
  C(end+1,:) = { 'int64_ext'     , int64( [intmin('int64') intmax('int64'); -1 0] ) , [0 1] , [0 1] , 0 , 0 , eye(4) , [7 5] };
  C(end+1,:) = { 'uint64_max'    , uint64( [intmax('uint64') 0 1] )         , 0 , [0 1 2] , 0 , 0 , eye(4) , [7 5] };
  C(end+1,:) = { 'int32_trans'   , int32( randi([-9e8 9e8],[3 3 2 3]) )     , [0 1 2] , [0 1 2] , [0 1] , [0 5 10] , [1 0 0 -12.5; 0 1 0 7; 0 0 1 0.1; 0 0 0 1] , [7 5 1 3] };
  z = cumsum( repmat( 0.1 , 1 , 10 ) ) - 0.1;          % "casi" uniforme: tiene que ir como LISTA
  C(end+1,:) = { 'almost_uniform', int8( randi([-128 127],[2 2 10]) )       , [0 1] , [0 1] , z , 0 , eye(4) , [7 5] };
  % uint8 con 3 componentes: un bloque jpegls por plano Y por componente
  C(end+1,:) = { 'uint8_rgb'     , uint8( randi([0 255],[4 3 2 2 3]) )      , 0:3 , 0:2 , [0 2] , [0 1] , eye(4) , [7 5 3 2] };

  % las variantes que escribe la DLL: { sufijo , opciones , info visibles }
  V = { 'canon'     , {}                                 , 'default'
        'visall'    , {}                                 , 'all'
        'volume'    , { 'Blocks' , 'volume' }            , 'default'
        'tblocks'   , { 'Blocks' , 't' }                 , 'default'
        'chunked'   , { 'MaxBlockBytes' , 'PLANE' }      , 'default'
        'hidden'    , { 'Hidden' , '1' }                 , 'default'
        'hidekeys'  , {}                                 , 'none'
        'hidekeysb' , { 'Hidden' , '1' }                 , 'none' };
  names = C(:,1);
  by = @(f) fread_all_( f );
  for i = 1:size( C , 1 )
    D = C{i,2};  TH = uint8( randi( [0 255] , C{i,8} ) );
    pl = numel( typecast( D(1) , 'uint8' ) ) * size( D , 1 ) * size( D , 2 ) * prod( size( D , 5:max( 5 , ndims( D ) ) ) );
    for v = 1:size( V , 1 )
      o = V{v,2};  o( strcmp( o , 'PLANE' ) ) = { sprintf( '%d' , pl ) };
      write_( fullfile( dn , [ names{i} '_' V{v,1} '.i3d' ] ) , C(i,:) , TH , o , V{v,3} );
      canon_( fullfile( dn , [ names{i} '_' V{v,1} '.i3d' ] ) , ndims( D ) );
    end
    % por defecto (SPEC 1.2, 9) se ve todo lo que hace falta para leer data -- los
    % bloques de data y el thumbnail -- y los info.* visibles; PatientName y
    % $DICOMDIR$ van a la parte oculta, que el lector despliega
    fc = fullfile( dn , [ names{i} '_canon.i3d' ] );
    S = hdr_( fc );  hc = S.header;
    nvis = numel( regexp( hc , '\ndata\(' , 'start' ) );  nall = nnz( strcmp( S.entries(:,1) , 'data' ) );
    if isempty( strfind( hc , 'header = <hidden @0:' ) ) || nvis ~= nall || isempty( regexp( hc , '(?m)^thumbnail = <png' , 'once' ) ) || ...
       isempty( strfind( hc , 'info.StudyDate' ) ) || ~isempty( strfind( hc , 'PatientName' ) ) || ~isempty( strfind( hc , '$DICOMDIR$ =' ) ) || ...
       ~any( strcmp( S.entries(:,1) , 'info.PatientName' ) )
      error('check_roundtrip:visible','%s: by default the data, the thumbnail and the visible info.* are in the clear, info.PatientName and $DICOMDIR$ hidden:\n%s', names{i} , hc );
    end
    % todos los info.* ocultos: ni la cabecera en claro ni la de la I3Db los muestran
    for g = { 'hidekeys' , 'hidekeysb' }
      Sk = hdr_( fullfile( dn , [ names{i} '_' g{1} '.i3d' ] ) );
      if isempty( strfind( Sk.header , 'header = <hidden @' ) ) || ~isempty( strfind( Sk.header , [ newline 'info.' ] ) ) || ~any( strcmp( Sk.entries(:,1) , 'info.StudyDate' ) )
        error('check_roundtrip:hideKeys','%s_%s: the <hidden> part is missing, an info.* is visible, or the reader does not return them.', names{i} , g{1} );
      end
    end
    % la I3Db no deja ver nada en claro
    hb = char( by( fullfile( dn , [ names{i} '_hidden.i3d' ] ) ).' );
    for w = { 'I3D ' , 'transform' , 'data' , 'X[' , 'thumbnail' }
      if ~isempty( strfind( hb , w{1} ) ), error('check_roundtrip:plain','%s: "%s" is visible in the hidden file.', names{i} , w{1} ); end
    end
    % determinista: otra vez lo mismo, los mismos bytes
    f2 = [ tempname , '.i3d' ];
    write_( f2 , C(i,:) , TH , {} , 'default' );
    same = isequal( by( f2 ) , by( fc ) );  delete( f2 );
    if ~same, error('check_roundtrip:determinism','%s: written twice, the files differ.', names{i} ); end
    % i3d_rewrite: texto -> oculto y oculto -> texto, byte a byte
    for g = { 'canon' , 'hidden' ; 'hidekeys' , 'hidekeysb' }.'
      ft = fullfile( dn , [ names{i} '_' g{1} '.i3d' ] );  fh = fullfile( dn , [ names{i} '_' g{2} '.i3d' ] );
      a = [ tempname , '.i3d' ];  b = [ tempname , '.i3d' ];
      rw = [ calllib( 'i3d' , 'i3d_rewrite' , ft , a , 1 ) , calllib( 'i3d' , 'i3d_rewrite' , fh , b , 0 ) ];
      ok = all( rw == 0 ) && isequal( by( a ) , by( fh ) ) && isequal( by( b ) , by( ft ) );
      delete( a , b );
      if ~ok, error('check_roundtrip:rewrite','%s: i3d_rewrite %s <-> %s is not byte for byte.', names{i} , g{1} , g{2} ); end
    end
    REF.( names{i} ) = struct( 'X',C{i,3} , 'Y',C{i,4} , 'Z',C{i,5} , 'T',C{i,6} , 'A',C{i,7} , 'D',D , 'TH',TH );
  end
  save( fullfile( dn , 'ref.mat' ) , '-struct' , 'REF' , '-v7' );

  % la prueba tambien tiene que saber FALLAR: una copia con el primer byte del
  % PRIMER BLOQUE DE DATA alterado. De 'visall' (todos los info.* a la vista):
  % su parte oculta solo lleva $DICOMDIR$, va primero en el binario, y las
  % ediciones de abajo (@a+Inf en el ultimo @ de la cabecera) suponen que el
  % ultimo descriptor visible es el ultimo bloque
  b = by( fullfile( dn , 'int16_rot_visall.i3d' ) );
  b0 = strfind( char( b(:).' ) , [ newline '---' newline ] ) + 5;           % el primer byte del binario
  o1 = str2double( regexp( char( b(1:b0).' ) , '(?m)^data\([^)]*\) = <\w+ \w+ (?:\{[^}]*\} )?@(\d+):' , 'tokens' , 'once' ) );
  ib = b0 + o1;
  b(ib) = bitxor( b(ib) , uint8(1) );
  write_bytes_( fullfile( dn , 'int16_rot_corrupt.i3d' ) , b );

  % EDITADO A MANO: X[5] -> X[999] (la anotacion [..] no se lee) y una linea de
  % comentario de mas. Los offsets son relativos al binario: tiene que leerse IGUAL
  b = b(:).';  b(ib) = bitxor( b(ib) , uint8(1) );            % deshacer la corrupcion
  s = char( b );
  k = strfind( s , [ newline '---' newline ] );
  h = s( 1:k );
  h = strrep( h , 'X[5] = ' , 'X[999] = ' );
  h = strrep( h , [ newline 'transform =' ] , [ newline '# a comment added by hand' newline 'transform =' ] );
  if isempty( strfind( h , 'X[999] = ' ) ) || isempty( strfind( h , 'added by hand' ) )
    error('check_roundtrip:editNotApplied','the hand edit did not apply: the test would prove nothing.');
  end
  write_bytes_( fullfile( dn , 'int16_rot_edited.i3d' ) , [ uint8( h ) , b( k+1:end ) ] );

  % UN INFO ILEGIBLE: un $ suelto. Es un aviso de read_I3D (y un info_errors en
  % Python); el resto del fichero se lee igual
  hl = strrep( h , [ newline 'info.StudyDate' ] , [ newline 'info.lone = "precio $5"' newline 'info.StudyDate' ] );
  if isempty( strfind( hl , 'info.lone' ) ), error('check_roundtrip:editNotApplied','the lone-$ edit did not apply.'); end
  write_bytes_( fullfile( dn , 'int16_rot_lone.i3d' ) , [ uint8( hl ) , b( k+1:end ) ] );

  % LAS OTRAS FORMAS DEL OFFSET (no canonicas): @a+n, el ultimo @a+Inf, y @a:EOF
  hp = regexprep( h , '@(\d+):(\d+)(?=( crc [0-9a-f]{8})?>)' , '@$1+${num2str(str2double($2)-str2double($1)+1)}' );
  hp = regexprep( hp , '@(\d+)\+(\d+)(?=( crc [0-9a-f]{8})?>[^@]*$)' , '@$1+Inf' );
  he = regexprep( h , '@(\d+):(\d+)(?=( crc [0-9a-f]{8})?>[^@]*$)' , '@$1:EOF' );
  if isempty( strfind( hp , '+Inf' ) ) || isempty( strfind( he , ':EOF' ) )
    error('check_roundtrip:editNotApplied','the offset edits did not apply.');
  end
  write_bytes_( fullfile( dn , 'int16_rot_plus.i3d' ) , [ uint8( hp ) , b( k+1:end ) ] );
  write_bytes_( fullfile( dn , 'int16_rot_eof.i3d' ) ,  [ uint8( he ) , b( k+1:end ) ] );

  % RAW (no canonico): data entero en UN bloque raw, a mano, con la cabecera del
  % original sin sus bloques (ni el <hidden>: su $DICOMDIR$, a la vista)
  D0 = REF.int16_rot.D;
  hl = strsplit( h , newline );
  hl = hl( ~strncmp( hl , 'data' , 4 ) & ~strncmp( hl , 'thumbnail' , 9 ) & ~strncmp( hl , 'header' , 6 ) & ~cellfun( 'isempty' , hl ) );
  hl{end+1} = '$DICOMDIR$ = "D:/x$y"';
  hl{end+1} = sprintf( 'data(:,:,:,:) = <raw int16 @0:%d>' , numel( D0 ) * 2 - 1 );
  fid = fopen( fullfile( dn , 'int16_rot_rawhand.i3d' ) , 'w' );
  fwrite( fid , uint8( [ strjoin( hl , newline ) , newline , '---' , newline ] ) , 'uint8' );   % h son BYTES (UTF-8): 'char' los recodificaria
  fwrite( fid , D0(:) , 'int16' );  fclose( fid );

  % CRC: el crc es de los bytes DECODIFICADOS (SPEC 4). El dato queda intacto y se
  % altera UNA cifra del crc del primer bloque: los lectores lo RECHAZAN con badCRC
  fb = fullfile( dn , 'int16_rot_crcbad.i3d' );
  write_( fb , C( strcmp( names , 'int16_rot' ) , : ) , [] , {} , 'none' );
  b = by( fb );  s = char( b(:).' );
  q = strfind( s , ' crc ' );
  if isempty( q ), error('check_roundtrip:editNotApplied','the canonical file has no crc: the crc test would prove nothing.'); end
  q = q(1) + 5 + 7;                                          % la ULTIMA cifra hex del primer crc
  b(q) = uint8( char( '0' + ( s(q) == '0' ) ) );
  write_bytes_( fb , b );

  % ---------------------------------------------------------------- read_I3D
  % la TERCERA lectura: la DLL dentro de MATLAB, contra los originales, bit a bit
  nbad = 0;
  bits = @(x) typecast( x(:).' , 'uint8' );
  HAND = { 'corrupt' , 'edited' , 'lone' , 'plus' , 'eof' , 'rawhand' , 'crcbad' };
  for i = 1:size( C , 1 )
    R = REF.( names{i} );
    for enc = [ V(:,1).' , HAND ]
      f = fullfile( dn , [ names{i} '_' enc{1} '.i3d' ] );
      if ~exist( f , 'file' ), continue; end
      [ good , what ] = check_file_( f , R , enc{1} , bits );
      nbad = nbad + ~good;
      fprintf( '  %s %-16s %-9s read_I3D: %s\n' , repmat( 'ok  ' , 1 , good ) , names{i} , enc{1} , what );
      if ~good, fprintf( '  FAIL\n' ); end
    end
  end

  % UNA RUTA LARGA (> 260 caracteres): se escribe y se lee. MATLAB no crea la
  % carpeta (MAX_PATH): la crea cmd con \\?\
  L0 = tempname;  L = L0;  while numel( L ) < 280, L = fullfile( L , repmat( 'a' , 1 , 40 ) ); end
  system( [ 'cmd /c mkdir "\\?\' L '"' ] );
  fl = fullfile( L , 'int16_rot_long.i3d' );
  try
    write_( fl , C( strcmp( names , 'int16_rot' ) , : ) , REF.int16_rot.TH , {} , 'default' );
    [ good , what ] = check_file_( fl , REF.int16_rot , 'canon' , bits );
  catch LE
    good = false;  what = LE.message;
  end
  system( [ 'cmd /c rmdir /s /q "\\?\' L0 '"' ] );                % la carpeta que se creo, entera
  nbad = nbad + ~good;
  fprintf( '  %s %-16s %-9s read_I3D: %s (%d characters)\n' , repmat( 'ok  ' , 1 , good ) , 'int16_rot' , 'longpath' , what , numel( fl ) );
  if nbad, error('check_roundtrip:dllFailed','%d file(s) failed through read_I3D.', nbad ); end

  % las cabeceras, para MIRARLAS
  for g = { 'int16_rot_canon' , 'uint8_rgb_canon' }
    fprintf( '----- %s\n%s\n' , g{1} , getfield( hdr_( fullfile( dn , [ g{1} '.i3d' ] ) ) , 'header' ) );  %#ok<GFLD>
  end

  % sin la barra final: '...\"' escapa la comilla en la linea de comandos
  dq = regexprep( dn , '[\\/]+$' , '' );
  [ st , out ] = system( sprintf( '"%s" "%s" "%s"' , i3d_python() , fullfile( here , 'check_roundtrip.py' ) , dq ) );
  fprintf( '%s' , out );
  if st ~= 0, error('check_roundtrip:failed','round trip failed (see above).'); end
end


function [ good , what ] = check_file_( f , R , enc , bits )
%CHECK_FILE_  un fichero con read_I3D contra su original R. Los controles negativos
% (corrupt, crcbad) tienen que fallar
  Dref = R.D;
  try
    lastwarn( '' );  ws = warning( 'off' , 'read_I3D:info' );
    S = read_I3D( f );
    [ ~ , wid ] = lastwarn;  warning( ws );
    same = isequal( bits( S.X ) , bits( R.X ) ) && isequal( bits( S.Y ) , bits( R.Y ) ) && ...
           isequal( bits( S.Z ) , bits( R.Z ) ) && isequal( bits( S.T ) , bits( R.T ) ) && ...
           isequal( bits( S.SpatialTransform ) , bits( R.A ) ) && ...
           strcmp( class( S.data ) , class( Dref ) ) && isequal( size( S.data ) , size( Dref ) ) && ...
           isequal( bits( S.data ) , bits( Dref ) );
    % el PRIMER INSTANTE (SPEC 5.7), leyendo solo sus bloques: data(:,:,:,1,c...)
    S1 = read_I3D( f , 'Data' , 'first' );
    sz = size( Dref );  sz(end+1:4) = 1;
    R1 = reshape( Dref , [ sz(1:4) , prod( sz(5:end) ) ] );  R1 = R1(:,:,:,1,:);
    same = same && strcmp( class( S1.data ) , class( Dref ) ) && numel( S1.data ) == numel( R1 ) && ...
           size( S1.data , 4 ) == 1 && isequal( bits( S1.data ) , bits( R1 ) );
    % el thumbnail (los hechos a mano sin el -- rawhand, crcbad -- no lo llevan)
    if ~any( strcmp( enc , { 'rawhand' , 'crcbad' } ) )
      same = same && isequal( S.thumbnail , R.TH );
    end
    % los info.* que escribio write_: resueltos, sin escapes; uno ilegible es un aviso
    if ~strcmp( enc , 'crcbad' )
      same = same && infos_ok_( S.INFO , size( Dref , 3 ) * size( Dref , 4 ) );
    end
    if strcmp( enc , 'lone' ), same = same && strcmp( wid , 'read_I3D:info' ) && ~isfield( S.INFO , 'lone' ); end
    if strcmp( enc , 'corrupt' ), good = ~same; else, good = same; end
    if strcmp( enc , 'crcbad' ), good = false; end            % TENIA que lanzar badCRC
    what = 'read';
  catch LE
    good = ( strcmp( enc , 'crcbad' ) && strcmp( LE.identifier , 'read_I3D:badCRC' ) ) || ...
           ( strcmp( enc , 'corrupt' ) && strncmp( LE.identifier , 'read_I3D:' , 9 ) );
    what = LE.identifier;
  end
end


function ok = infos_ok_( I , nplanes )
%INFOS_OK_  lo que escribio write_ (ver alli), como lo devuelve read_I3D
  fn = cellstr( getfield( I , 'planes' , 'Filename' ) );          %#ok<GFLD>
  ok = isequal( I.StudyDate , '20261024' ) && isequal( I.PatientName , 'Test^Name' ) && ...
       isequal( I.Price , 'cuesta 5$ "con comillas" \ y barra' ) && ...
       isequal( I.PixelSpacing , [ 0.703125 0.1 ] ) && ...
       isequal( fn(:).' , { 'D:/x$y/a.dcm' , 'D:/x$y/b$.dcm' } ) && ...
       isequal( I.series.SeriesNumber(:).' , [ 5 7 ] ) && ...
       isequal( I.Note , 'Muñoz^José' );
  if nplanes == 2, ok = ok && isequal( size( I.series.SeriesNumber ) , [ 2 1 ] ); end   % [nK nT]
end


function write_( f , c , TH , opts , vis )
%WRITE_  un .i3d con el escritor de la DLL (lo que hace write_I3D, sin DICOMstack).
% c: { nombre , data , X , Y , Z , T , A , ... }. vis: 'default' (StudyDate, Price,
% PixelSpacing, Note, series y planes visibles; PatientName oculto), 'all' o 'none'
  w = calllib( 'i3d' , 'i3d_new' );  CL = onCleanup( @() calllib( 'i3d' , 'i3d_free' , w ) );
  ck = @( rc ) assert( rc == 0 , 'check_roundtrip:write' , '%s' , calllib( 'i3d' , 'i3d_wlast_error' , w ) );
  D = c{2};
  ck( calllib( 'i3d' , 'i3d_set_Xgrid' , w , double( c{3} ) , numel( c{3} ) ) );
  ck( calllib( 'i3d' , 'i3d_set_Ygrid' , w , double( c{4} ) , numel( c{4} ) ) );
  ck( calllib( 'i3d' , 'i3d_set_Zgrid' , w , double( c{5} ) , numel( c{5} ) ) );
  ck( calllib( 'i3d' , 'i3d_set_Tgrid' , w , double( c{6} ) , numel( c{6} ) ) );
  ck( calllib( 'i3d' , 'i3d_set_transform' , w , reshape( c{7}.' , 1 , [] ) ) );
  ck( calllib( 'i3d' , 'i3d_set_data' , w , D , class( D ) , int32( ndims( D ) ) , int64( size( D ) ) ) );
  if ~isempty( TH ), ck( calllib( 'i3d' , 'i3d_set_thumbnail' , w , TH , 'uint8' , int32( ndims( TH ) ) , int64( size( TH ) ) ) ); end
  for o = 1:2:numel( opts ), ck( calllib( 'i3d' , 'i3d_set_option' , w , opts{o} , opts{o+1} ) ); end
  if ~strcmp( vis , 'none' ) || ~isempty( TH )
    v = double( ~strcmp( vis , 'none' ) );  p = double( strcmp( vis , 'all' ) );
    ck( calllib( 'i3d' , 'i3d_set_variable' , w , 'DICOMDIR' , 'D:/x$y' ) );              % el valor entra tal cual
    ck( calllib( 'i3d' , 'i3d_add_info_text' , w , 'StudyDate' , '20261024' , v , '' ) );
    ck( calllib( 'i3d' , 'i3d_add_info_text' , w , 'PatientName' , 'Test^Name' , p , '' ) );
    ck( calllib( 'i3d' , 'i3d_add_info_text' , w , 'Price' , 'cuesta 5$$ "con comillas" \ y barra' , v , '' ) );   % $$: un $
    ck( calllib( 'i3d' , 'i3d_add_info_text' , w , 'Note' , 'Muñoz^José' , v , 'UTF-8' ) );
    ck( calllib( 'i3d' , 'i3d_add_info_numbers' , w , 'PixelSpacing' , [ 0.703125 0.1 ] , 2 , v , '' ) );
    ck( calllib( 'i3d' , 'i3d_add_info_rows_numbers' , w , 'series.SeriesNumber' , 2 , [ 5 7 ] , { 'series 1' , 'series 2' } , v ) );
    ck( calllib( 'i3d' , 'i3d_add_info_rows_text' , w , 'planes.Filename' , 2 , { '$DICOMDIR$/a.dcm' , '$DICOMDIR$/b$$.dcm' } , { '' , '' } , v ) );
  end
  ck( calllib( 'i3d' , 'i3d_write' , w , f ) );
end


function canon_( f , nd )
%CANON_  que el fichero que escribio la DLL sea CANONICO (SPEC 9). La cabecera la da
% el lector C++ en claro (tambien de un I3Db). nd: ndims de data
  S = hdr_( f );
  bad = @( why ) error( 'check_roundtrip:notCanonical' , '%s is not canonical: %s' , f , why );
  E = S.entries;
  t = E( strcmp( E(:,1) , 'transform' ) , 3 );
  if numel( t ) ~= 1 || numel( strsplit( strtrim( t{1} ) ) ) ~= 12, bad( 'transform is not 12 numbers' ); end
  for e = 1:size( E , 1 )
    k = E{e,1};  v = E{e,3};
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
      hascrc = ~isempty( regexp( v , ' crc [0-9a-f]{8}>$' , 'once' ) );
      if strcmp( enc{1} , 'missing' ) == hascrc, bad( [ 'a block with no crc, or a <missing> with one: ' , v ] ); end
    elseif strcmp( k , 'header' )
      if isempty( regexp( v , '^<hidden @0:\d+>$' , 'once' ) ), bad( [ 'a header that is not <hidden @0:b>: ' , v ] ); end
    elseif strcmp( k , 'thumbnail' )
      if isempty( regexp( v , '^<png uint8 \{[^}]*\} @\d+:\d+ crc [0-9a-f]{8}>$' , 'once' ) ), bad( [ 'a thumbnail that is not <png uint8 {..} @a:b crc ..>: ' , v ] ); end
    end
  end
  % detras del bloque <hidden>, un hueco de 0 a 31 bytes hasta el siguiente
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
%HDR_  la cabecera de f segun el lector C++ (tambien de un I3Db): en claro, y sus
% entradas { clave , subindices , valor } con las de la parte oculta
  h = calllib( 'i3d' , 'i3d_open' , f );
  if isNull( h ), error( 'check_roundtrip:open' , '%s' , calllib( 'i3d' , 'i3d_last_error' , [] ) ); end
  CL = onCleanup( @() calllib( 'i3d' , 'i3d_close' , h ) );
  S.header = calllib( 'i3d' , 'i3d_header' , h );
  n = calllib( 'i3d' , 'i3d_entry_count' , h );
  S.entries = cell( n , 3 );
  for e = 0:n-1
    S.entries(e+1,:) = { calllib( 'i3d' , 'i3d_entry_key' , h , e ) , calllib( 'i3d' , 'i3d_entry_subs' , h , e ) , calllib( 'i3d' , 'i3d_entry_value' , h , e ) };
  end
end


function load_()
%LOAD_  i3d.dll de matlab\ (lo mismo que hacen write_I3D y read_I3D)
  if libisloaded( 'i3d' ), return; end
  old = cd( fullfile( fileparts( mfilename( 'fullpath' ) ) , '..' , 'matlab' ) );  C = onCleanup( @() cd( old ) );
  loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' );
end

function B = fread_all_( f )
  fid = fopen( f , 'r' );  B = fread( fid , Inf , '*uint8' );  fclose( fid );
end

function write_bytes_( f , b )
  fid = fopen( f , 'w' );  fwrite( fid , b , 'uint8' );  fclose( fid );
end
