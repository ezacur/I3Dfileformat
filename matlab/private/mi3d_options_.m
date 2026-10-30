function [ O , args ] = mi3d_options_( args , who )
%MI3D_OPTIONS_  the options shared by write_MI3D and append_MI3D
%
%   [ O , rest ] = mi3d_options_( args , who )
%   O.tags (cellstr o []), O.reserve, O.comment, O.lazykeep
  TAGS = [];
  try, [ args , ~ , TAGS ] = parseargs( args , 'Tags' , '$DEFS$' , [] ); end
  if ischar( TAGS ), TAGS = { TAGS }; end
  RESERVE = 8192;
  try, [ args , ~ , RESERVE ] = parseargs( args , 'Reserve' , '$DEFS$' , 8192 ); end
  if ~isnumeric( RESERVE ) || ~isscalar( RESERVE ) || RESERVE < 2 || RESERVE ~= round( RESERVE )
    error( [ who ':badInput' ] , '''Reserve'' is the bytes of the reserve line, an integer >= 2.' );
  end
  COMMENT = '';
  try, [ args , ~ , COMMENT ] = parseargs( args , 'Comment' , '$DEFS$' , '' ); end
  if ~ischar( COMMENT ) || any( COMMENT < 32 ), error( [ who ':badInput' ] , '''Comment'' is one line of text.' ); end
  LAZY = '';
  try, [ args , ~ , LAZY ] = parseargs( args , 'Lazy' , '$DEFS$' , '' ); end
  if ~isempty( LAZY ) && ~strcmpi( LAZY , 'keep' ), error( [ who ':badInput' ] , '''Lazy'' takes ''keep''.' ); end
  O = struct( 'tags' , { TAGS } , 'reserve' , double( RESERVE ) , 'comment' , COMMENT , 'lazykeep' , ~isempty( LAZY ) );
end
