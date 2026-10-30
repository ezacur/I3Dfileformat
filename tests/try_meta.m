function try_meta( folder , varargin )
%TRY_META   thumbnails and info.* from a real DICOMstack, written and read back
%
%   try_meta( 'D:\DICOMS\...\serie' )
%   try_meta( 'D:\DICOMS\...\serie' , 'info' )   DICOMstackCollect con dicominfo completo
%
% No es de regresion (depende de d:\DICOMS). Escribe el I3D de DICOMstackCollect
% en lazy y en materializado, lo lee con read_I3D, y comprueba: data bit a bit,
% CADA thumbnail de I.INFO identico en I.INFO leido, y que los info.* salen.
% Imprime la cabecera.
  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  [ dn , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>
  F = dir( fullfile( folder , '**' , '*' ) );  F( [ F.isdir ] ) = [];
  F = struct( 'name' , fullfile( { F.folder } , { F.name } ) );
  DS = DICOMstackCollect( F , varargin{:} );
  I = DS(1).IMAGE;
  for lazy = [ true false ]
    f = fullfile( dn , sprintf( 'm%d.i3d' , lazy ) );
    if lazy, write_I3D( I , f , 'Lazy' );  else, write_I3D( I , f );  end
    J = read_I3D( f );
    ok = isequal( J.DATA , I.DATA );
    for t = fieldnames( I.INFO ).', t = t{1};
      if strncmp( t , 'thumbnail' , 9 )
        same = isfield( J.INFO , t ) && isequal( J.INFO.(t) , I.INFO.(t) ) && strcmp( class( J.INFO.(t) ) , class( I.INFO.(t) ) );
        fprintf( '  lazy %d  %s %s %s  back identical: %d\n' , lazy , t , class( I.INFO.(t) ) , mat2str( size( I.INFO.(t) ) ) , same );
        ok = ok && same;
      end
    end
    fprintf( '  lazy %d  data bit for bit and thumbnails: %d\n' , lazy , ok );
    if ~ok, error('try_meta:mismatch','something did not come back.'); end
  end
  h = fileread( f );  h = h( 1:strfind( h , [ newline '---' newline ] ) );
  L = strsplit( h , newline );
  fprintf( '%s\n' , L{ ~strncmp( L , 'data(' , 5 ) } );
  disp( J.INFO );
end
