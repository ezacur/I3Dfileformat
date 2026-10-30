function tf = i3d_err_( who , kind , h )
%I3D_ERR_  the last error of a DLL call, thrown as the MATLAB error who:<id>
%
%   i3d_err_( who , kind , h )
%   kind  'f' un i3d_file (h [] : el ultimo i3d_open fallido), 'w' un i3d_writer,
%         'm' un mi3d_file (h [] : el ultimo mi3d_open o escritura de mi3d.dll)
%
% Devuelve un logico para poder usarse en  rc == 0 || i3d_err_( ... ) , pero
% siempre lanza.
  switch kind
    case 'f', id = calllib( 'i3d' , 'i3d_last_error_id' , h );    msg = calllib( 'i3d' , 'i3d_last_error' , h );
    case 'w', id = calllib( 'i3d' , 'i3d_wlast_error_id' , h );   msg = calllib( 'i3d' , 'i3d_wlast_error' , h );
    case 'm', id = calllib( 'mi3d' , 'mi3d_last_error_id' , h );  msg = calllib( 'mi3d' , 'mi3d_last_error' , h );
  end
  if isempty( id ), id = 'internal'; end
  tf = false;
  error( [ who ':' id ] , '%s' , msg );
end
