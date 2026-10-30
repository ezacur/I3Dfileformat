// i3d_c.cpp -- la API en C sobre i3d::File. Aqui se atrapan TODAS las
// excepciones: ninguna cruza la frontera (ver i3d_c.h).
#include "i3d_c.h"
#include "i3d.hpp"
#include <string>
#include <memory>
#include <map>
#include <vector>
#include <cstring>

struct i3d_file {
  std::unique_ptr<i3d::File> F;
  std::string err , err_id;
  std::vector<std::string> aux;               // los nombres que devuelve i3d_aux_name
};

struct i3d_writer {
  i3d::Writer W;
  std::string err , err_id;
};

// el error de un i3d_open fallido: no hay handle donde guardarlo
static thread_local std::string g_err , g_err_id;

#define GUARD( f , body )                                                     \
  do {                                                                        \
    if( !(f) ) return -1;                                                     \
    try { body }                                                              \
    catch( const i3d::Error &e ){ (f)->err = e.what(); (f)->err_id = e.id; return 1; } \
    catch( const std::exception &e ){ (f)->err = e.what(); (f)->err_id = "internal"; return 2; } \
    return 0;                                                                 \
  } while( 0 )

extern "C" {

i3d_file *i3d_open( const char *path ){ return i3d_open_vars( path , 0 , nullptr , nullptr ); }

// i3d_open_vars e i3d_open_window: base -1, el fichero entero; si no, la ventana
// [base, base+size) de path
static i3d_file *open_( const char *path , int64_t base , int64_t size , int n , const char **names , const char **values );

i3d_file *i3d_open_vars( const char *path , int n , const char **names , const char **values ){
  return open_( path , -1 , -1 , n , names , values );
}

i3d_file *i3d_open_window( const char *path , int64_t offset , int64_t length , int n , const char **names , const char **values ){
  if( offset < 0 || length < 0 ){ g_err = "i3d_open_window: offset and length are >= 0";  g_err_id = "badInput";  return nullptr; }
  return open_( path , offset , length , n , names , values );
}

static i3d_file *open_( const char *path , int64_t base , int64_t size , int n , const char **names , const char **values ){
  i3d_file *f = nullptr;
  // un NULL aqui no es un error de C++ sino un access violation: el proceso del
  // wrapper moriria en vez de recibir un error
  if( !path || n < 0 || ( n > 0 && ( !names || !values ) ) ){
    g_err = "i3d_open: NULL path, or n < 0, or NULL names/values";  g_err_id = "badInput";
    return nullptr;
  }
  for( int k = 0 ; k < n ; k++ ) if( !names[k] || !values[k] ){
    g_err = "i3d_open_vars: NULL name or value of variable " + std::to_string( k );  g_err_id = "badInput";
    return nullptr;
  }
  try {
    std::map<std::string,std::string> V;
    for( int k = 0 ; k < n ; k++ ) V[ names[k] ] = values[k];
    f = new i3d_file;
    if( base >= 0 ){
      f->F.reset( new i3d::File( path , V , base , size ) );
    } else {
      f->F.reset( new i3d::File( path , V ) );
    }
    // los nombres de los aux, UNA vez: los punteros de i3d_aux_name tienen que
    // vivir mientras el handle (i3d_c.h), y recalcularlos los invalidaria
    f->aux = f->F->aux_names();
    return f;
  } catch( const i3d::Error &e ){ g_err = e.what(); g_err_id = e.id; }
    catch( const std::exception &e ){ g_err = e.what(); g_err_id = "internal"; }
  delete f;                                    // si new File lanzo, el handle no sirve
  return nullptr;
}

void i3d_close( i3d_file *f ){ delete f; }

const char *i3d_last_error( const i3d_file *f ){ return f ? f->err.c_str() : g_err.c_str(); }
const char *i3d_last_error_id( const i3d_file *f ){ return f ? f->err_id.c_str() : g_err_id.c_str(); }

int i3d_grid( i3d_file *f , char axis , const double **values , size_t *n ){
  GUARD( f , { auto &g = f->F->grid( axis ); *values = g.data(); *n = g.size(); } );
}

int64_t i3d_grid_length( i3d_file *f , char axis ){
  if( !f ) return -1;
  try { return (int64_t)f->F->grid( axis ).size(); } catch( ... ){ return -1; }
}

int i3d_grid_copy( i3d_file *f , char axis , double *out , int64_t n ){
  GUARD( f , {
    auto &g = f->F->grid( axis );
    if( !out || n != (int64_t)g.size() ) throw i3d::Error( "badBuffer" , "the grid has " + std::to_string( g.size() ) + " values, the buffer " + std::to_string( n ) );
    std::copy( g.begin() , g.end() , out );
  } );
}

int i3d_transform( i3d_file *f , double out16[16] ){
  GUARD( f , { auto &A = f->F->transform(); for( int k = 0 ; k < 16 ; k++ ) out16[k] = A[k]; } );
}

int i3d_data_shape( i3d_file *f , int *ndims , int64_t dims[16] ){
  GUARD( f , {
    auto &s = f->F->data_shape();
    if( s.size() > 16 ) throw i3d::Error( "badData" , "more than 16 dimensions" );
    *ndims = (int)s.size();  for( size_t d = 0 ; d < s.size() ; d++ ) dims[d] = s[d];
  } );
}

const char *i3d_data_type( i3d_file *f ){ return f ? i3d::type_name( f->F->data_type() ) : ""; }
size_t i3d_data_bytes( i3d_file *f ){ return f ? f->F->data_bytes() : 0; }

int i3d_read_data( i3d_file *f , void *out , size_t nbytes ){
  GUARD( f , { f->F->read_data( out , nbytes ); } );
}

size_t i3d_first_frame_bytes( i3d_file *f ){ return f ? f->F->first_frame_bytes() : 0; }

int i3d_read_first_frame( i3d_file *f , void *out , size_t nbytes ){
  GUARD( f , { f->F->read_first_frame( out , nbytes ); } );
}

int i3d_rescale( i3d_file *f , double *slope , double *intercept ){
  GUARD( f , { *slope = f->F->slope(); *intercept = f->F->intercept(); } );
}

int i3d_window( i3d_file *f , int *has_window , double *center , double *width ){
  GUARD( f , { *has_window = f->F->has_window() ? 1 : 0; *center = f->F->window_center(); *width = f->F->window_width(); } );
}

int i3d_missing_count( i3d_file *f ){ return f ? (int)f->F->missing().size() : -1; }

int i3d_missing_box( i3d_file *f , int m , int *ndims , int64_t lo[16] , int64_t hi[16] ){
  GUARD( f , {
    auto M = f->F->missing();
    if( m < 0 || m >= (int)M.size() ) throw i3d::Error( "badIndex" , "no such missing block" );
    auto &b = M[(size_t)m]->box;
    *ndims = (int)b.size();
    for( size_t d = 0 ; d < b.size() && d < 16 ; d++ ){ lo[d] = b[d].lo; hi[d] = b[d].hi; }
  } );
}

int i3d_aux_count( i3d_file *f ){ return f ? (int)f->aux.size() : -1; }

const char *i3d_aux_name( i3d_file *f , int a ){
  if( !f ) return "";
  return ( a >= 0 && a < (int)f->aux.size() ) ? f->aux[(size_t)a].c_str() : "";
}

int i3d_aux_shape( i3d_file *f , const char *name , int *ndims , int64_t dims[16] , const char **type ){
  GUARD( f , {
    auto d = f->F->aux_descriptor( name );
    if( d.shape.size() > 16 ) throw i3d::Error( "badDescriptor" , "more than 16 dimensions" );
    *ndims = (int)d.shape.size();  for( size_t q = 0 ; q < d.shape.size() ; q++ ) dims[q] = d.shape[q];
    if( type ) *type = i3d::type_name( d.type );
  } );
}

const char *i3d_aux_type( i3d_file *f , const char *name ){
  if( !f || !name ) return "";
  try { return i3d::type_name( f->F->aux_descriptor( name ).type ); } catch( ... ){ return ""; }
}

int i3d_aux_read( i3d_file *f , const char *name , void *out , size_t nbytes ){
  GUARD( f , {
    auto b = f->F->read_aux( name );
    if( b.size() != nbytes ) throw i3d::Error( "badBuffer" , "aux." + std::string( name ) + " has " + std::to_string( b.size() ) + " bytes, the buffer " + std::to_string( nbytes ) );
    std::memcpy( out , b.data() , nbytes );
  } );
}

int i3d_entry_count( i3d_file *f ){ return f ? (int)f->F->entries().size() : -1; }

int i3d_entry( i3d_file *f , int e , const char **key , const char **subs , const char **value ){
  GUARD( f , {
    auto &E = f->F->entries();
    if( e < 0 || e >= (int)E.size() ) throw i3d::Error( "badIndex" , "no such entry" );
    *key = E[(size_t)e].key.c_str();  *subs = E[(size_t)e].subs.c_str();  *value = E[(size_t)e].value.c_str();
  } );
}

static const i3d::Entry *entry_( i3d_file *f , int e ){
  if( !f ) return nullptr;
  auto &E = f->F->entries();
  return ( e >= 0 && e < (int)E.size() ) ? &E[(size_t)e] : nullptr;
}
const char *i3d_entry_key( i3d_file *f , int e ){ auto p = entry_( f , e ); return p ? p->key.c_str() : ""; }
const char *i3d_entry_subs( i3d_file *f , int e ){ auto p = entry_( f , e ); return p ? p->subs.c_str() : ""; }
const char *i3d_entry_value( i3d_file *f , int e ){ auto p = entry_( f , e ); return p ? p->value.c_str() : ""; }

const char *i3d_header( i3d_file *f ){ return f ? f->F->header().c_str() : ""; }
int64_t i3d_binary_start( i3d_file *f ){ return f ? f->F->binary_start() : -1; }
int i3d_is_hidden( i3d_file *f ){ return f ? ( f->F->hidden() ? 1 : 0 ) : -1; }

// ---- el escritor
i3d_writer *i3d_new( void ){ try { return new i3d_writer; } catch( ... ){ return nullptr; } }
void i3d_free( i3d_writer *w ){ delete w; }
const char *i3d_wlast_error( const i3d_writer *w ){ return w ? w->err.c_str() : "NULL writer"; }
const char *i3d_wlast_error_id( const i3d_writer *w ){ return w ? w->err_id.c_str() : "badInput"; }

} // extern "C"

