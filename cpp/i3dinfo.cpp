// i3dinfo.cpp -- lo que el lector entiende de un .i3d, por la API en C.
//
//   i3dinfo serie.i3d            resumen
//   i3dinfo serie.i3d --sum      ademas lee data y da la suma y el min/max
//
// Sirve para dos cosas: comprobar a mano un fichero, y ser el primer cliente
// de la DLL (si algo no se puede hacer desde aqui, la API en C esta corta).
#include "i3d_c.h"
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>
#include <cmath>

template<typename T> static void stats( const void *p , size_t n , double &sum , double &mn , double &mx ){
  const T *v = (const T*)p;  sum = 0;  mn = INFINITY;  mx = -INFINITY;
  for( size_t i = 0 ; i < n ; i++ ){ double x = (double)v[i]; sum += x; if( x < mn ) mn = x; if( x > mx ) mx = x; }
}

int main( int argc , char **argv ){
  if( argc < 2 ){ std::fprintf( stderr , "usage: i3dinfo FILE.i3d [--sum | --header]\n" ); return 2; }
  i3d_file *f = i3d_open( argv[1] );
  if( !f ){ std::fprintf( stderr , "i3dinfo: [%s] %s\n" , i3d_last_error_id( nullptr ) , i3d_last_error( nullptr ) ); return 1; }
  if( argc > 2 && !std::strcmp( argv[2] , "--header" ) ){
    // la cabecera en claro, tambien la de un I3Db: el "mostrar" para un humano
    std::fputs( i3d_header( f ) , stdout );
    i3d_close( f );  return 0;
  }
  if( i3d_is_hidden( f ) ) std::printf( "(hidden header: I3Db)\n" );

  for( char a : { 'X' , 'Y' , 'Z' , 'T' } ){
    const double *v;  size_t n;
    i3d_grid( f , a , &v , &n );
    std::printf( "%c  %zu values  %.17g .. %.17g\n" , a , n , v[0] , v[n-1] );
  }
  double A[16];  i3d_transform( f , A );
  for( int r = 0 ; r < 4 ; r++ ) std::printf( "   %22.17g %22.17g %22.17g %22.17g\n" , A[4*r] , A[4*r+1] , A[4*r+2] , A[4*r+3] );

  int nd;  int64_t dims[16];  i3d_data_shape( f , &nd , dims );
  std::printf( "data  %s  [" , i3d_data_type( f ) );
  for( int d = 0 ; d < nd ; d++ ) std::printf( d ? " %lld" : "%lld" , (long long)dims[d] );
  std::printf( "]  %zu bytes\n" , i3d_data_bytes( f ) );
  std::printf( "missing blocks: %d    entries: %d\n" , i3d_missing_count( f ) , i3d_entry_count( f ) );

  if( argc > 2 && !std::strcmp( argv[2] , "--sum" ) ){
    std::vector<unsigned char> buf( i3d_data_bytes( f ) );
    if( i3d_read_data( f , buf.data() , buf.size() ) ){
      std::fprintf( stderr , "i3dinfo: [%s] %s\n" , i3d_last_error_id( f ) , i3d_last_error( f ) );
      i3d_close( f );  return 1;
    }
    std::string t = i3d_data_type( f );
    size_t n = 1;  for( int d = 0 ; d < nd ; d++ ) n *= (size_t)dims[d];
    double sum , mn , mx;
    if( t == "int8" )   stats<int8_t>( buf.data() , n , sum , mn , mx );
    else if( t == "uint8" )  stats<uint8_t>( buf.data() , n , sum , mn , mx );
    else if( t == "int16" )  stats<int16_t>( buf.data() , n , sum , mn , mx );
    else if( t == "uint16" ) stats<uint16_t>( buf.data() , n , sum , mn , mx );
    else if( t == "int32" )  stats<int32_t>( buf.data() , n , sum , mn , mx );
    else if( t == "uint32" ) stats<uint32_t>( buf.data() , n , sum , mn , mx );
    else if( t == "int64" )  stats<int64_t>( buf.data() , n , sum , mn , mx );
    else if( t == "uint64" ) stats<uint64_t>( buf.data() , n , sum , mn , mx );
    else if( t == "single" ) stats<float>( buf.data() , n , sum , mn , mx );
    else                     stats<double>( buf.data() , n , sum , mn , mx );
    std::printf( "sum %.17g   min %.17g   max %.17g\n" , sum , mn , mx );
  }
  i3d_close( f );
  return 0;
}
