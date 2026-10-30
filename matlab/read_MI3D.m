function out = read_MI3D( filename , n , varargin )
%READ_MI3D   list a .mi3d container, or read one of its members (SPEC 14)
%
%   C = read_MI3D( 'estudio.mi3d' )        la lista, sin leer ningun miembro
%   I = read_MI3D( f , n )                 el miembro n, un @I3D como read_I3D;
%                                          [] si es un HUECO
%   I = read_MI3D( f , n , 'firstFrame' )  ... las opciones de read_I3D
%
% C tiene:
%   N         el numero de miembros (huecos incluidos)
%   present   1 x N logical
%   offset    1 x N, donde empieza cada miembro en el FICHERO (0-based; NaN un hueco)
%   length    1 x N, sus bytes (NaN un hueco)
%   tag       1 x N cellstr, la etiqueta del comentario de su linea i3d(n) (el
%             nombre del fichero de origen: solo un comentario; '' si no hay)
%   INFO      el RESUMEN, info.* de la cabecera del contenedor (lo que todos
%             los miembros tienen igual), como el INFO de read_I3D
%   header    la cabecera TAL CUAL (sin desplegar la parte <hidden>)
%   entries   {key subs value} de toda la cabecera, la parte <hidden> incluida
%   binstart  donde empieza el binario (0-based): la longitud de la cabecera
%
% Lee con mi3d.dll (la cabecera y el rango de cada miembro: mi3d_range) e
% i3d.dll (un miembro es un .i3d como cualquier otro, leido por su ventana del
% fichero: i3d_open_window).
%
% ERROR IDENTIFIERS: read_I3D:<id> -- los de read_I3D, y de mi3d.dll badMagic
% (no es un .mi3d), badIndex (n fuera de 1..N)...
%
% See also write_MI3D, append_MI3D, remove_MI3D, read_I3D, enableI3Dlibrary.

  if nargin >= 2
    if ~isnumeric( n ) || ~isscalar( n ) || n ~= round( n ), error('read_I3D:badInput','n must be an integer.'); end
    if n < 1, error('read_I3D:badIndex','no member %d: members are numbered from 1.' , n ); end
    try
      out = read_I3D( filename , varargin{:} , 'Member' , n );
    catch E
      if ~strcmp( E.identifier , 'read_I3D:missingMember' ), rethrow( E ); end
      out = [];
    end
    return;
  end

  enableI3Dlibrary;
  m = calllib( 'mi3d' , 'mi3d_open' , filename );
  if isNull( m ), i3d_err_( 'read_I3D' , 'm' , [] ); end
  C = onCleanup( @() calllib( 'mi3d' , 'mi3d_close' , m ) );
  N = double( calllib( 'mi3d' , 'mi3d_count' , m ) );
  out = struct( 'N' , N , 'present' , false( 1 , N ) , 'offset' , NaN( 1 , N ) , 'length' , NaN( 1 , N ) , ...
                'tag' , { repmat( { '' } , 1 , N ) } , 'INFO' , struct() , 'header' , calllib( 'mi3d' , 'mi3d_header' , m ) , 'entries' , { {} } , ...
                'binstart' , double( calllib( 'mi3d' , 'mi3d_binary_start' , m ) ) );
  for k = 1:N
    out.tag{k} = calllib( 'mi3d' , 'mi3d_tag' , m , k );
    if calllib( 'mi3d' , 'mi3d_present' , m , k ) ~= 1, continue; end
    [ rc , ~ , a , L ] = calllib( 'mi3d' , 'mi3d_range' , m , k , 0 , 0 );
    if rc, i3d_err_( 'read_I3D' , 'm' , m ); end
    out.present(k) = true;  out.offset(k) = double( a );  out.length(k) = double( L );
  end
  ne = calllib( 'mi3d' , 'mi3d_entry_count' , m );
  out.entries = cell( ne , 3 );
  for e = 1:ne
    out.entries(e,:) = { calllib( 'mi3d' , 'mi3d_entry_key' , m , e - 1 ) , calllib( 'mi3d' , 'mi3d_entry_subs' , m , e - 1 ) , calllib( 'mi3d' , 'mi3d_entry_value' , m , e - 1 ) };
  end
  for e = 1:ne
    k = out.entries{e,1};
    if ~strncmp( k , 'info.' , 5 ), continue; end
    f = strrep( k(6:end) , '.' , '_' );
    if ~isvarname( f ), f = matlab.lang.makeValidName( f ); end
    out.INFO.( f ) = i3d_value_( out.entries{e,3} );
  end
end