// fuera del extern "C": con /EHsc una funcion extern "C" se supone que no lanza
static std::string s_( const char *p ){ return p ? std::string( p ) : std::string(); }
static std::vector<int64_t> dims_( int nd , const int64_t *d ){
  if( nd < 1 || nd > 16 || !d ) throw i3d::Error( "badInput" , "1 to 16 dimensions" );
  return std::vector<int64_t>( d , d + nd );
}
static std::vector<std::string> strs_( int64_t n , const char **v , const char *what ){
  if( n < 0 || ( n > 0 && !v ) ) throw i3d::Error( "badInput" , std::string( "NULL " ) + what );
  std::vector<std::string> s;
  for( int64_t i = 0 ; i < n ; i++ ){ if( !v[i] ) throw i3d::Error( "badInput" , std::string( "a NULL in " ) + what );  s.push_back( v[i] ); }
  return s;
}
static i3d::Type type_( const char *t ){
  i3d::Type T = i3d::type_from_name( s_( t ) );
  if( T == i3d::Type::none ) throw i3d::Error( "badData" , "data of class " + s_( t ) + " is not supported." );
  return T;
}

extern "C" {

int i3d_set_data( i3d_writer *w , const void *data , const char *type , int ndims , const int64_t *dims ){
  GUARD( w , { w->W.set_data( data , type_( type ) , dims_( ndims , dims ) ); } );
}
}
static int set_grid_( i3d_writer *w , char axis , const double *values , int64_t n ){
  GUARD( w , { if( n < 0 ) throw i3d::Error( "badInput" , "n < 0" );  w->W.set_grid( axis , values , (size_t)n ); } );
}
extern "C" {
int i3d_set_Xgrid( i3d_writer *w , const double *values , int64_t n ){ return set_grid_( w , 'X' , values , n ); }
int i3d_set_Ygrid( i3d_writer *w , const double *values , int64_t n ){ return set_grid_( w , 'Y' , values , n ); }
int i3d_set_Zgrid( i3d_writer *w , const double *values , int64_t n ){ return set_grid_( w , 'Z' , values , n ); }
int i3d_set_Tgrid( i3d_writer *w , const double *values , int64_t n ){ return set_grid_( w , 'T' , values , n ); }
int i3d_set_transform( i3d_writer *w , const double rows16[16] ){ GUARD( w , { w->W.set_transform( rows16 ); } ); }
int i3d_set_rescale( i3d_writer *w , double slope , double intercept , const char *comment ){
  GUARD( w , { w->W.set_rescale( slope , intercept , s_( comment ) ); } );
}
int i3d_set_window( i3d_writer *w , double center , double width , const char *comment ){
  GUARD( w , { w->W.set_window( center , width , s_( comment ) ); } );
}
int i3d_add_info_text( i3d_writer *w , const char *key , const char *value , int visible , const char *comment ){
  GUARD( w , { if( !value ) throw i3d::Error( "badInput" , "NULL value" );  w->W.add_info_text( s_( key ) , value , visible , s_( comment ) ); } );
}
int i3d_add_info_numbers( i3d_writer *w , const char *key , const double *values , int64_t n , int visible , const char *comment ){
  GUARD( w , { if( n < 0 ) throw i3d::Error( "badInput" , "n < 0" );  w->W.add_info_numbers( s_( key ) , values , (size_t)n , visible , s_( comment ) ); } );
}
int i3d_add_info_rows_text( i3d_writer *w , const char *key , int64_t n , const char **values , const char **comments , int visible ){
  GUARD( w , {
    auto v = strs_( n , values , "values" );
    if( comments ){ auto c = strs_( n , comments , "comments" );  w->W.add_info_rows_text( s_( key ) , v , &c , visible ); }
    else w->W.add_info_rows_text( s_( key ) , v , nullptr , visible );
  } );
}
int i3d_add_info_rows_numbers( i3d_writer *w , const char *key , int64_t n , const double *values , int integer , const char **comments , int visible ){
  GUARD( w , {
    if( n < 0 ) throw i3d::Error( "badInput" , "n < 0" );
    if( comments ){ auto c = strs_( n , comments , "comments" );  w->W.add_info_rows_numbers( s_( key ) , values , (size_t)n , integer != 0 , &c , visible ); }
    else w->W.add_info_rows_numbers( s_( key ) , values , (size_t)n , integer != 0 , nullptr , visible );
  } );
}
int i3d_add_comment( i3d_writer *w , const char *text ){ GUARD( w , { w->W.add_comment( s_( text ) ); } ); }
int i3d_add_aux( i3d_writer *w , const char *name , const void *data , const char *type , int ndims , const int64_t *dims ){
  GUARD( w , { w->W.add_aux( s_( name ) , data , i3d::type_from_name( s_( type ) ) , s_( type ) , dims_( ndims , dims ) ); } );
}
int i3d_set_plane_ref( i3d_writer *w , int64_t k , int64_t t , const char *path ){ GUARD( w , { w->W.set_plane_ref( k , t , s_( path ) ); } ); }
int i3d_set_option( i3d_writer *w , const char *name , const char *value ){ GUARD( w , { w->W.set_option( s_( name ) , s_( value ) ); } ); }
int i3d_write( i3d_writer *w , const char *path ){
  GUARD( w , { if( !path ) throw i3d::Error( "badInput" , "NULL path" );  w->W.write( path ); } );
}

const char *i3d_num2str( double x ){
  static thread_local std::string s;
  s = i3d::num2str( x );
  return s.c_str();
}

int i3d_rewrite( const char *src , const char *dst , int hidden ){
  if( !src || !dst ){ g_err = "i3d_rewrite: NULL path";  g_err_id = "badInput";  return -1; }
  try { i3d::rewrite( src , dst , hidden != 0 );  return 0; }
  catch( const i3d::Error &e ){ g_err = e.what(); g_err_id = e.id; return 1; }
  catch( const std::exception &e ){ g_err = e.what(); g_err_id = "internal"; return 2; }
}

} // extern "C"
