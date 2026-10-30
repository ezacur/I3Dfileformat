// i3d.cpp -- ver i3d.hpp. Implementa SPEC.md draft v0.
//
// NOMINMAX ANTES de todo: las cabeceras de DCMTK incluyen windows.h, cuyas macros
// min/max rompen std::max
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "i3d.hpp"

#include <charconv>
#include <cstring>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <limits>
#include <cmath>
#include <cctype>
#include <type_traits>
#include <filesystem>
#include <mutex>

#ifdef I3D_HAVE_ZLIB
#include <zlib.h>
#endif
#ifdef I3D_HAVE_CHARLS
#include <charls/charls.h>
#endif
#ifdef I3D_HAVE_LODEPNG
#include "lodepng.h"
#endif
#ifdef I3D_HAVE_DCMTK
#include "dcmtk/config/osconfig.h"
#include "dcmtk/dcmdata/dctk.h"
#include "dcmtk/dcmdata/dcrledrg.h"
#include "dcmtk/dcmjpeg/djdecode.h"
#include "dcmtk/dcmdata/dcpixel.h"
#include "dcmtk/dcmdata/dcpixseq.h"
#include "dcmtk/dcmdata/dcpxitem.h"
#endif

namespace i3d {

// ====================================================================== tipos
static const char *TNAMES[] = { "int8","uint8","int16","uint16","int32","uint32","int64","uint64","single","double" };
static const size_t TSIZES[] = { 1,1,2,2,4,4,8,8,4,8 };

const char *type_name( Type t ){ return t == Type::none ? "none" : TNAMES[ (int)t ]; }
size_t      type_size( Type t ){ return t == Type::none ? 0 : TSIZES[ (int)t ]; }

static Type type_from( const std::string &s ){
  for( int i = 0 ; i < 10 ; i++ ) if( s == TNAMES[i] ) return (Type)i;
  return Type::none;
}
Type type_from_name( const std::string &s ){ return type_from( s ); }
static bool is_float( Type t ){ return t == Type::single || t == Type::double_; }
static bool is_signed( Type t ){ return t == Type::int8 || t == Type::int16 || t == Type::int32 || t == Type::int64; }
static int  bits_of( Type t ){ return 8 * (int)type_size( t ); }

// La PROMOCION SIN PERDIDA de SPEC 5.4, hecha de verdad sin perdida.
// (La tabla de DICOMstackRead/promote_ no lo es: con uint32+int8 devuelve
// uint32 y pierde los negativos. Aqui se calcula el tipo que contiene a los dos.)
static Type promote( Type a , Type b ){
  if( a == Type::none ) return b;
  if( b == Type::none || a == b ) return a;
  if( is_float( a ) || is_float( b ) ){
    // single representa exacto un entero de hasta 24 bits; double, de hasta 53
    auto fits = [&]( Type t , int mant ){ return is_float( t ) ? ( t == Type::single || mant == 53 ) : ( bits_of( t ) - ( is_signed( t ) ? 1 : 0 ) ) <= mant; };
    if( fits( a , 24 ) && fits( b , 24 ) && !( a == Type::double_ || b == Type::double_ ) ) return Type::single;
    if( fits( a , 53 ) && fits( b , 53 ) ) return Type::double_;
    throw Error( "badType" , std::string( "no lossless type holds both " ) + type_name( a ) + " and " + type_name( b ) );
  }
  bool sgn = is_signed( a ) || is_signed( b );
  // bits de magnitud que hacen falta, mas el de signo si lo hay
  auto need = [&]( Type t ){ return is_signed( t ) ? bits_of( t ) : bits_of( t ) + ( sgn ? 1 : 0 ); };
  int n = std::max( need( a ) , need( b ) );
  int w = n <= 8 ? 8 : n <= 16 ? 16 : n <= 32 ? 32 : n <= 64 ? 64 : 0;
  if( !w ) throw Error( "badType" , std::string( "no lossless integer type holds both " ) + type_name( a ) + " and " + type_name( b ) );
  switch( w ){
    case 8:  return sgn ? Type::int8  : Type::uint8;
    case 16: return sgn ? Type::int16 : Type::uint16;
    case 32: return sgn ? Type::int32 : Type::uint32;
    default: return sgn ? Type::int64 : Type::uint64;
  }
}

// ====================================================================== texto
static std::string trim( const std::string &s ){
  size_t a = s.find_first_not_of( " \t\r" );
  if( a == std::string::npos ) return "";
  size_t b = s.find_last_not_of( " \t\r" );
  return s.substr( a , b - a + 1 );
}

// los UNICOS escapes de una cadena (SPEC 2): \" y \\ . Cualquier otra '\' es una
// barra literal -- "D:\dir\x.dcm" es una ruta de Windows, no una cadena con escapes
static bool is_escape( const std::string &s , size_t i ){
  return s[i] == '\\' && i + 1 < s.size() && ( s[i+1] == '"' || s[i+1] == '\\' );
}

// '#' fuera de una cadena entre comillas empieza un comentario
static std::string strip_comment( const std::string &s ){
  bool q = false;
  for( size_t i = 0 ; i < s.size() ; i++ ){
    if( q && is_escape( s , i ) ){ i++; continue; }
    if( s[i] == '"' ) q = !q;
    else if( s[i] == '#' && !q ) return s.substr( 0 , i );
  }
  return s;
}

// Toda ruta es UTF-8 (lo que pasan el MEX, Python y la API en C). En Windows un
// std::ifstream( const char* ) la leeria en la pagina de codigos ANSI, y una
// carpeta "Año" no abriria: se abre como ruta ancha
static std::filesystem::path native_( const std::string &utf8 ){ return std::filesystem::u8path( utf8 ); }

// una linea de la cabecera; las de la parte <hidden> (SPEC 1.2) van en negativo
static std::string where( int line ){
  return line < 0 ? "hidden line " + std::to_string( -line ) + ": " : "line " + std::to_string( line ) + ": ";
}

static double to_double( const std::string &t , const std::string &what , int line ){
  double v = 0.0;
  // from_chars no acepta '+' delante; el escritor nunca lo pone, pero se tolera
  const char *b = t.data() , *e = t.data() + t.size();
  if( b < e && *b == '+' ) b++;
  auto r = std::from_chars( b , e , v );   // redondeo correcto por el estandar
  if( r.ec != std::errc() || r.ptr != e ) throw Error( "badNumber" , where( line ) + "bad number '" + t + "' in " + what );
  return v;
}

static int64_t to_int( const std::string &t , const std::string &what , int line ){
  int64_t v = 0;
  auto r = std::from_chars( t.data() , t.data() + t.size() , v );
  if( r.ec != std::errc() || r.ptr != t.data() + t.size() ) throw Error( "badNumber" , where( line ) + "bad integer '" + t + "' in " + what );
  return v;
}

static std::vector<std::string> split_ws( const std::string &s ){
  std::vector<std::string> out;  std::istringstream is( s );  std::string w;
  while( is >> w ) out.push_back( w );
  return out;
}

std::vector<double> File::parse_numbers( const std::string &value , const std::string &what , int line ){
  std::vector<double> v;
  for( auto &t : split_ws( value ) ) v.push_back( to_double( t , what , line ) );
  return v;
}

// ====================================================================== rejillas
// SPEC 3.1: como mucho 2^24 valores por rejilla (16 777 216: ningun eje de un
// volumen real se acerca; 128 MiB de doubles)
static const double MAX_GRID = 16777216.0;

static std::vector<double> parse_grid( const std::string &name , const std::string &value , int line ){
  // el ':' del rango puede ir pegado o separado
  std::string s;  for( char c : value ){ if( c == ':' ) s += " : "; else s += c; }
  auto tok = split_ws( s );
  std::vector<double> v;
  if( std::find( tok.begin() , tok.end() , ":" ) != tok.end() ){
    if( tok.size() != 5 || tok[1] != ":" || tok[3] != ":" ) throw Error( "badGrid" , where( line ) + "a range is  a : s : b  in " + name );
    double a = to_double( tok[0] , name , line ) , st = to_double( tok[2] , name , line ) , b = to_double( tok[4] , name , line );
    if( !( st > 0 ) ) throw Error( "badGrid" , where( line ) + "the step of " + name + " must be > 0" );
    double nn = std::round( ( b - a ) / st ) + 1;
    // tope (SPEC 3.1): una rejilla de mas de 2^24 valores no es un volumen, es
    // un fichero roto que pediria memoria hasta reventar
    if( !( nn >= 1 && nn <= MAX_GRID ) ) throw Error( "badGrid" , where( line ) + "bad range in " + name + " (" + std::to_string( nn ) + " values; at most 2^24)" );
    int64_t n = (int64_t)nn;
    // que cierre ANTES de reservar: el ultimo valor con las mismas dos
    // operaciones que el bucle
    {
      volatile double p = (double)( n - 1 ) * st;
      if( a + p != b ) throw Error( "badGrid" , where( line ) + "the range of " + name + " does not end exactly at b" );
    }
    v.resize( (size_t)n );
    for( int64_t k = 0 ; k < n ; k++ ){
      // SPEC 3.1: k*s y la suma, DOS operaciones. El volatile impide que el
      // compilador las fusione en una FMA, que daria otros bits
      volatile double p = (double)k * st;
      v[(size_t)k] = a + p;
    }
    if( v.back() != b ) throw Error( "badGrid" , where( line ) + "the range of " + name + " does not end exactly at b" );
  } else {
    if( (double)tok.size() > MAX_GRID ) throw Error( "badGrid" , where( line ) + name + " has more than 2^24 values" );
    for( auto &t : tok ) v.push_back( to_double( t , name , line ) );
  }
  if( v.empty() ) throw Error( "badGrid" , where( line ) + name + " is empty" );
  for( size_t i = 0 ; i < v.size() ; i++ ){
    if( !std::isfinite( v[i] ) ) throw Error( "badGrid" , where( line ) + name + " is not finite" );
    if( i && !( v[i] > v[i-1] ) ) throw Error( "badGrid" , where( line ) + name + " is not strictly increasing" );
  }
  return v;
}

// ====================================================================== descriptores
Descriptor File::parse_descriptor( const std::string &value , int line ){
  Descriptor d;  d.text = value;
  if( value.size() < 2 || value.front() != '<' || value.back() != '>' )
    throw Error( "badDescriptor" , where( line ) + "not a descriptor <...>: " + value );
  std::string s = value.substr( 1 , value.size() - 2 );

  // fichas: palabra, "cadena", {forma}
  struct Tok { char kind; std::string text; };
  std::vector<Tok> T;
  for( size_t i = 0 ; i < s.size() ; ){
    char c = s[i];
    if( c == ' ' || c == '\t' ){ i++; continue; }
    if( c == '"' ){
      std::string out;  i++;
      for( ; i < s.size() && s[i] != '"' ; i++ ){ if( is_escape( s , i ) ) i++; out += s[i]; }
      if( i >= s.size() ) throw Error( "badDescriptor" , where( line ) + "unterminated string in " + value );
      i++;  T.push_back( { '"' , out } );
    } else if( c == '{' ){
      size_t e = s.find( '}' , i );
      if( e == std::string::npos ) throw Error( "badDescriptor" , where( line ) + "unterminated {shape} in " + value );
      T.push_back( { '{' , s.substr( i + 1 , e - i - 1 ) } );  i = e + 1;
    } else {
      size_t e = s.find_first_of( " \t" , i );  if( e == std::string::npos ) e = s.size();
      T.push_back( { 'w' , s.substr( i , e - i ) } );  i = e;
    }
  }
  if( T.empty() || T[0].kind != 'w' ) throw Error( "badDescriptor" , where( line ) + "a descriptor starts with its encoding: " + value );
  d.encoding = T[0].text;

  for( size_t i = 1 ; i < T.size() ; i++ ){
    const Tok &t = T[i];
    if( t.kind == '"' ){ if( !d.path.empty() ) throw Error( "badDescriptor" , where( line ) + "two paths in " + value ); d.path = t.text; continue; }
    if( t.kind == '{' ){
      if( !d.shape.empty() ) throw Error( "badDescriptor" , where( line ) + "two {shape} in " + value );
      for( auto &w : split_ws( t.text ) ) d.shape.push_back( to_int( w , "{shape}" , line ) );
      continue;
    }
    const std::string &w = t.text;
    Type ty = type_from( w );
    if( ty != Type::none ){ if( d.type != Type::none ) throw Error( "badDescriptor" , where( line ) + "two types in " + value ); d.type = ty; continue; }
    if( w[0] == '@' ){
      // @a  |  @a+longitud  |  @a+Inf  |  @a:b (INCLUSIVO, [a,b], como MATLAB)  |  @a:EOF
      std::string body = w.substr( 1 );
      size_t p = body.find_first_of( "+:" );
      d.offset = to_int( body.substr( 0 , p ) , "offset" , line );
      if( p != std::string::npos ){
        std::string rest = body.substr( p + 1 );
        if( body[p] == '+' ){
          d.length = rest == "Inf" ? Descriptor::LEN_EOF : to_int( rest , "length" , line );
        } else {
          if( rest == "EOF" ) d.length = Descriptor::LEN_EOF;
          else {
            int64_t e = to_int( rest , "end offset" , line );
            if( e < d.offset ) throw Error( "badDescriptor" , where( line ) + "@a:b with b < a in " + value );
            d.length = e - d.offset + 1;           // b es el ULTIMO byte del bloque
          }
        }
      }
      if( d.offset < 0 || ( d.length < 0 && d.length != -1 && d.length != Descriptor::LEN_EOF ) )
        throw Error( "badDescriptor" , where( line ) + "negative offset or length in " + value );
      continue;
    }
    // (no hay 'order': los bytes de un bloque van SIEMPRE en i j k t c, i el mas
    // rapido -- SPEC 5.3, decidido 2026-10-13. Un 'order' es un token desconocido)
    if( w == "crc" ){
      // 8 cifras hexadecimales: el CRC-32 de zlib de los bytes DECODIFICADOS del bloque
      if( i + 1 >= T.size() ) throw Error( "badDescriptor" , where( line ) + "crc needs 8 hex digits" );
      const std::string &h = T[i+1].text;
      unsigned long v = 0;
      auto r = std::from_chars( h.data() , h.data() + h.size() , v , 16 );
      if( h.size() != 8 || r.ec != std::errc() || r.ptr != h.data() + h.size() )
        throw Error( "badDescriptor" , where( line ) + "crc needs 8 hex digits, not '" + h + "'" );
      d.has_crc = true;  d.crc = (uint32_t)v;
      i += 1;  continue;
    }
    // (no hay 'rescale' por bloque: UNO para todo el stack, la clave rescale --
    // SPEC 6, decidido 2026-10-13. Aqui es un token desconocido)
    if( w == "frames" ){
      if( i + 1 >= T.size() ) throw Error( "badDescriptor" , where( line ) + "frames needs a:b" );
      // frames a:b, 1-based, a <= b. Un 0 o un negativo NO es "todos": antes
      // 'frames 0:0' leia el fichero entero sin decir nada
      const std::string &f = T[i+1].text;  size_t p = f.find( ':' );
      auto fr = [&]( const std::string &x ){
        if( x.empty() || x.find_first_not_of( "0123456789" ) != std::string::npos )
          throw Error( "badDescriptor" , where( line ) + "frames is a:b, 1-based, not '" + f + "'" );
        return to_int( x , "frames" , line );
      };
      d.frame_lo = fr( f.substr( 0 , p ) );
      d.frame_hi = p == std::string::npos ? d.frame_lo : fr( f.substr( p + 1 ) );
      if( d.frame_lo < 1 || d.frame_hi < d.frame_lo ) throw Error( "badDescriptor" , where( line ) + "frames is a:b with 1 <= a <= b, not '" + f + "'" );
      i += 1;  continue;
    }
    throw Error( "badDescriptor" , where( line ) + "unknown token '" + w + "' in " + value );
  }
  // frames solo significa algo en un <dicom>: en otro se ignoraria en silencio
  if( d.frame_lo != -1 && d.encoding != "dicom" )
    throw Error( "badDescriptor" , where( line ) + "frames is for <dicom> only: " + value );
  return d;
}

// ====================================================================== cabecera
// Tope para lo oculto (L) y para lo inflado: una cabecera de 1 GiB ya no es una
// cabecera, y un fichero roto no tiene que poder pedir memoria sin fin
static const uint64_t MAXH = 1ull << 30;

// Las dos ofuscaciones: la de la cabecera I3Db (SPEC 1.1) y la de un bloque
// <hidden> (SPEC 1.2). El MISMO procedimiento, cada una con SUS constantes (no
// comparten la secuencia k): r(i) = NOT( hidden(i) XOR k(i) ) con
// k(i) = ((i*mult + seed) mod 2^32 >> 8) & 0xFF, y r es el flujo zlib AL REVES
// (su cabecera fija no queda al principio ni en una posicion fija de k).
// Despues se infla. El texto sale con las lineas en LF. 'what': para los mensajes
// crc: si no es NULL, el CRC-32 de los bytes INFLADOS tal cual, antes de tocar
// los finales de linea (el de un bloque: de lo decodificado, SPEC 4)
struct Obfuscation { uint32_t mult , seed; bool reversed; };
static const Obfuscation OBF_I3DB   = { 0x5C2D8F1Bu , 0x49334462u , true };   // "I3Db"
static const Obfuscation OBF_HIDDEN = { 0x7A3F5C29u , 0x68696464u , true };   // "hidd"
static std::string unhide_inflate( std::vector<uint8_t> h , const Obfuscation &o , const std::string &what , uint32_t *crc = nullptr ){
  for( uint64_t i = 0 ; i < h.size() ; i++ ){
    uint32_t x = (uint32_t)i * o.mult + o.seed;                      // mod 2^32: aritmetica de uint32
    h[(size_t)i] = (uint8_t)~( h[(size_t)i] ^ (uint8_t)( ( x >> 8 ) & 0xFFu ) );
  }
  if( o.reversed ) std::reverse( h.begin() , h.end() );
#ifdef I3D_HAVE_ZLIB
  // Inflar POR TRAMOS: el tamano inflado no esta en el fichero. El flujo zlib
  // sabe donde acaba y su Adler-32 comprueba lo inflado. Y tiene que ocupar
  // EXACTAMENTE los bytes que tiene: ni corto, ni con bytes de mas detras
  std::string raw;
  z_stream zs{};
  if( inflateInit( &zs ) != Z_OK ) throw Error( "internal" , "inflateInit failed" );
  zs.next_in = h.data();  zs.avail_in = (uInt)h.size();
  std::vector<char> chunk( 1 << 16 );
  int z = Z_OK;
  for( ;; ){
    zs.next_out = (Bytef*)chunk.data();  zs.avail_out = (uInt)chunk.size();
    z = inflate( &zs , Z_NO_FLUSH );
    raw.append( chunk.data() , chunk.size() - zs.avail_out );
    if( z == Z_STREAM_END ) break;
    if( z != Z_OK || ( zs.avail_in == 0 && zs.avail_out != 0 ) || raw.size() > MAXH ) break;
  }
  const bool trailing = zs.avail_in != 0;
  inflateEnd( &zs );
  if( raw.size() > MAXH ) throw Error( "badHeader" , what + " inflates to more than 1 GiB" );
  if( z != Z_STREAM_END ) throw Error( "badHeader" , what + " does not inflate (zlib " + std::to_string( z ) + ")" );
  if( trailing ) throw Error( "badHeader" , what + " has bytes after its zlib stream" );
  if( crc ) *crc = (uint32_t)crc32( crc32( 0L , Z_NULL , 0 ) , (const Bytef*)raw.data() , (uInt)raw.size() );
  std::string text , l;
  std::istringstream is( raw );
  while( std::getline( is , l ) ){ if( !l.empty() && l.back() == '\r' ) l.pop_back(); text += l;  text += '\n'; }
  return text;
#else
  throw Error( "unsupportedEncoding" , what + " needs zlib (compiled without it)" );
#endif
}

// SPEC 1: la cabecera es UTF-8 (las claves, ASCII). Una secuencia invalida -- un
// Latin-1 escrito a mano, bytes sueltos -- es un error, no texto basura.
// RFC 3629, tabla 3.9 de Unicode: sin formas largas (C0 C1, E0 80-9F, F0 80-8F),
// sin surrogates (ED A0-BF) y nada por encima de U+10FFFF (F4 90-BF, F5-FF). Lo
// mismo que rechaza el decodificador de Python. sign: -1 en la parte <hidden>
static void check_utf8( const std::string &t , const std::string &what , int sign ){
  int line = 1;
  for( size_t i = 0 ; i < t.size() ; ){
    const unsigned char c = (unsigned char)t[i];
    if( c == '\n' ){ line++; i++; continue; }
    int n = c < 0x80 ? 1 : ( c >= 0xC2 && c <= 0xDF ) ? 2 : ( c >= 0xE0 && c <= 0xEF ) ? 3 : ( c >= 0xF0 && c <= 0xF4 ) ? 4 : 0;
    bool ok = n > 0 && i + n <= t.size();
    for( int k = 1 ; ok && k < n ; k++ ){
      const unsigned char b = (unsigned char)t[i+k];
      unsigned char lo = 0x80 , hi = 0xBF;                 // el rango del 2o byte depende del 1o
      if( k == 1 ){
        if( c == 0xE0 ) lo = 0xA0;
        else if( c == 0xED ) hi = 0x9F;
        else if( c == 0xF0 ) lo = 0x90;
        else if( c == 0xF4 ) hi = 0x8F;
      }
      ok = b >= lo && b <= hi;
    }
    if( !ok ) throw Error( "badHeader" , where( sign * line ) + "the header is not valid UTF-8 (SPEC 1) in " + what );
    i += n;
  }
}

// Un fichero se lee por una VENTANA [base, base+size): el fichero entero (base 0,
// size -1: hasta el final) o un miembro de un .mi3d (SPEC 14). Todo lo que se
// compara con "el tamano del fichero" se compara con size. Deja f en base
static std::ifstream open_window( const std::string &path , int64_t base , int64_t &size ){
  std::ifstream f( native_( path ) , std::ios::binary );
  if( !f ) throw Error( "cannotOpen" , "cannot open '" + path + "'" );
  f.seekg( 0 , std::ios::end );
  const int64_t fsize = (int64_t)f.tellg();
  if( size < 0 ) size = fsize - base;
  if( base < 0 || base > fsize || size < 0 || size > fsize - base )
    throw Error( "truncated" , "'" + path + "' ends before the bytes asked for" );
  f.seekg( base );
  return f;
}

// La cabecera en texto: hasta la PRIMERA linea que es exactamente --- (CR
// opcional), sin salir de la ventana. b0: donde empieza el binario, desde base
static std::string read_text_header( std::ifstream &f , int64_t size , const std::string &path , int64_t &b0 ){
  std::string line , text;  int64_t pos = 0;
  while( std::getline( f , line ) ){
    if( pos + (int64_t)line.size() > size ) break;            // se sale de la ventana
    pos += (int64_t)line.size() + 1;
    if( !line.empty() && line.back() == '\r' ) line.pop_back();
    if( line == "---" ){ b0 = std::min( pos , size ); return text; }   // --- al final, sin LF: binario vacio
    text += line;  text += '\n';
  }
  throw Error( "badHeader" , "no terminator line '---' in '" + path + "'" );
}

// Los bytes [off, off+len) de la ventana, comprobados contra ella ANTES de
// reservar. len LEN_EOF: hasta el final de la ventana
static std::vector<uint8_t> read_window( const std::string &path , int64_t base , int64_t size , int64_t off , int64_t len , const std::string &what ){
  if( len == Descriptor::LEN_EOF ) len = size - off;
  if( off < 0 || off > size || len < 0 || len > size - off ) throw Error( "truncated" , "the file ends inside " + what );
  int64_t s = -1;
  std::ifstream f = open_window( path , base , s );
  std::vector<uint8_t> buf( (size_t)len );
  f.seekg( base + off );
  f.read( (char*)buf.data() , (std::streamsize)len );
  if( f.gcount() != len ) throw Error( "truncated" , "the file ends inside " + what );
  return buf;
}

File::File( const std::string &path , const std::map<std::string,std::string> &overrides ) : path_( path ) , base_( 0 ) , size_( -1 ){
  open_( overrides );
}

File::File( const std::string &path , const std::map<std::string,std::string> &overrides , int64_t base , int64_t size ) : path_( path ) , base_( base ) , size_( size ){
  if( base < 0 || size < 0 ) throw Error( "badInput" , "a member is a window base >= 0, size >= 0" );
  open_( overrides );
}

void File::open_( const std::map<std::string,std::string> &overrides ){
  const std::string &path = path_;
  std::ifstream f = open_window( path , base_ , size_ );

  char magic[4] = { 0 , 0 , 0 , 0 };
  f.read( magic , 4 );
  if( f.gcount() == 4 && size_ >= 4 && !std::memcmp( magic , "I3Db" , 4 ) ){
    // SPEC 1.1: la variante OCULTA. "I3Db" | L | cabecera ofuscada | binario
    uint8_t len[8];
    f.read( (char*)len , 8 );
    if( f.gcount() != 8 || size_ < 12 ) throw Error( "badHeader" , "truncated I3Db preamble in '" + path + "'" );
    uint64_t L = 0;
    for( int b = 7 ; b >= 0 ; b-- ) L = ( L << 8 ) | len[b];   // little-endian
    if( L == 0 || L > MAXH ) throw Error( "badHeader" , "implausible hidden header length in '" + path + "'" );
    // L contra lo que el fichero TIENE, antes de reservar: 20 bytes no pueden
    // pedir 1 GiB
    if( L > (uint64_t)size_ - 12 ) throw Error( "truncated" , "the file ends inside the hidden header: '" + path + "'" );
    std::vector<uint8_t> h( (size_t)L );
    f.read( (char*)h.data() , (std::streamsize)L );
    if( (uint64_t)f.gcount() != L ) throw Error( "truncated" , "the file ends inside the hidden header: '" + path + "'" );
    header_ = unhide_inflate( std::move( h ) , OBF_I3DB , "the hidden header of '" + path + "'" );
    hidden_ = true;
    b0_ = 12 + (int64_t)L;
  } else {
    if( f.gcount() == 4 && !std::memcmp( magic , "MI3D" , 4 ) )
      throw Error( "badMagic" , "'" + path + "' is a .mi3d container, not an .i3d: open one of its members (SPEC 14)" );
    f.clear();  f.seekg( base_ );
    header_ = read_text_header( f , size_ , path , b0_ );
  }

  check_utf8( header_ , "'" + path + "'" , +1 );
  parse_header_();
  for( auto &kv : overrides ) vars_[ "$" + kv.first + "$" ] = kv.second;   // mandan
  build_data_();
}

std::string File::resolve_path( const std::string &p0 ) const {
  // $NOMBRE$ -> su valor, que entra TAL CUAL (no se vuelve a mirar); $$ -> un $
  // literal (SPEC 2, decidido 2026-10-23: \\srv\C$\... se escribe C$$); un $ sin
  // pareja es un error. Una variable que no existe, error AL PEDIR el bloque
  std::string p;
  for( size_t i = 0 ; i < p0.size() ; ){
    if( p0[i] != '$' ){ p += p0[i++]; continue; }
    if( i + 1 < p0.size() && p0[i+1] == '$' ){ p += '$';  i += 2;  continue; }
    const size_t b = p0.find( '$' , i + 1 );
    if( b == std::string::npos ) throw Error( "badVariable" , "unclosed $ in path '" + p0 + "' (a literal $ is $$)" );
    const std::string name = p0.substr( i , b - i + 1 );
    auto it = vars_.find( name );
    if( it == vars_.end() ) throw Error( "badVariable" , "undefined variable " + name + " in path '" + p0 + "'" );
    p += it->second;
    i = b + 1;
  }
  for( auto &c : p ) if( c == '\\' ) c = '/';
  bool absolute = ( p.size() > 2 && isalpha( (unsigned char)p[0] ) && p[1] == ':' ) || ( !p.empty() && p[0] == '/' );
  if( !absolute ){
    std::string dir = path_;  for( auto &c : dir ) if( c == '\\' ) c = '/';
    size_t s = dir.find_last_of( '/' );
    dir = s == std::string::npos ? "" : dir.substr( 0 , s + 1 );
    p = dir + p;
  }
  return p;
}

// las claves que v0 interpreta (SPEC 2-7); el resto son desconocidas y se ignoran
static bool known_key( const std::string &k ){
  static const char *K[] = { "X" , "Y" , "Z" , "T" , "transform" , "rescale" , "window" , "fill" , "data" , "header" };
  for( auto s : K ) if( k == s ) return true;
  return k[0] == '$' || !k.compare( 0 , 4 , "aux." ) || !k.compare( 0 , 5 , "info." );
}

// Las lineas de una cabecera -> sus entradas. magic: la primera linea, 'I3D 0.1'
// (o 'MI3D 0.1', SPEC 14); NULL, es el texto de una parte <hidden>, cuyas
// lineas se numeran en negativo (sign = -1) para los mensajes
static std::vector<Entry> parse_lines( const std::string &text , const char *magic , int sign ){
  std::vector<Entry> entries_;
  std::istringstream is( text );
  std::string raw;  int n = 0;
  while( std::getline( is , raw ) ){
    n++;
    const int ln = sign * n;
    if( n == 1 && magic ){
      // EMPIEZA por 'I3D 0.1', sin nada delante (SPEC 1: los 4 primeros bytes son
      // la firma, 'I3D ' o 'I3Db', y un visor detecta el formato por ellos), y
      // puede seguir un comentario: 'I3D 0.1  # ...'
      const size_t m = std::strlen( magic );
      if( raw.compare( 0 , m , magic ) != 0 || !trim( strip_comment( raw.substr( std::min( m , raw.size() ) ) ) ).empty() )
        throw Error( "badMagic" , std::string( "the first line must be '" ) + magic + "', not '" + raw + "'" );
      continue;
    }
    std::string s = strip_comment( raw );
    if( trim( s ).empty() ) continue;
    if( raw[0] == ' ' || raw[0] == '\t' ){              // continuacion
      if( entries_.empty() ) throw Error( "badHeader" , where( ln ) + "a continuation line with no entry before it" );
      Entry &e = entries_.back();
      e.value += ( e.value.empty() ? "" : " " ) + trim( s );
      continue;
    }
    Entry e;  e.line = ln;
    size_t i = 0;
    if( s[0] == '$' ){                                   // $NOMBRE$ = "valor"
      size_t c = s.find( '$' , 1 );
      if( c == std::string::npos ) throw Error( "badHeader" , where( ln ) + "unclosed $ in a variable name" );
      i = c + 1;
      for( size_t q = 1 ; q < c ; q++ ) if( !( isalnum( (unsigned char)s[q] ) || s[q] == '_' ) )
        throw Error( "badHeader" , where( ln ) + "a variable name is $[A-Za-z0-9_]+$" );
    } else {
      while( i < s.size() && ( isalnum( (unsigned char)s[i] ) || s[i] == '_' || s[i] == '.' ) ) i++;
    }
    e.key = s.substr( 0 , i );
    if( e.key.empty() ) throw Error( "badHeader" , where( ln ) + "expected a key: " + raw );
    if( i < s.size() && s[i] == '[' ){                   // anotacion para humanos: se SALTA
      size_t c = s.find( ']' , i );  if( c == std::string::npos ) throw Error( "badHeader" , where( ln ) + "unclosed [" );
      i = c + 1;
    }
    if( i < s.size() && s[i] == '(' ){                   // subindices
      size_t c = s.find( ')' , i );  if( c == std::string::npos ) throw Error( "badHeader" , where( ln ) + "unclosed (" );
      e.subs = s.substr( i + 1 , c - i - 1 );  e.paren = true;  i = c + 1;
    }
    while( i < s.size() && ( s[i] == ' ' || s[i] == '\t' ) ) i++;
    if( i >= s.size() || s[i] != '=' ) throw Error( "badHeader" , where( ln ) + "expected '=' after '" + e.key + "'" );
    e.value = trim( s.substr( i + 1 ) );
    // ( ) (SPEC 2): en data, la parte que asigna. En una clave CONOCIDA que no es
    // data es un error: se ignoraria en silencio, y quien lo escribio cree que
    // dice algo. En una clave DESCONOCIDA se ignora como toda clave desconocida:
    // asi un lector v0 abre un fichero de una version que anada arrays
    // asignados por bloques (labels(:,:,:,1) = ..., SPEC 8)
    if( e.paren && e.key != "data" && known_key( e.key ) )
      throw Error( "badHeader" , where( ln ) + "only data takes a ( ) subscript, not '" + e.key + "'" );
    entries_.push_back( e );
  }
  return entries_;
}

// SPEC 1.2: una PARTE de la cabecera oculta, 'header = <hidden @a:b>'. Sus
// lineas se leen como si estuvieran escritas en el sitio de esa entrada. Un solo
// nivel: dentro no puede haber otro 'header'. La cabecera en texto NO cambia: lo
// que se vuelca (i3d_header, i3dinfo --header, showI3Dfile) sigue sin mostrarla.
// La ventana del fichero (base, size) y su binario (b0): la de un .i3d, la de un
// miembro o la de un .mi3d (SPEC 14.3)
static void expand_hidden( std::vector<Entry> &E , const std::string &path , int64_t base , int64_t size , int64_t b0 ){
  size_t at = E.size();
  for( size_t q = 0 ; q < E.size() ; q++ ) if( E[q].key == "header" ){
    if( at != E.size() ) throw Error( "badHeader" , where( E[q].line ) + "repeated key 'header'" );
    at = q;
  }
  if( at == E.size() ) return;
  const Entry h = E[at];
  const Descriptor d = File::parse_descriptor( h.value , h.line );
  if( d.encoding != "hidden" )
    throw Error( "badDescriptor" , where( h.line ) + "header takes a <hidden @a:b> descriptor, not " + h.value );
  if( d.type != Type::none || !d.shape.empty() || !d.path.empty() || d.offset < 0 || d.length == -1 )
    throw Error( "badDescriptor" , where( h.line ) + "<hidden> is <hidden @a:b>: where its bytes are, nothing else: " + h.value );
  // dentro del fichero ANTES de reservar, como cualquier bloque
  const int64_t L = d.length == Descriptor::LEN_EOF ? size - ( b0 + d.offset ) : d.length;
  if( d.offset > size - b0 || L < 0 || L > size - b0 - d.offset )
    throw Error( "truncated" , where( h.line ) + "the file ends inside the <hidden> part of the header" );
  if( L == 0 || (uint64_t)L > MAXH ) throw Error( "badHeader" , where( h.line ) + "implausible length of the <hidden> part of the header" );
  std::vector<uint8_t> buf = read_window( path , base , size , b0 + d.offset , L , "the <hidden> part of the header" );
  uint32_t c = 0;
  const std::string text = unhide_inflate( std::move( buf ) , OBF_HIDDEN , where( h.line ) + "the <hidden> part of the header" , &c );
  check_utf8( text , "the <hidden> part of the header" , -1 );
  // el crc es opcional (el escritor no lo pone, SPEC 1.2); si esta, se cumple
  if( d.has_crc && c != d.crc ) throw Error( "badCRC" , where( h.line ) + "the <hidden> part of the header fails its crc" );
  auto H = parse_lines( text , nullptr , -1 );
  for( auto &e : H ) if( e.key == "header" )
    throw Error( "badHeader" , where( e.line ) + "a <hidden> part of the header cannot hold another 'header'" );
  E.insert( E.begin() + (std::ptrdiff_t)at + 1 , H.begin() , H.end() );
}

void File::parse_header_(){
  entries_ = parse_lines( header_ , "I3D 0.1" , +1 );
  expand_hidden( entries_ , path_ , base_ , size_ , b0_ );

  // claves sin ( ) aparecen una vez
  for( size_t a = 0 ; a < entries_.size() ; a++ ){
    if( entries_[a].key == "data" ) continue;
    for( size_t b = a + 1 ; b < entries_.size() ; b++ )
      if( entries_[b].key == entries_[a].key && !entries_[b].paren && !entries_[a].paren )
        throw Error( "badHeader" , where( entries_[b].line ) + "repeated key '" + entries_[a].key + "'" );
  }

  for( char g : { 'X' , 'Y' , 'Z' , 'T' } ){
    const Entry *e = find( std::string( 1 , g ) );
    if( !e ) throw Error( "badHeader" , std::string( "missing grid " ) + g );
    if( e->paren ) throw Error( "badGrid" , where( e->line ) + "a grid takes no ( ) subscript" );
    auto v = parse_grid( e->key , e->value , e->line );
    ( g == 'X' ? X_ : g == 'Y' ? Y_ : g == 'Z' ? Z_ : T_ ) = v;
  }

  // transform (SPEC 3.2): ausente = identidad; 3 numeros = traslacion pura;
  // 12 = las tres primeras filas. La cuarta es siempre 0 0 0 1
  A_ = { 1.0,0.0,0.0,0.0 , 0.0,1.0,0.0,0.0 , 0.0,0.0,1.0,0.0 , 0.0,0.0,0.0,1.0 };
  const Entry *e = find( "transform" );
  if( e ){
    auto a = parse_numbers( e->value , "transform" , e->line );
    if( a.size() == 3 ){ A_[3] = a[0];  A_[7] = a[1];  A_[11] = a[2]; }
    else if( a.size() == 12 ){ for( int k = 0 ; k < 12 ; k++ ) A_[k] = a[k]; }
    else throw Error( "badTransform" , where( e->line ) + "transform needs 3 numbers (a translation) or 12 (3 rows of 4), not " + std::to_string( a.size() ) );
  }

  if( ( e = find( "rescale" ) ) ){
    auto r = parse_numbers( e->value , "rescale" , e->line );
    if( r.size() != 2 ) throw Error( "badHeader" , where( e->line ) + "rescale = SLOPE INTERCEPT" );
    slope_ = r[0];  intercept_ = r[1];
  }
  if( ( e = find( "window" ) ) ){
    auto r = parse_numbers( e->value , "window" , e->line );
    if( r.size() != 2 ) throw Error( "badHeader" , where( e->line ) + "window = CENTER WIDTH" );
    has_window_ = true;  wc_ = r[0];  ww_ = r[1];
  }
  if( ( e = find( "fill" ) ) ){ has_fill_ = true;  fill_text_ = e->value; }

  // variables: su valor es una cadena entre comillas
  for( auto &v : entries_ ){
    if( v.key.empty() || v.key[0] != '$' ) continue;
    const std::string &x = v.value;
    if( x.size() < 2 || x.front() != '"' || x.back() != '"' ) throw Error( "badHeader" , where( v.line ) + v.key + " must be a quoted string" );
    std::string out;
    const std::string in = x.substr( 1 , x.size() - 2 );
    for( size_t q = 0 ; q < in.size() ; q++ ){ if( is_escape( in , q ) ) q++; out += in[q]; }
    vars_[ v.key ] = out;
  }
}

const Entry *File::find( const std::string &key ) const {
  for( auto &e : entries_ ) if( e.key == key ) return &e;
  return nullptr;
}

const std::vector<double> &File::grid( char axis ) const {
  switch( axis ){ case 'X': return X_; case 'Y': return Y_; case 'Z': return Z_; case 'T': return T_; }
  throw Error( "badAxis" , std::string( "no grid " ) + axis );
}

// ====================================================================== data
// un subindice de SPEC 2, sin resolver todavia: lo (1-based) / hi (1-based, incl.) o -1 si abierto
struct Sub { int64_t lo = -1 , hi = -1; bool all = false; };

// un indice de subindice (SPEC 2): cifras y nada mas, >= 1. Ni signo -- '1:-1'
// se leia como '1:', porque -1 es la marca interna de "abierto" --, ni vacio
static int64_t to_index( const std::string &t , const std::string &p , int line ){
  if( t.empty() || t.find_first_not_of( "0123456789" ) != std::string::npos )
    throw Error( "badSubscript" , where( line ) + "a subscript is a positive integer, not '" + p + "'" );
  int64_t v = to_int( t , "subscript" , line );
  if( v < 1 ) throw Error( "badSubscript" , where( line ) + "subscripts are 1-based: '" + p + "'" );
  return v;
}

static Sub parse_sub( std::string p , int line ){
  p = trim( p );  Sub s;
  if( p.empty() ) throw Error( "badSubscript" , where( line ) + "an empty subscript (data() or a stray ',')" );
  if( p == ":" ){ s.all = true; return s; }
  size_t c = p.find( ':' );
  if( c == std::string::npos ){ s.lo = s.hi = to_index( p , p , line ); return s; }
  std::string a = trim( p.substr( 0 , c ) ) , b = trim( p.substr( c + 1 ) );
  if( b.find( ':' ) != std::string::npos ) throw Error( "badSubscript" , where( line ) + "no steps in a subscript: " + p );
  s.lo = a.empty() ? 1 : to_index( a , p , line );
  s.hi = b.empty() ? -1 : to_index( b , p , line );
  return s;
}

static Range resolve( const Sub &s , int64_t n , int line ){
  Range r;
  if( s.all ){ r.lo = 0; r.hi = n; return r; }
  int64_t lo = s.lo , hi = s.hi < 0 ? n : s.hi;
  if( !( 1 <= lo && lo <= hi && hi <= n ) )
    throw Error( "badSubscript" , where( line ) + "subscript " + std::to_string( lo ) + ":" + std::to_string( hi ) + " outside 1.." + std::to_string( n ) );
  r.lo = lo - 1;  r.hi = hi;
  return r;
}

void File::build_data_(){
  struct Raw { std::vector<Sub> sub; Descriptor d; int line; };
  std::vector<Raw> R;
  size_t ncd = 0;
  for( auto &e : entries_ ){
    if( e.key != "data" ) continue;
    Raw r;  r.line = e.line;
    std::vector<Sub> s;
    if( e.paren ){
      // a mano y no con getline: getline se come el trozo vacio de 'data(:,:,1,)'
      for( size_t s0 = 0 ;; ){
        const size_t c = e.subs.find( ',' , s0 );
        s.push_back( parse_sub( e.subs.substr( s0 , c == std::string::npos ? std::string::npos : c - s0 ) , e.line ) );
        if( c == std::string::npos ) break;
        s0 = c + 1;
      }
    }
    // SPEC 5.2: si falta i, j o k vale ':'; si falta t vale 1 (y un componente,
    // abajo, tambien 1). Asi  data = <...>  es data(:,:,:,1). Nunca el plegado
    // de dimensiones de MATLAB
    while( s.size() < 3 ){ Sub a; a.all = true; s.push_back( a ); }
    if( s.size() < 4 ){ Sub a; a.lo = a.hi = 1; s.push_back( a ); }
    r.sub = s;
    r.d = parse_descriptor( e.value , e.line );
    ncd = std::max( ncd , s.size() - 4 );
    R.push_back( r );
  }
  if( R.empty() ) throw Error( "badData" , "no data entries" );

  // un subindice de componente que falta vale 1
  for( auto &r : R ) while( r.sub.size() < 4 + ncd ){ Sub a; a.lo = a.hi = 1; r.sub.push_back( a ); }

  // extension de cada dimension de componente: el mayor indice que alguien usa
  std::vector<int64_t> cext( ncd , 0 );
  for( size_t c = 0 ; c < ncd ; c++ )
    for( auto &r : R ){ const Sub &s = r.sub[4+c]; if( !s.all ) cext[c] = std::max( cext[c] , std::max( s.lo , s.hi ) ); }
  for( size_t c = 0 ; c < ncd ; c++ )
    if( cext[c] < 1 ) throw Error( "badData" , "the extent of component dimension " + std::to_string( 5 + c ) + " is not determined by any entry" );

  shape_ = { (int64_t)X_.size() , (int64_t)Y_.size() , (int64_t)Z_.size() , (int64_t)T_.size() };
  shape_.insert( shape_.end() , cext.begin() , cext.end() );
  const size_t nd = shape_.size();

  // el numero de elementos, y sus bytes en el tipo mas ancho, sin desbordar
  int64_t total = 1;
  for( auto n : shape_ ){
    if( n > ( int64_t( 1 ) << 59 ) / total ) throw Error( "badData" , "data would have more than 2^59 elements" );
    total *= n;
  }
  int64_t covered = 0;
  type_ = Type::none;
  for( auto &r : R ){
    Block b;  b.line = r.line;  b.desc = r.d;
    for( size_t d = 0 ; d < nd ; d++ ) b.box.push_back( resolve( r.sub[d] , shape_[d] , r.line ) );
    int64_t vol = 1;  for( auto &x : b.box ) vol *= ( x.hi - x.lo );
    covered += vol;

    const Descriptor &D = b.desc;
    // un <missing> no tiene dato que proteger: un crc ahi diria algo que no se
    // comprueba nunca
    if( D.encoding == "missing" && D.has_crc ) throw Error( "badDescriptor" , where( r.line ) + "<missing> takes no crc: it has no data" );
    // <png> y <gif> son de aux (SPEC 4): un bloque de data asi no es v0
    if( D.encoding == "png" || D.encoding == "gif" )
      throw Error( "badDescriptor" , where( r.line ) + "<" + D.encoding + "> is for aux only, not for a data block" );
    // y <hidden> es de la clave header (SPEC 1.2)
    if( D.encoding == "hidden" ) throw Error( "badDescriptor" , where( r.line ) + "<hidden> is for the key header only" );
    if( D.encoding == "dicom" && ( b.box[0].lo != 0 || b.box[0].hi != shape_[0] || b.box[1].lo != 0 || b.box[1].hi != shape_[1] ) )
      throw Error( "badData" , where( r.line ) + "a <dicom> block is made of whole i,j planes" );
    if( D.encoding == "dicom" && ( D.type == Type::none || D.path.empty() ) )
      throw Error( "badDescriptor" , where( r.line ) + "<dicom> needs a type and a \"path\"" );
    if( ( D.encoding == "raw" || D.encoding == "zlib" ) && ( D.type == Type::none || D.offset < 0 ) )
      throw Error( "badDescriptor" , where( r.line ) + "<" + D.encoding + "> needs a type and @offset" );
    if( D.encoding == "zlib" && D.length == -1 ) throw Error( "badDescriptor" , where( r.line ) + "<zlib> needs its length: @a+n , @a:b , @a+Inf or @a:EOF" );
    if( D.encoding == "jpegls" ){
      // SPEC 4: planos i,j ENTEROS (cualquier tramo de k, t y componentes), en
      // (u)int8 o (u)int16: una imagen de ni x (nj * planos), los planos apilados
      if( D.type != Type::uint8 && D.type != Type::int8 && D.type != Type::uint16 && D.type != Type::int16 )
        throw Error( "badDescriptor" , where( r.line ) + "<jpegls> holds uint8, int8, uint16 or int16, not " + type_name( D.type ) );
      if( D.offset < 0 || D.length == -1 ) throw Error( "badDescriptor" , where( r.line ) + "<jpegls> needs @a:b (or @a+n, @a:EOF)" );
      if( b.box[0].lo != 0 || b.box[0].hi != shape_[0] || b.box[1].lo != 0 || b.box[1].hi != shape_[1] )
        throw Error( "badData" , where( r.line ) + "a <jpegls> block is made of whole i,j planes" );
      // y su imagen, como mucho 65535 x 65535: mas grande necesita la extension
      // LSE de dimensiones grandes, que CharLS 2.4.5 lee pero no el CharLS del
      // navegador ni el de imagecodecs (MEDIDO 2026-10-14). Un fichero que este
      // lector aceptara y esos no, no se acepta
      int64_t rows = 1;  for( size_t d = 1 ; d < nd ; d++ ) rows *= b.box[d].hi - b.box[d].lo;
      if( shape_[0] > 65535 || rows > 65535 )
        throw Error( "badData" , where( r.line ) + "a <jpegls> image is " + std::to_string( shape_[0] ) + " x " + std::to_string( rows ) + "; at most 65535 x 65535" );
    }
    if( !D.shape.empty() ){
      // {shape} en un bloque de data: tiene que coincidir con el subindice
      for( size_t d = 0 ; d < std::max( D.shape.size() , nd ) ; d++ ){
        int64_t a = d < D.shape.size() ? D.shape[d] : 1 , c = d < nd ? b.box[d].hi - b.box[d].lo : 1;
        if( a != c ) throw Error( "badDescriptor" , where( r.line ) + "{shape} does not match the subscript" );
      }
    }
    if( D.encoding != "missing" ) type_ = promote( type_ , D.type );
    blocks_.push_back( b );
  }
  if( type_ == Type::none ) throw Error( "badData" , "no block declares a type" );

  // COBERTURA exacta (SPEC 5.5): ningun par se solapa y los volumenes suman el
  // total. Las dos juntas son "cada elemento exactamente una vez", sin un mapa
  // de bits del tamano del volumen
  for( size_t a = 0 ; a < blocks_.size() ; a++ )
    for( size_t c = a + 1 ; c < blocks_.size() ; c++ ){
      bool over = true;
      for( size_t d = 0 ; d < nd && over ; d++ )
        over = blocks_[a].box[d].lo < blocks_[c].box[d].hi && blocks_[c].box[d].lo < blocks_[a].box[d].hi;
      if( over ) throw Error( "coverage" , "data blocks of lines " + std::to_string( blocks_[a].line ) + " and " + std::to_string( blocks_[c].line ) + " overlap" );
    }
  if( covered != total )
    throw Error( "coverage" , "data blocks cover " + std::to_string( covered ) + " of " + std::to_string( total ) + " elements" );

  // fill: en el tipo de data (SPEC 5.5)
  if( has_fill_ ){
    const int fl = find( "fill" )->line;
    if( is_float( type_ ) ) fill_ = to_double( trim( fill_text_ ) , "fill" , fl );
    else {
      ifill_ = to_int( trim( fill_text_ ) , "fill" , fl );
      // que QUEPA en el tipo de data: si no, al copiar sus bytes bajos se
      // convertiria en otro numero sin avisar (70000 en int16 = 4464)
      const int bits = bits_of( type_ );
      const bool sg = is_signed( type_ );
      bool fits;
      if( bits == 64 ) fits = sg || ifill_ >= 0;      // uint64: solo hasta 2^63-1 (to_int lee int64)
      else if( sg )    fits = ifill_ >= -( int64_t( 1 ) << ( bits - 1 ) ) && ifill_ < ( int64_t( 1 ) << ( bits - 1 ) );
      else             fits = ifill_ >= 0 && ifill_ < ( int64_t( 1 ) << bits );
      if( !fits ) throw Error( "badHeader" , where( fl ) + "fill " + std::to_string( ifill_ ) + " does not fit in " + type_name( type_ ) );
    }
  } else {
    fill_ = std::numeric_limits<double>::quiet_NaN();  ifill_ = 0;
  }
}

size_t File::data_bytes() const {
  size_t n = type_size( type_ );  for( auto s : shape_ ) n *= (size_t)s;
  return n;
}

std::vector<const Block*> File::missing() const {
  std::vector<const Block*> m;
  for( auto &b : blocks_ ) if( b.desc.encoding == "missing" ) m.push_back( &b );
  return m;
}

// ====================================================================== bytes de un bloque
// Los bytes decodificados, y el crc sobre ELLOS (SPEC 4, decidido 2026-10-14): lo
// que protege es el DATO, no su forma en el fichero. Asi tambien lo puede llevar
// un <dicom>, y un decodificador que se equivoca -- la CharLS de DCMTK, el signo
// de dicomread, un JPEG-LS near-lossless -- no pasa el crc. El precio: lo corrupto
// llega al decodificador antes de detectarse, que por eso tiene que ser robusto
std::vector<uint8_t> File::read_bytes( const Descriptor &d , size_t expected ) const {
  std::vector<uint8_t> out = decode_( d , expected );
  if( d.has_crc ){
#ifdef I3D_HAVE_ZLIB
    // crc32 de zlib toma uInt (32 bits): por tramos
    uLong c = crc32( 0L , Z_NULL , 0 );
    for( size_t p = 0 ; p < out.size() ; p += 0x40000000 )
      c = crc32( c , out.data() + p , (uInt)std::min<size_t>( 0x40000000 , out.size() - p ) );
    if( (uint32_t)c != d.crc ){
      char got[16];  std::snprintf( got , sizeof got , "%08x" , (unsigned)c );
      throw Error( "badCRC" , "the block " + d.text + " decodes to data that fails its crc (computed " + got + ")" );
    }
#else
    throw Error( "unsupportedEncoding" , "the crc check needs zlib (compiled without it): " + d.text );
#endif
  }
  return out;
}

std::vector<uint8_t> File::decode_( const Descriptor &d , size_t expected ) const {
  auto unsupported = [&]( const std::string &why ){
    return Error( "unsupportedEncoding" , "<" + d.encoding + "> " + why + " (" + d.text + ")" );
  };
  if( d.encoding == "raw" || d.encoding == "zlib" || d.encoding == "jpegls" || d.encoding == "png" ){
    int64_t fsize = size_;                                 // la ventana: el fichero o el miembro
    std::ifstream f = open_window( path_ , base_ , fsize );
    int64_t L = d.length;
    if( L == Descriptor::LEN_EOF ){                        // hasta el final del fichero
      L = fsize - ( b0_ + d.offset );
      if( L < 0 ) throw Error( "truncated" , "the block starts after the end of the file: " + d.text );
    }
    int64_t len = d.encoding == "raw" ? (int64_t)expected : L;
    // solo raw puede ir sin longitud (@a): la da su forma. Un comprimido sin ella
    // pediria un buffer de 2^64 bytes
    if( len < 0 ) throw Error( "badDescriptor" , "<" + d.encoding + "> needs its length: @a:b , @a+n , @a+Inf or @a:EOF (" + d.text + ")" );
    if( d.encoding == "raw" && L >= 0 && L != (int64_t)expected )
      throw Error( "badBlock" , "<raw> has " + std::to_string( L ) + " bytes but the block needs " + std::to_string( expected ) );
    // el bloque, DENTRO del fichero, antes de reservar nada: un fichero de 127
    // bytes no puede pedir 1.5 GB (escrito sin sumar, que no desborde)
    if( d.offset > fsize - b0_ || len > fsize - b0_ - d.offset )
      throw Error( "truncated" , "the file ends inside the block " + d.text );
    // y lo que puede salir de el: deflate no comprime mas de 1032:1, asi que un
    // <zlib> de len bytes no infla a mas de ~1032*len. Lo que lo pida miente
    if( d.encoding == "zlib" && (uint64_t)expected / 1032u > (uint64_t)len + 64u )
      throw Error( "badBlock" , "a <zlib> block of " + std::to_string( len ) + " bytes cannot inflate to " + std::to_string( expected ) + ": " + d.text );
    std::vector<uint8_t> buf( (size_t)len );
    f.seekg( base_ + b0_ + d.offset );
    f.read( (char*)buf.data() , len );
    if( f.gcount() != len ) throw Error( "truncated" , "the file ends inside the block " + d.text );
    if( d.encoding == "raw" ) return buf;
    if( d.encoding == "png" ){
#ifdef I3D_HAVE_LODEPNG
      // SPEC 7: un aux uint8 {r c} o {r c 1 f} es UNA imagen PNG gris de 8 bits
      // de r filas y c*f columnas, los frames uno al lado de otro. En orden
      // columna eso es exactamente el array {r c 1 f}: el pixel (y, X) va a
      // y + r*X. Gris de 8 bits y nada mas: lodepng convertiria en silencio un
      // RGB o un 16 bits, y eso ya no seria lo que se escribio
      const auto &s = d.shape;
      bool shape_ok = d.type == Type::uint8 && s.size() >= 2 && ( s.size() == 2 || s[2] == 1 );
      for( size_t q = 4 ; q < s.size() ; q++ ) shape_ok = shape_ok && s[q] == 1;
      if( !shape_ok ) throw Error( "badDescriptor" , "<png> holds uint8 {rows cols} or {rows cols 1 frames}, not " + d.text );
      const int64_t r = s[0] , W = s[1] * ( s.size() >= 4 ? s[3] : 1 );
      // la cabecera IHDR primero: su tamano y su tipo, ANTES de que lodepng
      // reserve lo que diga (una PNG de 100 bytes puede declarar 2^31 x 2^31)
      {
        lodepng::State si;  unsigned w0 = 0 , h0 = 0;
        unsigned ei = lodepng_inspect( &w0 , &h0 , &si , buf.data() , buf.size() );
        if( ei ) throw Error( "badBlock" , std::string( "PNG: " ) + lodepng_error_text( ei ) + " in " + d.text );
        if( si.info_png.color.colortype != LCT_GREY || si.info_png.color.bitdepth != 8 )
          throw Error( "badBlock" , "<png> must be 8-bit grey, not colour type " + std::to_string( (int)si.info_png.color.colortype ) + " at " + std::to_string( si.info_png.color.bitdepth ) + " bits: " + d.text );
        if( (int64_t)h0 != r || (int64_t)w0 != W )
          throw Error( "badBlock" , "<png> is " + std::to_string( w0 ) + "x" + std::to_string( h0 ) + " (width x height); {shape} needs " + std::to_string( W ) + "x" + std::to_string( r ) + ": " + d.text );
      }
      lodepng::State st;
      st.info_raw.colortype = LCT_GREY;  st.info_raw.bitdepth = 8;
      std::vector<unsigned char> img;  unsigned w = 0 , h = 0;
      unsigned e = lodepng::decode( img , w , h , st , buf.data() , buf.size() );
      if( e ) throw Error( "badBlock" , std::string( "PNG: " ) + lodepng_error_text( e ) + " in " + d.text );
      if( st.info_png.color.colortype != LCT_GREY || st.info_png.color.bitdepth != 8 )
        throw Error( "badBlock" , "<png> must be 8-bit grey, not colour type " + std::to_string( (int)st.info_png.color.colortype ) + " at " + std::to_string( st.info_png.color.bitdepth ) + " bits: " + d.text );
      if( (int64_t)h != r || (int64_t)w != W || img.size() != expected )
        throw Error( "badBlock" , "<png> is " + std::to_string( w ) + "x" + std::to_string( h ) + " (width x height); {shape} needs " + std::to_string( W ) + "x" + std::to_string( r ) + ": " + d.text );
      std::vector<uint8_t> out( expected );
      for( int64_t y = 0 ; y < r ; y++ )
        for( int64_t X = 0 ; X < W ; X++ ) out[(size_t)( y + r * X )] = img[(size_t)( y * W + X )];   // filas -> orden columna
      return out;
#else
      throw unsupported( "is not available in this build (compiled without lodepng)" );
#endif
    }
    if( d.encoding == "jpegls" ){
#ifdef I3D_HAVE_CHARLS
      // SPEC 4: los planos i,j del bloque apilados en UNA imagen; ancho = ni (x
      // de JPEG-LS = i), alto = nj * planos (en orden k, t, c: la imagen ES el
      // bloque en orden columna); bits por muestra = los del tipo. Un tipo CON
      // signo viene desplazado 2^(bits-1): se deshace con un XOR del bit alto
      try {
        charls::jpegls_decoder dec;
        dec.source( buf.data() , buf.size() );
        dec.read_header();
        const charls::frame_info &fi = dec.frame_info();
        const int bits = 8 * (int)type_size( d.type );
        const int64_t height = (int64_t)( expected / ( type_size( d.type ) * (size_t)shape_[0] ) );   // nj * planos
        if( fi.component_count != 1 || (int64_t)fi.width != shape_[0] || (int64_t)fi.height != height || fi.bits_per_sample != bits )
          throw Error( "badBlock" , "<jpegls> frame is " + std::to_string( fi.width ) + "x" + std::to_string( fi.height ) + "x" + std::to_string( fi.component_count ) +
                       " at " + std::to_string( fi.bits_per_sample ) + " bits; the block needs " + std::to_string( shape_[0] ) + "x" + std::to_string( height ) +
                       "x1 at " + std::to_string( bits ) + " bits (" + d.text + ")" );
        // SPEC 4: NEAR = 0. Un flujo near-lossless decodifica sin queja a OTROS
        // valores (medido: NEAR = 3 da hasta 3 de error), asi que se rechaza
        if( dec.near_lossless() != 0 )
          throw Error( "badBlock" , "<jpegls> is near-lossless (NEAR = " + std::to_string( dec.near_lossless() ) + "), not exact: " + d.text );
        if( dec.destination_size() != expected ) throw Error( "badBlock" , "<jpegls> decodes to " + std::to_string( dec.destination_size() ) + " bytes, expected " + std::to_string( expected ) );
        std::vector<uint8_t> out( expected );
        dec.decode( out.data() , out.size() );
        if( d.type == Type::int8 )  for( auto &v : out ) v ^= 0x80;
        if( d.type == Type::int16 ) for( size_t p = 1 ; p < out.size() ; p += 2 ) out[p] ^= 0x80;   // little-endian: el byte alto es el segundo
        return out;
      } catch( const charls::jpegls_error &e ){
        throw Error( "badBlock" , std::string( "JPEG-LS: " ) + e.what() + " in " + d.text );
      }
#else
      throw unsupported( "is not available in this build (compiled without CharLS)" );
#endif
    }
#ifdef I3D_HAVE_ZLIB
    // uncompress mide en uLong, que en Windows es de 32 bits
    if( expected > 0xFFFFFFFFull || (uint64_t)len > 0xFFFFFFFFull )
      throw Error( "badBlock" , "a <zlib> block over 4 GiB is not supported by this reader: " + d.text );
    std::vector<uint8_t> out( expected );
    uLongf dl = (uLongf)expected;
    int z = uncompress( out.data() , &dl , buf.data() , (uLong)len );
    if( z != Z_OK ) throw Error( "badBlock" , "zlib error " + std::to_string( z ) + " in " + d.text );
    if( dl != expected ) throw Error( "badBlock" , "zlib block inflates to " + std::to_string( dl ) + " bytes, expected " + std::to_string( expected ) );
    return out;
#else
    throw unsupported( "is not available in this build (compiled without zlib)" );
#endif
  }
  if( d.encoding == "dicom" ) return read_dicom_( d , expected );
  if( d.encoding == "gif" ) throw unsupported( "is not decoded by this reader" );
  throw unsupported( "is an unknown encoding" );
}

// ====================================================================== <dicom>
// Los pixeles ALMACENADOS de un .dcm (SPEC 4): sin el Rescale del DICOM. Plano =
// Columns x Rows con la columna mas rapida, que es la i de @I3D (DICOMstack hace
// permute([2 1]) sobre lo que devuelve dicomread). Los bits: los BitsStored que
// acaban en HighBit, enmascarados, y con el signo extendido si
// PixelRepresentation = 1. [VERIFICADO contra dicomread en tests/check_dicom.m]
#ifdef I3D_HAVE_DCMTK
// Los frames f0..f1 (1-based) de un PixelData ENCAPSULADO en JPEG-LS, con NUESTRA
// CharLS (ver el comentario de read_dicom_: el codec de DCMTK no se puede usar).
// Devuelve las muestras tal cual -- los bits almacenados, sin signo ni mascara:
// eso lo hace read_dicom_ igual que para los demas --, ba/8 bytes cada una,
// Columns (= ni) la mas rapida, frame tras frame.
// Item 0 de la secuencia: la tabla de offsets. Despues los fragmentos; un frame
// puede ocupar varios, y acaba en su EOI (FF D9) -- que dentro del flujo no
// puede salir: en JPEG-LS, tras un FF el byte siguiente tiene el bit alto a 0 --,
// seguido como mucho de un 00 de relleno (los items son de longitud par).
static std::vector<uint8_t> jpegls_frames_( DcmElement *pe , const std::string &fn , int64_t f0 , int64_t f1 ,
                                            int64_t ni , int64_t nj , int ba ){
#ifndef I3D_HAVE_CHARLS
  (void)pe; (void)f0; (void)f1; (void)ni; (void)nj; (void)ba;
  throw Error( "unsupportedEncoding" , "a JPEG-LS DICOM needs CharLS (compiled without it): " + fn );
#else
  DcmPixelData *pd = dynamic_cast<DcmPixelData*>( pe );
  if( !pd ) throw Error( "badBlock" , "'" + fn + "': PixelData is not encapsulated" );
  E_TransferSyntax rt = EXS_Unknown;  const DcmRepresentationParameter *rp = nullptr;
  pd->getOriginalRepresentationKey( rt , rp );
  DcmPixelSequence *seq = nullptr;
  if( pd->getEncapsulatedRepresentation( rt , rp , seq ).bad() || !seq )
    throw Error( "badBlock" , "'" + fn + "': no encapsulated JPEG-LS pixel data" );

  const size_t bps = (size_t)ba / 8 , fbytes = (size_t)( ni * nj ) * bps;
  std::vector<uint8_t> out( (size_t)( f1 - f0 + 1 ) * fbytes ) , cur , tmp;
  int64_t frame = 0;                                   // frames completos vistos
  for( unsigned long it = 1 ; it < seq->card() && frame < f1 ; it++ ){
    DcmPixelItem *item = nullptr;  Uint8 *p = nullptr;
    if( seq->getItem( item , it ).bad() || !item || item->getUint8Array( p ).bad() )
      throw Error( "badBlock" , "'" + fn + "': cannot read JPEG-LS fragment " + std::to_string( it ) );
    const size_t L = item->getLength();
    if( L ) cur.insert( cur.end() , p , p + L );
    size_t e = cur.size();  while( e > 0 && cur[e-1] == 0 ) e--;
    if( !( e >= 2 && cur[e-2] == 0xFF && cur[e-1] == 0xD9 ) ) continue;    // el frame sigue
    frame++;
    if( frame >= f0 ){
      try {
        charls::jpegls_decoder dec;
        dec.source( cur.data() , e );
        dec.read_header();
        const charls::frame_info &fi = dec.frame_info();
        if( fi.component_count != 1 || (int64_t)fi.width != ni || (int64_t)fi.height != nj || fi.bits_per_sample > ba )
          throw Error( "badBlock" , "'" + fn + "': JPEG-LS frame " + std::to_string( frame ) + " is " + std::to_string( fi.width ) + "x" +
                       std::to_string( fi.height ) + "x" + std::to_string( fi.component_count ) + " at " + std::to_string( fi.bits_per_sample ) + " bits" );
        uint8_t *dst = out.data() + (size_t)( frame - f0 ) * fbytes;
        if( fi.bits_per_sample <= 8 && ba == 16 ){
          // CharLS da 1 byte por muestra hasta 8 bits: se ensancha a 16
          tmp.assign( (size_t)( ni * nj ) , 0 );
          dec.decode( tmp.data() , tmp.size() );
          for( size_t q = 0 ; q < tmp.size() ; q++ ){ dst[2*q] = tmp[q]; dst[2*q+1] = 0; }
        } else {
          if( dec.destination_size() != fbytes ) throw Error( "badBlock" , "'" + fn + "': JPEG-LS frame decodes to " + std::to_string( dec.destination_size() ) + " bytes, expected " + std::to_string( fbytes ) );
          dec.decode( dst , fbytes );
        }
      } catch( const charls::jpegls_error &x ){
        throw Error( "badBlock" , "'" + fn + "': JPEG-LS frame " + std::to_string( frame ) + ": " + x.what() );
      }
    }
    cur.clear();
  }
  if( frame < f1 ) throw Error( "badBlock" , "'" + fn + "' has " + std::to_string( frame ) + " JPEG-LS frame(s); the block needs up to frame " + std::to_string( f1 ) );
  return out;
#endif
}
#endif

std::vector<uint8_t> File::read_dicom_( const Descriptor &d , size_t expected ) const {
#ifndef I3D_HAVE_DCMTK
  (void)expected;
  throw Error( "unsupportedEncoding" , "<dicom> is not available in this build (compiled without DCMTK): " + d.text );
#else
  // los decodificadores, UNA vez por proceso, y sin carrera si dos hilos abren
  // un <dicom> a la vez
  // JPEG-LS NO se registra: el dcmjpls de DCMTK trae su propia CharLS vieja
  // (dcmtkcharls), con funciones del MISMO nombre que la CharLS 2.4.5 que
  // enlazamos; el enlazador se queda con una y el codec de DCMTK llamaba a la
  // otra: access violation en TODO DICOM JPEG-LS (medido, 2026-10-13, 4 de 4
  // ficheros reales). Lo decodifica jpegls_frames_, con nuestra CharLS
  static std::once_flag registered;
  std::call_once( registered , [](){
    DJDecoderRegistration::registerCodecs();       // JPEG (lossless y lossy)
    DcmRLEDecoderRegistration::registerCodecs();   // RLE
  } );
  const std::string fn = resolve_path( d.path );
  const int64_t ni = shape_[0] , nj = shape_[1];
  const size_t ts = type_size( d.type );
  const size_t plane = (size_t)( ni * nj ) * ts;
  if( !plane || expected % plane ) throw Error( "badBlock" , "<dicom> block of " + std::to_string( expected ) + " bytes is not whole planes: " + d.text );
  const int64_t nplanes = (int64_t)( expected / plane );

  DcmFileFormat ff;
#if defined(_WIN32) && defined(WIDE_CHAR_FILE_IO_FUNCTIONS)
  // ruta ancha: build_dcmtk.bat compila DCMTK con DCMTK_WIDE_CHAR_FILE_IO_FUNCTIONS
  const std::wstring wfn = native_( fn ).wstring();
  OFCondition st = ff.loadFile( OFFilename( wfn.c_str() ) );
#else
  OFCondition st = ff.loadFile( fn.c_str() );
#endif
  if( st.bad() ) throw Error( "cannotOpen" , "DCMTK cannot load '" + fn + "': " + st.text() );
  DcmDataset *ds = ff.getDataset();
  const E_TransferSyntax xfer = ds->getOriginalXfer();
  const bool jls = xfer == EXS_JPEGLSLossless || xfer == EXS_JPEGLSLossy;
  if( !jls ){
    st = ds->chooseRepresentation( EXS_LittleEndianExplicit , NULL );
    if( st.bad() || !ds->canWriteXfer( EXS_LittleEndianExplicit ) )
      throw Error( "unsupportedEncoding" , "DCMTK cannot decode the pixel data of '" + fn + "' (transfer syntax " +
                   DcmXfer( xfer ).getXferName() + ")" );
  }

  Uint16 rows = 0 , cols = 0 , ba = 0 , bs = 0 , hb = 0 , pr = 0 , spp = 1;
  Sint32 nf = 1;
  ds->findAndGetUint16( DCM_Rows , rows );
  ds->findAndGetUint16( DCM_Columns , cols );
  ds->findAndGetUint16( DCM_BitsAllocated , ba );
  ds->findAndGetUint16( DCM_BitsStored , bs );
  ds->findAndGetUint16( DCM_HighBit , hb );
  ds->findAndGetUint16( DCM_PixelRepresentation , pr );
  ds->findAndGetUint16( DCM_SamplesPerPixel , spp );
  if( ds->findAndGetSint32( DCM_NumberOfFrames , nf ).bad() || nf < 1 ) nf = 1;

  if( spp != 1 ) throw Error( "unsupportedEncoding" , "<dicom> with SamplesPerPixel " + std::to_string( spp ) + " is not supported yet: " + fn );
  if( (int64_t)cols != ni || (int64_t)rows != nj )
    throw Error( "badBlock" , "'" + fn + "' is " + std::to_string( cols ) + "x" + std::to_string( rows ) + " (Columns x Rows); the planes are " + std::to_string( ni ) + "x" + std::to_string( nj ) );
  Type ft = ba == 8 ? ( pr ? Type::int8 : Type::uint8 ) : ba == 16 ? ( pr ? Type::int16 : Type::uint16 ) : ba == 32 ? ( pr ? Type::int32 : Type::uint32 ) : Type::none;
  if( ft != d.type ) throw Error( "badType" , "'" + fn + "' holds " + type_name( ft ) + " (BitsAllocated " + std::to_string( ba ) + ", PixelRepresentation " + std::to_string( pr ) + "); the descriptor says " + type_name( d.type ) );
  if( !( bs >= 1 && bs <= ba && hb + 1 >= bs && hb < ba ) ) throw Error( "badBlock" , "'" + fn + "' has inconsistent BitsStored/HighBit" );

  int64_t f0 = 1 , f1 = nf;
  if( d.frame_lo >= 1 ){ f0 = d.frame_lo; f1 = d.frame_hi; }
  if( f0 < 1 || f1 > nf || f1 - f0 + 1 != nplanes )
    throw Error( "badBlock" , "'" + fn + "' has " + std::to_string( nf ) + " frame(s); the block needs " + std::to_string( nplanes ) + " (frames " + std::to_string( f0 ) + ":" + std::to_string( f1 ) + ")" );

  Uint8 *px8 = nullptr;  Uint16 *px16 = nullptr;  Uint32 *px32 = nullptr;
  unsigned long count = 0;
  size_t base = (size_t)( ( f0 - 1 ) * ni * nj );
  DcmElement *pe = nullptr;
  if( ds->findAndGetElement( DCM_PixelData , pe ).bad() || !pe ) throw Error( "badBlock" , "'" + fn + "' has no pixel data" );
  std::vector<uint8_t> jbuf;                       // JPEG-LS: los frames ya decodificados
  if( jls ){
    if( ba != 8 && ba != 16 ) throw Error( "badBlock" , "'" + fn + "': JPEG-LS with BitsAllocated " + std::to_string( ba ) );
    jbuf = jpegls_frames_( pe , fn , f0 , f1 , ni , nj , ba );
    if( ba == 8 ) px8 = jbuf.data();  else px16 = reinterpret_cast<Uint16*>( jbuf.data() );
    base = 0;                                      // jbuf empieza en el frame f0
  } else {
    if( ba == 8 )       st = pe->getUint8Array( px8 );
    else if( ba == 16 ) st = pe->getUint16Array( px16 );
    else                st = pe->getUint32Array( px32 );
    count = pe->getLength() / ( ba / 8 );
    if( st.bad() || (int64_t)count < nf * ni * nj ) throw Error( "badBlock" , "'" + fn + "': pixel data shorter than " + std::to_string( nf ) + " frames" );
  }

  // los bits almacenados: BitsStored bits que acaban en HighBit; signo si pr
  const unsigned shift = (unsigned)( hb + 1 - bs );
  const uint32_t mask = bs >= 32 ? 0xFFFFFFFFu : ( ( 1u << bs ) - 1u );
  const uint32_t sbit = 1u << ( bs - 1 );
  std::vector<uint8_t> out( expected );
  const size_t n = (size_t)( nplanes * ni * nj );
  for( size_t q = 0 ; q < n ; q++ ){
    uint32_t v = ba == 8 ? px8[ base + q ] : ba == 16 ? px16[ base + q ] : px32[ base + q ];
    v = ( v >> shift ) & mask;
    if( pr && ( v & sbit ) ) v |= ~mask;                       // extension de signo
    std::memcpy( out.data() + q * ts , &v , ts );             // little-endian: los ts bytes bajos
  }
  return out;
#endif
}

Descriptor File::aux_descriptor( const std::string &name ) const {
  const Entry *e = find( "aux." + name );
  if( !e ) throw Error( "noAux" , "no aux." + name );
  return parse_descriptor( e->value , e->line );
}

std::vector<std::string> File::aux_names() const {
  std::vector<std::string> v;
  for( auto &e : entries_ ) if( e.key.size() > 4 && !e.key.compare( 0 , 4 , "aux." ) ) v.push_back( e.key.substr( 4 ) );
  return v;
}

std::vector<uint8_t> File::read_aux( const std::string &name ) const {
  // SPEC 7: un aux no tiene rejilla de la que sacar su forma: la lleva en {shape}
  Descriptor d = aux_descriptor( name );
  if( d.encoding != "raw" && d.encoding != "zlib" && d.encoding != "png" )
    throw Error( "unsupportedEncoding" , "aux." + name + ": <" + d.encoding + "> is not decoded for aux arrays by this reader" );
  if( d.type == Type::none || d.shape.empty() ) throw Error( "badDescriptor" , "aux." + name + " needs a type and a {shape}" );
  size_t n = type_size( d.type );
  for( auto s : d.shape ){ if( s < 0 ) throw Error( "badDescriptor" , "aux." + name + ": negative {shape}" ); n *= (size_t)s; }
  return read_bytes( d , n );
}

// ====================================================================== colocar un bloque
// Un "run": cuenta elementos contiguos en el fichero, a destino con un paso.
typedef void (*RunFn)( const uint8_t *src , uint8_t *dst , int64_t count , int64_t dstep );

template<typename S , typename D>
static void run_( const uint8_t *src , uint8_t *dst , int64_t count , int64_t dstep ){
  if constexpr( std::is_same<S,D>::value ){ if( dstep == 1 ){ std::memcpy( dst , src , (size_t)count * sizeof(D) ); return; } }
  for( int64_t n = 0 ; n < count ; n++ ){
    S s;  std::memcpy( &s , src + n * sizeof(S) , sizeof(S) );
    D v = static_cast<D>( s );            // sin perdida: lo garantiza promote()
    std::memcpy( dst + n * dstep * sizeof(D) , &v , sizeof(D) );
  }
}

template<typename S> static RunFn pick_( Type d ){
  switch( d ){
    case Type::int8:    return &run_<S,int8_t>;
    case Type::uint8:   return &run_<S,uint8_t>;
    case Type::int16:   return &run_<S,int16_t>;
    case Type::uint16:  return &run_<S,uint16_t>;
    case Type::int32:   return &run_<S,int32_t>;
    case Type::uint32:  return &run_<S,uint32_t>;
    case Type::int64:   return &run_<S,int64_t>;
    case Type::uint64:  return &run_<S,uint64_t>;
    case Type::single:  return &run_<S,float>;
    case Type::double_: return &run_<S,double>;
    default: return nullptr;
  }
}
static RunFn pick( Type s , Type d ){
  switch( s ){
    case Type::int8:    return pick_<int8_t>( d );
    case Type::uint8:   return pick_<uint8_t>( d );
    case Type::int16:   return pick_<int16_t>( d );
    case Type::uint16:  return pick_<uint16_t>( d );
    case Type::int32:   return pick_<int32_t>( d );
    case Type::uint32:  return pick_<uint32_t>( d );
    case Type::int64:   return pick_<int64_t>( d );
    case Type::uint64:  return pick_<uint64_t>( d );
    case Type::single:  return pick_<float>( d );
    case Type::double_: return pick_<double>( d );
    default: return nullptr;
  }
}

// Copia la INTERSECCION de un bloque B con la caja pedida W. Los bytes del bloque
// van en orden columna sobre B (i j k t c..., i el mas rapido: SPEC 5.3), y el
// destino en orden columna sobre W. A trozos contiguos en i.
// src == nullptr: rellena la interseccion con 'fillv'.
static void copy_box( const std::vector<Range> &B , const uint8_t *src , Type st ,
                      const std::vector<Range> &W , uint8_t *out , Type dt , const uint8_t *fillv ){
  const size_t nd = B.size();
  std::vector<Range> I( nd );
  for( size_t d = 0 ; d < nd ; d++ ){
    I[d].lo = std::max( B[d].lo , W[d].lo );  I[d].hi = std::min( B[d].hi , W[d].hi );
    if( I[d].lo >= I[d].hi ) return;                       // no se tocan
  }
  std::vector<int64_t> sB( nd ) , sW( nd );                // pasos en elementos
  sB[0] = sW[0] = 1;
  for( size_t d = 1 ; d < nd ; d++ ){ sB[d] = sB[d-1] * ( B[d-1].hi - B[d-1].lo );  sW[d] = sW[d-1] * ( W[d-1].hi - W[d-1].lo ); }

  const int64_t runlen = I[0].hi - I[0].lo;               // un trozo: una fila en i
  RunFn fn = src ? pick( st , dt ) : nullptr;
  const size_t ss = type_size( st ) , ds = type_size( dt );
  std::vector<int64_t> cnt( nd , 0 );
  for( ;; ){
    int64_t si = 0 , di = 0;
    for( size_t d = 0 ; d < nd ; d++ ){
      const int64_t x = I[d].lo + cnt[d];
      si += ( x - B[d].lo ) * sB[d];  di += ( x - W[d].lo ) * sW[d];
    }
    uint8_t *dp = out + di * ds;
    if( src ) fn( src + si * ss , dp , runlen , 1 );
    else for( int64_t n = 0 ; n < runlen ; n++ ) std::memcpy( dp + n * ds , fillv , ds );
    // siguiente trozo: contador sobre j k t c...
    size_t k = 1;
    for( ; k < nd ; k++ ){
      if( ++cnt[k] < I[k].hi - I[k].lo ) break;
      cnt[k] = 0;
    }
    if( k == nd ) break;
  }
}

// La caja W de data (0-based, hi exclusivo) en 'out', en orden columna sobre W.
// SOLO se leen y decodifican los bloques que la cortan: es lo que hace que el
// primer instante, que el escritor deja en sus propios bloques, salga barato
void File::read_box_( const std::vector<Range> &W , void *out , size_t nbytes ) const {
  size_t need = type_size( type_ );
  for( auto &w : W ) need *= (size_t)( w.hi - w.lo );
  if( nbytes != need )
    throw Error( "badBuffer" , "the buffer has " + std::to_string( nbytes ) + " bytes; it needs " + std::to_string( need ) );

  // el valor de relleno, en el tipo de data
  uint8_t fillv[8] = {0};
  switch( type_ ){
    case Type::single:  { float  v = (float)fill_;  std::memcpy( fillv , &v , 4 ); break; }
    case Type::double_: { double v = fill_;         std::memcpy( fillv , &v , 8 ); break; }
    default:            { int64_t v = ifill_;       std::memcpy( fillv , &v , type_size( type_ ) ); break; }   // little-endian
  }

  for( auto &b : blocks_ ){
    bool cuts = true;
    for( size_t d = 0 ; d < W.size() && cuts ; d++ ) cuts = b.box[d].lo < W[d].hi && W[d].lo < b.box[d].hi;
    if( !cuts ) continue;                                  // ni se lee
    const Descriptor &D = b.desc;
    if( D.encoding == "missing" ){ copy_box( b.box , nullptr , type_ , W , (uint8_t*)out , type_ , fillv ); continue; }
    int64_t vol = 1;  for( auto &x : b.box ) vol *= ( x.hi - x.lo );
    auto bytes = read_bytes( D , (size_t)vol * type_size( D.type ) );
    copy_box( b.box , bytes.data() , D.type , W , (uint8_t*)out , type_ , nullptr );
  }
}

void File::read_data( void *out , size_t nbytes ) const {
  std::vector<Range> W( shape_.size() );
  for( size_t d = 0 ; d < W.size() ; d++ ){ W[d].lo = 0;  W[d].hi = shape_[d]; }
  read_box_( W , out , nbytes );
}

std::vector<int64_t> File::first_frame_shape() const {
  std::vector<int64_t> s = shape_;  s[3] = 1;             // i j k 1 c...
  return s;
}

size_t File::first_frame_bytes() const { return data_bytes() / (size_t)shape_[3]; }

void File::read_first_frame( void *out , size_t nbytes ) const {
  // data(:,:,:,1,:...): el primer instante, todas sus componentes
  std::vector<Range> W( shape_.size() );
  for( size_t d = 0 ; d < W.size() ; d++ ){ W[d].lo = 0;  W[d].hi = d == 3 ? 1 : shape_[d]; }
  read_box_( W , out , nbytes );
}

// ====================================================================== .mi3d
// SPEC 14: 'MI3D 0.1', i3d(n) = <i3d @a:b> | <missing>, header = <hidden ...>,
// info.* (un resumen: no se interpreta) y nada mas que cuente. Cada miembro es
// un .i3d completo que se lee por su ventana del fichero
Container::Container( const std::string &path ) : path_( path ){
  size_ = -1;
  std::ifstream f = open_window( path , 0 , size_ );
  char magic[4] = { 0 , 0 , 0 , 0 };
  f.read( magic , 4 );
  if( f.gcount() == 4 && ( !std::memcmp( magic , "I3Db" , 4 ) || !std::memcmp( magic , "I3D " , 4 ) ) )
    throw Error( "badMagic" , "'" + path + "' is an .i3d, not a .mi3d container" );
  f.clear();  f.seekg( 0 );
  header_ = read_text_header( f , size_ , path , b0_ );
  check_utf8( header_ , "'" + path + "'" , +1 );
  entries_ = parse_lines( header_ , "MI3D 0.1" , +1 );
  expand_hidden( entries_ , path_ , 0 , size_ , b0_ );

  // claves sin ( ) aparecen una vez (i3d lleva siempre la suya)
  for( size_t a = 0 ; a < entries_.size() ; a++ ){
    if( entries_[a].key == "i3d" || entries_[a].paren ) continue;
    for( size_t b = a + 1 ; b < entries_.size() ; b++ )
      if( entries_[b].key == entries_[a].key && !entries_[b].paren )
        throw Error( "badHeader" , where( entries_[b].line ) + "repeated key '" + entries_[a].key + "'" );
  }

  std::map<int,int> seen;                     // n -> su linea, huecos incluidos
  for( auto &e : entries_ ){
    if( e.key != "i3d" ) continue;
    // n: UN entero >= 1, solo cifras, como los subindices de data (SPEC 5.2). Ni
    // rangos, ni end, ni vacio. 9 cifras como mucho: n cabe en un int
    const std::string s = trim( e.subs );
    if( !e.paren || s.empty() || s.size() > 9 || s.find_first_not_of( "0123456789" ) != std::string::npos || std::stoi( s ) < 1 )
      throw Error( "badSubscript" , where( e.line ) + "a member is i3d(n), n one integer >= 1, not '" + e.key + ( e.paren ? "(" + e.subs + ")" : "" ) + "'" );
    const int n = std::stoi( s );
    if( seen.count( n ) ) throw Error( "badHeader" , where( e.line ) + "repeated i3d(" + s + ")" );
    seen[n] = e.line;
    N_ = std::max( N_ , n );
    const Descriptor d = File::parse_descriptor( e.value , e.line );
    const bool bare = d.type == Type::none && d.shape.empty() && d.path.empty() && d.frame_lo == -1;
    if( d.encoding == "missing" ){              // un hueco declarado (SPEC 14.2)
      if( !bare || d.offset != -1 || d.has_crc )
        throw Error( "badDescriptor" , where( e.line ) + "a hole is <missing>, nothing else: " + e.value );
      continue;
    }
    if( d.encoding != "i3d" )
      throw Error( "badDescriptor" , where( e.line ) + "i3d(n) takes <i3d @a:b> or <missing>, not " + e.value );
    if( !bare || d.offset < 0 || d.length == -1 )
      throw Error( "badDescriptor" , where( e.line ) + "a member is <i3d @a:b [crc X]>: where its bytes are, nothing else: " + e.value );
    // dentro del binario, como cualquier bloque, ya al abrir: es barato
    const int64_t L = d.length == Descriptor::LEN_EOF ? size_ - b0_ - d.offset : d.length;
    if( d.offset > size_ - b0_ || L <= 0 || L > size_ - b0_ - d.offset )
      throw Error( "truncated" , where( e.line ) + "the file ends inside member " + s + ": " + e.value );
    Member m;  m.desc = d;  m.length = L;  m.line = e.line;
    members_[n] = m;
  }
}

bool Container::present( int n ) const {
  if( n < 1 || n > N_ ) throw Error( "badIndex" , "no member " + std::to_string( n ) + ": the container has members 1.." + std::to_string( N_ ) );
  return members_.count( n ) > 0;
}

const Member &Container::member( int n ) const {
  if( !present( n ) ) throw Error( "missingMember" , "member " + std::to_string( n ) + " is a hole (SPEC 14.2)" );
  return members_.at( n );
}

void Container::window( int n , int64_t &base , int64_t &size ) const {
  const Member &m = member( n );
  base = b0_ + m.desc.offset;  size = m.length;
  // un nivel: un miembro no es otro contenedor
  auto head = read_window( path_ , 0 , size_ , base , std::min<int64_t>( 4 , size ) , "member " + std::to_string( n ) );
  if( head.size() == 4 && !std::memcmp( head.data() , "MI3D" , 4 ) )
    throw Error( "badBlock" , where( m.line ) + "member " + std::to_string( n ) + " is a .mi3d: a container holds .i3d files only (one level)" );
  if( m.desc.has_crc ){
#ifdef I3D_HAVE_ZLIB
    // el crc de un miembro es de sus bytes tal cual (es lo que el miembro ES).
    // Por tramos: un miembro puede ser de cientos de MB
    int64_t s = -1;
    std::ifstream f = open_window( path_ , 0 , s );
    f.seekg( base );
    std::vector<char> chunk( 1 << 20 );
    uLong c = crc32( 0L , Z_NULL , 0 );
    for( int64_t left = size ; left > 0 ; ){
      const int64_t k = std::min<int64_t>( left , (int64_t)chunk.size() );
      f.read( chunk.data() , (std::streamsize)k );
      if( f.gcount() != k ) throw Error( "truncated" , "the file ends inside member " + std::to_string( n ) );
      c = crc32( c , (const Bytef*)chunk.data() , (uInt)k );
      left -= k;
    }
    if( (uint32_t)c != m.desc.crc ) throw Error( "badCRC" , where( m.line ) + "member " + std::to_string( n ) + " fails its crc" );
#else
    throw Error( "unsupportedEncoding" , "the crc of a member needs zlib (compiled without it)" );
#endif
  }
}

File Container::open( int n , const std::map<std::string,std::string> &overrides ) const {
  int64_t base = 0 , size = 0;
  window( n , base , size );
  return File( path_ , overrides , base , size );
}

} // namespace i3d
