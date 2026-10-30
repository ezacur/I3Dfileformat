function n = append_MI3D( filename , files , varargin )
%APPEND_MI3D   add .i3d files to a .mi3d container, without rewriting it (SPEC 14.4)
%
%   n = append_MI3D( 'estudio.mi3d' , 'serie.i3d' )       n: su numero, N+1
%   n = append_MI3D( f , { 'a.i3d' , 'b.i3d' } )          N+1, N+2
%   n = append_MI3D( f , ... , 'Tags' , { 'a' , 'b' } )
%
% Si el contenedor no existe, lo crea. Si existe, mi3d.dll (mi3d_append) hace,
% en este orden, para que valga con lo de antes hasta el ultimo paso:
%   1. los .i3d nuevos, con sus separadores, al FINAL del fichero;
%   2. el bloque <hidden> del resumen nuevo detras (el viejo queda como unos
%      pocos bytes sin referencia: write_MI3D( f ) los quita);
%   3. la cabecera, EN SU SITIO: crece dentro de la reserva, sin mover nada.
% Si ya no cabe en la reserva, se reescribe el fichero entero (a un temporal
% que se renombra encima) con una reserva nueva.
%
% OPCIONES: 'Tags', 'Reserve' (la de una reescritura), 'Comment', 'Lazy','keep'
% (ver write_MI3D).
%
% See also write_MI3D, remove_MI3D, read_MI3D.

  if ischar( files ), files = { files }; end
  if ~iscell( files ) || isempty( files ) || any( cellfun( @isempty , files ) )
    error('append_MI3D:badInput','files: one .i3d path or a cell of them (no holes: they are added at the end).');
  end
  [ O , varargin ] = mi3d_options_( varargin , 'append_MI3D' );
  if ~isempty( varargin ), error('append_MI3D:badInput','unrecognised arguments.'); end
  [ F , T ] = mi3d_files_( files , O , 'append_MI3D' );
  enableI3Dlibrary;
  [ rc , ~ , ~ , ~ , ~ , first ] = calllib( 'mi3d' , 'mi3d_append' , filename , numel( F ) , F , T , O.reserve , O.comment , double( O.lazykeep ) , 0 );
  if rc, i3d_err_( 'append_MI3D' , 'm' , [] ); end
  n = double( first ) + ( 0:numel( F ) - 1 );
end
