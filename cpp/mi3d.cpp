// mi3d.cpp -- escribir y modificar un contenedor .mi3d (SPEC 14): ver mi3d.hpp.
//
// La traduccion de lo que hacian write_MI3D.m, append_MI3D.m, remove_MI3D.m y
// sus private/mi3d_*.m. Leer un .mi3d es i3d::Container (i3d.cpp).
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "mi3d.hpp"

#include <cstring>
#include <fstream>
#include <filesystem>
#include <algorithm>
#include <set>

namespace i3d {
namespace mi3d {

static std::filesystem::path u8p( const std::string &s ){ return detail::fs_path( s ); }
static std::string i2s( int64_t v ){ return std::to_string( v ); }

// lo que el escritor necesita de un miembro
struct M {
  int n = 0;
  std::string tag , dims;                   // dims: "i x j x k x t"
  detail::Chunk src;                        // sus bytes: un .i3d entero, o un rango de un .mi3d
  int64_t at = -1;                          // su offset en el binario del contenedor
  std::vector<std::string> keys , vals;     // sus info.*, en orden, el valor crudo
  std::vector<bool> vis;                    // cada una, a la vista (y el fichero no es I3Db)
  bool lazyrel = false;                     // un <dicom> con ruta relativa
  std::vector<std::string> note;            // su NOTA: lineas de comentario en la cabecera (SPEC 14.7)
};

// una nota: sus lineas (separadas por LF), sin otros caracteres de control, sin
// blancos al final y sin lineas vacias
static std::vector<std::string> note_lines_( const std::string &t ){
  std::vector<std::string> L;
  for( size_t a = 0 ; a <= t.size() ; ){
    size_t b = t.find( '\n' , a );  if( b == std::string::npos ) b = t.size();
    std::string l = t.substr( a , b - a );
    for( char &c : l ) if( (unsigned char)c < 32 || c == 127 ) c = ' ';
    const size_t e = l.find_last_not_of( ' ' );
    if( e != std::string::npos ) L.push_back( l.substr( 0 , e + 1 ) );
    a = b + 1;
  }
  return L;
}
static std::string note_head_( const std::string &t ){
  std::string h = t;  for( char &c : h ) if( (unsigned char)c < 32 || c == 127 ) c = ' ';
  const size_t a = h.find_first_not_of( ' ' ) , b = h.find_last_not_of( ' ' );
  return a == std::string::npos ? std::string( "notes" ) : h.substr( a , b - a + 1 );
}

// un valor "..." sin las comillas ni los escapes; si no es una cadena, tal cual
static std::string unq_( const std::string &v ){
  size_t a = v.find_first_not_of( " \t" ) , b = v.find_last_not_of( " \t" );
  if( a == std::string::npos ) return v;
  const std::string t = v.substr( a , b - a + 1 );
  if( t.size() < 2 || t.front() != '"' || t.back() != '"' ) return v;
  std::string s;
  for( size_t i = 1 ; i + 1 < t.size() ; i++ ){
    if( t[i] == '\\' && i + 2 < t.size() && ( t[i+1] == '"' || t[i+1] == '\\' ) ) i++;
    s += t[i];
  }
  return s;
}

// algun <dicom> con una ruta RELATIVA (en el contenedor se resuelve desde SU
// carpeta, SPEC 14.2). Con las $VARIABLES$ del fichero; una que no define se da
// al abrir: no se sabe, no cuenta
static bool lazyrel_( const std::vector<Entry> &E ){
  std::map<std::string,std::string> vars;
  for( const Entry &e : E ) if( e.key.size() > 1 && e.key[0] == '$' ) vars[e.key] = unq_( e.value );
  for( const Entry &e : E ){
    if( e.key != "data" || e.value.find( "<dicom" ) == std::string::npos ) continue;
    const size_t q0 = e.value.find( '"' );
    if( q0 == std::string::npos ) continue;
    std::string p;  size_t i = q0 + 1;
    for( ; i < e.value.size() && e.value[i] != '"' ; i++ ){
      if( e.value[i] == '\\' && i + 1 < e.value.size() && ( e.value[i+1] == '"' || e.value[i+1] == '\\' ) ) i++;
      p += e.value[i];
    }
    std::string out;  bool known = true;
    for( size_t k = 0 ; k < p.size() && known ; ){
      if( p[k] != '$' ){ out += p[k++];  continue; }
      if( k + 1 < p.size() && p[k+1] == '$' ){ out += '$';  k += 2;  continue; }
      const size_t j = p.find( '$' , k + 1 );
      if( j == std::string::npos ){ known = false;  break; }
      auto v = vars.find( p.substr( k , j - k + 1 ) );
      if( v == vars.end() ){ known = false;  break; }
      out += v->second;  k = j + 1;
    }
    const bool abs = ( out.size() >= 2 && isalpha( (unsigned char)out[0] ) && out[1] == ':' ) || ( !out.empty() && ( out[0] == '/' || out[0] == '\\' ) );
    if( known && !abs ) return true;
  }
  return false;
}

static M member_( const File &S , const std::string &tag , const detail::Chunk &src ){
  M m;  m.tag = tag;  m.src = src;
  m.dims = i2s( (int64_t)S.grid( 'X' ).size() ) + " x " + i2s( (int64_t)S.grid( 'Y' ).size() ) + " x " +
           i2s( (int64_t)S.grid( 'Z' ).size() ) + " x " + i2s( (int64_t)S.grid( 'T' ).size() );
  // una entrada a la vista empieza su linea por la clave: las de la parte <hidden>
  // no estan en header(), que es la cabecera TAL CUAL. Un I3Db lo esconde todo
  std::set<std::string> V;
  if( !S.hidden() ){
    const std::string &h = S.header();
    for( size_t a = 0 ; a < h.size() ; ){
      size_t b = h.find( '\n' , a );  if( b == std::string::npos ) b = h.size();
      if( h.compare( a , 5 , "info." ) == 0 ){
        size_t k = a + 5;
        while( k < b && ( isalnum( (unsigned char)h[k] ) || h[k] == '_' || h[k] == '.' ) ) k++;
        size_t r = k;  while( r < b && ( h[r] == ' ' || h[r] == '\t' ) ) r++;
        if( r < b && ( h[r] == '[' || h[r] == '(' || h[r] == '=' ) ) V.insert( h.substr( a , k - a ) );
      }
      a = b + 1;
    }
  }
  for( const Entry &e : S.entries() ){
    if( e.key.compare( 0 , 5 , "info." ) != 0 ) continue;
    m.keys.push_back( e.key );  m.vals.push_back( e.value );  m.vis.push_back( V.count( e.key ) > 0 );
  }
  m.lazyrel = lazyrel_( S.entries() );
  return m;
}

// el RESUMEN (SPEC 14.3): una info.key esta si TODOS la tienen con el mismo valor
// crudo; a la vista (V) si lo esta en todos, y si no a la parte oculta (H)
static void summary_( const std::vector<M> &L , std::vector<std::string> &V , std::vector<std::string> &H ){
  V.clear();  H.clear();
  if( L.empty() ) return;
  for( size_t k = 0 ; k < L[0].keys.size() ; k++ ){
    const std::string &key = L[0].keys[k] , &val = L[0].vals[k];
    bool vis = L[0].vis[k] , common = true;
    for( size_t i = 1 ; i < L.size() && common ; i++ ){
      auto j = std::find( L[i].keys.begin() , L[i].keys.end() , key );
      if( j == L[i].keys.end() || L[i].vals[j - L[i].keys.begin()] != val ) common = false;
      else vis = vis && L[i].vis[j - L[i].keys.begin()];
    }
    if( !common ) continue;
    ( vis ? V : H ).push_back( key + " = " + val );
  }
}

static std::vector<uint8_t> hide_( const std::vector<std::string> &H ){
  if( H.empty() ) return {};
  std::string t = "# -- common to every stack\n";
  for( const auto &l : H ) t += l + "\n";
  return detail::hide_block( t );
}

static std::string tagsp_( const std::string &t ){ return t.empty() ? "" : t + " "; }

// la cabecera rellena hasta R bytes con la reserva: '#' espacios LF '---' LF.
// R < 0: la justa, con la reserva minima. Vacia si no cabe en R
static std::string text_( const std::vector<M> &L , int N , const std::string &comment , const std::vector<std::string> &V ,
                          int64_t ha , int64_t hb , int64_t R , const std::string &nhead ){
  std::vector<std::string> lines = { comment.empty() ? std::string( "MI3D" ) : "MI3D  # " + comment };
  std::vector<std::string> D;  size_t w = 0;
  for( const M &m : L ){ D.push_back( "i3d(" + i2s( m.n ) + ") = <i3d @" + i2s( m.at ) + ":" + i2s( m.at + m.src.len - 1 ) + ">" );  w = std::max( w , D.back().size() ); }
  for( size_t i = 0 ; i < L.size() ; i++ ) lines.push_back( D[i] + std::string( w - D[i].size() , ' ' ) + "  # " + tagsp_( L[i].tag ) + "[ " + L[i].dims + " ]" );
  int maxn = 0;  for( const M &m : L ) maxn = std::max( maxn , m.n );
  if( N > 0 && maxn < N ) lines.push_back( "i3d(" + i2s( N ) + ") = <missing>" );
  // las NOTAS (SPEC 14.7): "# -- <titulo>", y de cada miembro con nota sus lineas,
  // la primera tras su i3d(n), todas desde la misma columna
  size_t wn = 0;
  for( const M &m : L ) if( !m.note.empty() ) wn = std::max( wn , ( "i3d(" + i2s( m.n ) + ")" ).size() );
  if( wn > 0 ){
    lines.push_back( "" );  lines.push_back( "# -- " + note_head_( nhead ) );
    for( const M &m : L ){
      const std::string t = "i3d(" + i2s( m.n ) + ")";
      for( size_t i = 0 ; i < m.note.size() ; i++ )
        lines.push_back( "#  " + ( i == 0 ? t + std::string( wn - t.size() , ' ' ) : std::string( wn , ' ' ) ) + "  " + m.note[i] );
    }
  }
  if( ha >= 0 ){ lines.push_back( "" );  lines.push_back( "header = <hidden @" + i2s( ha ) + ":" + i2s( hb ) + ">  # the rest of the header" ); }
  if( !V.empty() ){ lines.push_back( "" );  lines.push_back( "# -- common to every stack" );  lines.insert( lines.end() , V.begin() , V.end() ); }
  std::string c;  for( const auto &l : lines ) c += l + "\n";
  if( R < 0 ) R = (int64_t)c.size() + 6;
  const int64_t pad = R - (int64_t)c.size() - 6;               // '#' pad LF '---' LF
  if( pad < 0 ) return "";
  return c + "#" + std::string( (size_t)pad , ' ' ) + "\n---\n";
}

// los separadores del escritor amable, delante y detras de cada miembro
static std::string open_sep_( const M &m ){ return "****** # " + tagsp_( m.tag ) + "[ " + m.dims + " ]\n"; }
static std::string close_sep_( const M &m ){ return "\n++++++ # " + m.tag + "\n"; }

// el .mi3d entero, todo o nada. El binario: cada miembro entre sus separadores y
// el bloque <hidden> del resumen el ULTIMO. Los offsets son del binario, asi que la
// cabecera no depende de su propia longitud: R = la justa + la reserva
static void write_full_( const std::string &f , std::vector<M> L , int N , int64_t reserve , const std::string &comment , const std::string &nhead ){
  std::vector<std::string> V , H;
  summary_( L , V , H );
  const std::vector<uint8_t> hb = hide_( H );
  std::vector<std::vector<uint8_t>> seps;  seps.reserve( 2 * L.size() );
  std::vector<detail::Chunk> ch( 1 );
  int64_t pos = 0;
  for( M &m : L ){
    const std::string o = open_sep_( m ) , c = close_sep_( m );
    seps.emplace_back( o.begin() , o.end() );  seps.emplace_back( c.begin() , c.end() );
    m.at = pos + (int64_t)o.size();
    pos = m.at + m.src.len + (int64_t)c.size();
    detail::Chunk a;  a.b = &seps[seps.size() - 2];
    detail::Chunk z;  z.b = &seps.back();
    ch.push_back( a );  ch.push_back( m.src );  ch.push_back( z );
  }
  int64_t ha = -1 , hz = -1;
  if( !hb.empty() ){ ha = pos;  hz = pos + (int64_t)hb.size() - 1;  detail::Chunk h;  h.b = &hb;  ch.push_back( h ); }
  const std::string h0 = text_( L , N , comment , V , ha , hz , -1 , nhead );
  const std::string head = text_( L , N , comment , V , ha , hz , (int64_t)h0.size() - 2 + reserve , nhead );
  const std::vector<uint8_t> hv( head.begin() , head.end() );
  ch[0].b = &hv;
  detail::write_atomic( f , ch );
}

static std::string folder_( const std::string &f ){
  std::error_code ec;
  std::filesystem::path p = std::filesystem::weakly_canonical( std::filesystem::u8path( f ) , ec );   // sin \?\: se compara
  if( ec ) p = std::filesystem::absolute( std::filesystem::u8path( f ) , ec );
  std::string s = p.parent_path().u8string();
  std::transform( s.begin() , s.end() , s.begin() , []( unsigned char c ){ return (char)tolower( c ); } );
  return s;
}

// los miembros nuevos, de ficheros .i3d. Un "" es un hueco (no da miembro). Un
// Lazy con rutas relativas de OTRA carpeta es un error: en el contenedor se
// resolverian desde la suya (SPEC 14.2)
static std::vector<M> new_( const std::string &container , const std::vector<std::string> &files , const std::vector<int> &ns ,
                            const std::vector<std::string> *tags , bool lazykeep ){
  if( tags && tags->size() != files.size() )
    throw Error( "badInput" , "one tag per file (" + i2s( (int64_t)files.size() ) + ", not " + i2s( (int64_t)tags->size() ) + ")" );
  std::vector<M> L;
  for( size_t i = 0 ; i < files.size() ; i++ ){
    const std::string &f = files[i];
    if( f.empty() ) continue;
    std::error_code ec;
    if( !std::filesystem::is_regular_file( u8p( f ) , ec ) ) throw Error( "badInput" , "no file '" + f + "'" );
    const int64_t size = (int64_t)std::filesystem::file_size( u8p( f ) , ec );
    File S( f );                                       // un .mi3d da badMagic
    std::string tag = tags ? (*tags)[i] : u8p( f ).filename().u8string();
    for( char &c : tag ) if( (unsigned char)c < 32 ) c = ' ';
    detail::Chunk src;  src.file = f;  src.off = 0;  src.len = size;
    M m = member_( S , tag , src );
    if( m.lazyrel && !lazykeep && folder_( f ) != folder_( container ) )
      throw Error( "lazyFolder" , "'" + f + "' is Lazy with RELATIVE paths, and in the container they would resolve from the folder of '" +
                   container + "' (SPEC 14.2). Put the container in its folder, or pass Lazy keep." );
    m.n = ns[i];
    L.push_back( m );
  }
  return L;
}

// las etiquetas de un .mi3d: los comentarios de sus lineas i3d(n), sin el [ dims ]
std::map<int,std::string> tags( const Container &C ){
  std::map<int,std::string> T;
  const std::string &h = C.header();
  for( size_t a = 0 ; a < h.size() ; ){
    size_t b = h.find( '\n' , a );  if( b == std::string::npos ) b = h.size();
    const std::string l = h.substr( a , b - a );
    a = b + 1;
    if( l.compare( 0 , 4 , "i3d(" ) != 0 ) continue;
    size_t p = 4;  while( p < l.size() && l[p] == ' ' ) p++;
    size_t q = p;  while( q < l.size() && isdigit( (unsigned char)l[q] ) ) q++;
    if( q == p || q - p > 9 ) continue;
    const int n = std::stoi( l.substr( p , q - p ) );
    while( q < l.size() && l[q] == ' ' ) q++;
    if( q >= l.size() || l[q] != ')' ) continue;
    const size_t hsh = l.find( '#' , q );
    if( hsh == std::string::npos ) continue;
    std::string t = l.substr( hsh + 1 );
    // sin el [ dims ] del final, y sin espacios a los lados
    size_t e = t.find_last_not_of( " \t" );
    if( e != std::string::npos && t[e] == ']' ){ size_t o = t.rfind( '[' , e );  if( o != std::string::npos ) t = t.substr( 0 , o ); }
    size_t s0 = t.find_first_not_of( " \t" ) , s1 = t.find_last_not_of( " \t" );
    T[n] = s0 == std::string::npos ? "" : t.substr( s0 , s1 - s0 + 1 );
  }
  return T;
}

// las NOTAS de un .mi3d (SPEC 14.7): el bloque "# -- <titulo>" cuya linea siguiente
// es "#  i3d(n)"; cada "#  i3d(n)" empieza la nota de n, y las lineas "#" que la
// siguen (hasta una que no empieza por '#' o vacia) la continuan. El texto, desde
// la columna en que lo escribe text_: tras el i3d(n) mas largo y dos blancos
std::map<int,std::vector<std::string>> notes( const Container &C , std::string &head ){
  std::map<int,std::vector<std::string>> NT;  head.clear();
  std::vector<std::string> H;
  const std::string &h = C.header();
  for( size_t a = 0 ; a < h.size() ; ){
    size_t b = h.find( '\n' , a );  if( b == std::string::npos ) b = h.size();
    std::string l = h.substr( a , b - a );  if( !l.empty() && l.back() == '\r' ) l.pop_back();
    H.push_back( l );  a = b + 1;
  }
  // n del "i3d(n)" en la columna 3 de l, y donde acaba; 0 si no
  auto tok = []( const std::string &l , size_t &e ) -> int {
    if( l.compare( 0 , 7 , "#  i3d(" ) != 0 ) return 0;
    size_t q = 7;  while( q < l.size() && isdigit( (unsigned char)l[q] ) ) q++;
    if( q == 7 || q - 7 > 9 || q >= l.size() || l[q] != ')' ) return 0;
    e = q + 1;  return std::stoi( l.substr( 7 , q - 7 ) );
  };
  for( size_t i = 0 ; i + 1 < H.size() ; i++ ){
    size_t e = 0;
    if( H[i].compare( 0 , 5 , "# -- " ) != 0 || !tok( H[i+1] , e ) ) continue;
    head = H[i].substr( 5 );
    size_t j = i + 1 , col = 0;
    for( ; j < H.size() && !H[j].empty() && H[j][0] == '#' ; j++ ) if( tok( H[j] , e ) ) col = std::max( col , e + 2 );
    int n = 0;
    for( size_t k = i + 1 ; k < j ; k++ ){
      const int t = tok( H[k] , e );  if( t ) n = t;
      std::string s = H[k].size() > col ? H[k].substr( col ) : "";
      const size_t z = s.find_last_not_of( ' ' );
      if( z != std::string::npos ) NT[n].push_back( s.substr( 0 , z + 1 ) );     // sin las vacias (la de la reserva)
    }
    break;
  }
  return NT;
}

// los miembros PRESENTES de un .mi3d, en orden de n; su src es su rango en f; y
// el titulo de sus notas
static std::vector<M> load_( const std::string &f , int &N , std::unique_ptr<Container> &C , std::string &nhead ){
  C.reset( new Container( f ) );
  N = C->count();
  const auto T = tags( *C );
  const auto NT = notes( *C , nhead );
  std::vector<M> L;
  for( int n = 1 ; n <= N ; n++ ){
    if( !C->present( n ) ) continue;
    int64_t base = 0 , size = 0;
    C->window( n , base , size );
    File S( f , {} , base , size );
    detail::Chunk src;  src.file = f;  src.off = base;  src.len = size;
    auto t = T.find( n );
    M m = member_( S , t == T.end() ? "" : t->second , src );
    m.n = n;
    auto o = NT.find( n );  if( o != NT.end() ) m.note = o->second;
    L.push_back( m );
  }
  return L;
}

static std::string comment_( const std::string &c , const char *who , size_t k ){
  return c.empty() ? std::string( who ) + " " + detail::now_text() + ", " + i2s( (int64_t)k ) + " stacks" : c;
}

// en el sitio, sin mover lo que hay (SPEC 14.4). En este orden, para que el
// fichero valga con lo de antes hasta el ultimo paso:
//   1. los miembros nuevos, con sus separadores, al FINAL del fichero;
//   2. el bloque <hidden> nuevo detras (el viejo queda como bytes sin referencia);
//   3. la cabecera, EN SU SITIO, con la reserva ajustada a la misma longitud R.
// Si la cabecera nueva no cabe en R: el fichero entero, con una reserva nueva.
// keephidden: si el <hidden> nuevo es IGUAL al de ahora, se queda donde esta
static bool commit_( const std::string &f , const Container &C , std::vector<M> L , int N , int64_t reserve ,
                     const std::string &comment , bool keephidden , const std::string &nhead ){
  const int64_t R = C.binary_start();
  std::error_code ec;
  int64_t pos = (int64_t)std::filesystem::file_size( u8p( f ) , ec ) - R;     // el final, desde el binario
  if( ec ) throw Error( "cannotOpen" , "cannot read '" + f + "'" );
  std::vector<std::string> V , H;
  summary_( L , V , H );
  const std::vector<uint8_t> hb = hide_( H );
  std::vector<detail::Chunk> app;
  std::vector<std::vector<uint8_t>> seps;  seps.reserve( 2 * L.size() );
  for( M &m : L ){
    if( m.src.file == f ){ m.at = m.src.off - R;  continue; }
    const std::string o = open_sep_( m ) , c = close_sep_( m );
    seps.emplace_back( o.begin() , o.end() );  seps.emplace_back( c.begin() , c.end() );
    m.at = pos + (int64_t)o.size();
    pos = m.at + m.src.len + (int64_t)c.size();
    detail::Chunk a;  a.b = &seps[seps.size() - 2];
    detail::Chunk z;  z.b = &seps.back();
    app.push_back( a );  app.push_back( m.src );  app.push_back( z );
  }
  int64_t ha = -1 , hz = -1;
  if( !hb.empty() ){
    // el bloque <hidden> de ahora: sus bytes y su @a:b
    bool same = false;
    for( const Entry &e : C.entries() ){
      if( e.key != "header" ) continue;
      const Descriptor d = File::parse_descriptor( e.value , e.line );
      if( d.encoding != "hidden" || d.offset < 0 || d.length < 0 ) break;
      if( keephidden && d.length == (int64_t)hb.size() ){
        std::ifstream s( u8p( f ) , std::ios::binary );
        s.seekg( R + d.offset );
        std::vector<uint8_t> old( (size_t)d.length );
        s.read( (char*)old.data() , (std::streamsize)old.size() );
        if( s.gcount() == d.length && old == hb ){ same = true;  ha = d.offset;  hz = d.offset + d.length - 1; }
      }
      break;
    }
    if( !same ){ ha = pos;  hz = pos + (int64_t)hb.size() - 1;  detail::Chunk h;  h.b = &hb;  app.push_back( h ); }
  }
  const std::string head = text_( L , N , comment , V , ha , hz , R , nhead );
  if( head.empty() ){
    for( M &m : L ) m.at = -1;
    write_full_( f , L , N , reserve , comment , nhead );
    return true;
  }
  // 1, 2: al final
  if( !app.empty() ){
    std::fstream o( u8p( f ) , std::ios::binary | std::ios::in | std::ios::out );
    if( !o ) throw Error( "cannotOpen" , "cannot write '" + f + "'" );
    o.seekp( 0 , std::ios::end );
    for( const detail::Chunk &c : app ){
      if( c.b ) o.write( (const char*)c.b->data() , (std::streamsize)c.b->size() );
      else {
        std::ifstream s( u8p( c.file ) , std::ios::binary );
        if( !s ) throw Error( "cannotOpen" , "cannot read '" + c.file + "'" );
        s.seekg( c.off );
        std::vector<char> buf( 1 << 26 );
        for( int64_t left = c.len ; left > 0 ; ){
          const int64_t k = std::min<int64_t>( left , (int64_t)buf.size() );
          s.read( buf.data() , (std::streamsize)k );
          if( s.gcount() != k ) throw Error( "cannotOpen" , "'" + c.file + "' ends early" );
          o.write( buf.data() , (std::streamsize)k );
          left -= k;
        }
      }
      if( !o ) throw Error( "cannotOpen" , "cannot write '" + f + "' (disk full?)" );
    }
  }
  // 3: la cabecera en su sitio, la misma longitud
  std::fstream o( u8p( f ) , std::ios::binary | std::ios::in | std::ios::out );
  if( !o ) throw Error( "cannotOpen" , "cannot write '" + f + "'" );
  o.seekp( 0 );
  o.write( head.data() , (std::streamsize)head.size() );
  o.flush();
  if( !o ) throw Error( "cannotOpen" , "cannot write the header of '" + f + "'" );
  return false;
}

static int64_t reserve_( int64_t r ){
  if( r == 0 ) return 8192;
  if( r < 2 ) throw Error( "badInput" , "the reserve is the bytes of the reserve line, an integer >= 2" );
  return r;
}

void write( const std::string &f , const std::vector<std::string> &files , const std::vector<std::string> *tg , int64_t reserve ,
            const std::string &comment , bool lazykeep ){
  if( files.empty() ) throw Error( "badInput" , "no files: give the .i3d files to put in the container" );
  std::vector<int> ns;  for( size_t i = 0 ; i < files.size() ; i++ ) ns.push_back( (int)i + 1 );
  std::vector<M> L = new_( f , files , ns , tg , lazykeep );
  write_full_( f , L , (int)files.size() , reserve_( reserve ) , comment_( comment , "mi3d_write" , L.size() ) , "" );
}

// lo mismo, con los miembros en memoria: cada uno se lee (su cabecera, para el
// resumen y sus dimensiones) y se copia byte a byte, como el de un fichero
void write( const std::string &f , const std::vector<Stack> &stacks , int64_t reserve , const std::string &comment , bool lazykeep ,
            const std::string &nhead ){
  if( stacks.empty() ) throw Error( "badInput" , "no stacks: give the .i3d to put in the container" );
  std::vector<M> L;
  for( size_t i = 0 ; i < stacks.size() ; i++ ){
    const Stack &s = stacks[i];
    if( !s.bytes ) continue;                                     // un hueco
    const std::string name = "stack " + i2s( (int64_t)i + 1 );
    File S( s.bytes , name );                                    // un .mi3d da badMagic
    std::string tag = s.tag;
    for( char &c : tag ) if( (unsigned char)c < 32 ) c = ' ';
    detail::Chunk src;  src.b = s.bytes.get();  src.len = (int64_t)s.bytes->size();
    M m = member_( S , tag , src );
    if( m.lazyrel && !lazykeep )
      throw Error( "lazyFolder" , name + " is Lazy with RELATIVE paths, and in the container they would resolve from the folder of '" +
                   f + "' (SPEC 14.2). Pass LazyKeep if that is what you want." );
    m.n = (int)i + 1;
    m.note = note_lines_( s.note );
    L.push_back( m );
  }
  write_full_( f , L , (int)stacks.size() , reserve_( reserve ) , comment_( comment , "mi3d_write" , L.size() ) , nhead );
}

void compact( const std::string &f , bool renumber , int64_t reserve , const std::string &comment ){
  int N = 0;  std::unique_ptr<Container> C;
  std::string nh;  std::vector<M> L = load_( f , N , C , nh );
  if( renumber ){ for( size_t i = 0 ; i < L.size() ; i++ ) L[i].n = (int)i + 1;  N = (int)L.size(); }
  C.reset();
  write_full_( f , L , N , reserve_( reserve ) , comment_( comment , "mi3d_compact" , L.size() ) , nh );
}

int append( const std::string &f , const std::vector<std::string> &files , const std::vector<std::string> *tg , int64_t reserve ,
            const std::string &comment , bool lazykeep ){
  if( files.empty() || std::any_of( files.begin() , files.end() , []( const std::string &s ){ return s.empty(); } ) )
    throw Error( "badInput" , "the files to append: one or more .i3d paths (no holes: they go at the end)" );
  std::error_code ec;
  if( !std::filesystem::exists( u8p( f ) , ec ) ){
    write( f , files , tg , reserve , comment , lazykeep );
    return 1;
  }
  int N = 0;  std::unique_ptr<Container> C;
  std::string nh;  std::vector<M> L = load_( f , N , C , nh );
  std::vector<int> ns;  for( size_t i = 0 ; i < files.size() ; i++ ) ns.push_back( N + (int)i + 1 );
  std::vector<M> A = new_( f , files , ns , tg , lazykeep );
  L.insert( L.end() , A.begin() , A.end() );
  commit_( f , *C , L , ns.back() , reserve_( reserve ) , comment_( comment , "mi3d_append" , L.size() ) , false , nh );
  return N + 1;
}

void remove( const std::string &f , const std::vector<int> &ns , const std::string &comment ){
  int N = 0;  std::unique_ptr<Container> C;
  std::string nh;  std::vector<M> L = load_( f , N , C , nh );
  if( ns.empty() ) throw Error( "badInput" , "no members to remove" );
  for( int n : ns )
    if( std::none_of( L.begin() , L.end() , [n]( const M &m ){ return m.n == n; } ) )
      throw Error( "badInput" , "member " + i2s( n ) + " is not in '" + f + "' (1.." + i2s( N ) + ", not the holes)" );
  L.erase( std::remove_if( L.begin() , L.end() , [&]( const M &m ){ return std::count( ns.begin() , ns.end() , m.n ) > 0; } ) , L.end() );
  commit_( f , *C , L , N , 8192 , comment_( comment , "mi3d_remove" , L.size() ) , true , nh );
}

} // namespace mi3d
} // namespace i3d
