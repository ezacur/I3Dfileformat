function rebuildI3Dprototypes()
%REBUILDI3DPROTOTYPES   regenerate the loadlibrary prototypes of i3d.dll and mi3d.dll
%
%   rebuildI3Dprototypes
%
% REGENERA, en lib/, lo que enableI3Dlibrary usa para cargar las DLL sin
% compilador: i3d_proto.m y mi3d_proto.m (la lista de funciones con sus tipos)
% y sus thunk (i3d_thunk_pcwin64.dll, mi3d_thunk_pcwin64.dll), desde las
% cabeceras lib/i3d_c.h y lib/mi3d_c.h. Borra los intermedios (.exp .lib .obj).
%
% CUANDO: solo si cambia la API en C (se anade, quita o cambia la firma de una
% funcion de i3d_c.h o mi3d_c.h). Un cambio dentro de la DLL no lo necesita:
% basta recompilar (cpp\build.bat) y volver a cargarla. Con la cabecera nueva
% y el prototipo viejo, calllib no conoce la funcion nueva, o pasa mal los
% argumentos de una que cambio.
%
%   unloadlibrary i3d; unloadlibrary mi3d     (si no, build.bat no puede copiar la DLL)
%   cpp\build.bat                             (desde la raiz del repositorio)
%   rebuildI3Dprototypes
%   enableI3Dlibrary
%
% NECESITA un compilador de C configurado (mex -setup C): loadlibrary analiza
% la cabecera y compila el thunk. Deja las DLL cargadas.
%
% See also enableI3Dlibrary, loadlibrary.

  lib = fullfile( fileparts( mfilename( 'fullpath' ) ) , 'lib' );
  old = cd( lib );  C = onCleanup( @() cd( old ) );
  for n = { 'i3d' , 'mi3d' }
    if libisloaded( n{1} ), unloadlibrary( n{1} ); end
    % las definiciones de la CRT de Windows que el analizador no conoce salen
    % como avisos (voidPtr): no son de la API
    [ ~ , ~ ] = loadlibrary( [ n{1} '.dll' ] , [ n{1} '_c.h' ] , 'alias' , n{1} , 'mfilename' , [ n{1} '_proto' ] );
    delete( [ n{1} '_thunk_pcwin64.exp' ] , [ n{1} '_thunk_pcwin64.lib' ] , [ n{1} '_thunk_pcwin64.obj' ] );
  end
end
