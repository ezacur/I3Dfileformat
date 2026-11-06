// i3d.hpp -- lector del formato .i3d (SPEC.md), nucleo en C++17.
//
//   i3d::File f( "serie.i3d" );      // SOLO lee y valida la cabecera
//   f.grid('X')                       // la rejilla, exacta
//   f.transform()                     // 4x4, por filas
//   f.data_shape(), f.data_type()     // sin tocar el binario
//   f.read_data( buffer , nbytes )    // ahora si: lee y coloca todos los bloques
//
// Todo error es una i3d::Error con un identificador corto ("badHeader",
// "coverage", ...) y un mensaje. La API en C (i3d_c.h) la envuelve.
//
// Lo que esta version NO decodifica -- y por tanto da error AL PEDIRLO, no al
// abrir, como manda SPEC 4 --: <gif>; y <zlib>, <jpegls>, <png> o <dicom> si se
// compilo sin I3D_HAVE_ZLIB, I3D_HAVE_CHARLS, I3D_HAVE_LODEPNG o I3D_HAVE_DCMTK.
//
// Las rutas (la del .i3d, y las de los "path" de los descriptores) son UTF-8.
#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <array>
#include <map>
#include <stdexcept>
#include <filesystem>
#include <memory>

namespace i3d {

struct Error : std::runtime_error {
  std::string id;
  Error( const std::string &id_ , const std::string &msg ) : std::runtime_error( msg ) , id( id_ ) {}
};

enum class Type { int8 , uint8 , int16 , uint16 , int32 , uint32 , int64 , uint64 , single , double_ , none };
const char *type_name( Type t );
size_t      type_size( Type t );
Type        type_from_name( const std::string &s );   // "int16" -> Type::int16; Type::none si no es un tipo

// un intervalo [lo,hi) 0-based sobre una dimension
struct Range { int64_t lo = 0 , hi = 0; };

struct Descriptor {
  std::string encoding;                 // raw zlib dicom missing png gif ...
  Type        type = Type::none;
  std::vector<int64_t> shape;           // {shape}, si lo hay
  int64_t     offset = -1 , length = -1;   // length: -1 no dada, LEN_EOF hasta el final
  static const int64_t LEN_EOF = -2;    // @a+Inf  o  @a:EOF
  std::string path;                     // "path"
  bool        has_crc = false;          // crc XXXXXXXX: CRC-32 (el de zlib) de los bytes
  uint32_t    crc = 0;                  // DECODIFICADOS del bloque (SPEC 4): del dato, no del fichero
  int64_t     frame_lo = -1 , frame_hi = -1;
  std::string text;                     // el descriptor tal cual, para mensajes
};

struct Block {
  std::vector<Range> box;               // i j k t c...  (0-based, hi exclusivo)
  Descriptor desc;
  int line = 0;
};

struct Entry {                          // una entrada de la cabecera, cruda
  std::string key , subs , value;       // subs: lo que habia entre ( ), o ""
  bool paren = false;                   // habia ( ): distingue data() (error) de data
  int line = 0;
};

// un info.* ya interpretado (SPEC 7), en el orden del fichero, visible u oculto
struct Info {
  std::string name;                     // la clave sin 'info.': "planes.Filename"
  char kind = 'o';                      // 'n' numeros, 't' textos, 'o' otra cosa, 'e' error
  std::vector<double> numbers;          // 'n'
  std::vector<std::string> text;        // 't': sin escapes y con las $VARIABLES$ sustituidas
                                        // 'o': UNO, el valor crudo
  std::string err , err_id;             // 'e': una variable que no existe, un $ sin pareja
};

class File {
public:
  // overrides: variables $NOMBRE$ -> valor que MANDAN sobre las del fichero (asi
  // los .dcm se pueden mover sin tocar el .i3d). Claves sin los '$'.
  explicit File( const std::string &path , const std::map<std::string,std::string> &overrides = {} );
  // un MIEMBRO de un contenedor .mi3d (SPEC 14): los bytes [base, base+size) de
  // path se leen como si fueran el fichero entero. Las rutas relativas, respecto
  // al directorio de path (el del contenedor). Lo normal es Container::open
  File( const std::string &path , const std::map<std::string,std::string> &overrides , int64_t base , int64_t size );
  // un .i3d EN MEMORIA (los bytes de Writer::encode, p.ej.): name solo para los
  // mensajes, y las rutas relativas se resuelven desde su carpeta
  File( std::shared_ptr<const std::vector<uint8_t>> bytes , const std::string &name , const std::map<std::string,std::string> &overrides = {} );

