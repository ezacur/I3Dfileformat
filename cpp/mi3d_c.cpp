// mi3d_c.cpp -- la API en C de mi3d.dll (ver mi3d_c.h). Aqui se atrapan TODAS
// las excepciones: ninguna cruza la frontera.
#include "mi3d_c.h"
#include "mi3d.hpp"
#include <string>
#include <memory>
#include <map>
#include <vector>

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

int mi3d_write( const char *path , int n , const char **files , const char **tags , int64_t reserve , const char *comment , int lazykeep ){
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
