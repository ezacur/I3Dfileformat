function try_collect_lazy( folder )
%TRY_COLLECT_LAZY   DICOMstackCollect_lazy against DICOMstackCollect 'onlyK', stack by stack
%
%   try_collect_lazy( 'D:\DICOMS\TAC 1' )
%
% No es de regresion (depende de d:\DICOMS). Para cada stack: cuantos planos se
% leyeron, que los leidos son BIT A BIT los de DICOMstackCollect, que los demas
% son cero y estan en INFO.unreadPlanes, cuanto se parece thumbnailK, y que hace
% write_I3D 'Lazy' (tal como esta) con el resultado.
  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  dn = fullfile( tempdir , 'try_collect_lazy' );  if ~exist( dn , 'dir' ), mkdir( dn ); end

  F = dir( fullfile( folder , '**' , '*' ) );  F( [ F.isdir ] ) = [];
  F = struct( 'name' , fullfile( { F.folder } , { F.name } ) );
  t0 = tic;  [ DL , RL ] = DICOMstackCollect_lazy( F );     tl = toc( t0 );
  t0 = tic;  [ DF , RF ] = DICOMstackCollect( F , 'onlyK' ); tf = toc( t0 );
  fprintf( '\n%s: %d files, %d stacks.  lazy %.1f s, full %.1f s.  REPORT lazy %d, full %d\n' , folder , numel( F ) , numel( DL ) , tl , tf , numel( RL ) , numel( RF ) );
  if numel( DL ) ~= numel( DF ), error('try_collect_lazy:stacks','different number of stacks.'); end

  nbad = 0;
  for d = 1:numel( DL )
    if ~isa( DL(d).IMAGE , 'I3D' ) || ~isa( DF(d).IMAGE , 'I3D' ), continue; end
    L = DL(d).IMAGE.DATA;  A = DF(d).IMAGE.DATA;
    has = ~cellfun( 'isempty' , DL(d).uids );
    U = false( size( has ) );  try, U = DL(d).IMAGE.INFO.unreadPlanes; end
    ts = '?';  try, h = dicominfo( DL(d).ffiles{ find( has , 1 ) } ); ts = h.TransferSyntaxUID; end
    okread = isequal( size( L ) , size( A ) ) && strcmp( class( L ) , class( A ) );
    okzero = true;
    for q = 1:numel( has )
      [ k , t ] = ind2sub( size( has ) , q );
      if U(q), okzero = okzero && ~any( L(:,:,k,t,:) , 'all' );
      else,    okread = okread && isequal( L(:,:,k,t,:) , A(:,:,k,t,:) );
      end
    end
    tl_ = DL(d).IMAGE.INFO.thumbnailK;  tf_ = DF(d).IMAGE.INFO.thumbnailK;
    if isequal( size( tl_ ) , size( tf_ ) ), r = corr( double( tl_(:) ) , double( tf_(:) ) ); sth = sprintf( 'same size, corr %.4f' , r );
    else, sth = sprintf( 'size %s vs %s' , mat2str( size( tl_ ) ) , mat2str( size( tf_ ) ) );
    end
    fprintf( '  %2d  %-28s %-18s %-24s read %4d of %4d | read bit for bit %d | unread zero %d | thumbK %s\n' , d , ...
             char( DL(d).SeriesDescription ) , mat2str( size( L ) ) , ts , nnz( has & ~U ) , nnz( has ) , okread , okzero , sth );
    nbad = nbad + ~okread + ~okzero;
  end
  if nbad, error('try_collect_lazy:mismatch','%d stack(s) wrong.', nbad ); end

  % write_I3D 'Lazy', TAL COMO ESTA, con el stack con mas planos sin leer
  nU = arrayfun( @(d) nnz_( DL(d) ) , 1:numel( DL ) );
  [ m , d ] = max( nU );
  if m == 0, fprintf( '\nno stack has unread planes: nothing to try with write_I3D.\n' ); return; end
  I = DL(d).IMAGE;  A = DF(d).IMAGE.DATA;
  fprintf( '\nwrite_I3D ''Lazy'' on stack %d (%d unread planes):\n' , d , m );
  for v = { true , false }
    f = fullfile( dn , 'lazy.i3d' );
    write_I3D( I , f , 'Lazy' , 'Verify' , v{1} );
    h = fileread( f );  h = h( 1:strfind( h , [ newline '---' newline ] ) );
    l = regexp( h , '\$DICOMDIR\$[^\n]*' , 'match' , 'once' );
    try
      J = read_I3D( f );  s = sprintf( 'read_I3D ok, equals the full DICOMstackCollect data: %d' , isequal( J.DATA , A ) );
    catch e
      s = sprintf( 'read_I3D: %s' , e.identifier );
    end
    fprintf( '  Verify %d: %s\n            %s\n' , v{1} , l , s );
  end
end

function n = nnz_( D )
  n = 0;  try, n = nnz( D.IMAGE.INFO.unreadPlanes ); end
end
