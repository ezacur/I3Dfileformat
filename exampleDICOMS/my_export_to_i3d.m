%%
cd( 'C:\repos\I3Dfileformat\exampleDICOMS' )
addpath( 'C:\Dropbox\mTools' );  mTools_SETUP;                    % I3D, parseargs...
addpath( 'C:\Dropbox\mTools\libraries\scratch\DICOM' );           % DICOMstackCollect
addpath( 'C:\repos\I3Dfileformat\matlab' );                       % write_I3D

%%
tic; DS = DICOMstackCollect( pwd , 'Threads' , maxNumCompThreads * 0 + 12 * 1 ); toc
% tic; DS = DS.dicominfo; toc

for TS = unique( DS.StudyInstanceUID_ ).'
  T = DS.byStudyInstanceUID( TS{1} );

  dname = fixfilename( sprintf( '%s.%s' , T(1).Person , T(1).StudyDescription ) );
  if ~isfolder( dname ), mkdir( dname ); end

  for s = 1:numel( T )
    S = T(s);

    fname = fullfile( dname , filename( fixfilename( sprintf('%03d.%s(%s).i3d', S.SeriesNumber , S.SeriesDescription , S.PlaneName ) ) ) );
    while isfile( fname ), fname = regexprep( fname , '\.i3d$','_.i3d'); end

    write_I3D( S , fname );
  end
end
