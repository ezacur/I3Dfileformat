// i3d_write.cpp -- el escritor de la forma canonica (SPEC 9): ver i3d.hpp.
//
// Es la traduccion de lo que hacia write_I3D.m, y escribe lo mismo: la misma
// cabecera, el mismo reparto en bloques, los mismos crc. Los bytes comprimidos
// de un <png> no (antes los hacia imwrite, ahora lodepng), ni el comentario de
// la rotacion en el ultimo digito (antes svd de LAPACK). Lo que era de MATLAB --
// que sacar de un DICOMstack, la lista de visibles por defecto -- sigue en
// write_I3D.m, que llama a esto por la API en C.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "i3d.hpp"

#include <cstring>
#include <cstdio>
#include <cmath>
#include <ctime>
#include <fstream>
#include <algorithm>
#include <filesystem>
#include <set>

#include <zlib.h>
#include <charls/charls.h>
#include "lodepng.h"

#ifdef _WIN32
#include <process.h>
#define I3D_GETPID _getpid
#else
#include <unistd.h>
#define I3D_GETPID getpid
#endif

namespace i3d {

static std::filesystem::path u8p( const std::string &s ){ return detail::fs_path( s ); }

// ====================================================================== numeros
// La forma mas corta que, leida de vuelta, da EXACTAMENTE el mismo double: se
// prueba %.15g, %.16g y %.17g (desde %.1g un subnormal) y se queda la primera que
// vuelve. Y la regla de SPEC 2: un valor entero lleva ".0". (Era i3d_num2str.m,
// MEDIDO contra Python en tests/check_num2str)
std::string num2str( double x ){
  if( std::isnan( x ) ) return "nan";
  if( std::isinf( x ) ) return x > 0 ? "inf" : "-inf";
  if( x == 0 ) return std::signbit( x ) ? "-0.0" : "0.0";
  char b[64];
  const int p0 = std::fabs( x ) < 2.2250738585072014e-308 ? 1 : 15;
  for( int p = p0 ; p <= 17 ; p++ ){
    std::snprintf( b , sizeof b , "%.*g" , p , x );
    if( std::strtod( b , nullptr ) == x ) break;
  }
  std::string s( b );
  if( s.find( '.' ) == std::string::npos && s.find( 'e' ) == std::string::npos ) s += ".0";
  return s;
}

static std::string fmtg( double x , int p ){ char b[64];  std::snprintf( b , sizeof b , "%.*g" , p , x );  return b; }
static std::string i2s( int64_t v ){ return std::to_string( v ); }
static std::string spaces( int64_t n ){ return n > 0 ? std::string( (size_t)n , ' ' ) : std::string(); }
static std::string hex8( uint32_t c ){ char b[16];  std::snprintf( b , sizeof b , "%08x" , c );  return b; }
static std::string join( const std::vector<std::string> &v , const std::string &sep ){
  std::string s;
  for( size_t i = 0 ; i < v.size() ; i++ ){ if( i ) s += sep;  s += v[i]; }
  return s;
}
static std::string dims_text( const std::vector<int64_t> &d , const std::string &sep ){
  std::vector<std::string> s;  for( int64_t n : d ) s.push_back( i2s( n ) );
  return join( s , sep );
}

// ====================================================================== bytes
static uint32_t crc32_( const uint8_t *p , size_t n ){
  uLong c = crc32( 0L , Z_NULL , 0 );
  for( size_t q = 0 ; q < n ; q += 0x40000000 ) c = crc32( c , p + q , (uInt)std::min<size_t>( 0x40000000 , n - q ) );
  return (uint32_t)c;
}

// un flujo zlib (RFC 1950), nivel 9: lo de java.util.zip.Deflater(9)
static std::vector<uint8_t> deflate_( const uint8_t *p , size_t n ){
  z_stream zs{};
  if( deflateInit( &zs , 9 ) != Z_OK ) throw Error( "internal" , "deflateInit failed" );
  std::vector<uint8_t> out;
  std::vector<uint8_t> chunk( 1 << 20 );
  size_t q = 0;
  int z;
  do {
    const size_t k = std::min<size_t>( n - q , 0x40000000 );
    zs.next_in = (Bytef*)( p + q );  zs.avail_in = (uInt)k;  q += k;
    const int flush = q == n ? Z_FINISH : Z_NO_FLUSH;
    do {
      zs.next_out = chunk.data();  zs.avail_out = (uInt)chunk.size();
      z = deflate( &zs , flush );
      if( z == Z_STREAM_ERROR ){ deflateEnd( &zs );  throw Error( "internal" , "deflate failed" ); }
      out.insert( out.end() , chunk.data() , chunk.data() + ( chunk.size() - zs.avail_out ) );
    } while( zs.avail_out == 0 );
  } while( q < n );
  deflateEnd( &zs );
  if( z != Z_STREAM_END ) throw Error( "internal" , "deflate did not finish" );
  return out;
}

// SPEC 1.1, 1.2: el flujo zlib AL REVES, y  NOT r XOR k , k(i) = ((i*mult + seed) mod 2^32 >> 8) & 0xFF
static std::vector<uint8_t> hide_( const std::string &text , uint32_t seed , uint32_t mult ){
  std::vector<uint8_t> h = deflate_( (const uint8_t*)text.data() , text.size() );
  std::reverse( h.begin() , h.end() );
  for( size_t i = 0 ; i < h.size() ; i++ ){
    const uint32_t x = (uint32_t)i * mult + seed;
    h[i] = (uint8_t)( (uint8_t)~h[i] ^ (uint8_t)( ( x >> 8 ) & 0xFFu ) );
  }
  return h;
}
static const uint32_t I3DB_SEED = 0x49334462u , I3DB_MULT = 0x5C2D8F1Bu;     // "I3Db"
static const uint32_t HIDD_SEED = 0x68696464u , HIDD_MULT = 0x7A3F5C29u;     // "hidd"

// la cabecera I3Db: "I3Db" | L (uint64 LE) | lo oculto
static std::vector<uint8_t> i3db_( const std::string &text ){
  std::vector<uint8_t> h = hide_( text , I3DB_SEED , I3DB_MULT );
  std::vector<uint8_t> B = { 'I' , '3' , 'D' , 'b' };
  uint64_t L = h.size();
  for( int b = 0 ; b < 8 ; b++ ) B.push_back( (uint8_t)( L >> ( 8 * b ) ) );
  B.insert( B.end() , h.begin() , h.end() );
  return B;
}

// JPEG-LS sin perdida de UNA imagen ni x rows de un componente (SPEC 4): la x es
// la i. Un tipo con signo, desplazado 2^(bits-1) (un XOR del bit alto)
static std::vector<uint8_t> jpegls_( std::vector<uint8_t> src , Type t , int64_t ni , int64_t rows ){
  const int bits = (int)type_size( t ) * 8;
  if( t == Type::int8 ) for( auto &x : src ) x ^= 0x80;
  if( t == Type::int16 ) for( size_t p = 1 ; p < src.size() ; p += 2 ) src[p] ^= 0x80;
  try {
    charls::frame_info fi{ (uint32_t)ni , (uint32_t)rows , bits , 1 };
    charls::jpegls_encoder enc;
    enc.frame_info( fi );                                  // NEAR = 0: sin perdida
    std::vector<uint8_t> B( enc.estimated_destination_size() );
    enc.destination( B );
    const size_t n = enc.encode( src );
    B.resize( n );
    return B;
  } catch( const std::exception &e ){
    throw Error( "internal" , std::string( "CharLS: " ) + e.what() );
  }
}

// un thumbnail uint8 {r c nch f} (nch 1: gris, 3: RGB) como UNA imagen PNG de 8
// bits de r x (c*f): los frames uno al lado de otro (SPEC 7). 8 bits SIEMPRE, gris o
// RGB segun nch: sin la conversion automatica de lodepng, que con pocos grises
// escribiria 1, 2 o 4 bits o una paleta, y el lector solo acepta gris o RGB de 8
static std::vector<uint8_t> png_( const std::vector<uint8_t> &v , int64_t r , int64_t c , int64_t nch , int64_t nf ){
  const int64_t w = c * nf;
  std::vector<uint8_t> img( (size_t)( r * w * nch ) );
  for( int64_t f = 0 ; f < nf ; f++ ) for( int64_t ch = 0 ; ch < nch ; ch++ ) for( int64_t x = 0 ; x < c ; x++ ) for( int64_t y = 0 ; y < r ; y++ )
    img[(size_t)( ( y * w + f * c + x ) * nch + ch )] = v[(size_t)( y + r * ( x + c * ( ch + nch * f ) ) )];
  const LodePNGColorType ct = nch == 3 ? LCT_RGB : LCT_GREY;
  lodepng::State st;
  st.info_raw.colortype = ct;          st.info_raw.bitdepth = 8;
  st.info_png.color.colortype = ct;    st.info_png.color.bitdepth = 8;
  st.encoder.auto_convert = 0;
  std::vector<unsigned char> out;
  unsigned e = lodepng::encode( out , img , (unsigned)w , (unsigned)r , st );
  if( e ) throw Error( "internal" , std::string( "PNG: " ) + lodepng_error_text( e ) );
  return std::vector<uint8_t>( out.begin() , out.end() );
}

// todo o nada: a un temporal AL LADO del destino y un renombrado al final. Un
// fallo a mitad deja el destino como estaba. chunks: bytes, o un rango de otro
// fichero (que puede ser el propio destino: se lee del original)
namespace detail {
void write_atomic( const std::string &path , const std::vector<Chunk> &chunks ){
  const std::string tmp = path + ".part" + std::to_string( I3D_GETPID() );
  {
    std::ofstream o( u8p( tmp ) , std::ios::binary | std::ios::trunc );
    if( !o ) throw Error( "cannotOpen" , "cannot create '" + tmp + "'" );
    try {
      for( const Chunk &c : chunks ){
        if( c.b ){
          o.write( (const char*)c.b->data() , (std::streamsize)c.b->size() );
        } else {
          std::ifstream s( u8p( c.file ) , std::ios::binary );
          if( !s ) throw Error( "cannotOpen" , "cannot read '" + c.file + "'" );
          s.seekg( c.off );
          std::vector<char> buf( 1 << 26 );
          int64_t left = c.len;
          while( left > 0 ){
            const int64_t k = std::min<int64_t>( left , (int64_t)buf.size() );
            s.read( buf.data() , (std::streamsize)k );
            if( s.gcount() != k ) throw Error( "cannotOpen" , "'" + c.file + "' ends before byte " + i2s( c.off + c.len ) );
            o.write( buf.data() , (std::streamsize)k );
            left -= k;
          }
        }
        if( !o ) throw Error( "cannotOpen" , "cannot write '" + tmp + "' (disk full?)" );
      }
      o.close();
      if( !o ) throw Error( "cannotOpen" , "cannot close '" + tmp + "'" );
    } catch( ... ){
      o.close();  std::error_code ec;  std::filesystem::remove( u8p( tmp ) , ec );
      throw;
    }
  }
  std::error_code ec;
  std::filesystem::rename( u8p( tmp ) , u8p( path ) , ec );
  if( ec ){
    std::error_code e2;  std::filesystem::remove( u8p( tmp ) , e2 );
    throw Error( "cannotOpen" , "cannot replace '" + path + "': " + ec.message() );
  }
}

std::vector<uint8_t> hide_block( const std::string &text ){ return hide_( text , HIDD_SEED , HIDD_MULT ); }

std::string now_text(){
  char b[64];  std::time_t now = std::time( nullptr );  std::tm tm{};
#ifdef _WIN32
  localtime_s( &tm , &now );
#else
  localtime_r( &now , &tm );
#endif
  std::strftime( b , sizeof b , "%Y-%m-%d %H:%M:%S" , &tm );
  return b;
}
} // namespace detail
using detail::Chunk;

// ====================================================================== entradas
static bool valid_key( const std::string &k ){
  if( k.empty() || k.front() == '.' || k.back() == '.' ) return false;
  for( char c : k ) if( !( isalnum( (unsigned char)c ) || c == '_' || c == '.' ) ) return false;
  return k.find( ".." ) == std::string::npos;
}
// una linea de la cabecera: UTF-8, sin caracteres de control (SPEC 1)
static void check_text( const std::string &s , const std::string &what ){
  for( unsigned char c : s ) if( c < 32 || c == 127 ) throw Error( "badInput" , what + " has control characters" );
  for( size_t i = 0 ; i < s.size() ; ){
    const unsigned char c = (unsigned char)s[i];
    int n = c < 0x80 ? 1 : ( c >= 0xC2 && c <= 0xDF ) ? 2 : ( c >= 0xE0 && c <= 0xEF ) ? 3 : ( c >= 0xF0 && c <= 0xF4 ) ? 4 : 0;
    bool ok = n > 0 && i + n <= s.size();
    for( int k = 1 ; ok && k < n ; k++ ){
      const unsigned char b = (unsigned char)s[i+k];
      unsigned char lo = 0x80 , hi = 0xBF;
      if( k == 1 ){
        if( c == 0xE0 ) lo = 0xA0;  else if( c == 0xED ) hi = 0x9F;
        else if( c == 0xF0 ) lo = 0x90;  else if( c == 0xF4 ) hi = 0x8F;
      }
      ok = b >= lo && b <= hi;
    }
    if( !ok ) throw Error( "badInput" , what + " is not valid UTF-8" );
    i += n;
  }
}
static std::string info_key_( std::string k ){
  if( k.compare( 0 , 5 , "info." ) == 0 ) k = k.substr( 5 );
  if( !valid_key( k ) ) throw Error( "badInput" , "'" + k + "' is not a key: letters, digits, _ and . (info.a.b)" );
  return k;
}
static bool vis_( int v ){
  if( v != 0 && v != 1 ) throw Error( "badInput" , "visible is 1 (true: in the header, readable) or 0 (false: in the hidden part)" );
  return v == 1;
}
static std::string quote_( const std::string &s ){
  std::string q = "\"";
  for( char c : s ){ if( c == '\\' || c == '"' ) q += '\\';  q += c; }
  return q + "\"";
}
static std::string tail_( const std::string &comment ){ return comment.empty() ? "" : "  # " + comment; }

void Writer::set_grid( char axis , const double *v , size_t n ){
  const char *A = "XYZT";
  const char *p = std::strchr( A , axis );
  if( !p || !axis ) throw Error( "badInput" , "the axis is 'X', 'Y', 'Z' or 'T'" );
  if( !v || n == 0 ) throw Error( "badGrid" , std::string( 1 , axis ) + " is empty" );
  G_[p - A].assign( v , v + n );  hasG_[p - A] = true;
  took_( GRID , (size_t)( p - A ) );
}

void Writer::set_transform( const double *A ){
  if( !A ) throw Error( "badInput" , "NULL transform" );
  std::copy( A , A + 16 , A_ );
  took_( TRANSFORM );
}

void Writer::set_data( const void *p , Type t , const std::vector<int64_t> &dims ){
  if( t == Type::none ) throw Error( "badData" , "data of a type that is not int8 .. uint64, single or double" );
  if( dims.empty() || dims.size() > 16 ) throw Error( "badData" , "data needs 1 to 16 dimensions" );
  uint64_t n = 1;
  for( int64_t d : dims ){ if( d < 1 ) throw Error( "badData" , "data is empty" );  n *= (uint64_t)d; }
  if( !p ) throw Error( "badInput" , "NULL data" );
  // las dimensiones de componente que sobran: un 1 al final no es una dimension
  std::vector<int64_t> d = dims;
  while( d.size() > 4 && d.back() == 1 ) d.pop_back();
  const uint8_t *b = (const uint8_t*)p;
  D_.assign( b , b + n * type_size( t ) );
  type_ = t;  dims_ = d;
  took_( DATA );
}


void Writer::add_info_text( const std::string &key , const std::string &value , int visible , const std::string &comment ){
  Item it;  it.key = info_key_( key );  it.vis = vis_( visible );
  check_text( value , "info." + it.key );  check_text( comment , "the comment of info." + it.key );
  it.text = quote_( value );  it.comment = comment;
  info_.push_back( it );  took_( INFO , info_.size() - 1 );
}
void Writer::add_info_numbers( const std::string &key , const double *v , size_t n , int visible , const std::string &comment ){
  Item it;  it.key = info_key_( key );  it.vis = vis_( visible );
  if( !v || n == 0 ) throw Error( "badInput" , "info." + it.key + ": no numbers" );
  check_text( comment , "the comment of info." + it.key );
  std::vector<std::string> s;
  for( size_t i = 0 ; i < n ; i++ ){
    if( !std::isfinite( v[i] ) ) throw Error( "badInput" , "info." + it.key + ": a number that is not finite" );
    s.push_back( num2str( v[i] ) );
  }
  it.text = join( s , " " );  it.comment = comment;
  info_.push_back( it );  took_( INFO , info_.size() - 1 );
}
void Writer::add_info_rows_text( const std::string &key , const std::vector<std::string> &values , const std::vector<std::string> *comments , int visible ){
  Item it;  it.kind = 1;  it.key = info_key_( key );  it.vis = vis_( visible );
  if( values.empty() ) throw Error( "badInput" , "info." + it.key + ": no rows" );
  for( const auto &s : values ){ check_text( s , "info." + it.key );  it.rows.push_back( quote_( s ) ); }
  if( comments ){
    if( comments->size() != values.size() ) throw Error( "badInput" , "info." + it.key + ": one comment per row" );
    for( const auto &c : *comments ) check_text( c , "a comment of info." + it.key );
    it.rowc = *comments;
  } else it.perplane = true;
  info_.push_back( it );  took_( INFO , info_.size() - 1 );
}
void Writer::add_info_rows_numbers( const std::string &key , const double *v , size_t n , const std::vector<std::string> *comments , int visible ){
  Item it;  it.kind = 1;  it.key = info_key_( key );  it.vis = vis_( visible );
  if( !v || n == 0 ) throw Error( "badInput" , "info." + it.key + ": no rows" );
  // todos enteros (y exactos en double, |v| <= 2^53): se escriben como enteros,
  // '5' y no '5.0' (planes.series, series.SeriesNumber); si no, como doubles
  bool integer = true;
  for( size_t i = 0 ; i < n ; i++ ){
    if( !std::isfinite( v[i] ) ) throw Error( "badInput" , "info." + it.key + ": a number that is not finite" );
    if( v[i] != std::floor( v[i] ) || std::fabs( v[i] ) > 9007199254740992.0 ) integer = false;
  }
  for( size_t i = 0 ; i < n ; i++ ) it.rows.push_back( integer ? i2s( (int64_t)v[i] ) : num2str( v[i] ) );
  if( comments ){
    if( comments->size() != n ) throw Error( "badInput" , "info." + it.key + ": one comment per row" );
    for( const auto &c : *comments ) check_text( c , "a comment of info." + it.key );
    it.rowc = *comments;
  } else it.perplane = true;
  info_.push_back( it );  took_( INFO , info_.size() - 1 );
}
Writer::Notes &Writer::notes_( Piece p , size_t i ){
  switch( p ){
    case GRID:      return nG_[i];
    case TRANSFORM: return nA_;
    case DATA:      return nD_;
    case THUMB:     return nT_;
    case INFO:      return info_[i].notes;
    default:        throw Error( "internal" , "no piece" );
  }
}
// una pieza que se acaba de dar: se lleva los comentarios que la esperaban, y es
// la ultima (la de un '\b')
void Writer::took_( Piece p , size_t i ){
  Notes &n = notes_( p , i );
  n.pre.insert( n.pre.end() , pend_.begin() , pend_.end() );
  pend_.clear();
  last_ = p;  lastI_ = i;
}
void Writer::add_comment( const std::string &text ){
  std::string t = text;
  bool tail = false;
  if( !t.empty() && t[0] == '\b' ){ t.erase( 0 , 1 );  tail = true; }      // un BACKSPACE: sprintf('\b...') en MATLAB
  check_text( t , "a comment" );
  if( !tail ){ pend_.push_back( "# " + t );  return; }
  // sin nada dado todavia: al final de la PRIMERA linea, 'I3D  # texto'
  if( last_ == NONE ) comment_ += "  # " + t;
  else notes_( last_ , lastI_ ).tail += "  # " + t;
}
void Writer::set_thumbnail( const void *p , Type t , const std::string &tname , const std::vector<int64_t> &dims ){
  const bool ok = t == Type::uint8 && dims.size() >= 2 && dims.size() <= 4 && ( dims.size() < 3 || dims[2] == 1 || dims[2] == 3 ) &&
                  std::all_of( dims.begin() , dims.end() , []( int64_t d ){ return d > 0; } );
  if( !ok ) throw Error( "badInput" , "the thumbnail is uint8 grey {rows cols} or {rows cols 1 frames}, or RGB {rows cols 3 frames}, not " + tname + " [" + dims_text( dims , " " ) + "]" );
  if( !p ) throw Error( "badInput" , "NULL thumbnail data" );
  uint64_t n = 1;  for( int64_t d : dims ) n *= (uint64_t)d;
  // uno solo: darlo otra vez lo reemplaza (y conserva sus comentarios)
  hasTh_ = true;  th_.dims = dims;
  th_.v.assign( (const uint8_t*)p , (const uint8_t*)p + n );
  took_( THUMB );
}
void Writer::set_plane_ref( int64_t k , int64_t t , const std::string &path ){
  if( k < 1 || t < 1 ) throw Error( "badInput" , "planes are numbered from 1" );
  check_text( path , "the path of plane (" + i2s( k ) + "," + i2s( t ) + ")" );
  std::string p = path;  std::replace( p.begin() , p.end() , '\\' , '/' );
  refs_[{ k , t }] = p;
}

static bool truth_( const std::string &v , const std::string &name ){
  if( v == "1" || v == "true" || v == "on" ) return true;
  if( v == "0" || v == "false" || v == "off" ) return false;
  throw Error( "badOption" , name + " is 0 or 1" );
}
void Writer::set_option( const std::string &name , const std::string &value ){
  if( name == "Blocks" ){
    if( value != "auto" && value != "volume" && value != "t" ) throw Error( "badOption" , "Blocks must be 'auto', 'volume' or 't'." );
    blocks_ = value;
  } else if( name == "MaxBlockBytes" ){
    char *e = nullptr;  const double m = std::strtod( value.c_str() , &e );
    if( value.empty() || *e || !( m >= 1 ) ) throw Error( "badOption" , "MaxBlockBytes must be a positive number." );
    maxb_ = m;
  } else if( name == "Hidden" ) hidden_ = truth_( value , name );
  else if( name == "Verify" ) verify_ = truth_( value , name );
  else if( name == "Lazy" ) lazy_ = truth_( value , name );
  else throw Error( "badOption" , "no option '" + name + "' (Blocks, MaxBlockBytes, Hidden, Lazy, Verify)" );
}

void Writer::set_variable( const std::string &name , const std::string &value ){
  if( name.empty() || !std::all_of( name.begin() , name.end() , []( char c ){ return isalnum( (unsigned char)c ) || c == '_'; } ) )
    throw Error( "badInput" , "'" + name + "' is not a variable name: letters, digits and _ (DICOMDIR, not $DICOMDIR$)" );
  check_text( value , "$" + name + "$" );
  for( auto &v : vars_ ) if( v.first == name ){ v.second = value;  return; }
  vars_.push_back( { name , value } );
}

// ====================================================================== cabecera
// una linea; las de data y del thumbnail con bytes en el binario llevan su @a:b aparte, para
// correrlo D bytes cuando delante va el bloque <hidden>
struct Line {
  std::string pre , post;                  // text = pre [ a+D ":" b+D post ]
  bool off = false;  int64_t a = 0 , b = 0;
  bool info = false;  bool vis = true;          // vis: un info.* a la vista
  Line( const std::string &t = "" ) : pre( t ) {}
  std::string text( int64_t D = 0 ) const { return off ? pre + i2s( a + D ) + ":" + i2s( b + D ) + post : pre; }
};

static std::string grid_head_( char name , size_t n , size_t w ){
  const std::string ns = i2s( (int64_t)n );
  return std::string( 1 , name ) + "[" + ns + "]" + spaces( (int64_t)w - (int64_t)ns.size() ) + " = ";
}

static std::vector<std::string> grid_( char name , const std::vector<double> &v , size_t w ){
  const size_t n = v.size();
  for( size_t i = 0 ; i < n ; i++ )
    if( !std::isfinite( v[i] ) || ( i && !( v[i] > v[i-1] ) ) ) throw Error( "badGrid" , std::string( 1 , name ) + " must be finite and strictly increasing." );
  const std::string head = grid_head_( name , n , w );
  if( n == 1 ) return { head + num2str( v[0] ) };
  // RANGO: solo si a + k*s da los MISMOS bits (SPEC 3.1), k*s y la suma como dos
  // operaciones IEEE. Dos candidatos para s: el primer salto y el medio
  const double a = v[0] , b = v[n-1];
  std::vector<double> cand = { v[1] - v[0] , ( b - a ) / (double)( n - 1 ) };
  std::sort( cand.begin() , cand.end() );
  cand.erase( std::unique( cand.begin() , cand.end() ) , cand.end() );
  for( double s : cand ){
    if( s <= 0 ) continue;
    if( std::round( ( b - a ) / s ) + 1 != (double)n ) continue;
    bool same = true;
    for( size_t k = 0 ; k < n && same ; k++ ){
      volatile double ks = (double)k * s;
      const double r = a + ks;
      same = std::memcmp( &r , &v[k] , 8 ) == 0;
    }
    if( same ) return { head + num2str( a ) + " : " + num2str( s ) + " : " + num2str( b ) };
  }
  // LISTA, en lineas de ~100 columnas alineadas con el primer valor; y los saltos
  // exactos en el comentario (con 6 digitos 8 y 8.000000000000004 se verian iguales)
  std::vector<std::string> L;
  std::string line = head;  const std::string pad = spaces( (int64_t)head.size() );
  double dmin = INFINITY , dmax = -INFINITY;
  for( size_t i = 0 ; i < n ; i++ ){
    const std::string s = num2str( v[i] );
    if( line.size() + 1 + s.size() > 100 && line.size() > head.size() ){ L.push_back( line );  line = pad; }
    if( line.back() != ' ' ) line += ' ';
    line += s;
    if( i ){ dmin = std::min( dmin , v[i] - v[i-1] );  dmax = std::max( dmax , v[i] - v[i-1] ); }
  }
  L.push_back( line + "  # not uniform: steps " + num2str( dmin ) + " .. " + num2str( dmax ) );
  return L;
}

// ---- la parte lineal en palabras (solo un comentario: NO es normativo)
typedef std::array<double,9> M3;                     // por filas
static double det3( const M3 &m ){
  return m[0]*( m[4]*m[8] - m[5]*m[7] ) - m[1]*( m[3]*m[8] - m[5]*m[6] ) + m[2]*( m[3]*m[7] - m[4]*m[6] );
}
// autovalores y autovectores de una simetrica 3x3 (Jacobi), de mayor a menor;
// V por columnas: V[3*i + j] = componente i del autovector j
static void eig3( M3 S , double ev[3] , M3 &V ){
  V = { 1,0,0 , 0,1,0 , 0,0,1 };
  for( int sweep = 0 ; sweep < 60 ; sweep++ ){
    const double off = S[1]*S[1] + S[2]*S[2] + S[5]*S[5];
    if( off < 1e-300 ) break;
    for( int p = 0 ; p < 2 ; p++ ) for( int q = p + 1 ; q < 3 ; q++ ){
      const double apq = S[3*p+q];
      if( apq == 0 ) continue;
      const double app = S[3*p+p] , aqq = S[3*q+q];
      const double th = ( aqq - app ) / ( 2 * apq );
      const double t = ( th >= 0 ? 1 : -1 ) / ( std::fabs( th ) + std::sqrt( th*th + 1 ) );
      const double c = 1 / std::sqrt( t*t + 1 ) , s = t * c;
      for( int k = 0 ; k < 3 ; k++ ){           // S = J' S J
        const double skp = S[3*k+p] , skq = S[3*k+q];
        S[3*k+p] = c*skp - s*skq;  S[3*k+q] = s*skp + c*skq;
      }
      for( int k = 0 ; k < 3 ; k++ ){
        const double spk = S[3*p+k] , sqk = S[3*q+k];
        S[3*p+k] = c*spk - s*sqk;  S[3*q+k] = s*spk + c*sqk;
      }
      for( int k = 0 ; k < 3 ; k++ ){
        const double vkp = V[3*k+p] , vkq = V[3*k+q];
        V[3*k+p] = c*vkp - s*vkq;  V[3*k+q] = s*vkp + c*vkq;
      }
    }
  }
  int o[3] = { 0 , 1 , 2 };
  std::sort( o , o + 3 , [&]( int a , int b ){ return S[4*a] > S[4*b]; } );
  M3 W;
  for( int j = 0 ; j < 3 ; j++ ){ ev[j] = S[4*o[j]];  for( int i = 0 ; i < 3 ; i++ ) W[3*i+j] = V[3*i+o[j]]; }
  V = W;
}
// los valores singulares (de mayor a menor) y la rotacion mas cercana R = U V'
// (con U(:,3) cambiada de signo si hay reflexion)
static void svd3( const M3 &M , double sv[3] , M3 &R , bool &refl ){
  M3 S{};
  for( int i = 0 ; i < 3 ; i++ ) for( int j = 0 ; j < 3 ; j++ ) for( int k = 0 ; k < 3 ; k++ ) S[3*i+j] += M[3*k+i] * M[3*k+j];
  double ev[3];  M3 V;
  eig3( S , ev , V );
  M3 U{};
  for( int j = 0 ; j < 3 ; j++ ){
    sv[j] = std::sqrt( std::max( ev[j] , 0.0 ) );
    for( int i = 0 ; i < 3 ; i++ ){
      double s = 0;  for( int k = 0 ; k < 3 ; k++ ) s += M[3*i+k] * V[3*k+j];
      U[3*i+j] = sv[j] > 0 ? s / sv[j] : 0;
    }
  }
  if( !( sv[2] > 1e-300 ) ){                    // singular: la 3a columna, ortogonal a las otras
    U[2] = U[3]*U[7] - U[6]*U[4];  U[5] = U[6]*U[1] - U[0]*U[7];  U[8] = U[0]*U[4] - U[3]*U[1];
  }
  M3 UV{};
  for( int i = 0 ; i < 3 ; i++ ) for( int j = 0 ; j < 3 ; j++ ) for( int k = 0 ; k < 3 ; k++ ) UV[3*i+j] += U[3*i+k] * V[3*j+k];
  refl = det3( UV ) < 0;
  if( refl ) for( int i = 0 ; i < 3 ; i++ ) U[3*i+2] = -U[3*i+2];
  R = M3{};
  for( int i = 0 ; i < 3 ; i++ ) for( int j = 0 ; j < 3 ; j++ ) for( int k = 0 ; k < 3 ; k++ ) R[3*i+j] += U[3*i+k] * V[3*j+k];
}

static std::string describe_( const M3 &M ){
  double sv[3];  M3 R;  bool refl;
  svd3( M , sv , R , refl );
  const double PI = 3.14159265358979323846;
  const double ang = std::acos( std::max( -1.0 , std::min( 1.0 , ( R[0] + R[4] + R[8] - 1 ) / 2 ) ) ) * 180 / PI;
  std::string s;
  if( ang < 1e-9 ) s = "no rotation";
  else {
    double ax[3] = { R[7] - R[5] , R[2] - R[6] , R[3] - R[1] };
    double nn = std::sqrt( ax[0]*ax[0] + ax[1]*ax[1] + ax[2]*ax[2] );
    if( nn < 1e-6 ){
      // ~180 grados: el eje es el autovector de R de valor 1, el de (R-I)'(R-I) de
      // menor autovalor. Su signo es arbitrario: el primer componente no nulo, positivo
      M3 Q{} , RI = R;  RI[0] -= 1;  RI[4] -= 1;  RI[8] -= 1;
      for( int i = 0 ; i < 3 ; i++ ) for( int j = 0 ; j < 3 ; j++ ) for( int k = 0 ; k < 3 ; k++ ) Q[3*i+j] += RI[3*k+i] * RI[3*k+j];
      double ev[3];  M3 V;  eig3( Q , ev , V );
      for( int i = 0 ; i < 3 ; i++ ) ax[i] = V[3*i+2];
      for( int i = 0 ; i < 3 ; i++ ) if( std::fabs( ax[i] ) > 1e-12 ){ if( ax[i] < 0 ) for( double &x : ax ) x = -x;  break; }
      nn = std::sqrt( ax[0]*ax[0] + ax[1]*ax[1] + ax[2]*ax[2] );
    }
    std::vector<std::string> a;
    for( double &x : ax ){ x /= nn;  if( std::fabs( x ) < 1e-12 ) x = 0;  a.push_back( fmtg( x , 4 ) ); }
    s = "rot " + fmtg( ang , 6 ) + " deg about [" + join( a , " " ) + "]";
  }
  if( refl ) s += " + reflection";
  // lo que no es rotacion: una matriz de DICOMstack es ortonormal HASTA EL
  // REDONDEO, y se dice cuanto se aparta
  const double dev = std::max( { std::fabs( sv[0] - 1 ) , std::fabs( sv[1] - 1 ) , std::fabs( sv[2] - 1 ) } );
  if( dev == 0 ){
  } else if( dev < 1e-6 ){
    s += " (orthonormal to " + fmtg( dev , 2 ) + ")";
  } else if( std::max( { std::fabs( sv[0] - sv[0] ) , std::fabs( sv[1] - sv[0] ) , std::fabs( sv[2] - sv[0] ) } ) <= 1e-12 * sv[0] ){
    s += " + scale " + fmtg( sv[0] , 6 );
  } else {
    s += " + scale/shear (singular values " + fmtg( sv[0] , 6 ) + " " + fmtg( sv[1] , 6 ) + " " + fmtg( sv[2] , 6 ) + ")";
  }
  return s;
}

// la rotacion como tres giros sobre los ejes FIJOS: R = Rz(c) Ry(b) Rx(a). Solo de
// una rotacion propia, y solo si los angulos COMPROBADOS la reconstruyen
static std::string euler_( const M3 &M ){
  double sv[3];  M3 R;  bool refl;
  svd3( M , sv , R , refl );
  if( std::max( { std::fabs( sv[0] - 1 ) , std::fabs( sv[1] - 1 ) , std::fabs( sv[2] - 1 ) } ) > 1e-6 || det3( M ) <= 0 ) return "";
  const double PI = 3.14159265358979323846 , D = 180 / PI;
  const double b = std::asin( std::max( -1.0 , std::min( 1.0 , -M[6] ) ) ) * D;
  double a , c;
  if( std::fabs( M[6] ) < 1 - 1e-12 ){ a = std::atan2( M[7] , M[8] ) * D;  c = std::atan2( M[3] , M[0] ) * D; }
  else { a = 0;  c = std::atan2( -M[1] , M[4] ) * D; }
  const double ca = std::cos( a / D ) , sa = std::sin( a / D ) , cb = std::cos( b / D ) , sb = std::sin( b / D ) , cc = std::cos( c / D ) , sc = std::sin( c / D );
  const M3 Z = { cc*cb , cc*sb*sa - sc*ca , cc*sb*ca + sc*sa ,
                 sc*cb , sc*sb*sa + cc*ca , sc*sb*ca - cc*sa ,
                 -sb   , cb*sa            , cb*ca };
  for( int i = 0 ; i < 9 ; i++ ) if( std::fabs( Z[i] - M[i] ) > 1e-6 ) return "";
  std::vector<std::string> P;
  const double ang[3] = { a , b , c };  const char *ax = "xyz";
  for( int k = 0 ; k < 3 ; k++ ){
    if( std::fabs( ang[k] ) < 1e-9 ) continue;
    P.push_back( ( P.empty() ? "turn " + fmtg( ang[k] , 6 ) + " deg about " : "then " + fmtg( ang[k] , 6 ) + " about " ) + ax[k] );
  }
  return P.size() > 1 ? join( P , ", " ) + " (fixed axes)" : "";
}

static std::vector<std::string> transform_( const double *A ){
  if( A[12] != 0 || A[13] != 0 || A[14] != 0 || A[15] != 1 ) throw Error( "badTransform" , "the 4th row of the transform must be exactly 0 0 0 1." );
  // cada numero en parte entera (a la derecha) y resto (a la izquierda): el punto,
  // o si no el exponente, marca el corte. Siempre las tres filas, 12 numeros
  std::string ip[3][4] , rp[3][4];
  size_t wi[4] = { 0 } , wr[4] = { 0 };
  for( int r = 0 ; r < 3 ; r++ ) for( int c = 0 ; c < 4 ; c++ ){
    const std::string s = num2str( A[4*r+c] );
    size_t k = s.find( '.' );  if( k == std::string::npos ) k = s.find( 'e' );  if( k == std::string::npos ) k = s.size();
    ip[r][c] = s.substr( 0 , k );  rp[r][c] = s.substr( k );
    wi[c] = std::max( wi[c] , ip[r][c].size() );  wr[c] = std::max( wr[c] , rp[r][c].size() );
  }
  const std::string head = "transform = ";
  std::vector<std::string> L;
  for( int r = 0 ; r < 3 ; r++ ){
    std::string line = r == 0 ? head : spaces( (int64_t)head.size() );
    for( int c = 0 ; c < 4 ; c++ ){
      if( c ) line += "   ";
      line += spaces( (int64_t)( wi[c] - ip[r][c].size() ) ) + ip[r][c] + rp[r][c] + spaces( (int64_t)( wr[c] - rp[r][c].size() ) );
    }
    while( !line.empty() && line.back() == ' ' ) line.pop_back();
    L.push_back( line );
  }
  const M3 M = { A[0] , A[1] , A[2] , A[4] , A[5] , A[6] , A[8] , A[9] , A[10] };
  for( const std::string &c : { describe_( M ) , euler_( M ) } ) if( !c.empty() ) L.push_back( "# " + c );
  return L;
}

// un tramo a..b (1-based) de una dimension de n: un indice como numero, ':' la
// dimension entera de mas de uno, a:b si no
static std::string r_( int64_t a , int64_t b , int64_t n ){
  if( a == b ) return i2s( a );
  if( a == 1 && b == n ) return ":";
  return i2s( a ) + ":" + i2s( b );
}

// los bloques, como filas k1 k2 t1 t2 (1-based):
//   auto    el primer instante solo; el resto en los MENOS bloques que quepan
//   volume  todo en los menos bloques que quepan
//   t       uno por instante (troceado por k si un instante no cabe)
struct Blk { int64_t k1 , k2 , t1 , t2; };
static std::vector<Blk> plan_( int64_t ni , int64_t nj , int64_t nk , int64_t nt , int64_t ev , const std::string &mode , double MAXB ){
  std::vector<Blk> P;
  auto chunk = [&]( int64_t t1 , int64_t t2 ){
    const double Bt = (double)ni * nj * nk * ev , Bp = (double)ni * nj * ev;
    if( Bt <= MAXB ){
      const int64_t m = std::max<int64_t>( 1 , (int64_t)std::floor( MAXB / Bt ) );
      for( int64_t a = t1 ; a <= t2 ; a += m ) P.push_back( { 1 , nk , a , std::min( a + m - 1 , t2 ) } );
    } else {
      const int64_t mk = (int64_t)std::floor( MAXB / Bp );
      if( mk < 1 ) throw Error( "badOption" , "one i,j plane (" + i2s( (int64_t)Bp ) + " bytes) does not fit in MaxBlockBytes." );
      for( int64_t t = t1 ; t <= t2 ; t++ ) for( int64_t a = 1 ; a <= nk ; a += mk ) P.push_back( { a , std::min( a + mk - 1 , nk ) , t , t } );
    }
  };
  if( mode == "auto" ){ chunk( 1 , 1 );  if( nt > 1 ) chunk( 2 , nt ); }
  else if( mode == "volume" ) chunk( 1 , nt );
  else for( int64_t t = 1 ; t <= nt ; t++ ) chunk( t , t );
  return P;
}

// la clave de una linea: $NOMBRE$ o [A-Za-z0-9_.]+
static std::string key_of_( const std::string &l ){
  if( !l.empty() && l[0] == '$' ){
    size_t i = 1;
    while( i < l.size() && ( isalnum( (unsigned char)l[i] ) || l[i] == '_' ) ) i++;
    if( i > 1 && i < l.size() && l[i] == '$' ) return l.substr( 0 , i + 1 );
  }
  size_t i = 0;
  while( i < l.size() && ( isalnum( (unsigned char)l[i] ) || l[i] == '_' || l[i] == '.' ) ) i++;
  return l.substr( 0 , i );
}

// ====================================================================== write
void Writer::write( const std::string &path ) const {
  std::vector<std::vector<uint8_t>> P;
  encode_( P );
  std::vector<Chunk> ch;
  for( const auto &p : P ) ch.push_back( { &p } );
  detail::write_atomic( path , ch );
}

std::vector<uint8_t> Writer::encode() const {
  std::vector<std::vector<uint8_t>> P;
  encode_( P );
  size_t n = 0;  for( const auto &p : P ) n += p.size();
  std::vector<uint8_t> out;  out.reserve( n );
  for( auto &p : P ){ out.insert( out.end() , p.begin() , p.end() );  std::vector<uint8_t>().swap( p ); }
  return out;
}

// el fichero entero, en sus trozos: la cabecera, el bloque <hidden> (si lo hay) y
// los bloques de data y aux, en el orden del fichero
void Writer::encode_( std::vector<std::vector<uint8_t>> &pieces ) const {
  pieces.clear();
  if( D_.empty() ) throw Error( "badData" , "no data: set_data first" );
  const Type T = type_;
  const int64_t es = (int64_t)type_size( T );
  std::vector<int64_t> sz = dims_;  while( sz.size() < 5 ) sz.push_back( 1 );
  const int64_t ni = sz[0] , nj = sz[1] , nk = sz[2] , nt = sz[3];
  const std::vector<int64_t> csz( sz.begin() + 4 , sz.end() );
  int64_t ncomp = 1;  for( int64_t c : csz ) ncomp *= c;
  const std::string tn = type_name( T );
  // FORMA CANONICA (SPEC 9): el encoding lo fija el tipo
  const bool jls = T == Type::uint8 || T == Type::int8 || T == Type::uint16 || T == Type::int16;
  const std::string encoding = jls ? "jpegls" : "zlib";

  std::vector<Line> H;
  std::vector<int64_t> ssz = sz;  if( ncomp == 1 ) ssz.resize( 4 );
  // la primera linea: con los add_comment('\b...') dados antes que ninguna pieza
  H.push_back( Line( "I3D" + comment_ ) );

  // las rejillas: sin darlas, 0 : 1 : n-1
  std::vector<double> G[4];
  size_t w = 0;
  const char *AX = "XYZT";
  for( int g = 0 ; g < 4 ; g++ ){
    if( hasG_[g] ) G[g] = G_[g];
    else for( int64_t q = 0 ; q < sz[g] ; q++ ) G[g].push_back( (double)q );
    if( (int64_t)G[g].size() != sz[g] ) throw Error( "badGrid" , std::string( 1 , AX[g] ) + " has " + i2s( (int64_t)G[g].size() ) + " values and data " + i2s( sz[g] ) + " along it" );
    w = std::max( w , i2s( (int64_t)G[g].size() ).size() );
  }
  // los comentarios de add_comment: los de encima de una pieza, y su '\b' al final
  // de la primera linea de la pieza
  auto pre = [&]( const Notes &n , bool info ){ for( const std::string &c : n.pre ){ Line L( c );  L.info = info;  H.push_back( L ); } };
  auto lines = [&]( const std::vector<std::string> &ls , const Notes &n ){
    pre( n , false );
    for( size_t i = 0 ; i < ls.size() ; i++ ) H.push_back( Line( i == 0 ? ls[i] + n.tail : ls[i] ) );
  };
  for( int g = 0 ; g < 4 ; g++ ) lines( grid_( AX[g] , G[g] , w ) , nG_[g] );
  lines( transform_( A_ ) , nA_ );

  // ---------------------------------------------------------------- bloques
  const bool lazy = lazy_ || !refs_.empty();
  const int64_t plane = ni * nj * es;
  auto plane_ptr = [&]( int64_t k , int64_t t , int64_t c ){ return D_.data() + ( ( c * nt + ( t - 1 ) ) * nk + ( k - 1 ) ) * plane; };
  std::vector<Blk> P;
  // Lazy: lo de cada plano: 0 materializar, 1 referencia, 2 <missing>
  std::vector<int> kind;  std::vector<std::string> ref;
  size_t iddir = 0;  std::string DDIR;
  if( lazy ){
    if( ncomp > 1 ) throw Error( "notLazy" , "'Lazy' with more than one component is not supported." );
    kind.assign( (size_t)( nk * nt ) , 0 );  ref.assign( (size_t)( nk * nt ) , "" );
    for( const auto &r : refs_ ){
      const int64_t k = r.first.first , t = r.first.second;
      if( k > nk || t > nt ) throw Error( "lazyMismatch" , "plane (" + i2s( k ) + "," + i2s( t ) + ") is outside data (" + i2s( nk ) + " x " + i2s( nt ) + ")" );
      const size_t q = (size_t)( ( t - 1 ) * nk + ( k - 1 ) );
      if( r.second.empty() ){
        // <missing> SOLO en clases enteras y de un plano de ceros: el lector rellena
        // con 0 en enteros pero con NaN en float. Si no, se materializa
        const uint8_t *p = plane_ptr( k , t , 0 );
        if( !( T == Type::single || T == Type::double_ ) && std::all_of( p , p + plane , []( uint8_t x ){ return x == 0; } ) ) kind[q] = 2;
      } else { kind[q] = 1;  ref[q] = r.second; }
    }
    // VERIFY: un .i3d temporal con TODAS las referencias (lo demas, <missing>),
    // leido una vez con el lector; cada plano que no da exactamente su plano de
    // data se materializa. Si el lector no puede con alguno, plano a plano
    bool anyref = std::count( kind.begin() , kind.end() , 1 ) > 0;
    if( verify_ && anyref ){
      auto esc = []( const std::string &p ){ std::string s;  for( char c : p ){ s += c;  if( c == '$' ) s += '$'; }  return s; };
      auto idx = []( int64_t n ){ return n == 1 ? std::string( "0.0" ) : "0.0 : 1.0 : " + num2str( (double)( n - 1 ) ); };
      const std::string hx = "X[" + i2s( ni ) + "] = " + idx( ni ) + "\nY[" + i2s( nj ) + "] = " + idx( nj ) + "\n";
      const std::filesystem::path tf = std::filesystem::temp_directory_path() / ( "i3d_verify_" + std::to_string( I3D_GETPID() ) + "_" + std::to_string( (uintptr_t)this ) + ".i3d" );
      auto put = [&]( const std::string &t ){
        std::ofstream o( tf , std::ios::binary | std::ios::trunc );
        o << t;
        if( !o ) throw Error( "cannotOpen" , "cannot write the verification file " + tf.u8string() );
      };
      struct Rm { std::filesystem::path p; ~Rm(){ std::error_code ec;  std::filesystem::remove( p , ec ); } } rm{ tf };
      std::string hv = "I3D\n" + hx + "Z[" + i2s( nk ) + "] = " + idx( nk ) + "\nT[" + i2s( nt ) + "] = " + idx( nt ) + "\n";
      for( int64_t t = 1 ; t <= nt ; t++ ) for( int64_t k = 1 ; k <= nk ; k++ ){
        const size_t q = (size_t)( ( t - 1 ) * nk + ( k - 1 ) );
        hv += "data(:,:," + i2s( k ) + "," + i2s( t ) + ") = " + ( kind[q] == 1 ? "<dicom " + tn + " \"" + esc( ref[q] ) + "\">" : std::string( "<missing>" ) ) + "\n";
      }
      put( hv + "---\n" );
      try {
        File F( tf.u8string() );
        std::vector<uint8_t> out( D_.size() );
        F.read_data( out.data() , out.size() );
        for( size_t q = 0 ; q < kind.size() ; q++ )
          if( kind[q] == 1 && std::memcmp( out.data() + q * plane , D_.data() + q * plane , (size_t)plane ) != 0 ) kind[q] = 0;
      } catch( const std::exception & ){
        for( int64_t t = 1 ; t <= nt ; t++ ) for( int64_t k = 1 ; k <= nk ; k++ ){
          const size_t q = (size_t)( ( t - 1 ) * nk + ( k - 1 ) );
          if( kind[q] != 1 ) continue;
          put( "I3D\n" + hx + "Z[1] = 0.0\nT[1] = 0.0\ndata = <dicom " + tn + " \"" + esc( ref[q] ) + "\">\n---\n" );
          bool ok = false;
          try {
            File F( tf.u8string() );
            std::vector<uint8_t> out( (size_t)plane );
            F.read_data( out.data() , out.size() );
            ok = std::memcmp( out.data() , D_.data() + q * plane , (size_t)plane ) == 0;
          } catch( const std::exception & ){}
          if( !ok ) kind[q] = 0;
        }
      }
    }
    // $DICOMDIR$: el dado, o la raiz comun de lo que se referencia, componente a componente
    for( auto &v : vars_ ) if( v.first == "DICOMDIR" ) DDIR = v.second;
    if( DDIR.empty() ){
      std::vector<std::vector<std::string>> parts;
      for( size_t q = 0 ; q < kind.size() ; q++ ) if( kind[q] == 1 ){
        std::vector<std::string> p;  size_t a = 0;
        for( ;; ){ size_t b = ref[q].find( '/' , a );  p.push_back( ref[q].substr( a , b - a ) );  if( b == std::string::npos ) break;  a = b + 1; }
        parts.push_back( p );
      }
      if( parts.empty() ) DDIR = "./";
      else {
        size_t n = SIZE_MAX;  for( auto &p : parts ) n = std::min( n , p.size() );
        n -= 1;                                                  // el ultimo es el fichero
        size_t c = 0;
        while( c < n && std::all_of( parts.begin() , parts.end() , [&]( const std::vector<std::string> &p ){ return p[c] == parts[0][c]; } ) ) c++;
        if( c == 0 ) throw Error( "badOption" , "the referenced .dcm have no directory in common (different drives?): $DICOMDIR$ cannot hold them all." );
        std::vector<std::string> head( parts[0].begin() , parts[0].begin() + c );
        DDIR = join( head , "/" ) + "/";
      }
    }
    std::replace( DDIR.begin() , DDIR.end() , '\\' , '/' );
    if( DDIR.back() != '/' ) DDIR += '/';
    for( size_t q = 0 ; q < kind.size() ; q++ ){
      if( kind[q] != 1 ) continue;
      if( ref[q].compare( 0 , DDIR.size() , DDIR ) != 0 ) throw Error( "badOption" , "'" + ref[q] + "' is not under $DICOMDIR$ '" + DDIR + "'." );
      std::string s;  for( char c : ref[q].substr( DDIR.size() ) ){ s += c;  if( c == '$' ) s += '$'; }   // '$' literal: '$$' (SPEC 2)
      ref[q] = "$DICOMDIR$/" + s;
    }
    DDIR.pop_back();
    for( int64_t t = 1 ; t <= nt ; t++ ) for( int64_t k = 1 ; k <= nk ; k++ ) P.push_back( { k , k , t , t } );
  } else {
    double MB = maxb_;
    if( jls ){
      // SPEC 4: la imagen de un <jpegls> no pasa de 65535 de ancho ni de alto (sin
      // la extension LSE, que no leen ni el CharLS del navegador ni imagecodecs).
      // Cada (k,t) son nj*ncomp filas: el tope en planos es un tope en bytes
      if( ni > 65535 || nj * ncomp > 65535 )
        throw Error( "badData" , "a " + i2s( ni ) + " x " + i2s( nj ) + " plane with " + i2s( ncomp ) + " component(s) does not fit in one JPEG-LS image (at most 65535 x 65535)." );
      MB = std::min( MB , (double)( 65535 / ( nj * ncomp ) ) * ni * nj * ncomp * es );
    }
    P = plan_( ni , nj , nk , nt , ncomp * es , blocks_ , MB );
  }
  // las variables (set_variable), en el orden en que se dieron; con Lazy,
  // $DICOMDIR$ siempre, con el valor de las referencias (iddir: su linea)
  bool ddone = false;
  for( const auto &v : vars_ ){
    const bool dd = lazy && v.first == "DICOMDIR";
    if( dd ){ iddir = H.size();  ddone = true; }
    H.push_back( Line( "$" + v.first + "$ = " + quote_( dd ? DDIR : v.second ) ) );
  }
  if( lazy && !ddone ){ iddir = H.size();  H.push_back( Line( "$DICOMDIR$ = " + quote_( DDIR ) ) ); }
  const size_t nb = P.size();
  const std::string summary = "  # " + dims_text( ssz , " x " ) + ", " + tn;

  // el subindice COMPLETO de cada bloque: i, j, k, t y cada dimension de componente
  std::vector<std::string> S( nb );
  size_t wsub = 0;
  for( size_t p = 0 ; p < nb ; p++ ){
    std::string C;
    if( ncomp > 1 ) for( int64_t n : csz ) C += "," + r_( 1 , n , INT64_MAX );
    S[p] = "data(:,:," + r_( P[p].k1 , P[p].k2 , nk ) + "," + r_( P[p].t1 , P[p].t2 , nt ) + C + ")";
    wsub = std::max( wsub , S[p].size() );
  }

  std::vector<std::vector<uint8_t>> B;
  int64_t off = 0 , nref = 0 , nmis = 0;
  for( size_t p = 0 ; p < nb ; p++ ){
    const std::string lhs = S[p] + spaces( (int64_t)( wsub - S[p].size() ) ) + " = ";
    if( lazy ){
      const size_t q = (size_t)( ( P[p].t1 - 1 ) * nk + ( P[p].k1 - 1 ) );
      if( kind[q] ){
        Line L;
        if( kind[q] == 2 ){ L.pre = lhs + "<missing>";  nmis++; }
        else {
          // el crc de SU plano de data: lo que tenia el escritor. Si el .dcm cambia
          // o se decodifica distinto, badCRC
          L.pre = lhs + "<dicom " + tn + " \"" + ref[q] + "\" crc " + hex8( crc32_( plane_ptr( P[p].k1 , P[p].t1 , 0 ) , (size_t)plane ) ) + ">";
          nref++;
        }
        if( p == 0 ){ L.pre += summary + nD_.tail;  pre( nD_ , false ); }
        H.push_back( L );
        continue;
      }
    }
    // los bytes del bloque, en orden i j k t c
    const int64_t nkb = P[p].k2 - P[p].k1 + 1 , ntb = P[p].t2 - P[p].t1 + 1;
    std::vector<uint8_t> raw( (size_t)( plane * nkb * ntb * ncomp ) );
    uint8_t *o = raw.data();
    for( int64_t c = 0 ; c < ncomp ; c++ ) for( int64_t t = P[p].t1 ; t <= P[p].t2 ; t++ ){
      std::memcpy( o , plane_ptr( P[p].k1 , t , c ) , (size_t)( plane * nkb ) );
      o += plane * nkb;
    }
    const uint32_t crc = crc32_( raw.data() , raw.size() );
    B.push_back( jls ? jpegls_( raw , T , ni , nj * nkb * ntb * ncomp ) : deflate_( raw.data() , raw.size() ) );
    // @a:b INCLUSIVO, como en MATLAB: b es el ULTIMO byte del bloque
    Line L;
    L.pre = lhs + "<" + encoding + spaces( 4 - (int64_t)encoding.size() ) + " " + tn + " @";
    L.off = true;  L.a = off;  L.b = off + (int64_t)B.back().size() - 1;
    L.post = " crc " + hex8( crc ) + ">";
    if( p == 0 ){ L.post += summary + nD_.tail;  pre( nD_ , false ); }
    H.push_back( L );
    off += (int64_t)B.back().size();
  }
  // el thumbnail, DETRAS de los bloques de data
  if( hasTh_ ){
    pre( nT_ , false );
    const auto &td = th_.dims;
    B.push_back( png_( th_.v , td[0] , td[1] , td.size() >= 3 ? td[2] : 1 , td.size() >= 4 ? td[3] : 1 ) );
    Line L;
    L.pre = "thumbnail = <png uint8 {" + dims_text( th_.dims , " " ) + "} @";
    L.off = true;  L.a = off;  L.b = off + (int64_t)B.back().size() - 1;
    L.post = " crc " + hex8( crc32_( th_.v.data() , th_.v.size() ) ) + ">" + nT_.tail;     // de los PIXELES, no del PNG
    H.push_back( L );
    off += (int64_t)B.back().size();
  }

  // la seccion info.*, en el orden en que se dio
  for( const Item &it : info_ ){
    pre( it.notes , true );
    if( it.kind == 0 ){ Line L( "info." + it.key + " = " + it.text + tail_( it.comment ) + it.notes.tail );  L.info = true;  L.vis = it.vis;  H.push_back( L );  continue; }
    // UN VALOR POR FILA: la primera en la linea de 'key =', las demas alineadas con
    // ella, y su comentario al final (alineados entre si)
    std::vector<std::string> cm = it.rowc;
    if( it.perplane ){
      if( (int64_t)it.rows.size() != nk * nt ) throw Error( "badInput" , "info." + it.key + ": a row per plane is " + i2s( nk * nt ) + " rows, not " + i2s( (int64_t)it.rows.size() ) );
      for( int64_t q = 0 ; q < nk * nt ; q++ ){
        const int64_t k = q % nk + 1 , t = q / nk + 1;
        std::vector<std::string> in;  bool single = true;
        for( size_t p = 0 ; p < nb ; p++ ) if( P[p].k1 <= k && k <= P[p].k2 && P[p].t1 <= t && t <= P[p].t2 ){
          in.push_back( S[p] );  single = single && P[p].k1 == P[p].k2 && P[p].t1 == P[p].t2;
        }
        const std::string kt = "data(:,:," + i2s( k ) + "," + i2s( t ) + ")";
        cm.push_back( in.empty() ? kt : single ? join( in , ", " ) : kt + " in " + join( in , ", " ) );
      }
    }
    std::string head = "info." + it.key;  head += spaces( 30 - (int64_t)head.size() ) + " = ";
    size_t wv = 0;  for( const auto &v : it.rows ) wv = std::max( wv , v.size() );
    for( size_t i = 0 ; i < it.rows.size() ; i++ ){
      Line L( ( i == 0 ? head : spaces( (int64_t)head.size() ) ) + it.rows[i] );
      if( !cm.empty() && !cm[i].empty() ) L.pre +=spaces( (int64_t)( wv - it.rows[i].size() ) ) + "  # " + cm[i];
      if( i == 0 ) L.pre += it.notes.tail;
      L.info = true;  L.vis = it.vis;
      H.push_back( L );
    }
  }
  // los comentarios que no esperaban a nada: al final
  for( const std::string &c : pend_ ){ Line L( c );  L.info = true;  H.push_back( L ); }
  if( lazy ) H[iddir].pre += "  # " + i2s( nref ) + " planes referenced, " + i2s( (int64_t)nb - nref - nmis ) + " materialised, " + i2s( nmis ) + " missing";

  // ---------------------------------------------------------------- la parte oculta
  // Una ENTRADA es su linea, sus continuaciones (empiezan por espacio) y los
  // comentarios de linea entera que la preceden; los de transform -- lo que es en
  // palabras -- van DEBAJO y son suyos. Se oculta un info.* que se dio con
  // visible = 0, y las variables $NOMBRE$ (rutas locales, que pueden nombrar al paciente);
  // nada mas: lo que hace falta para leer data esta siempre a la vista. Los
  // comentarios van con su entrada
  std::vector<Line> Hpre = { H[0] } , Hinf , Hh , pend;
  auto app = []( std::vector<Line> &a , const std::vector<Line> &b ){ a.insert( a.end() , b.begin() , b.end() ); };
  size_t q = 1;
  while( q < H.size() ){
    const std::string l = H[q].text();
    if( !l.empty() && l[0] == '#' ){ pend.push_back( H[q] );  q++;  continue; }
    const bool ininfo = H[q].info , vis = H[q].vis;
    std::vector<Line> u = { H[q] };  q++;
    while( q < H.size() && !H[q].pre.empty() && ( H[q].pre[0] == ' ' || H[q].pre[0] == '\t' ) ) u.push_back( H[q++] );
    const std::string k = key_of_( l );
    if( k == "transform" ) while( q < H.size() && !H[q].pre.empty() && H[q].pre[0] == '#' ) u.push_back( H[q++] );
    const bool hide = ( ininfo && !vis ) || ( !k.empty() && k[0] == '$' );
    std::vector<Line> &to = hide ? Hh : ininfo ? Hinf : Hpre;
    app( to , pend );  app( to , u );
    pend.clear();
  }
  app( H.back().info ? Hinf : Hpre , pend );

  // el bloque <hidden>, el PRIMERO del binario y sin crc. Los demas bloques se
  // corren D bytes; si lo oculto lleva offsets, D depende del tamano del propio
  // bloque: se estima, se codifica y se acepta si cabe (n <= D) dejando un hueco
  // de menos de 32 bytes, relleno con ceros; si no, se reestima
  int64_t D = 0;
  std::vector<uint8_t> z;
  std::vector<Line> hline;
  if( !Hh.empty() ){
    const int64_t HOLE = 32;
    bool ok = false;
    for( int it = 0 ; it < 20 && !ok ; it++ ){
      std::string t;  for( const Line &L : Hh ) t += L.text( D ) + "\n";
      z = hide_( t , HIDD_SEED , HIDD_MULT );
      if( (int64_t)z.size() <= D && D - (int64_t)z.size() < HOLE ) ok = true;
      else D = (int64_t)z.size() + HOLE / 2;
    }
    if( !ok ) throw Error( "internal" , "the <hidden> block does not settle in front of the data (20 tries)." );
    hline.push_back( Line( "header = <hidden @0:" + i2s( (int64_t)z.size() - 1 ) + ">  # the rest of the header" ) );
    z.resize( (size_t)D , 0 );
  }
  // la disposicion: lo de antes de info, 'header = <hidden>' delante del primer
  // bloque de data, una linea en blanco, los info.* a la vista y otra linea en blanco
  if( !hline.empty() ){
    size_t p = 0;
    for( size_t i = 0 ; i < Hpre.size() && !p ; i++ ) if( Hpre[i].pre.compare( 0 , 4 , "data" ) == 0 ) p = i + 1;
    if( p < 1 || p > Hpre.size() ) p = Hpre.size() + 1;
    Hpre.insert( Hpre.begin() + ( p - 1 ) , hline[0] );
  }
  std::string text;
  for( const Line &L : Hpre ) text += L.text( D ) + "\n";
  if( !Hinf.empty() ){ text += "\n";  for( const Line &L : Hinf ) text += L.text( D ) + "\n"; }
  text += "\n";

  // ---------------------------------------------------------------- escribir
  std::vector<uint8_t> head;
  if( hidden_ ) head = i3db_( text );                    // la MISMA cabecera, sin el '---'
  else { text += "---\n";  head.assign( text.begin() , text.end() ); }
  pieces.push_back( std::move( head ) );
  if( !z.empty() ) pieces.push_back( std::move( z ) );
  for( auto &b : B ) pieces.push_back( std::move( b ) );
}

// ====================================================================== rewrite
void rewrite( const std::string &src , const std::string &dst , bool hidden ){
  File F( src );
  std::vector<uint8_t> head;
  if( hidden ) head = i3db_( F.header() );
  else { const std::string t = F.header() + "---\n";  head.assign( t.begin() , t.end() ); }
  std::error_code ec;
  const int64_t size = (int64_t)std::filesystem::file_size( u8p( src ) , ec );
  if( ec ) throw Error( "cannotOpen" , "cannot read '" + src + "'" );
  Chunk h;  h.b = &head;
  Chunk b;  b.file = src;  b.off = F.binary_start();  b.len = size - F.binary_start();
  detail::write_atomic( dst , { h , b } );
}

} // namespace i3d
