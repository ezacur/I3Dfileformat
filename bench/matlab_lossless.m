function matlab_lossless( folder )
%MATLAB_LOSSLESS   what MATLAB itself can write losslessly: ratio, exactness, time
%
%   matlab_lossless( 'D:\DICOMS\...\serie' )
%
% Corte a corte, sobre los pixeles ALMACENADOS de una serie (uint16 sin
% rescale), con lo que MATLAB escribe de serie: imwrite JPEG lossless 16 bits
% y JPEG 2000 lossless. Comprueba la ida y vuelta bit a bit. Para comparar con
% bench/results_all.txt (JPEG-LS de imagecodecs, zlib, ...).

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
  V = cat( 3 , V{:} );
  raw = numel( V ) * 2;
  fprintf( '%s\n  %s %s  raw %.1f MiB\n' , folder , mat2str( size(V) ) , class(V) , raw/2^20 );

  [ d , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>
  M = { 'jpg lossless 16' , 'jpg' , { 'Mode','lossless' , 'BitDepth',16 } ;
        'jp2 lossless'    , 'jp2' , { 'Mode','lossless' } };
  for m = 1:size( M , 1 )
    bytes = 0;  te = 0;  td = 0;  exact = true;
    for k = 1:size( V , 3 )
      f = fullfile( d , sprintf( 's%04d.%s' , k , M{m,2} ) );
      t0 = tic;  imwrite( V(:,:,k) , f , M{m,3}{:} );  te = te + toc( t0 );
      q = dir( f );  bytes = bytes + q.bytes;
      t0 = tic;  R = imread( f );  td = td + toc( t0 );
      exact = exact && isequal( R , V(:,:,k) );
    end
    fprintf( '  %-16s ratio %6.3f   enc %6.2f s   dec %6.2f s   %s\n' , M{m,1} , raw/bytes , te , td , iff_( exact , 'EXACT' , 'NOT EXACT' ) );
  end
end

function v = iff_( c , a , b )
  if c, v = a; else, v = b; end
end
