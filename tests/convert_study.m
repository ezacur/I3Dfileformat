function convert_study( dicomroot , outdir )
%CONVERT_STUDY   every stack of a study to .i3d, rotating through the writer options
%
%   convert_study( 'D:\DICOMS\20171028_Cine3D_Breathing_from_PIECHNIK\dicoms' , outdir )
%   convert_study( F , outdir )   F: the files with their headers already read
%                                 (DICOMheader's struct), e.g. from another MATLAB
%
% DICOMstackCollect(...,'info') -- con dicominfo completo, para que info.* y
% window salgan --, y cada stack con UNA de las combinaciones de OPTS, por
% turno. Cada fichero se lee de vuelta con read_I3D y se comprueba: data bit a
% bit y cada thumbnail identico. Imprime una fila por fichero.
  here = fileparts( mfilename('fullpath') );
  addpath( fullfile( here , '..' , 'matlab' ) );
  if ~exist( outdir , 'dir' ), mkdir( outdir ); end

  % la forma canonica fija el encoding por tipo (estos son uint16: jpegls) y
  % lleva el crc siempre; se rotan las opciones que quedan
  OPTS = { {}                                                            'canon'
           { 'Lazy' }                                                    'lazy'
           { 'Lazy' , 'Hidden' }                                         'lazy-hidden'
           { 'Hidden' }                                                  'hidden'
           { 'Lazy' , 'Verify' , false }                                 'lazy-noverify'
           { 'Lazy' , 'Hidden' , 'Info' , { 'SeriesDescription' 'Modality' 'StudyDate' } }  'lazy-hidden-info3'
           { 'Comment' , 'convert_study: a comment of its own' }         'comment'
           { 'Info' , {} }                                               'noinfo' };

  if isstruct( dicomroot )
    % the headers already read (DICOMheader, in ANOTHER process): DICOMstackCollect
    % only calls DICOMheader for what is missing, so no header MEX loads here
    F = dicomroot;
  else
    F = dir( fullfile( dicomroot , '**' , '*' ) );  F( [ F.isdir ] ) = [];
    F = struct( 'name' , fullfile( { F.folder } , { F.name } ) );
  end
  t0 = tic;
  DS = DICOMstackCollect( F , 'onlyK' , 'info' );
  fprintf( '%d files -> %d stacks in %.1f s\n\n' , numel( F ) , numel( DS ) , toc( t0 ) );
  fprintf( '%3s  %-30s %-20s %-30s %9s %8s %7s  %s\n' , '#' , 'series' , 'size' , 'options' , 'KiB' , 'raw MiB' , 'write' , 'back' );
  nbad = 0;  tot = 0;  totraw = 0;
  for d = 1:numel( DS )
    I = DS(d).IMAGE;
    if ~isa( I , 'I3D' ), continue; end
    D = I.DATA;
    o = mod( d - 1 , size( OPTS , 1 ) ) + 1;
    ser = regexprep( char( DS(d).SeriesDescription ) , '[^A-Za-z0-9_+-]' , '_' );
    f = fullfile( outdir , sprintf( '%02d_%s__%s.i3d' , d , ser , OPTS{o,2} ) );
    try
      t1 = tic;  write_I3D( I , f , OPTS{o,1}{:} );  tw = toc( t1 );
      J = read_I3D( f );
      ok = isequal( J.DATA , D );
      for t = fieldnames( I.INFO ).', t = t{1};
        if strncmp( t , 'thumbnail' , 9 ), ok = ok && isfield( J.INFO , t ) && isequal( J.INFO.(t) , I.INFO.(t) ); end
      end
      q = dir( f );  tot = tot + q.bytes;  totraw = totraw + numel( D ) * 2;
      fprintf( '%3d  %-30s %-20s %-30s %9.1f %8.1f %6.1fs  %d\n' , d , ser(1:min(end,30)) , mat2str( size(D) ) , OPTS{o,2} , q.bytes/1024 , numel(D)*2/2^20 , tw , ok );
      nbad = nbad + ~ok;
    catch LE
      fprintf( '%3d  %-30s %-20s %-30s  ERROR %s: %s\n' , d , ser(1:min(end,30)) , mat2str( size(D) ) , OPTS{o,2} , LE.identifier , LE.message(1:min(end,90)) );
      nbad = nbad + 1;
    end
  end
  fprintf( '\n%d files, %.1f MiB on disk for %.1f MiB of pixels; %d not exact or failed\n' , numel( DS ) , tot/2^20 , totraw/2^20 , nbad );
end
