function n = stackI3Dfilenames( DS )
%STACKI3DFILENAMES   {%03d SeriesNumber}.{%s SeriesDescription}.i3d, limpio con fixfilename
% (sin los caracteres que Windows no admite: "HR>60" da "HR60"). Si varios
% stacks dan el mismo (una serie que DICOMstack parte por planos: AX/COR/SAG),
% los de ese nombre llevan su plano detras:  003.3-Plane SSFSE RESPIRADO(COR).i3d
%
% Parte del ejemplo export_to_i3d.m.
  n = cell( 1 , numel( DS ) );  p = cell( 1 , numel( DS ) );
  for d = 1:numel( DS )
    % las barras, fuera ANTES: fixfilename las tomaria por carpetas
    sd = strrep( strrep( char( DS(d).SeriesDescription ) , '/' , '_' ) , '\' , '_' );
    [ ~ , b , e ] = fileparts( fixfilename( sprintf( '%03d.%s' , DS(d).SeriesNumber , sd ) ) );
    n{d} = [ b , e ];
    pn = DS(d).PlaneName;  if iscell( pn ), pn = pn{1}; end
    p{d} = sprintf( '%s(%s)' , n{d} , char( pn ) );
  end
  [ ~ , ~ , ix ] = unique( lower( n ) );
  rep = accumarray( ix(:) , 1 ) > 1;
  n( rep( ix ) ) = p( rep( ix ) );
  % y si aun se repite, _2, _3...
  for d = 2:numel( n )
    b = n{d};  j = 1;
    while any( strcmpi( n{d} , n(1:d-1) ) ), j = j + 1;  n{d} = sprintf( '%s_%d' , b , j ); end
  end
  n = strcat( n , '.i3d' );
end
