function showI3Dfile( src , dst )
%SHOWI3DFILE   rewrite an .i3d with its header in plain text (undo hideI3Dfile, SPEC 1.1)
%
%   showI3Dfile( 'serie_hidden.i3d' , 'serie.i3d' )
%   showI3Dfile( 'serie_hidden.i3d' )                en el sitio
%
% La cabecera la decodifica el lector, se escribe en claro seguida de la linea
% '---', y el binario se copia BYTE A BYTE -- los offsets son relativos al
% inicio del binario, asi que no cambia ninguno. Un fichero que ya esta en
% claro se reescribe igual. Lo hace i3d.dll (i3d_rewrite), todo o nada.
%
% ERROR IDENTIFIERS
%   showI3Dfile:<id>    el de la DLL: cannotOpen (no se puede escribir dst), o el
%                    del lector si src no es un .i3d valido (badMagic, ...)
%
% See also hideI3Dfile, read_I3D.
  if nargin < 2, dst = src; end
  enableI3Dlibrary;
  if calllib( 'i3d' , 'i3d_rewrite' , src , dst , 0 ), i3d_err_( 'showI3Dfile' , 'f' , [] ); end
end
