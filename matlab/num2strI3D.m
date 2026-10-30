function s = num2strI3D( x )
%NUM2STRI3D   a double as the .i3d header writes it: shortest exact form, with ".0"
%
%   s = num2strI3D( 2 )            '2.0'
%   s = num2strI3D( 0 )            '0.0'
%   s = num2strI3D( -0 )           '-0.0'
%   s = num2strI3D( 0.1 )          '0.1'
%   s = num2strI3D( cos(pi/4) )    '0.7071067811865476'
%   s = num2strI3D( 1e20 )         '1e+20'
%
% La forma mas corta que, leida de vuelta, da EXACTAMENTE el mismo double (lo
% que dan repr de Python, Number.toString de JS o std::to_chars de C++17), y
% encima la regla cosmetica de SPEC.md seccion 2: un double con valor entero
% lleva ".0", el cero incluido ("0.0", y "-0.0" para -0, que es otro double).
% Un exponente, inf o nan se dejan como estan.
%
% COMO: lo calcula i3d.dll (i3d_num2str de la API en C, el MISMO numero que
% escribe la cabecera): se prueba %.15g, %.16g y %.17g y se queda la primera
% que, leida con strtod, devuelve los mismos 64 bits. Que eso coincida con la
% forma mas corta lo comprueba tests/check_num2str.m contra Python.
%
% NaN se escribe 'nan' y PIERDE SIGNO Y CARGA UTIL: el NaN de MATLAB es
% fff8000000000000 y el que lee strtod, 7ff8000000000000. En el binario no pasa
% (los bits se copian); en la cabecera si. [OPEN] en SPEC.md.
%
% MEDIDO (tests/check_num2str.m, R2022a, 240 003 valores contra Python): todos
% exactos y todos la forma mas corta.
%
% ENTRADA: x, un double escalar real.
%
% ERROR IDENTIFIERS
%   num2strI3D:badInput     x no es un double escalar real
%
% See also write_I3D.

  if ~isa( x , 'double' ) || ~isscalar( x ) || ~isreal( x )
    error('num2strI3D:badInput','x must be a real double scalar.');
  end

  enableI3Dlibrary;
  s = calllib( 'i3d' , 'i3d_num2str' , x );
end
