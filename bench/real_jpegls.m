function real_jpegls( folder )
%REAL_JPEGLS   a real series through write_I3D 'zlib' and 'jpegls', back through the MEX
%
%   real_jpegls( 'D:\DICOMS\...\serie' )
%
% Los pixeles almacenados de la serie (dicomread, ordenados por InstanceNumber)
% en un @I3D, escritos con write_I3D en zlib y en jpegls, y leidos con read_I3D
% (el lector C++). Imprime tamano, relacion, tiempos y si la vuelta es exacta.
%
% HISTORICO: se corrio el 2026-10-13 con el escritor ANTERIOR a la forma
% canonica, que dejaba elegir el encoding. Su resultado (real_jpegls_results.txt)
% es la medida que justifica jpegls para los enteros de 8/16 bits en SPEC 9. El
% escritor actual no deja elegir: este banco ya no corre, y lanza al empezar.
  error('real_jpegls:historical','historical bench: write_I3D no longer takes an encoding (SPEC 9). See real_jpegls_results.txt.');

  F = dir( folder );  F( [ F.isdir ] ) = [];
  V = {};  n = [];
  for f = 1:numel( F )
    p = fullfile( folder , F(f).name );
    try, I = dicomread( p ); h = dicominfo( p ); catch, continue; end
    if isempty( I ), continue; end
    V{end+1} = I;  n(end+1) = h.InstanceNumber; %#ok<AGROW>
  end
  [ ~ , o ] = sort( n );  V = V( o );
  sz = size( V{1} );  V = V( cellfun( @(x) isequal( size(x) , sz ) , V ) );
  V = permute( cat( 3 , V{:} ) , [2 1 3] );          % i = columna, como DICOMstack
  raw = numel( V ) * numel( typecast( V(1) , 'uint8' ) );
  I = I3D( V );
  fprintf( '%s\n  %s %s  raw %.1f MiB\n' , folder , mat2str( size(V) ) , class(V) , raw/2^20 );

  [ d , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>
  for enc = { 'zlib' , 'jpegls' }
    f = fullfile( d , [ 'serie_' enc{1} '.i3d' ] );
    t0 = tic;  write_I3D( I , f , enc{1} );  tw = toc( t0 );
    q = dir( f );
    t0 = tic;  [ ~ , S ] = read_I3D( f );  tr = toc( t0 );
    exact = isequal( S.data , V );
    fprintf( '  %-6s %8.1f MiB  ratio %6.3f   write %6.2f s   read %6.2f s   %s\n' , enc{1} , q.bytes/2^20 , raw/q.bytes , tw , tr , iff_( exact , 'EXACT' , 'NOT EXACT' ) );
    if ~exact, error('real_jpegls:notExact','%s does not come back exact.', enc{1} ); end
  end
end

function v = iff_( c , a , b )
  if c, v = a; else, v = b; end
end
