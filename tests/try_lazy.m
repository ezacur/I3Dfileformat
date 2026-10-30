function try_lazy( folder )
%TRY_LAZY   a real series: DICOMstackCollect -> write_I3D 'Lazy' -> read_I3D, bit for bit
%
%   try_lazy( 'D:\DICOMS\...\serie' )   los planos materializados, en la forma
%                                       canonica (jpegls o zlib segun el tipo)
%
% No es de regresion (depende de d:\DICOMS). Escribe el I3D que da
% DICOMstackCollect en modo perezoso, lo lee con el lector C++ y comprueba que
% devuelve EXACTAMENTE I.data. Imprime cuantos planos se referenciaron, el
% tamano del .i3d y el principio de la cabecera.
  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  [ dn , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>

  F = dir( folder );  F( [ F.isdir ] ) = [];
  F = struct( 'name' , fullfile( folder , { F.name } ) );
  DS = DICOMstackCollect( F , 'onlyK' , 'nomerge' );
  [ ~ , d ] = max( arrayfun( @(i) numel( DS(i).IMAGE.DATA ) , 1:numel(DS) ) );
  I = DS(d).IMAGE;  D = I.DATA;
  fprintf( '%s\n  stack %d: %s %s\n' , folder , d , mat2str( size(D) ) , class(D) );

  f = fullfile( dn , 'lazy.i3d' );
  t0 = tic;  write_I3D( I , f , 'Lazy' );  tw = toc( t0 );
  q = dir( f );
  t0 = tic;  [ ~ , S ] = read_I3D( f );  tr = toc( t0 );
  ok = isequal( S.data , D );
  h = fileread( f );  h = h( 1:strfind( h , [ newline '---' newline ] ) );
  L = strsplit( h , newline );
  iv = find( strncmp( L , '$DICOMDIR$' , 10 ) , 1 );
  fprintf( '  %s\n  .i3d %.1f KiB (data raw %.1f MiB)   write %.2f s   read %.2f s   bit for bit: %d\n' , ...
           L{iv} , q.bytes/1024 , numel(D)*numel(typecast(D(1),'uint8'))/2^20 , tw , tr , ok );
  fprintf( '%s\n' , L{ 1:min( end , iv+3 ) } );
  if ~ok, error('try_lazy:mismatch','the lazy file does not give back I.data.'); end
end
