function v = i3d_value_( s )
%I3D_VALUE_  el valor de una entrada info.* como MATLAB (read_I3D, read_MI3D): cadenas entre comillas -> char (una) o fila cellstr (una lista);
% numeros -> fila double; si no, el texto crudo
  s = strtrim( s );
  if ~isempty( s ) && s(1) == '"'
    % "a" "b" ... : cada una con sus escapes \" y \\ (SPEC 2)
    t = regexp( s , '"((?:[^"\\]|\\.)*)"' , 'tokens' );
    rest = regexprep( s , '"((?:[^"\\]|\\.)*)"' , '' );
    if ~isempty( t ) && isempty( strtrim( rest ) )
      t = cellfun( @(c) regexprep( c{1} , '\\(["\\])' , '$1' ) , t , 'un' , 0 );
      if isscalar( t ), v = t{1}; else, v = t; end
      return;
    end
  end
  t = strsplit( s );
  n = str2double( t );
  if ~isempty( t ) && all( ~isnan( n ) | strcmpi( t , 'nan' ) )
    v = n;
  else
    v = s;
  end
end