  // la ruta de un descriptor, con las $VARIABLES$ sustituidas y resuelta
  // respecto al directorio del .i3d
  std::string resolve_path( const std::string &p ) const;

  const std::vector<double> &grid( char axis ) const;      // 'X' 'Y' 'Z' 'T'
  const std::array<double,16> &transform() const { return A_; }   // por filas

  // data
  const std::vector<int64_t> &data_shape() const { return shape_; }  // i j k t c...
  Type    data_type() const { return type_; }
  size_t  data_bytes() const;
  void    read_data( void *out , size_t nbytes ) const;   // lanza si nbytes no cuadra
  // el PRIMER INSTANTE, data(:,:,:,1,c...): solo decodifica los bloques que lo
  // cortan. Forma i j k 1 c...
  std::vector<int64_t> first_frame_shape() const;
  size_t  first_frame_bytes() const;
  void    read_first_frame( void *out , size_t nbytes ) const;
  const std::vector<Block> &blocks() const { return blocks_; }
  std::vector<const Block*> missing() const;

  // fill

  // todo lo demas: info.*, y claves que esta version no conoce
  const std::vector<Entry> &entries() const { return entries_; }
  const Entry *find( const std::string &key ) const;
  // los info.* interpretados: numeros, o textos con las $VARIABLES$ ya sustituidas
  // (las del fichero y las de overrides), como en las rutas de los descriptores
  const std::vector<Info> &infos() const { return infos_; }
  // en claro, tambien si el fichero es I3Db, pero TAL CUAL: una parte <hidden>
  // (SPEC 1.2) sigue siendo su linea 'header = <hidden ...>'. Sus entradas, en
  // cambio, si estan en entries(), en el sitio de esa linea
  const std::string &header() const { return header_; }
  bool    hidden() const { return hidden_; }                // SPEC 1.1
  int64_t binary_start() const { return b0_; }           // desde el inicio del fichero (o del miembro)

  // thumbnail (SPEC 7): si lo hay, su descriptor (lanza noThumbnail si no), y sus
  // bytes decodificados, uint8 en orden columna {filas cols}, {filas cols 1 frames} o RGB {filas cols 3 frames}
  bool has_thumbnail() const { return find( "thumbnail" ) != nullptr; }
  Descriptor thumbnail_descriptor() const;
  std::vector<uint8_t> read_thumbnail() const;
  // los bytes DECODIFICADOS de un bloque, y si lleva crc, comprobados (badCRC)
  std::vector<uint8_t> read_bytes( const Descriptor &d , size_t expected ) const;

  // utilidades publicas, para la API en C y los tests
  static Descriptor parse_descriptor( const std::string &value , int line );
  static std::vector<double> parse_numbers( const std::string &value , const std::string &what , int line );

private:
  std::string path_ , header_;
  int64_t base_ = 0 , size_ = 0;                // la ventana del fichero: [base_, base_+size_)
  std::shared_ptr<const std::vector<uint8_t>> mem_;   // en memoria: sus bytes (path_ es solo un nombre)
  bool hidden_ = false;
  std::map<std::string,std::string> vars_;      // "$NOMBRE$" -> valor (fichero + overrides)
  std::vector<uint8_t> read_dicom_( const Descriptor &d , size_t expected ) const;
  std::vector<uint8_t> decode_( const Descriptor &d , size_t expected ) const;
  int64_t b0_ = 0;
  std::vector<Entry> entries_;
  std::vector<double> X_ , Y_ , Z_ , T_;
  std::array<double,16> A_{};
  std::vector<Block> blocks_;
  std::vector<int64_t> shape_;
  Type type_ = Type::none;
  bool has_fill_ = false;    double fill_ = 0.0;  int64_t ifill_ = 0;  std::string fill_text_;
  std::vector<Info> infos_;

  void open_( const std::map<std::string,std::string> &overrides );
  void parse_header_();
  void build_infos_();
  std::string substitute_( const std::string &s0 , const std::string &what ) const;   // $VAR$ y $$
  void build_data_();
  void read_box_( const std::vector<Range> &W , void *out , size_t nbytes ) const;
};

// ====================================================================== .mi3d
// El contenedor (SPEC 14): una cabecera 'MI3D' con i3d(n) = <i3d @a:b>, un
// resumen info.* y quiza una parte <hidden>; cada miembro es un .i3d completo.
//
//   i3d::Container C( "estudio.mi3d" );     // solo lee y valida la cabecera
//   C.count()                               // N, el mayor n declarado
//   C.present( 5 )                          // false si es un hueco
//   i3d::File F = C.open( 2 );              // el miembro 2, como un .i3d
struct Member {
  Descriptor desc;                      // <i3d @a:b [crc X]>; offset desde el binario
  int64_t length = 0;                   // ya resuelta (@a+Inf / @a:EOF incluidas)
  int line = 0;
};

class Container {
public:
  explicit Container( const std::string &path );
  int  count() const { return N_; }
  bool present( int n ) const;          // badIndex fuera de 1..N
  const Member &member( int n ) const;  // badIndex, o missingMember en un hueco
  // la ventana del miembro en el FICHERO, comprobada (y su crc, si lo lleva):
  // lo que toma el constructor de File con base y size
  void window( int n , int64_t &base , int64_t &size ) const;
  File open( int n , const std::map<std::string,std::string> &overrides = {} ) const;

