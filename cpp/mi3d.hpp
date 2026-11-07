// mi3d.hpp -- el contenedor .mi3d (SPEC 14): escribirlo y modificarlo. Leerlo
// es i3d::Container (i3d.hpp).
//
//   i3d::mi3d::write( "estudio.mi3d" , { "a.i3d" , "" , "c.i3d" } , nullptr , 0 , "" , false );
//   int n = i3d::mi3d::append( "estudio.mi3d" , { "d.i3d" } , nullptr , 0 , "" , false );
//   i3d::mi3d::remove( "estudio.mi3d" , { 3 } , "" );
//   i3d::mi3d::compact( "estudio.mi3d" , false , 0 , "" );
//
// Cada miembro es un .i3d de cualquier variante copiado BYTE A BYTE. Los
// miembros no tienen nombre, solo numero; un "" en files es un HUECO. tags: una
// etiqueta por fichero (nullptr: su nombre), solo para los comentarios. reserve:
// los bytes de la linea de reserva (0: 8192). comment: el de la primera linea
// ("": "<funcion> <fecha>, K stacks"). lazykeep: acepta un miembro Lazy con
// rutas relativas de otra carpeta.
#pragma once
#include "i3d.hpp"

namespace i3d {
namespace mi3d {

// uno nuevo (o encima del que haya), todo o nada
void write( const std::string &f , const std::vector<std::string> &files , const std::vector<std::string> *tags ,
            int64_t reserve , const std::string &comment , bool lazykeep );
// un miembro EN MEMORIA: los bytes de un .i3d entero (Writer::encode) y su
// etiqueta; bytes nullptr es un HUECO. note: su NOTA (SPEC 14.7), lineas separadas por LF
struct Stack { std::shared_ptr<const std::vector<uint8_t>> bytes;  std::string tag;  std::string note; };
// uno nuevo desde miembros en memoria, todo o nada: el mismo .mi3d que write()
// con esos mismos bytes en ficheros y las mismas etiquetas, sin pasar por disco
// nhead: el titulo del bloque de notas ("": "notes")
void write( const std::string &f , const std::vector<Stack> &stacks , int64_t reserve , const std::string &comment , bool lazykeep ,
            const std::string &nhead = "" );
// al final, sin reescribir el fichero si la cabecera cabe en su reserva; si f no
// existe, lo crea. Devuelve el numero del primero que anade
int  append( const std::string &f , const std::vector<std::string> &files , const std::vector<std::string> *tags ,
             int64_t reserve , const std::string &comment , bool lazykeep );
// los miembros ns quedan como HUECOS; solo se reescribe la cabecera
void remove( const std::string &f , const std::vector<int> &ns , const std::string &comment );
// sin bytes sin referencia, el <hidden> el ultimo y una reserva nueva; renumber
// cierra los huecos
void compact( const std::string &f , bool renumber , int64_t reserve , const std::string &comment );
// las etiquetas: los comentarios de las lineas i3d(n), sin el [ dims ] del final
std::map<int,std::string> tags( const Container &C );
// las notas (SPEC 14.7): las lineas de cada miembro, y en head el titulo del bloque
std::map<int,std::vector<std::string>> notes( const Container &C , std::string &head );

} // namespace mi3d
} // namespace i3d
