function code = convert_to_MI3D_cli( varargin )
%CONVERT_TO_MI3D_CLI   convert_to_MI3D desde la linea de comandos (compilado con build_convert)
%
%   convert_to_MI3D <folder> [outdir] [-t1|-t01] [-info] [-threads N]
%
%   folder        los DICOM (se recorre entero)
%   outdir        donde van los .mi3d (sin darlo: folder)
%   -t1           solo el primer instante de cada pila; el thumbnail, animado
%   -t01          lo mismo, y el thumbnail solo de ese instante
%   -info         la cabecera entera de cada fichero (dicominfo; lento)
%   -threads N    hilos de lectura (12)
%
% Escribe un <Person>.<StudyDescription>.mi3d por paciente y estudio, y al final la
% lista de los escritos. Codigo de salida: 0 bien; 1 algun estudio no se escribio;
% 2 un error (argumentos, carpeta...). En MATLAB tambien vale:
%   convert_to_MI3D_cli( 'D:\DICOMS\x' , 'E:\out' , '-t1' )
%
% See also convert_to_MI3D, build_convert.

  code = 2;
  try
    % calllib pasa las cadenas en este juego de caracteres, y las DLL quieren UTF-8 (el
    % ejecutable arranca con el de Windows)
    feature( 'DefaultCharacterSet' , 'UTF-8' );

    pos = {};  opts = {};  k = 1;
    while k <= numel( varargin )
      a = varargin{k};
      switch lower( a )
        case { '-h' , '-help' , '--help' , '/?' }, usage_();  code = 0;  exit_( code );  return;
        case '-t1',      opts = [ opts , { 'T1' , true } ];   %#ok<AGROW>
        case '-t01',     opts = [ opts , { 'T01' , true } ];  %#ok<AGROW>
        case '-info',    opts = [ opts , { 'Info' , true } ]; %#ok<AGROW>
        case '-threads'
          if k == numel( varargin ), error( 'convert_to_MI3D:input' , '-threads needs a number' ); end
          n = str2double( varargin{k+1} );  k = k + 1;
          if ~isfinite( n ) || n < 1 || n ~= round( n ), error( 'convert_to_MI3D:input' , '-threads needs a positive integer' ); end
          opts = [ opts , { 'Threads' , n } ]; %#ok<AGROW>
        otherwise
          if startsWith( a , '-' ), error( 'convert_to_MI3D:input' , 'unknown option %s (-t1, -t01, -info, -threads N)' , a ); end
          pos{end+1} = a; %#ok<AGROW>
      end
      k = k + 1;
    end
    if isempty( pos ) || numel( pos ) > 2, usage_();  error( 'convert_to_MI3D:input' , 'give a folder, and optionally an output folder' ); end
    if numel( pos ) < 2, pos{2} = ''; end

    [ files , failed ] = convert_to_MI3D( pos{1} , pos{2} , opts{:} );
    fprintf( '\n%d .mi3d written:\n' , numel( files ) );
    fprintf( '  %s\n' , files{:} );
    if failed, fprintf( 2 , '%d studies NOT written (see the warnings above)\n' , failed ); end
    code = double( failed > 0 );
  catch E
    fprintf( 2 , 'convert_to_MI3D: %s\n' , E.message );
    code = 2;
  end
  exit_( code );
end

function usage_()
  fprintf( 'usage: convert_to_MI3D <folder> [outdir] [-t1|-t01] [-info] [-threads N]\n' );
end

function exit_( code )
  % compilado, el codigo de salida del proceso; en MATLAB, solo el valor de vuelta
  if isdeployed, exit( code ); end
end
