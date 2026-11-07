// mi3d_c.cpp -- la API en C de mi3d.dll (ver mi3d_c.h). Aqui se atrapan TODAS
// las excepciones: ninguna cruza la frontera.
#include "mi3d_c.h"
#include "mi3d.hpp"
#include <string>
#include <memory>
#include <map>
#include <vector>
#include <cstdlib>
#include <cstdint>

struct mi3d_file {
  std::unique_ptr<i3d::Container> C;
  std::map<int,std::string> tags;
  std::string err , err_id;
};

static thread_local std::string g_err , g_err_id;

#define GUARD( m , body )                                                     \
  do {                                                                        \
    if( !(m) ) return -1;                                                     \
    try { body }                                                              \
    catch( const i3d::Error &e ){ (m)->err = e.what(); (m)->err_id = e.id; return 1; } \
    catch( const std::exception &e ){ (m)->err = e.what(); (m)->err_id = "internal"; return 2; } \
    return 0;                                                                 \
  } while( 0 )

#define GUARD0( body )                                                        \
  do {                                                                        \
    try { body }                                                              \
    catch( const i3d::Error &e ){ g_err = e.what(); g_err_id = e.id; return 1; } \
    catch( const std::exception &e ){ g_err = e.what(); g_err_id = "internal"; return 2; } \
    return 0;                                                                 \
  } while( 0 )

static std::string s_( const char *p ){ return p ? std::string( p ) : std::string(); }
static std::vector<std::string> strs_( int n , const char **v , const char *what ){
  if( n < 0 || ( n > 0 && !v ) ) throw i3d::Error( "badInput" , std::string( "NULL " ) + what );
  std::vector<std::string> s;
  for( int i = 0 ; i < n ; i++ ){ if( !v[i] ) throw i3d::Error( "badInput" , std::string( "a NULL in " ) + what );  s.push_back( v[i] ); }
  return s;
}
static void path_( const char *p ){ if( !p || !*p ) throw i3d::Error( "badInput" , "NULL or empty path" ); }

extern "C" {

mi3d_file *mi3d_open( const char *path ){
  if( !path ){ g_err = "mi3d_open: NULL path";  g_err_id = "badInput";  return nullptr; }
  mi3d_file *m = nullptr;
  try {
    m = new mi3d_file;
    m->C.reset( new i3d::Container( path ) );
    m->tags = i3d::mi3d::tags( *m->C );
    return m;
  } catch( const i3d::Error &e ){ g_err = e.what(); g_err_id = e.id; }
    catch( const std::exception &e ){ g_err = e.what(); g_err_id = "internal"; }
  delete m;
  return nullptr;
}

void mi3d_close( mi3d_file *m ){ delete m; }

const char *mi3d_last_error( const mi3d_file *m ){ return m ? m->err.c_str() : g_err.c_str(); }
const char *mi3d_last_error_id( const mi3d_file *m ){ return m ? m->err_id.c_str() : g_err_id.c_str(); }

int mi3d_count( mi3d_file *m ){ return m ? m->C->count() : -1; }

int mi3d_present( mi3d_file *m , int n ){
  if( !m || n < 1 || n > m->C->count() ) return -1;
  return m->C->present( n ) ? 1 : 0;
}

int mi3d_range( mi3d_file *m , int n , int64_t *offset , int64_t *length ){
  GUARD( m , {
    if( !offset || !length ) throw i3d::Error( "badInput" , "NULL offset or length" );
    m->C->window( n , *offset , *length );
  } );
}

const char *mi3d_tag( mi3d_file *m , int n ){
  if( !m ) return "";
  auto t = m->tags.find( n );
  return t == m->tags.end() ? "" : t->second.c_str();
}

int mi3d_entry_count( mi3d_file *m ){ return m ? (int)m->C->entries().size() : -1; }

static const i3d::Entry *entry_( mi3d_file *m , int e ){
  if( !m ) return nullptr;
  auto &E = m->C->entries();
  return ( e >= 0 && e < (int)E.size() ) ? &E[(size_t)e] : nullptr;
}
const char *mi3d_entry_key( mi3d_file *m , int e ){ auto p = entry_( m , e ); return p ? p->key.c_str() : ""; }
const char *mi3d_entry_subs( mi3d_file *m , int e ){ auto p = entry_( m , e ); return p ? p->subs.c_str() : ""; }
const char *mi3d_entry_value( mi3d_file *m , int e ){ auto p = entry_( m , e ); return p ? p->value.c_str() : ""; }

const char *mi3d_header( mi3d_file *m ){ return m ? m->C->header().c_str() : ""; }
int64_t mi3d_binary_start( mi3d_file *m ){ return m ? m->C->binary_start() : -1; }

int mi3d_write_files( const char *path , int n , const char **files , const char **tags , int64_t reserve , const char *comment , int lazykeep ){
  GUARD0( {
    path_( path );
    auto F = strs_( n , files , "files" );
    if( tags ){ auto T = strs_( n , tags , "tags" );  i3d::mi3d::write( path , F , &T , reserve , s_( comment ) , lazykeep != 0 ); }
    else i3d::mi3d::write( path , F , nullptr , reserve , s_( comment ) , lazykeep != 0 );
  } );
}

int mi3d_append( const char *path , int n , const char **files , const char **tags , int64_t reserve , const char *comment , int lazykeep , int *first ){
  GUARD0( {
    path_( path );
    auto F = strs_( n , files , "files" );
    int k;
    if( tags ){ auto T = strs_( n , tags , "tags" );  k = i3d::mi3d::append( path , F , &T , reserve , s_( comment ) , lazykeep != 0 ); }
    else k = i3d::mi3d::append( path , F , nullptr , reserve , s_( comment ) , lazykeep != 0 );
    if( first ) *first = k;
  } );
}

int mi3d_remove( const char *path , int n , const int *members , const char *comment ){
  GUARD0( {
    path_( path );
    if( n < 1 || !members ) throw i3d::Error( "badInput" , "no members to remove" );
    i3d::mi3d::remove( path , std::vector<int>( members , members + n ) , s_( comment ) );
  } );
}

int mi3d_compact( const char *path , int renumber , int64_t reserve , const char *comment ){
  GUARD0( { path_( path );  i3d::mi3d::compact( path , renumber != 0 , reserve , s_( comment ) ); } );
}

} // extern "C"

