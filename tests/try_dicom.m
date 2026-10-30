function try_dicom( folder )
%TRY_DICOM   a real series through DICOMstackCollect -> write_I3D -> MEX and read_i3d.py
%
%   try_dicom( 'D:\DICOMS\MR 001\DICOM\000062D6\AA77D253\AA0655D4\00007844' )
%
% No es un test de regresion (depende de d:\DICOMS): es para MIRAR la cabecera
% que sale de un DICOM de verdad y medir cuanto cuesta escribir. Escribe la
% forma canonica (el encoding lo fija el tipo) y comprueba con el MEX y con el
% lector de referencia que devuelven el volumen bit a bit.

  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  [ dn , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>

  % la LISTA de ficheros, no la carpeta: con dicomparse como parser,
  % DICOMheader trata la carpeta como un fichero (bytes -1, todo vacio) en vez
  % de recorrerla. Visto el 2026-10-13; no investigado
  F = dir( folder );  F( [ F.isdir ] ) = [];
  F = struct( 'name' , fullfile( folder , { F.name } ) );
  t0 = tic;
  DS = DICOMstackCollect( F , 'onlyK' , 'nomerge' );
  fprintf( 'DICOMstackCollect: %.1f s, %d stack(s)\n' , toc(t0) , numel(DS) );
  [ ~ , d ] = max( arrayfun( @(i) numel( DS(i).IMAGE.DATA ) , 1:numel(DS) ) );
  I = DS(d).IMAGE;
  D = I.DATA;
  fprintf( 'stack %d: %s %s\n' , d , mat2str( size(D) ) , class(D) );

  nraw = numel(D) * numel( typecast( D(1) , 'uint8' ) );
  f = fullfile( dn , 'serie.i3d' );
  t0 = tic;  write_I3D( I , f );  tw = toc(t0);
  q = dir( f );
  fprintf( 'write %.2f s   %.1f MiB  (ratio %.3f)\n' , tw , q.bytes/2^20 , nraw / q.bytes );
  h = fileread( f );
  k = strfind( h , [ newline '---' newline ] );
  fprintf( '\n%s\n\n' , h( 1:k+4 ) );

  % el MEX (lector C++): bit a bit y cuanto tarda
  t0 = tic;  [ J , S ] = read_I3D( f );  tr = toc( t0 );
  okmex = isequal( typecast( S.data(:) , 'uint8' ) , typecast( D(:) , 'uint8' ) ) && isequal( J.X , I.X ) && isequal( J.SpatialTransform , I.SpatialTransform );
  fprintf( 'MEX read_I3D: %.3f s, bit for bit %d\n' , tr , okmex );
  if ~okmex, error('try_dicom:mexMismatch','the MEX disagrees.'); end

  % que el lector de referencia devuelva lo mismo que MATLAB tiene
  fr = fullfile( dn , 'ref.raw' );
  fid = fopen( fr , 'w' );  fwrite( fid , D(:) , class(D) );  fclose( fid );
  py = [ 'import sys; sys.path.insert(0,r''' here '''); from read_i3d import read_i3d;' ...
         'ref=open(r''' fr ''',''rb'').read();' ...
         'print(read_i3d(r''' f ''')[''data''].tobytes(order=''F'')==ref)' ];
  [ st , out ] = system( sprintf( '"%s" -c "%s"' , i3d_python() , py ) );
  fprintf( 'reference reader, bit for bit: %s' , out );
  if st ~= 0 || ~isempty( strfind( out , 'False' ) ), error('try_dicom:mismatch','the reference reader disagrees.'); end
end
