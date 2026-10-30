function try_study( dicomroot , outdir )
%TRY_STUDY   a whole study: DICOMstackCollect -> one lazy .i3d per stack -> read back
%
%   try_study( 'D:\DICOMS\20171028_Cine3D_Breathing_from_PIECHNIK\dicoms' , outdir )
%
% Recoge TODOS los ficheros bajo dicomroot, los agrupa con DICOMstackCollect y
% escribe cada stack en outdir/<nn>_<SeriesDescription>.i3d en modo 'Lazy'.
% Lee cada uno con read_I3D (lector C++) y comprueba que da EXACTAMENTE I.data.
% Imprime una fila por stack. No es de regresion (depende de d:\DICOMS).
  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  if ~exist( outdir , 'dir' ), mkdir( outdir ); end

  F = dir( fullfile( dicomroot , '**' , '*' ) );  F( [ F.isdir ] ) = [];
  F = struct( 'name' , fullfile( { F.folder } , { F.name } ) );
  fprintf( '%d files under %s\n' , numel( F ) , dicomroot );
  t0 = tic;
  [ DS , REPORT ] = DICOMstackCollect( F , 'onlyK' );
  fprintf( 'DICOMstackCollect: %.1f s, %d stacks, %d report entries\n\n' , toc(t0) , numel(DS) , numel(REPORT) );

  fprintf( '%3s  %-34s %-22s %6s %6s %5s %9s %9s  %s\n' , '#' , 'series' , 'size' , 'ref' , 'mat' , 'miss' , 'i3d KiB' , 'raw MiB' , 'exact' );
  nbad = 0;
  for d = 1:numel( DS )
    I = DS(d).IMAGE;
    if ~isa( I , 'I3D' ), fprintf( '%3d  (no I3D)\n' , d ); continue; end
    D = I.DATA;
    name = sprintf( '%02d_%s' , d , regexprep( char( DS(d).SeriesDescription ) , '[^A-Za-z0-9_+-]' , '_' ) );
    f = fullfile( outdir , [ name '.i3d' ] );
    try
      write_I3D( I , f , 'Lazy' , 'Comment' , sprintf( 'try_study, series %d %s' , DS(d).SeriesNumber , char( DS(d).SeriesDescription ) ) );
      [ ~ , S ] = read_I3D( f );
      ok = isequal( S.data , D );
      h = fileread( f );  h = h( 1:strfind( h , [ newline '---' newline ] ) );
      c = regexp( h , '# (\d+) planes referenced, (\d+) materialised, (\d+) missing' , 'tokens' , 'once' );
      q = dir( f );
      fprintf( '%3d  %-34s %-22s %6s %6s %5s %9.1f %9.1f  %d\n' , d , name(4:min(end,37)) , mat2str( size(D) ) , c{1} , c{2} , c{3} , q.bytes/1024 , numel(D)*numel(typecast(D(1),'uint8'))/2^20 , ok );
      nbad = nbad + ~ok;
    catch LE
      fprintf( '%3d  %-34s %-22s  ERROR %s: %s\n' , d , name(4:min(end,37)) , mat2str( size(D) ) , LE.identifier , LE.message(1:min(end,100)) );
      nbad = nbad + 1;
    end
  end
  fprintf( '\n%d stacks, %d not exact or failed\n' , numel(DS) , nbad );
end
