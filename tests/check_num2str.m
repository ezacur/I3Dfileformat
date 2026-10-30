function check_num2str( N )
%CHECK_NUM2STR   num2strI3D against Python: exact round trip, shortest form, ".0"
%
%   check_num2str( 2e5 )
%
% Genera N doubles de varias familias, los escribe con num2strI3D y deja que
% tests/check_num2str.py los verifique: Python lee con un parser correctamente
% redondeado (lo que hara strtod en la libreria C++) y su repr es la forma mas
% corta. Lanza si Python encuentra algun caso malo.
%
% Familias: bits aleatorios (todo el rango de exponentes, subnormales
% incluidos), uniformes en [0,1), decimales "de DICOM" (PixelSpacing,
% ImagePositionPatient: pocos decimales), productos k*h como los de una
% rejilla, enteros, y los casos especiales.

  if nargin < 1, N = 2e5; end
  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );

  rng( 20261013 );
  n = round( N/5 );
  B = typecast( randi( [0 intmax('uint32')] , 2*n , 1 , 'uint32' ) , 'uint64' );
  x = typecast( B , 'double' );
  x( ~isfinite( x ) ) = [];
  x = [ x                                                   % bits aleatorios
        rand( n , 1 )                                       % uniformes
        round( ( rand( n , 1 ) - 0.5 ) * 2e6 ) / 1e3        % -1000.000 .. 1000.000
        ( 0:n-1 ).' * 0.703125                              % rejilla k*h
        ( 0:n-1 ).' * 0.1                                   % k*h con h no representable
        round( ( rand( n , 1 ) - 0.5 ) * 1e9 )              % enteros
        [ 0 ; -0 ; 1 ; -1 ; 2 ; 1e15 ; 1e16 ; 1e17 ; 1e20 ; 1e-7 ; 5e-324 ; realmin ; realmax ; -realmax ; eps ; pi ; NaN ; Inf ; -Inf ] ];

  [ f , CLEAN ] = sandfile( '#_????.txt' );  %#ok<ASGLU>
  fid = fopen( f , 'w' );
  t0 = tic;
  for i = 1:numel( x )
    fprintf( fid , '%016x\t%s\n' , typecast( x(i) , 'uint64' ) , num2strI3D( x(i) ) );
  end
  fclose( fid );
  fprintf( '%d values written in %.1f s (%.1f us each)\n' , numel(x) , toc(t0) , toc(t0)/numel(x)*1e6 );

  [ st , out ] = system( sprintf( '"%s" "%s" "%s"' , i3d_python() , fullfile( here , 'check_num2str.py' ) , f ) );
  fprintf( '%s' , out );
  if st ~= 0, error('check_num2str:failed','Python found bad cases (see above).'); end
end
