function enableI3Dlibrary()
%ENABLEI3DLIBRARY   load i3d.dll and mi3d.dll with loadlibrary, as 'i3d' and 'mi3d'
%
%   enableI3Dlibrary          carga las que no esten cargadas
%
% Todo lo del formato -- leer, escribir, ocultar, el contenedor -- esta en las
% dos DLL (cpp/, SPEC.md). Desde MATLAB se llaman con calllib:
%
%   enableI3Dlibrary
%   w = calllib( 'i3d' , 'i3d_new' );
%   calllib( 'i3d' , 'i3d_set_data' , w , I.data , class( I.data ) , ndims( I.data ) , int64( size( I.data ) ) );
%   calllib( 'i3d' , 'i3d_set_Xgrid' , w , I.X , numel( I.X ) );                         % y Y, Z, T
%   calllib( 'i3d' , 'i3d_set_transform' , w , reshape( I.SpatialTransform.' , 1 , [] ) );   % POR FILAS
%   calllib( 'i3d' , 'i3d_add_info_numbers' , w , 'SeriesNumber' , 10 , 1 , 1 , '' );      % 1: a la vista
%   calllib( 'i3d' , 'i3d_add_info_text' , w , 'PatientName' , 'John Doe' , 2 , '' );      % 2: oculta
%   if calllib( 'i3d' , 'i3d_write' , w , 'image.i3d' ), error( calllib( 'i3d' , 'i3d_wlast_error' , w ) ); end
%   calllib( 'i3d' , 'i3d_free' , w );
%
% (cada funcion devuelve 0 si va bien; la lista, en lib/i3d_c.h y lib/mi3d_c.h,
% o con libfunctionsview i3d). write_I3D, read_I3D y las demas .m de esta
% carpeta son ejemplos de uso: traducen un @I3D a esas llamadas.
%
% Las DLL estan en lib/ (las copia cpp/build.bat), con un prototipo .m y un
% thunk por DLL: con ellos loadlibrary no necesita compilador. Despues de
% cambiar i3d_c.h o mi3d_c.h hay que regenerarlos: rebuildI3Dprototypes.
%
% Las cadenas cruzan como UTF-8 solo si MATLAB usa UTF-8
% (feature('DefaultCharacterSet')); si no, es un error.
%
% See also rebuildI3Dprototypes, calllib, libfunctionsview, write_I3D, read_I3D.

  % lo normal: ya estan (cada funcion de esta carpeta llama aqui antes de calllib)
  if libisloaded( 'i3d' ) && libisloaded( 'mi3d' ), return; end
  lib = fullfile( fileparts( mfilename( 'fullpath' ) ) , 'lib' );
  if ~strcmpi( feature( 'DefaultCharacterSet' ) , 'UTF-8' )
    error('enableI3Dlibrary:charset','MATLAB passes strings to the DLLs in %s, and they take UTF-8: set feature(''DefaultCharacterSet'',''UTF-8'').', feature( 'DefaultCharacterSet' ) );
  end
  old = cd( lib );  C = onCleanup( @() cd( old ) );
  if ~libisloaded( 'i3d' ),  loadlibrary( 'i3d.dll'  , @i3d_proto  , 'alias' , 'i3d' );  end
  if ~libisloaded( 'mi3d' ), loadlibrary( 'mi3d.dll' , @mi3d_proto , 'alias' , 'mi3d' ); end
end
