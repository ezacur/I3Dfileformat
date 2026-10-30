function py = i3d_python()
%I3D_PYTHON   the python.exe the tests call: the 'i3d' environment of Miniforge
%
%   py = i3d_python()
%
% UN solo sitio para la ruta de Python (antes cada .m llevaba la suya, fija, y
% al mover Anaconda se rompieron todos). En orden:
%   1. la variable de entorno I3D_PYTHON, si apunta a un fichero;
%   2. el entorno 'i3d' de Miniforge (tests/environment.yml), del usuario o de
%      todos los usuarios;
%   3. si no, error: no se cae en otro Python que quiza no tenga los paquetes.
%
% Crear el entorno:   mamba env create -f tests/environment.yml
%
% ERROR IDENTIFIERS
%   i3d_python:notFound    ni I3D_PYTHON ni el entorno 'i3d' de Miniforge
  py = getenv( 'I3D_PYTHON' );
  if ~isempty( py )
    if ~isfile( py ), error('i3d_python:notFound','I3D_PYTHON is ''%s'', which is not a file.', py ); end
    return;
  end
  C = { fullfile( getenv( 'USERPROFILE' ) , 'miniforge3' , 'envs' , 'i3d' , 'python.exe' ) , ...
        fullfile( getenv( 'LOCALAPPDATA' ) , 'miniforge3' , 'envs' , 'i3d' , 'python.exe' ) , ...
        fullfile( getenv( 'ProgramData' ) , 'miniforge3' , 'envs' , 'i3d' , 'python.exe' ) };
  for c = C
    if isfile( c{1} ), py = c{1}; return; end
  end
  error('i3d_python:notFound',[ 'no Python for the tests: create the Miniforge environment ' ...
        '(mamba env create -f tests/environment.yml) or set I3D_PYTHON. Looked in:\n  %s' ] , strjoin( C , '\n  ' ) );
end
