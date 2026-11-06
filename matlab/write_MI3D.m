function write_MI3D( S , fname , varargin )
%WRITE_MI3D   escribe un contenedor .mi3d (SPEC 14) con mi3d.dll (calllib), SIN PASAR POR DISCO
%
%   write_MI3D( DS(1:10) , fname )            un array de DICOMstacks: un miembro por pila
%   write_MI3D( { R1 , R2 , R3 } , fname )    structs como la de read_I3D
%   write_MI3D( { I1 , I2 , I3 } , fname )    I3D con su DICOMstack en I.INFO.DICOMstack
%   write_MI3D( ... , 'Comment' , c )         la primera linea (sin darla: "mi3d_write <fecha>, K stacks")
%
% Cada miembro es EXACTAMENTE el .i3d que escribiria write_I3D (la misma
% conversion a R y las mismas llamadas, sobre el escritor de mi3d.dll), pero se
% codifica en memoria y se copia al contenedor: ningun .i3d intermedio toca el
% disco. El resultado es el mismo .mi3d que escribir cada uno con write_I3D y
% juntarlos con mi3d_write_files, con las mismas etiquetas.
%
% El cell puede mezclar DICOMstacks, I3D y Rs. La etiqueta de cada miembro (el
% comentario de su linea i3d(n)) es NNN.descripcion (plano), la del comentario
% de su cabecera. En memoria quedan solo los miembros ya comprimidos (y la pila
% que se esta escribiendo).
%
% ERROR IDENTIFIERS
%   write_MI3D:input     S no es un array de DICOMstacks ni un cell; una opcion mala
%   write_MI3D:charset   MATLAB no pasa las cadenas en UTF-8
%   write_MI3D:<id>      lo que dice mi3d.dll (badData, badGrid, cannotOpen...)
%
% See also write_I3D, read_I3D, read_MI3D.

  if isa( S , 'DICOMstack' )
    S = arrayfun( @( d ) S( d ) , 1:numel( S ) , 'un' , 0 );   % un cell, una pila por celda
  elseif ~iscell( S )
    error( 'write_MI3D:input' , 'An array of DICOMstacks, or a cell of DICOMstacks, I3D or structs like the one of read_I3D, was expected.' );
  end
  if isempty( S ), error( 'write_MI3D:input' , 'No stacks to write.' ); end
  if mod( numel( varargin ) , 2 ), error( 'write_MI3D:input' , 'Options go in pairs: ''Comment'' , c.' ); end
  COMMENT = '';
  for o = 1:2:numel( varargin )
    switch lower( varargin{o} )
      case 'comment', COMMENT = varargin{o+1};
      otherwise,      error( 'write_MI3D:input' , 'Unknown option ''%s'' (Comment).' , varargin{o} );
    end
  end

  loadMI3Dlibrary();
  mi3dnew = calllib( 'mi3d' , 'mi3d_new' );  CLEAN = onCleanup( @() calllib( 'mi3d' , 'mi3d_free' , mi3dnew ) );
  callmi3d = @(api,varargin) chk_( calllib( 'mi3d' , ['mi3d_',api] , mi3dnew , varargin{:} ) , mi3dnew , api );   % un rc ~= 0: error (add_*: aviso)

  if ~isempty( COMMENT ), callmi3d( 'set_option' , 'Comment' , COMMENT ); end
  for s = 1:numel( S )
    write_I3D( S{s} , callmi3d );                         % mi3d_add_stack y las mismas llamadas que un .i3d
  end
  callmi3d( 'write' , fname );
  clearvars('CLEAN');
end


function loadMI3Dlibrary()
  % loadMI3Dlibrary  mi3d.dll de esta carpeta, una vez
  if libisloaded( 'mi3d' ), return; end
  if ~strcmpi( feature( 'DefaultCharacterSet' ) , 'UTF-8' )
    error( 'write_MI3D:charset' , 'MATLAB passes strings to the DLL in %s, and it takes UTF-8: set feature(''DefaultCharacterSet'',''UTF-8'').' , feature( 'DefaultCharacterSet' ) );
  end
  old = cd( fileparts( mfilename( 'fullpath' ) ) );  C = onCleanup( @() cd( old ) );
  loadlibrary( 'mi3d.dll' , @mi3d_proto , 'alias' , 'mi3d' );
end


function chk_( rc , m , api )
%CHK_  lo que devuelve una funcion de mi3d.dll: 0 bien; si no, su mensaje. Un info.* que
% no se puede escribir es un aviso (el miembro sale sin el); lo demas, un error
  if rc == 0, return; end
  msg = calllib( 'mi3d' , 'mi3d_wlast_error' , m );
  if strncmp( api , 'add_' , 4 ) && ~strcmp( api , 'add_stack' )
    warning( 'write_MI3D:skipped' , 'mi3d_%s: %s' , api , msg );
  else
    error( [ 'write_MI3D:' calllib( 'mi3d' , 'mi3d_wlast_error_id' , m ) ] , 'mi3d_%s: %s' , api , msg );
  end
end
