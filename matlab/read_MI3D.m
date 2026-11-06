function [ Rs , tags ] = read_MI3D( fname , varargin )
%READ_MI3D   lee un contenedor .mi3d (SPEC 14) con mi3d.dll e i3d.dll (calllib), SIN PASAR POR DISCO
%
%   Rs = read_MI3D( fname )                 una celda { R1 , R2 , ... }, un R por miembro
%   Rs = read_MI3D( fname , 'Data' , 'none' , 'Variables' , {...} )   las opciones de read_I3D
%   [ Rs , tags ] = read_MI3D( fname )      y la etiqueta de cada miembro (NNN.descripcion (plano))
%
% Cada R es EXACTAMENTE lo que daria read_I3D del .i3d de ese miembro: mi3d.dll da
% su rango de bytes (mi3d_range) y read_I3D lo lee en su sitio, dentro del .mi3d
% (i3d_open_window), sin copiarlo a ningun fichero. R.filename es el .mi3d.
%
% Rs{n} es el miembro n: un hueco (un numero sin miembro) es [], y su tag, ''.
% Lo contrario de write_MI3D.
%
% ERROR IDENTIFIERS
%   read_MI3D:charset   MATLAB no pasa las cadenas en UTF-8
%   read_MI3D:<id>      lo que dice mi3d.dll (cannotOpen, badHeader...)
%   read_I3D:<id>       lo que dice i3d.dll de un miembro
%
% See also write_MI3D, read_I3D.

  loadMI3Dlibrary();
  m = calllib( 'mi3d' , 'mi3d_open' , fname );
  if isNull( m )
    error( [ 'read_MI3D:' calllib( 'mi3d' , 'mi3d_last_error_id' , [] ) ] , '%s' , calllib( 'mi3d' , 'mi3d_last_error' , [] ) );
  end
  CLEAN = onCleanup( @() calllib( 'mi3d' , 'mi3d_close' , m ) );

  N = calllib( 'mi3d' , 'mi3d_count' , m );
  Rs = cell( 1 , N );  tags = repmat( { '' } , 1 , N );
  for n = 1:N
    if calllib( 'mi3d' , 'mi3d_present' , m , n ) ~= 1, continue; end      % un hueco
    [ rc , ~ , off , len ] = calllib( 'mi3d' , 'mi3d_range' , m , n , int64( 0 ) , int64( 0 ) );
    if rc ~= 0
      error( [ 'read_MI3D:' calllib( 'mi3d' , 'mi3d_last_error_id' , m ) ] , 'stack %d: %s' , n , calllib( 'mi3d' , 'mi3d_last_error' , m ) );
    end
    tags{n} = calllib( 'mi3d' , 'mi3d_tag' , m , n );
    Rs{n}   = read_I3D( fname , varargin{:} , 'Window' , [ double( off ) , double( len ) ] );
  end
  clearvars('CLEAN');
end


function loadMI3Dlibrary()
  % loadMI3Dlibrary  mi3d.dll de esta carpeta, una vez (lo mismo en write_MI3D)
  if libisloaded( 'mi3d' ), return; end
  if ~strcmpi( feature( 'DefaultCharacterSet' ) , 'UTF-8' )
    error( 'read_MI3D:charset' , 'MATLAB passes strings to the DLL in %s, and it takes UTF-8: set feature(''DefaultCharacterSet'',''UTF-8'').' , feature( 'DefaultCharacterSet' ) );
  end
  old = cd( fileparts( mfilename( 'fullpath' ) ) );  C = onCleanup( @() cd( old ) );
  loadlibrary( 'mi3d.dll' , @mi3d_proto , 'alias' , 'mi3d' );
end
