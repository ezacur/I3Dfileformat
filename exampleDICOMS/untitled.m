cd( 'C:\repos\I3Dfileformat\exampleDICOMS\' )
addpath( 'C:\Dropbox\mTools' );  mTools_SETUP;                    % I3D, parseargs...
addpath( 'C:\Dropbox\mTools\libraries\scratch\DICOM' );           % DICOMstackCollect
% addpath( 'C:\repos\I3Dfileformat\matlab' );                       % enableI3Dlibrary (y lib\)


tic; H = DICOMheader( 'd:\DICOMS\' ,'StudyInstanceUID', 20 ,'Progress',50); toc
H( [ H.bytes ] <= 0 ) = [];
H( fun([],{H.StudyInstanceUID}) ) = [];

H( fun( '\\fabricados\\' , { H.Filename } ) ) = [];

%1.2.392.200036.9116.4.2.9106.1467.20240204232401211.5.2

%%
CI = {};
DI = {};

T = unique( {H.StudyInstanceUID} );
for t = T(:).', t = t{1};
  printf( {1,+'reporte.txt'} , '\nAhora study: "%s"\n', t );
  DS = DICOMstack( H( strcmp( {H.StudyInstanceUID} , t ) ) );
  for d = 1:numel(DS)
    D = DS(d);
    D.commonFolder
    if prod( size( D ,3:4) ) <= 1, continue; end
    CI = unique( [ CI ; fieldnames( D.commonInfo ) ] );
    
    D = dicominfo(D);
    DI = unique( [ DI ; fieldnames( D.commonInfo ) ] );
  end
end