// ====================================================================== el escritor
// el miembro en curso es un i3d::Writer; al empezar otro (o al escribir) se
// codifica en memoria y se queda solo con sus bytes
struct mi3d_writer {
  std::vector<i3d::mi3d::Stack> S;              // los miembros ya codificados (y los huecos)
  std::unique_ptr<i3d::Writer> W;               // el miembro en curso
  std::string tag;                              // su etiqueta
  int64_t reserve = 0;  std::string comment;  bool lazykeep = false;
  std::map<int,std::string> notes;  std::string nhead;   // las notas de cada miembro (mi3d_set_note) y su titulo
  std::string err , err_id;
};

// fuera del extern "C": con /EHsc una funcion extern "C" se supone que no lanza
static std::vector<int64_t> dims_( int nd , const int64_t *d ){
  if( nd < 1 || nd > 16 || !d ) throw i3d::Error( "badInput" , "1 to 16 dimensions" );
  return std::vector<int64_t>( d , d + nd );
}
static i3d::Type type_( const char *t ){
  i3d::Type T = i3d::type_from_name( s_( t ) );
  if( T == i3d::Type::none ) throw i3d::Error( "badData" , "data of class " + s_( t ) + " is not supported." );
  return T;
}
// el miembro en curso; sin mi3d_add_stack, un error
static i3d::Writer &cur_( mi3d_writer *m ){
  if( !m->W ) throw i3d::Error( "badInput" , "no stack: mi3d_add_stack first" );
  return *m->W;
}
// el miembro en curso, codificado: sus bytes, y fuera sus datos
static void flush_( mi3d_writer *m ){
  if( !m->W ) return;
  const std::string n = std::to_string( m->S.size() + 1 );
  std::shared_ptr<const std::vector<uint8_t>> b;
  try { b = std::make_shared<const std::vector<uint8_t>>( m->W->encode() ); }
  catch( const i3d::Error &e ){ throw i3d::Error( e.id , "stack " + n + ": " + e.what() ); }
  m->S.push_back( { b , m->tag } );
  m->W.reset();  m->tag.clear();
}
static int64_t integer_( const std::string &name , const std::string &v ){
  char *e = nullptr;
  const long long r = std::strtoll( v.c_str() , &e , 10 );
  if( v.empty() || *e ) throw i3d::Error( "badOption" , name + " must be an integer" );
  return (int64_t)r;
}

