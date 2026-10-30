function [ F , T ] = mi3d_files_( FILES , O , who )
%MI3D_FILES_  the files and tags for mi3d_write / mi3d_append: F cellstr ('' a
% hole); T las etiquetas de 'Tags', o NULL (la DLL pone el nombre de cada fichero)
  if ~isempty( O.tags ) && numel( O.tags ) ~= numel( FILES )
    error( [ who ':badInput' ] , '''Tags'' needs one tag per file (%d, not %d).' , numel( FILES ) , numel( O.tags ) );
  end
  F = cell( 1 , numel( FILES ) );
  for i = 1:numel( FILES )
    f = FILES{i};
    if isempty( f ), F{i} = ''; continue; end
    if ~ischar( f ), error( [ who ':badInput' ] , 'the files are char paths (or '''' for a hole).' ); end
    F{i} = f;
  end
  if isempty( O.tags ), T = libpointer( 'stringPtrPtr' ); else, T = O.tags(:).'; end
end
