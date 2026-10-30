function probe_jpll()
%PROBE_JPLL   who decodes JPEG lossless 10/15-bit right: DCMTK or dicomread?
%
% Las imagenes CLUNIE RG1/RG2 estan en el corpus en JPEG lossless (JPLL) Y en RLE.
% En RLE coinciden el lector C++ y dicomread, asi que el RLE es el arbitro: quien
% de lo mismo que el RLE con el JPLL, decodifica bien. Y el caso 16/8 con signo:
% los valores de los pixeles que difieren, para ver quien enmascara.
  here = fileparts( mfilename('fullpath') );  addpath( fullfile( here , '..' , 'matlab' ) );
  [ dn , CLEAN ] = sanddir( '#_????' );  %#ok<ASGLU>
  G = 'D:/DICOMS/_test_readers/gdcmData/gdcmData/';
  for c = { 'D_CLUNIE_RG2' , 'D_CLUNIE_RG1' }
    rle  = read_( [ G c{1} '_RLE.dcm' ] , dn );
    jcpp = read_( [ G c{1} '_JPLL.dcm' ] , dn );
    jmat = dicomread( [ G c{1} '_JPLL.dcm' ] ).';
    fprintf( '%s: C++ JPLL == RLE %d   dicomread JPLL == RLE %d   (dicomread differs from RLE in %d px, max %d)\n' , ...
             c{1} , isequal( jcpp , rle ) , isequal( jmat , rle ) , nnz( jmat ~= rle ) , max( abs( double( jmat(:) ) - double( rle(:) ) ) ) );
  end
  f = [ G 'MR16BitsAllocated_8BitsStored.dcm' ];
  h = dicominfo( f );
  c = read_( f , dn );  m = dicomread( f ).';
  w = find( c ~= m );
  fprintf( 'MR16/8 signed: BitsStored %d HighBit %d PixelRepresentation %d\n' , h.BitsStored , h.HighBit , h.PixelRepresentation );
  fprintf( '  first differing pixels: C++ %s   dicomread %s\n' , mat2str( c( w(1:min(5,end)) ).' ) , mat2str( m( w(1:min(5,end)) ).' ) );
  fprintf( '  dicomread range [%d %d]; C++ range [%d %d]\n' , min( m(:) ) , max( m(:) ) , min( c(:) ) , max( c(:) ) );
end

function V = read_( fn , dn )
  h = dicominfo( fn );
  pr = isfield( h , 'PixelRepresentation' ) && h.PixelRepresentation == 1;
  cls = sprintf( '%sint%d' , repmat( 'u' , 1 , ~pr ) , h.BitsAllocated );
  H = { 'I3D 0.1' , sprintf( 'X[%d] = 0.0 : 1.0 : %s' , h.Columns , num2strI3D( double( h.Columns ) - 1 ) ) , ...
        sprintf( 'Y[%d] = 0.0 : 1.0 : %s' , h.Rows , num2strI3D( double( h.Rows ) - 1 ) ) , 'Z[1] = 0.0' , 'T[1] = 0.0' , ...
        sprintf( 'data = <dicom %s "%s">' , cls , fn ) , '---' };
  f = fullfile( dn , 'p.i3d' );  fid = fopen( f , 'w' );  fwrite( fid , [ strjoin( H , newline ) newline ] , 'char' );  fclose( fid );
  [ ~ , S ] = read_I3D( f );  V = S.data;
end
