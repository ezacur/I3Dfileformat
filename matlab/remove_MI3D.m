function remove_MI3D( filename , n )
%REMOVE_MI3D   remove members of a .mi3d container, rewriting only its header (SPEC 14.4)
%
%   remove_MI3D( 'estudio.mi3d' , 3 )
%   remove_MI3D( f , [ 2 5 ] )
%
% El miembro n queda como un HUECO: los demas conservan su numero. Si era el
% ultimo, 'i3d(N) = <missing>' mantiene N. Sus bytes se quedan donde estaban,
% sin referencia, hasta compactar (write_MI3D( f )). Si el resumen cambia (algo
% pasa a ser comun), su bloque <hidden> nuevo va al final; si no cambia, el de
% antes se queda. Lo hace mi3d.dll (mi3d_remove).
%
% ERROR IDENTIFIERS
%   remove_MI3D:badInput    n no es un miembro presente
%   remove_MI3D:<id>        f no es un .mi3d (badMagic, ...)
%
% See also write_MI3D, append_MI3D, read_MI3D.
  if ~isnumeric( n ) || isempty( n ) || any( n(:) ~= round( n(:) ) )
    error('remove_MI3D:badInput','n must be the numbers of members present in ''%s''.' , filename );
  end
  enableI3Dlibrary;
  if calllib( 'mi3d' , 'mi3d_remove' , filename , numel( n ) , int32( n(:).' ) , '' ), i3d_err_( 'remove_MI3D' , 'm' , [] ); end
end