  const std::vector<Entry> &entries() const { return entries_; }   // con las de la parte <hidden>
  const std::string &header() const { return header_; }             // TAL CUAL, sin desplegar
  int64_t binary_start() const { return b0_; }
  const std::string &path() const { return path_; }

private:
  std::string path_ , header_;
  int64_t b0_ = 0 , size_ = 0;
  int N_ = 0;
  std::map<int,Member> members_;
  std::vector<Entry> entries_;
};

// ====================================================================== escritor
// El escritor de la FORMA CANONICA (SPEC 9): una sola manera de escribir cada
// cosa. Se le dan las piezas y write() decide el resto -- el encoding por tipo,
// el reparto en bloques, los crc, la parte <hidden>, la disposicion --:
//
//   i3d::Writer W;
//   W.set_data( p , i3d::Type::int16 , { 256 , 256 , 12 , 30 } );   // COPIA
//   W.set_grid( 'X' , x , 256 );  ...  W.set_transform( A );          // por filas
//   W.add_info_text( "SeriesDescription" , "cine" , 1 , "" );          // 1: a la vista
//   W.write( "serie.i3d" );                                           // todo o nada
//
// La VISIBILIDAD (SPEC 1.2) la da cada add_info_*: visible 1, a la vista (texto
// legible de la cabecera); 0, a la parte oculta (el bloque <hidden>). Lo que hace
// falta para leer data (rejillas, transform, data, thumbnail) va
// siempre a la vista, y $DICOMDIR$ siempre a la parte oculta.
class Writer {
public:

  void set_grid( char axis , const double *v , size_t n );       // sin darla: 0 : 1 : n-1
  void set_transform( const double *rows16 );                     // 4x4 por filas; sin darla: eye(4)
  void set_data( const void *p , Type t , const std::vector<int64_t> &dims );   // i j k t c...

  // info.KEY (KEY sin el 'info.'): una cadena, o una lista de numeros; comment, al
  // final de la linea ("" ninguno)
  void add_info_text( const std::string &key , const std::string &value , int visible , const std::string &comment );
  void add_info_numbers( const std::string &key , const double *v , size_t n , int visible , const std::string &comment );
  // una lista con UN VALOR POR FILA, cada fila con su comentario. Sin comentarios
  // (nullptr) y con nk*nt filas: una por PLANO (k la mas rapida), y el comentario
  // de cada una lo pone write(): el bloque de data de ese plano
  void add_info_rows_text( const std::string &key , const std::vector<std::string> &values , const std::vector<std::string> *comments , int visible );
  void add_info_rows_numbers( const std::string &key , const double *v , size_t n , const std::vector<std::string> *comments , int visible );   // todos enteros: como enteros
  // un comentario, EN EL SITIO donde se pide (la cabecera sale en el orden
  // canonico, no en el de las llamadas: el sitio es lo que se da antes o despues):
  //   "texto"    una linea '# texto' ENCIMA de lo SIGUIENTE que se de (rejilla,
  //              transform, data, thumbnail, info.*); si no se da nada
  //              mas, al final de la cabecera
  //   "\btexto"  '  # texto' al FINAL de la linea de lo ULTIMO que se dio (de una
  //              entrada de varias lineas, la primera); si no se dio nada todavia,
  //              al final de la PRIMERA linea, 'I3D  # texto'. '\b' es un BACKSPACE
  //              (char 8: sprintf('\b...') en MATLAB)
  void add_comment( const std::string &text );
  // thumbnail: uint8 gris {filas cols} o {filas cols 1 frames}, o RGB {filas cols 3 frames}, como UNA
  // imagen PNG (los frames uno al lado de otro). Otra cosa es badInput. Uno solo:
  // darlo otra vez lo reemplaza
  void set_thumbnail( const void *p , Type t , const std::string &tname , const std::vector<int64_t> &dims );
  // 'Lazy' (SPEC 4): el plano (k,t), 1-based, es una REFERENCIA a un .dcm sin
  // perdida de un componente. path "" = el plano no tiene fichero: <missing> si
  // data es entera y ese plano es todo ceros; si no, se materializa
  void set_plane_ref( int64_t k , int64_t t , const std::string &path );
  // Blocks (auto|volume|t), MaxBlockBytes, Hidden (0|1: I3Db),
  // Lazy (0|1: un bloque por plano y $DICOMDIR$, aunque ningun plano sea una
  // referencia; con alguna set_plane_ref ya lo es),
  // Verify (0|1, default 1: cada referencia se lee y tiene que dar su plano)
  void set_option( const std::string &name , const std::string &value );
  // $NOMBRE$ = "valor" (SPEC 2), NOMBRE de [A-Za-z0-9_]; va a la parte oculta. Lo
  // citan las rutas de <dicom> y, como texto, los info.* ("$DICOMDIR$/x.dcm").
  // Darla otra vez la reemplaza. Con Lazy, $DICOMDIR$ es la raiz de las
  // referencias (sin darla: la raiz comun de los .dcm)
  void set_variable( const std::string &name , const std::string &value );
  void write( const std::string &path ) const;
  // el fichero entero EN MEMORIA, los mismos bytes que escribiria write()
  std::vector<uint8_t> encode() const;

