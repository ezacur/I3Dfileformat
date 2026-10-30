function hideI3Dfile( src , dst )
%HIDEI3DFILE   rewrite an .i3d with its header hidden (the I3Db variant, SPEC 1.1)
%
%   hideI3Dfile( 'serie.i3d' , 'serie_hidden.i3d' )
%   hideI3Dfile( 'serie.i3d' )                      en el sitio
%
% La cabecera en claro se comprime (zlib) y se ofusca -- un flip de bits y un
% XOR con una secuencia que depende de la posicion --, y el binario se copia
% BYTE A BYTE: como los offsets son relativos al inicio del binario, no cambia
% ninguno. Un fichero que ya es I3Db se reescribe igual. Lo hace i3d.dll
% (i3d_rewrite), todo o nada: con dst = src, un fallo a mitad no se lleva el
% original.
%
% NO protege: lo necesario para leerla esta en SPEC 1.1. Solo evita al curioso
% con un editor de texto. La vuelta es showI3Dfile.
%
% ERROR IDENTIFIERS
%   hideI3Dfile:<id>    el de la DLL: cannotOpen (no se puede escribir dst), o el
%                    del lector si src no es un .i3d valido (badMagic, ...)
%
% See also showI3Dfile, write_I3D.
  if nargin < 2, dst = src; end
  enableI3Dlibrary;
  if calllib( 'i3d' , 'i3d_rewrite' , src , dst , 1 ), i3d_err_( 'hideI3Dfile' , 'f' , [] ); end
end
