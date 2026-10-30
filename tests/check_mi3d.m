function check_mi3d( outdir )
%CHECK_MI3D   the .mi3d container (SPEC 14): write_MI3D, append_MI3D, remove_MI3D, read_MI3D
%
%   check_mi3d
%   check_mi3d( outdir )   the same, and the containers STAY in outdir
%
% Escribe cuatro series con write_I3D (en texto con parte <hidden>, I3Db, todo a
% la vista) y con ellas contenedores. Comprueba:
%   - cada miembro es BYTE A BYTE su .i3d, y read_MI3D( f , n ) lee lo mismo que
%     read_I3D del original; un hueco da []; n fuera de 1..N, badIndex;
%   - el RESUMEN: lo comun a todos, a la vista solo si lo esta en todos (un I3Db
%     lo oculta todo), el resto en la parte <hidden>, cuyo bloque es el ULTIMO;
%   - append_MI3D NO mueve nada: la cabecera tiene la misma longitud y todo lo
%     que habia en el binario sigue igual, byte a byte; cuando la reserva se
%     acaba, reescribe el fichero entero y sigue leyendose bien;
%   - remove_MI3D deja el hueco (y N, con <missing> si era el ultimo); compactar
%     conserva numeros y huecos, 'Renumber' los cierra;
%   - un miembro Lazy con rutas relativas de otra carpeta: lazyFolder;
%   - y todos los contenedores, leidos por la DLL y por Python, miembro a
%     miembro, iguales entre si (tests/check_mi3d.py DIR).
% Lanza si algun caso falla.

  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  if nargin
    if ~exist( outdir , 'dir' ), mkdir( outdir ); end
    dn = outdir;
  else
    [ dn , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>
  end
  rng( 7 );
  F = @(n) fullfile( dn , n );

  % ---- cuatro series del mismo estudio
  S = { 'a' , int16( randi( [-1024 3000] , [5 4 3 2] ) ) , {} ;
        'b' , uint8( randi( [0 255] , [4 3 2] ) )        , { 'Hidden' } ;
        'c' , single( randn( [3 3 2] ) )                 , { 'Visible' , 'all' } ;
        'd' , int16( randi( [-9 9] , [3 3 2 3] ) )       , { 'Visible' , 'all' } };
  for i = 1:size( S , 1 )
    I = I3D( S{i,2} , 'X' , 0:size( S{i,2} , 1 )-1 , 'Y' , 0:size( S{i,2} , 2 )-1 , 'Z' , 0:size( S{i,2} , 3 )-1 , 'T' , 0:size( S{i,2} , 4 )-1 );
    nk = size( S{i,2} , 3 );  nt = size( S{i,2} , 4 );
    I.INFO = struct( 'DICOMstack' , struct( 'ffiles' , { repmat( {''} , nk , nt ) } , 'uids' , { repmat( {''} , nk , nt ) } , ...
                     'infos' , { repmat( { struct() } , nk , nt ) } , ...
                     'commonINFO' , struct( 'StudyDate' , '20261024' , 'PatientName' , 'Test^Name' , ...
                                            'InstitutionName' , 'Hospital' , 'SeriesDescription' , [ 'serie ' S{i,1} ] ) ) );
    write_I3D( I , F( [ S{i,1} '.i3d' ] ) , S{i,3}{:} );
  end
  A = F( 'a.i3d' );  B = F( 'b.i3d' );  C = F( 'c.i3d' );  D = F( 'd.i3d' );

  % ---- uno nuevo, con un hueco
  f1 = F( 'one.mi3d' );
  write_MI3D( f1 , { A , '' , C } );
  L = read_MI3D( f1 );
  must( L.N == 3 && isequal( L.present , [ true false true ] ) , 'N and present' );
  must( isequal( L.tag , { 'a.i3d' , '' , 'c.i3d' } ) , 'tags from the file names' );
  members_( f1 , { A , [] , C } );
  % a y c: StudyDate e InstitutionName a la vista en los dos; PatientName oculto
  % en a; SeriesDescription no es comun
  summary_( f1 , { 'StudyDate' , 'InstitutionName' } , { 'PatientName' } , { 'SeriesDescription' } );
  canon_( f1 , 8192 );
  try, read_MI3D( f1 , 4 ); error('check_mi3d:fail','member 4 opened'); catch E, must( strcmp( E.identifier , 'read_I3D:badIndex' ) , [ 'n > N: ' E.identifier ] ); end
  try, read_I3D( f1 ); error('check_mi3d:fail','a .mi3d opened as .i3d'); catch E, must( strcmp( E.identifier , 'read_I3D:badMagic' ) , [ '.mi3d as .i3d: ' E.identifier ] ); end
  ok( 'write_MI3D: members byte for byte, a hole, the summary, the reserve' );

  % ---- anadir sin mover nada
  before = fread_all_( f1 );  R = read_bin_( f1 );
  n = append_MI3D( f1 , B );
  after = fread_all_( f1 );
  must( n == 4 , 'append gives N+1' );
  must( read_bin_( f1 ) == R , 'append: the header changed its length' );
  must( isequal( after( R+1:numel( before ) ) , before( R+1:end ) ) , 'append moved or changed bytes of the binary section' );
  members_( f1 , { A , [] , C , B } );
  % b es I3Db: todo lo suyo cuenta como oculto
  summary_( f1 , {} , { 'StudyDate' , 'InstitutionName' , 'PatientName' } , { 'SeriesDescription' } );
  canon_( f1 , [] );
  ok( 'append_MI3D: in place, the binary untouched, the hidden block last' );

  % ---- quitar: el hueco se queda, y N
  before = fread_all_( f1 );
  remove_MI3D( f1 , 4 );
  L = read_MI3D( f1 );
  must( L.N == 4 && isequal( L.present , [ true false true false ] ) , 'remove the last: N stays' );
  must( ~isempty( regexp( L.header , '(?m)^i3d\(4\) = <missing>' , 'once' ) ) , 'remove the last: i3d(4) = <missing>' );
  must( read_bin_( f1 ) == R , 'remove: the header changed its length' );
  after = fread_all_( f1 );
  must( isequal( after( R+1:numel( before ) ) , before( R+1:end ) ) , 'remove moved bytes' );
  members_( f1 , { A , [] , C , [] } );
  summary_( f1 , { 'StudyDate' , 'InstitutionName' } , { 'PatientName' } , { 'SeriesDescription' } );
  % quitar sin que cambie el resumen: el <hidden> se queda donde esta
  write_MI3D( F( 'keep.mi3d' ) , { A , C , D } );
  b0 = fread_all_( F( 'keep.mi3d' ) );
  remove_MI3D( F( 'keep.mi3d' ) , 3 );
  must( numel( fread_all_( F( 'keep.mi3d' ) ) ) == numel( b0 ) , 'remove with the same summary: the file grew' );
  members_( F( 'keep.mi3d' ) , { A , C , [] } );
  ok( 'remove_MI3D: a hole, N kept, nothing moved' );

  % ---- compactar: quita lo que sobra, conserva numeros y huecos
  s0 = numel( fread_all_( f1 ) );
  write_MI3D( f1 );
  must( numel( fread_all_( f1 ) ) < s0 , 'compacting did not shrink the file' );
  members_( f1 , { A , [] , C , [] } );
  canon_( f1 , 8192 );
  write_MI3D( f1 , 'Renumber' );
  members_( f1 , { A , C } );
  canon_( f1 , 8192 );
  ok( 'write_MI3D( f ): compacted, numbers and holes kept; Renumber' );

  % ---- de uno en uno, con una reserva chica: hasta que no cabe
  f2 = F( 'many.mi3d' );
  if exist( f2 , 'file' ), delete( f2 ); end
  want = {};  full = 0;
  for k = 1:12
    src = { A , B , C , D };  src = src{ mod( k - 1 , 4 ) + 1 };
    if k == 1
      append_MI3D( f2 , src , 'Reserve' , 300 );
    else
      R0 = read_bin_( f2 );  before = fread_all_( f2 );
      append_MI3D( f2 , src , 'Reserve' , 300 );
      if read_bin_( f2 ) == R0
        after = fread_all_( f2 );
        must( isequal( after( R0+1:numel( before ) ) , before( R0+1:end ) ) , sprintf( 'append %d moved bytes' , k ) );
      else
        full = full + 1;
      end
    end
    want{end+1} = src;                                                       %#ok<AGROW>
    members_( f2 , want );
  end
  must( full >= 1 , 'the reserve never ran out: the full rewrite was not exercised' );
  canon_( f2 , [] );
  ok( sprintf( 'append_MI3D one by one: 12 members, %d full rewrite(s) when the reserve ran out' , full ) );

  % ---- un miembro Lazy con rutas relativas
  mkdir( F( 'sub' ) );
  lz = fullfile( F( 'sub' ) , 'lazy.i3d' );
  fid = fopen( lz , 'w' );
  fprintf( fid , 'I3D 0.1\nX = 0.0\nY = 0.0\nZ = 0.0\nT = 0.0\ndata = <dicom uint16 "dcm/a.dcm">\n---\n' );
  fclose( fid );
  try, write_MI3D( F( 'lazy.mi3d' ) , { A , lz } ); error('check_mi3d:fail','lazyFolder not raised');
  catch E, must( strcmp( E.identifier , 'write_MI3D:lazyFolder' ) , [ 'lazy: ' E.identifier ] ); end
  write_MI3D( F( 'lazy.mi3d' ) , { A , lz } , 'Lazy' , 'keep' );
  write_MI3D( fullfile( F( 'sub' ) , 'lazy.mi3d' ) , { A , lz } );
  delete( F( 'lazy.mi3d' ) );  delete( fullfile( F( 'sub' ) , 'lazy.mi3d' ) );
  ok( 'Lazy member with relative paths from another folder: lazyFolder (and ''Lazy'',''keep'')' );

  % ---- y los mismos contenedores, por la DLL y por Python
  % sin la '\' final: delante de la comilla la escaparia
  [ st , out ] = system( sprintf( '"%s" "%s" "%s"' , i3d_python() , fullfile( here , 'check_mi3d.py' ) , regexprep( dn , '[\\/]+$' , '' ) ) );
  fprintf( '%s' , out );
  must( st == 0 , 'the DLL and Python disagree on some container' );
  fprintf( 'check_mi3d: all ok\n' );
end

% ======================================================================
function members_( f , W )
  % W{n}: el .i3d que tiene que ser el miembro n, o [] (un hueco)
  L = read_MI3D( f );
  must( L.N == numel( W ) , sprintf( '%s: N = %d, not %d' , f , L.N , numel( W ) ) );
  B = fread_all_( f );
  for n = 1:numel( W )
    if isempty( W{n} )
      must( ~L.present(n) && isempty( read_MI3D( f , n ) ) , sprintf( 'member %d should be a hole' , n ) );
      continue;
    end
    must( L.present(n) , sprintf( 'member %d missing' , n ) );
    must( isequal( B( L.offset(n)+1 : L.offset(n)+L.length(n) ) , fread_all_( W{n} ) ) , sprintf( 'member %d is not byte for byte %s' , n , W{n} ) );
    I = read_MI3D( f , n );  J = read_I3D( W{n} );
    must( isequaln( I.data , J.data ) && isequal( I.X , J.X ) && isequal( I.Y , J.Y ) && isequal( I.Z , J.Z ) && isequal( I.T , J.T ) && ...
          isequal( I.SpatialTransform , J.SpatialTransform ) , sprintf( 'member %d reads differently from %s' , n , W{n} ) );
    a = rmfield( I.INFO , { 'filename' , 'member' } );  b = rmfield( J.INFO , 'filename' );
    must( isequaln( a , b ) , sprintf( 'member %d: INFO differs from %s' , n , W{n} ) );
  end
end

function summary_( f , vis , hid , none )
  % las info.* del resumen: a la vista, en la parte oculta, y las que no estan
  L = read_MI3D( f );
  for k = vis,  must( ~isempty( regexp( L.header , [ '(?m)^info\.' k{1} ' = ' ] , 'once' ) ) , [ 'info.' k{1} ' should be visible' ] ); end
  for k = hid
    must( isempty( strfind( L.header , [ 'info.' k{1} ] ) ) , [ 'info.' k{1} ' should be hidden' ] );
    must( isfield( L.INFO , k{1} ) , [ 'info.' k{1} ' should be in the summary (hidden)' ] );
  end
  for k = none, must( ~isfield( L.INFO , k{1} ) , [ 'info.' k{1} ' is not common' ] ); end
end

function canon_( f , reserve )
  % lo que escribe el escritor: la reserva al final de la cabecera ('#' y
  % espacios, reserve bytes con su LF; [] no se mira el tamano), y el <hidden>
  % el ULTIMO bloque: acaba en el ultimo byte del fichero
  L = read_MI3D( f );
  h = native2unicode( fread_all_( f ).' , 'UTF-8' );  h = h( 1:L.binstart );
  t = regexp( h , '\n(#[ ]*)\n---\n$' , 'tokens' , 'once' );
  must( ~isempty( t ) , 'no reserve line before ---' );
  if ~isempty( reserve ), must( numel( t{1} ) + 1 == reserve , sprintf( 'the reserve is %d bytes, not %d' , numel( t{1} ) + 1 , reserve ) ); end
  e = find( strcmp( L.entries(:,1) , 'header' ) , 1 );
  if ~isempty( e )
    r = sscanf( regexp( L.entries{e,3} , '@\d+:\d+' , 'match' , 'once' ) , '@%d:%d' );
    d = dir( f );
    must( L.binstart + r(2) + 1 == d.bytes , 'the <hidden> block is not the last' );
  end
end

function n = read_bin_( f )
  L = read_MI3D( f );  n = L.binstart;
end

function B = fread_all_( f )
  fid = fopen( f , 'r' );  B = fread( fid , Inf , '*uint8' );  fclose( fid );
end

function must( c , msg )
  if ~c, error( 'check_mi3d:fail' , '%s' , msg ); end
end

function ok( msg )
  fprintf( '  ok   %s\n' , msg );
end