extern "C" {

mi3d_writer *mi3d_new( void ){ try { return new mi3d_writer; } catch( ... ){ return nullptr; } }
void mi3d_free( mi3d_writer *m ){ delete m; }
const char *mi3d_wlast_error( const mi3d_writer *m ){ return m ? m->err.c_str() : "NULL writer"; }
const char *mi3d_wlast_error_id( const mi3d_writer *m ){ return m ? m->err_id.c_str() : "badInput"; }

int mi3d_add_stack( mi3d_writer *m , const char *tag ){
  GUARD( m , { flush_( m );  m->W.reset( new i3d::Writer );  m->tag = s_( tag ); } );
}
int mi3d_add_hole( mi3d_writer *m ){
  GUARD( m , { flush_( m );  m->S.push_back( { nullptr , "" } ); } );
}
int mi3d_set_data( mi3d_writer *m , const void *data , const char *type , int ndims , const int64_t *dims ){
  GUARD( m , { cur_( m ).set_data( data , type_( type ) , dims_( ndims , dims ) ); } );
}
}
static int set_grid_( mi3d_writer *m , char axis , const double *values , int64_t n ){
  GUARD( m , { if( n < 0 ) throw i3d::Error( "badInput" , "n < 0" );  cur_( m ).set_grid( axis , values , (size_t)n ); } );
}
extern "C" {
int mi3d_set_Xgrid( mi3d_writer *m , const double *values , int64_t n ){ return set_grid_( m , 'X' , values , n ); }
int mi3d_set_Ygrid( mi3d_writer *m , const double *values , int64_t n ){ return set_grid_( m , 'Y' , values , n ); }
int mi3d_set_Zgrid( mi3d_writer *m , const double *values , int64_t n ){ return set_grid_( m , 'Z' , values , n ); }
int mi3d_set_Tgrid( mi3d_writer *m , const double *values , int64_t n ){ return set_grid_( m , 'T' , values , n ); }
int mi3d_set_transform( mi3d_writer *m , const double rows16[16] ){ GUARD( m , { cur_( m ).set_transform( rows16 ); } ); }
int mi3d_add_info_text( mi3d_writer *m , const char *key , const char *value , int visible , const char *comment ){
  GUARD( m , { if( !value ) throw i3d::Error( "badInput" , "NULL value" );  cur_( m ).add_info_text( s_( key ) , value , visible , s_( comment ) ); } );
}
int mi3d_add_info_numbers( mi3d_writer *m , const char *key , const double *values , int64_t n , int visible , const char *comment ){
  GUARD( m , { if( n < 0 ) throw i3d::Error( "badInput" , "n < 0" );  cur_( m ).add_info_numbers( s_( key ) , values , (size_t)n , visible , s_( comment ) ); } );
}
int mi3d_add_info_rows_text( mi3d_writer *m , const char *key , int64_t n , const char **values , const char **comments , int visible ){
  GUARD( m , {
    if( n < 0 || n > INT32_MAX ) throw i3d::Error( "badInput" , "n out of range" );
    auto v = strs_( (int)n , values , "values" );
    if( comments ){ auto c = strs_( (int)n , comments , "comments" );  cur_( m ).add_info_rows_text( s_( key ) , v , &c , visible ); }
    else cur_( m ).add_info_rows_text( s_( key ) , v , nullptr , visible );
  } );
}
int mi3d_add_info_rows_numbers( mi3d_writer *m , const char *key , int64_t n , const double *values , const char **comments , int visible ){
  GUARD( m , {
    if( n < 0 || n > INT32_MAX ) throw i3d::Error( "badInput" , "n out of range" );
    if( comments ){ auto c = strs_( (int)n , comments , "comments" );  cur_( m ).add_info_rows_numbers( s_( key ) , values , (size_t)n , &c , visible ); }
    else cur_( m ).add_info_rows_numbers( s_( key ) , values , (size_t)n , nullptr , visible );
  } );
}
int mi3d_add_comment( mi3d_writer *m , const char *text ){ GUARD( m , { cur_( m ).add_comment( s_( text ) ); } ); }
int mi3d_set_thumbnail( mi3d_writer *m , const void *data , const char *type , int ndims , const int64_t *dims ){
  GUARD( m , { cur_( m ).set_thumbnail( data , i3d::type_from_name( s_( type ) ) , s_( type ) , dims_( ndims , dims ) ); } );
}
int mi3d_set_plane_ref( mi3d_writer *m , int64_t k , int64_t t , const char *path ){ GUARD( m , { cur_( m ).set_plane_ref( k , t , s_( path ) ); } ); }
int mi3d_set_option( mi3d_writer *m , const char *name , const char *value ){
  GUARD( m , {
    const std::string N = s_( name );  const std::string V = s_( value );
    if(      N == "Comment" ) m->comment = V;
    else if( N == "Reserve" ){ m->reserve = integer_( N , V );  if( m->reserve != 0 && m->reserve < 2 ) throw i3d::Error( "badOption" , "Reserve: 0 (8192) or the bytes of the reserve line, >= 2" ); }
    else if( N == "LazyKeep" ){ if( V != "0" && V != "1" ) throw i3d::Error( "badOption" , "LazyKeep must be 0 or 1" );  m->lazykeep = V == "1"; }
    else cur_( m ).set_option( N , V );
  } );
}
int mi3d_set_note( mi3d_writer *m , int n , const char *text ){
  GUARD( m , {
    const int K = (int)m->S.size() + ( m->W ? 1 : 0 );
    if( n == 0 ){ m->nhead = s_( text );  return 0; }
    if( n < 0 || n > K ) throw i3d::Error( "badInput" , "mi3d_set_note: no member " + std::to_string( n ) + " (0 for the title, or 1.." + std::to_string( K ) + ")" );
    if( n <= (int)m->S.size() && !m->S[n-1].bytes ) throw i3d::Error( "badInput" , "mi3d_set_note: member " + std::to_string( n ) + " is a hole" );
    if( text && *text ) m->notes[n] = text;  else m->notes.erase( n );
  } );
}
int mi3d_set_variable( mi3d_writer *m , const char *name , const char *value ){ GUARD( m , { cur_( m ).set_variable( s_( name ) , s_( value ) ); } ); }
int mi3d_write( mi3d_writer *m , const char *path ){
  GUARD( m , {
    path_( path );
    flush_( m );
    for( auto &t : m->notes ) m->S[t.first-1].note = t.second;
    i3d::mi3d::write( path , m->S , m->reserve , m->comment , m->lazykeep , m->nhead );
  } );
}

} // extern "C"