  struct Notes {                                 // los comentarios de add_comment de una pieza
    std::vector<std::string> pre;                // las lineas '# ...' de encima
    std::string tail;                            // lo de '\b': '  # a  # b' al final de su linea
  };
  struct Item {                                  // una pieza de la seccion info, en orden
    int kind = 0;                                // 0 linea, 1 filas
    std::string key , text , comment;            // text: el valor ya escrito
    std::vector<std::string> rows , rowc;        // las filas, y sus comentarios
    bool perplane = false;
    bool vis = true;                             // visible: a la vista (si no, la parte oculta)
    Notes notes;
  };

private:
  void encode_( std::vector<std::vector<uint8_t>> &out ) const;
  std::vector<double> G_[4];  bool hasG_[4] = { false , false , false , false };
  double A_[16] = { 1,0,0,0 , 0,1,0,0 , 0,0,1,0 , 0,0,0,1 };
  std::vector<uint8_t> D_;  Type type_ = Type::none;  std::vector<int64_t> dims_;
  std::vector<Item> info_;
  struct Thumb { std::vector<int64_t> dims; std::vector<uint8_t> v; };
  bool hasTh_ = false;  Thumb th_;
  // add_comment: los comentarios de las piezas que no son de info_, los que
  // esperan a la siguiente pieza, y cual fue la ultima (para '\b')
  enum Piece { NONE , GRID , TRANSFORM , DATA , THUMB , INFO };
  Notes nG_[4] , nA_ , nD_ , nT_;
  std::vector<std::string> pend_;
  Piece last_ = NONE;  size_t lastI_ = 0;
  Notes &notes_( Piece p , size_t i );
  void took_( Piece p , size_t i = 0 );
  std::map<std::pair<int64_t,int64_t>,std::string> refs_;
  std::string comment_;                          // el '  # ...' de la primera linea
  std::string blocks_ = "auto";  double maxb_ = 2147483647.0 - 8;
  bool hidden_ = false , verify_ = true , lazy_ = false;
  std::vector<std::pair<std::string,std::string>> vars_;   // set_variable, en orden
};

// La cabecera de src en claro y su binario byte a byte, a dst: oculta (I3Db,
// SPEC 1.1) o en texto. Todo o nada; dst puede ser src
void rewrite( const std::string &src , const std::string &dst , bool hidden );

// numeros como los escribe la cabecera: la forma mas corta exacta, con ".0"
std::string num2str( double x );

// lo que comparten los escritores (i3d_write.cpp, mi3d.cpp)
namespace detail {
  // un trozo del fichero: bytes, o un rango [off, off+len) de otro fichero
  struct Chunk { const std::vector<uint8_t> *b = nullptr; std::string file; int64_t off = 0 , len = 0; };
  // todo o nada: a un temporal al lado y un renombrado al final
  void write_atomic( const std::string &path , const std::vector<Chunk> &chunks );
  std::vector<uint8_t> hide_block( const std::string &text );     // un bloque <hidden> (SPEC 1.2)
  std::string now_text();                                         // "2026-10-25 10:00:00"
  // la ruta UTF-8 para abrir, renombrar o borrar; en Windows, una larga (>= 200)
  // va con \\?\ y absoluta, que MAX_PATH (260) no la corte
  std::filesystem::path fs_path( const std::string &utf8 );
}

} // namespace i3d
