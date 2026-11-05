function check_dicom( listfile )
%CHECK_DICOM   <dicom> blocks through the C++ reader (DCMTK) against dicomread, bit for bit
%
%   check_dicom( 'dicom_variety.txt' )
%
% Por cada fichero de la lista (tests/dicom_variety.py: uno por combinacion de
% sintaxis de transferencia, BitsAllocated, BitsStored, HighBit, signo,
% SamplesPerPixel y multiframe), escribe un .i3d que lo referencia con
% $DICOMDIR$ y lo lee con read_I3D (i3d.dll). Compara contra dicomread -- lo que usa
% DICOMstack --, traspuesto (la i de @I3D es la columna).
%
% No es de regresion (depende de d:\DICOMS). Clasifica cada fichero:
%   EXACT        el lector C++ da exactamente lo de dicomread
%   DIFF         da otra cosa: cuantos pixeles y la mayor diferencia
%   C++ <id>     el lector C++ no lo lee (y dicomread si)
%   REF <id>     dicomread no lo lee: no hay contra que comparar
% Y prueba que una variable pasada al abrir MANDA sobre la del fichero.

  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  if ~libisloaded( 'i3d' )                                      % i3d.dll de matlab\
    old = cd( fullfile( here , '..' , 'matlab' ) );  loadlibrary( 'i3d.dll' , @i3d_proto , 'alias' , 'i3d' );  cd( old );
  end
  dn = tempname;  mkdir( dn );  CLEAN = onCleanup( @() rmdir( dn , 's' ) );  %#ok<NASGU>
  L = strsplit( strtrim( fileread( listfile ) ) , newline );
  root = 'D:/DICOMS';
  fprintf( '%-24s %3s %3s %3s %2s %2s %2s  %s\n' , 'transfer syntax' , 'BA' , 'BS' , 'HB' , 'PR' , 'S' , 'MF' , 'result' );
  nexact = 0;  nbad = 0;
  for q = 1:numel( L )
    c = strsplit( strtrim( L{q} ) , sprintf( '\t' ) );
    fn = strrep( c{8} , '\' , '/' );
    tag = sprintf( '%-24s %3s %3s %3s %2s %2s %2s' , c{1} , c{2:7} );
    % la referencia: dicomread
    try
      R = dicomread( fn );
    catch LE
      fprintf( '%s  REF %s\n' , tag , LE.identifier );  continue;
    end
    nf = size( R , 4 );  nc = size( R , 3 );
    V = permute( R , [ 2 1 4 3 ] );                    % cols x rows x frames (x samples)
    cls = class( R );
    % el .i3d: rejillas de indices, y UN bloque <dicom> con todos sus frames
    H = { 'I3D  # check_dicom' , ...
          sprintf( '$DICOMDIR$ = "%s"' , root ) , ...
          sprintf( 'X[%d] = %s' , size(V,1) , rng_( size(V,1) ) ) , ...
          sprintf( 'Y[%d] = %s' , size(V,2) , rng_( size(V,2) ) ) , ...
          sprintf( 'Z[%d] = %s' , nf , rng_( nf ) ) , ...
          'T[1] = 0.0' , ...
          sprintf( 'data = <dicom %s "$DICOMDIR$/%s">' , cls , fn( numel(root)+2:end ) ) , '---' };
    f = fullfile( dn , sprintf( 'f%03d.i3d' , q ) );
    fid = fopen( f , 'w' );  fwrite( fid , [ strjoin( H , newline ) , newline ] , 'char' );  fclose( fid );
    try
      S = read_I3D( f );
    catch LE
      if nc > 1, why = '(SamplesPerPixel > 1: v0)'; else, why = ''; end
      fprintf( '%s  C++ %s %s -- %s\n' , tag , LE.identifier , why , strtrim( LE.message(1:min(end,90)) ) );
      if nc == 1, nbad = nbad + 1; end
      continue;
    end
    if isequal( class( S.data ) , cls ) && isequal( S.data , V )
      fprintf( '%s  EXACT\n' , tag );  nexact = nexact + 1;
    else
      d = double( S.data(:) ) - double( V(:) );
      fprintf( '%s  DIFF  %d px differ, max |d| %g  (%s)\n' , tag , nnz( d ) , max( abs( d ) ) , fn );
      nbad = nbad + 1;
    end
  end
  fprintf( '\n%d exact, %d wrong (grey files that dicomread reads)\n' , nexact , nbad );

  % una variable pasada AL ABRIR manda: el mismo fichero con $DICOMDIR$ roto
  h = fileread( fullfile( dn , 'f001.i3d' ) );
  h = strrep( h , sprintf( '$DICOMDIR$ = "%s"' , root ) , '$DICOMDIR$ = "Z:/does/not/exist"' );
  f = fullfile( dn , 'moved.i3d' );  fid = fopen( f , 'w' );  fwrite( fid , h , 'char' );  fclose( fid );
  try, read_I3D( f ); ok1 = false; catch, ok1 = true; end               % sin override: falla
  S = read_I3D( f , 'Variables' , { 'DICOMDIR' , root } );      % con override: lee
  fprintf( 'override: broken path fails %d, override reads %d\n' , ok1 , ~isempty( S.data ) );
end

function s = rng_( n )
  if n == 1, s = '0.0'; else, s = sprintf( '0.0 : 1.0 : %s' , calllib( 'i3d' , 'i3d_num2str' , n - 1 ) ); end
end
