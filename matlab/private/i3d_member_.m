function win = i3d_member_( f , n , who )
%I3D_MEMBER_  [offset length] of member n of the .mi3d f, in the file (mi3d_range)
%
%   win = i3d_member_( f , n , who )
% ERROR IDENTIFIERS: who:<id> de mi3d.dll -- badMagic (f no es un .mi3d),
% badIndex (n fuera de 1..N), missingMember (un hueco), badCRC ...
  enableI3Dlibrary;
  m = calllib( 'mi3d' , 'mi3d_open' , f );
  if isNull( m ), i3d_err_( who , 'm' , [] ); end
  C = onCleanup( @() calllib( 'mi3d' , 'mi3d_close' , m ) );
  [ rc , ~ , a , L ] = calllib( 'mi3d' , 'mi3d_range' , m , n , 0 , 0 );
  if rc, i3d_err_( who , 'm' , m ); end
  win = double( [ a L ] );
end
