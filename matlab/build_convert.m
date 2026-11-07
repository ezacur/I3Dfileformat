function exe = build_convert( src , out )
%BUILD_CONVERT   compila convert_to_MI3D_cli en un ejecutable (MATLAB Compiler)
%
%   build_convert                 desde esta carpeta, a ..\dist
%   build_convert( src , out )    los .m, las DLL y los prototipos de src; a out
%
% En out quedan solo convert_to_MI3D.exe y convert_to_MI3D.txt (el readme de mcc);
% mcc trabaja en una carpeta temporal, y si deja simbolos sin resolver o ficheros
% excluidos es un error.
%
% El ejecutable, convert_to_MI3D.exe, necesita el MATLAB Runtime de ESTA version de
% MATLAB (gratis, sin licencia); i3d.dll, mi3d.dll y sus prototipos van dentro.
% Hace falta en el path lo de mTools que usa (DICOMstackCollect, fixfilename...): el
% analisis de dependencias de mcc lo mete.
%
%   convert_to_MI3D.exe <folder> [outdir] [-t1|-t01] [-info] [-threads N]
%
% Antes, buildI3Dlibrary: las DLL y los prototipos de src tienen que ser los de ahora.
%
% See also convert_to_MI3D_cli, convert_to_MI3D, buildI3Dlibrary.

  here = fileparts( mfilename( 'fullpath' ) );
  if nargin < 1 || isempty( src ), src = here; end
  if nargin < 2 || isempty( out ), out = fullfile( fileparts( here ) , 'dist' ); end
  if ~license( 'test' , 'Compiler' ), error( 'build_convert:compiler' , 'No MATLAB Compiler license.' ); end
  if isempty( which( 'DICOMstackCollect' ) ), error( 'build_convert:path' , 'DICOMstackCollect is not on the path (mTools).' ); end

  need = { 'convert_to_MI3D_cli.m' , 'convert_to_MI3D.m' , 'write_MI3D.m' , 'write_I3D.m' , ...
           'i3d.dll' , 'mi3d.dll' , 'i3d_proto.m' , 'mi3d_proto.m' };
  miss = need( ~cellfun( @( f ) isfile( fullfile( src , f ) ) , need ) );
  if ~isempty( miss ), error( 'build_convert:files' , 'Missing in %s: %s' , src , strjoin( miss , ', ' ) ); end

  addpath( src );                                         % los de src, delante
  if ~strcmpi( fileparts( which( 'write_I3D' ) ) , src ), error( 'build_convert:path' , 'write_I3D is not the one of %s.' , src ); end
  tmp = tempname;  mkdir( tmp );  CL = onCleanup( @() rmdir( tmp , 's' ) );

  mcc( '-m' , fullfile( src , 'convert_to_MI3D_cli.m' ) , '-o' , 'convert_to_MI3D' , '-d' , tmp , ...
       '-a' , fullfile( src , 'i3d.dll' ) , '-a' , fullfile( src , 'mi3d.dll' ) , ...
       '-a' , fullfile( src , 'i3d_proto.m' ) , '-a' , fullfile( src , 'mi3d_proto.m' ) );
  if ~isfile( fullfile( tmp , 'convert_to_MI3D.exe' ) ), error( 'build_convert:mcc' , 'mcc did not make convert_to_MI3D.exe' ); end
  % los logs de mcc: sin nada mas que su linea de titulos
  for L = { 'unresolvedSymbols.txt' , 'mccExcludedFiles.log' }
    f = fullfile( tmp , L{1} );
    if isfile( f ) && numel( splitlines( strtrim( fileread( f ) ) ) ) > ( 1 + strcmp( L{1} , 'mccExcludedFiles.log' ) )
      error( 'build_convert:mcc' , 'mcc %s is not empty:\n%s' , L{1} , fileread( f ) );
    end
  end

  if ~isfolder( out ), mkdir( out ); end
  exe = fullfile( out , 'convert_to_MI3D.exe' );
  copyfile( fullfile( tmp , 'convert_to_MI3D.exe' ) , exe , 'f' );
  copyfile( fullfile( tmp , 'readme.txt' ) , fullfile( out , 'convert_to_MI3D.txt' ) , 'f' );
  fprintf( 'build_convert: %s\n' , exe );
end
