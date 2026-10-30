function write_MI3D( filename , varargin )
%WRITE_MI3D   write a .mi3d container of .i3d files (SPEC 14), or compact one
%
%   write_MI3D( 'estudio.mi3d' , { 'a.i3d' , 'b.i3d' , ... } )   uno nuevo
%   write_MI3D( f , { 'a.i3d' , '' , 'c.i3d' } )    un '' (o []) es un HUECO: el
%                                                   miembro 2 no existe
%   write_MI3D( f )                                 COMPACTA un .mi3d existente:
%                                                   sin bytes sin referencia, el
%                                                   <hidden> el ultimo y una
%                                                   reserva nueva. Conserva los
%                                                   numeros y los huecos
%   write_MI3D( f , 'Renumber' )                    compacta cerrando los huecos
%
% Cada miembro es un .i3d de cualquier variante (texto, I3Db, con parte
% <hidden>, Lazy) copiado BYTE A BYTE: se puede abrir sin leer los demas
% (read_MI3D( f , n )). Los miembros no tienen nombre, solo numero; el nombre del
% fichero de origen va como etiqueta en los comentarios.
%
% Lo escribe mi3d.dll (mi3d_write, mi3d_compact; cpp/mi3d.cpp), todo o nada:
%   MI3D 0.1  # mi3d_write <fecha>, K stacks
%   i3d(1) = <i3d @a:b>  # a.i3d [ i x j x k x t ]   uno por miembro, en orden
%   i3d(N) = <missing>                                si el ultimo es un hueco
%   header = <hidden @a:b>                            si el resumen oculta algo
%   info.*                                            el RESUMEN: lo que TODOS los
%                                                     miembros tienen igual; a la
%                                                     vista si lo esta en todos
%   #<espacios>                                       la RESERVA ('Reserve' bytes)
%   ---
%   binario: cada miembro entre '****** # tag [ dims ]' y '++++++ # tag', y el
%   bloque <hidden> el ULTIMO.
% La reserva deja anadir y quitar miembros reescribiendo solo la cabecera en su
% sitio (append_MI3D, remove_MI3D).
%
% OPCIONES
%   'Tags' , C        las etiquetas, una por fichero (default: su nombre)
%   'Reserve' , n     los bytes de la linea de reserva (default 8192; >= 2)
%   'Comment' , s     el comentario de la primera linea
%   'Lazy' , 'keep'   acepta un miembro Lazy con rutas RELATIVAS de otra carpeta:
%                     se resuelven desde la del contenedor (SPEC 14.2), asi que
%                     sin esto es un error
%
% ERROR IDENTIFIERS
%   write_MI3D:badInput     argumentos que no son lo de arriba
%   write_MI3D:lazyFolder   un miembro Lazy con rutas relativas de otra carpeta
%   write_MI3D:cannotOpen   no se puede escribir
%   write_MI3D:<id>         un miembro que no se puede leer (badMagic, ...)
%
% See also read_MI3D, append_MI3D, remove_MI3D, write_I3D, enableI3Dlibrary.

  FILES = [];
  if ~isempty( varargin ) && iscell( varargin{1} ), FILES = varargin{1};  varargin(1) = []; end
  [ O , varargin ] = mi3d_options_( varargin , 'write_MI3D' );
  RENUMBER = false;
  try, [ varargin , RENUMBER ] = parseargs( varargin , 'Renumber' , '$FORCE$' , { true , false } ); end
  if ~isempty( varargin ), error('write_MI3D:badInput','unrecognised arguments.'); end
  if ~ischar( filename ) || isempty( filename ), error('write_MI3D:badInput','filename must be a char row.'); end

  enableI3Dlibrary;
  if isempty( FILES )
    % compactar
    if ~exist( filename , 'file' ), error('write_MI3D:badInput','''%s'' does not exist: give the .i3d files to put in it.' , filename ); end
    rc = calllib( 'mi3d' , 'mi3d_compact' , filename , double( RENUMBER ) , O.reserve , O.comment );
  else
    if RENUMBER, error('write_MI3D:badInput','''Renumber'' is for compacting an existing .mi3d.'); end
    [ F , T ] = mi3d_files_( FILES , O , 'write_MI3D' );
    rc = calllib( 'mi3d' , 'mi3d_write' , filename , numel( F ) , F , T , O.reserve , O.comment , double( O.lazykeep ) );
  end
  if rc, i3d_err_( 'write_MI3D' , 'm' , [] ); end
end
