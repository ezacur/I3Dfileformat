/* mi3d_c.h -- API en C del contenedor .mi3d (SPEC 14): mi3d.dll. Las mismas
 * reglas que i3d_c.h: ninguna excepcion cruza la frontera, cada funcion devuelve
 * 0 si va bien (o lo que dice), el mensaje se pide con mi3d_last_error, y toda
 * ruta es UTF-8.
 *
 * Leer:
 *   mi3d_file *m = mi3d_open( "estudio.mi3d" );          solo la cabecera
 *   int N = mi3d_count( m );                              miembros 1..N
 *   if( mi3d_present( m , 2 ) == 1 ) ...                  0: un hueco
 *   int64_t off , len;  mi3d_range( m , 2 , &off , &len );
 *   i3d_file *f = i3d_open_window( "estudio.mi3d" , off , len , 0 , NULL , NULL );   (i3d.dll)
 *
 * Escribir desde memoria: el escritor de abajo (mi3d_new ... mi3d_write).
 * Escribir por ruta (el error, en mi3d_last_error(NULL)):
 *   const char *files[] = { "a.i3d" , "" , "c.i3d" };    "" es un HUECO
 *   mi3d_write_files( "estudio.mi3d" , 3 , files , NULL , 0 , NULL , 0 );
 *   int first;  mi3d_append( "estudio.mi3d" , 1 , more , NULL , 0 , NULL , 0 , &first );
 *   int ns[] = { 3 };  mi3d_remove( "estudio.mi3d" , 1 , ns , NULL );
 *   mi3d_compact( "estudio.mi3d" , 0 , 0 , NULL );
 * tags: una etiqueta por fichero (NULL: su nombre), solo para los comentarios.
 * reserve: los bytes de la linea de reserva (0: 8192). comment: el de la primera
 * linea (NULL o "": "<funcion> <fecha>, K stacks"). lazykeep: acepta un miembro
 * Lazy con rutas relativas de otra carpeta (SPEC 14.2) */
#ifndef MI3D_C_H
#define MI3D_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(MI3D_BUILD_DLL)
#  define MI3D_API __declspec(dllexport)
#elif defined(_WIN32) && defined(MI3D_USE_DLL)
#  define MI3D_API __declspec(dllimport)
#else
#  define MI3D_API
#endif

typedef struct mi3d_file mi3d_file;

MI3D_API mi3d_file  *mi3d_open( const char *path );          /* NULL si falla: mi3d_last_error(NULL) */
MI3D_API void        mi3d_close( mi3d_file *m );
/* el ultimo error: de ese handle, o con NULL el del ultimo mi3d_open o escritura */
MI3D_API const char *mi3d_last_error( const mi3d_file *m );
MI3D_API const char *mi3d_last_error_id( const mi3d_file *m );

MI3D_API int         mi3d_count( mi3d_file *m );               /* N, el mayor n declarado */
MI3D_API int         mi3d_present( mi3d_file *m , int n );     /* 1, 0 (hueco), -1 (fuera de 1..N) */
/* los bytes del miembro n en el FICHERO (offset desde su inicio), comprobados:
 * que no es otro .mi3d, y su crc si lo lleva. Un hueco: el error missingMember */
MI3D_API int         mi3d_range( mi3d_file *m , int n , int64_t *offset , int64_t *length );
MI3D_API const char *mi3d_tag( mi3d_file *m , int n );         /* su etiqueta, "" si no tiene */
MI3D_API int         mi3d_entry_count( mi3d_file *m );
MI3D_API const char *mi3d_entry_key( mi3d_file *m , int e );   /* "" si e no existe */
MI3D_API const char *mi3d_entry_subs( mi3d_file *m , int e );
MI3D_API const char *mi3d_entry_value( mi3d_file *m , int e );
MI3D_API const char *mi3d_header( mi3d_file *m );              /* TAL CUAL, sin desplegar la parte <hidden> */
MI3D_API int64_t     mi3d_binary_start( mi3d_file *m );


/* ---- el ESCRITOR, como el de i3d_c.h, SIN PASAR POR DISCO ---------------------
 *
 *   mi3d_writer *m = mi3d_new();
 *   mi3d_add_stack( m , "001.cine" );                   empieza el miembro 1
 *   mi3d_set_data( m , p , "int16" , 4 , dims );        y lo demas, como i3d_*
 *   mi3d_add_info_text( m , "SeriesDescription" , "cine" , 1 , NULL );
 *   mi3d_add_stack( m , "002.loc" );                    el 1 se codifica (en memoria) y empieza el 2
 *   ...
 *   if( mi3d_write( m , "estudio.mi3d" ) ) puts( mi3d_wlast_error( m ) );
 *   mi3d_free( m );
 *
 * Cada mi3d_set_* / mi3d_add_info_* / mi3d_add_comment / mi3d_set_option /
 * mi3d_set_variable / mi3d_set_plane_ref hace lo que su i3d_* (i3d_c.h) sobre el
 * miembro EN CURSO, el del ultimo mi3d_add_stack. Al empezar otro (o en
 * mi3d_write) el anterior se codifica en memoria, como lo escribiria i3d_write, y
 * sus datos se liberan: en memoria quedan los miembros ya comprimidos. El
 * resultado es el mismo .mi3d que escribir cada miembro con i3d_write y juntarlos
 * con mi3d_write_files (con las mismas etiquetas), sin ningun fichero intermedio.
 * mi3d_add_hole: un HUECO (un numero sin miembro).
 * Opciones del CONTENEDOR (mi3d_set_option, en cualquier momento): Comment (el de
 * la primera linea; sin darla, "mi3d_write <fecha>, K stacks"), Reserve (los bytes
 * de la reserva; 0: 8192), LazyKeep (1: acepta un miembro Lazy con rutas
 * relativas, SPEC 14.2). Las demas (Blocks, MaxBlockBytes, Hidden, Lazy, Verify),
 * del miembro en curso. Seis argumentos como mucho (calllib sin thunk) */
typedef struct mi3d_writer mi3d_writer;
MI3D_API mi3d_writer *mi3d_new( void );
MI3D_API void         mi3d_free( mi3d_writer *m );
MI3D_API const char  *mi3d_wlast_error( const mi3d_writer *m );
MI3D_API const char  *mi3d_wlast_error_id( const mi3d_writer *m );
MI3D_API int mi3d_add_stack( mi3d_writer *m , const char *tag );       /* tag: el comentario de su linea (NULL: "") */
MI3D_API int mi3d_add_hole( mi3d_writer *m );
MI3D_API int mi3d_set_data( mi3d_writer *m , const void *data , const char *type , int ndims , const int64_t *dims );
MI3D_API int mi3d_set_Xgrid( mi3d_writer *m , const double *values , int64_t n );
MI3D_API int mi3d_set_Ygrid( mi3d_writer *m , const double *values , int64_t n );
MI3D_API int mi3d_set_Zgrid( mi3d_writer *m , const double *values , int64_t n );
MI3D_API int mi3d_set_Tgrid( mi3d_writer *m , const double *values , int64_t n );
MI3D_API int mi3d_set_transform( mi3d_writer *m , const double rows16[16] );
MI3D_API int mi3d_add_info_text( mi3d_writer *m , const char *key , const char *value , int visible , const char *comment );
MI3D_API int mi3d_add_info_numbers( mi3d_writer *m , const char *key , const double *values , int64_t n , int visible , const char *comment );
MI3D_API int mi3d_add_info_rows_text( mi3d_writer *m , const char *key , int64_t n , const char **values , const char **comments , int visible );
MI3D_API int mi3d_add_info_rows_numbers( mi3d_writer *m , const char *key , int64_t n , const double *values , const char **comments , int visible );
MI3D_API int mi3d_add_comment( mi3d_writer *m , const char *text );
MI3D_API int mi3d_set_thumbnail( mi3d_writer *m , const void *data , const char *type , int ndims , const int64_t *dims );
MI3D_API int mi3d_set_plane_ref( mi3d_writer *m , int64_t k , int64_t t , const char *path );
MI3D_API int mi3d_set_option( mi3d_writer *m , const char *name , const char *value );
MI3D_API int mi3d_set_variable( mi3d_writer *m , const char *name , const char *value );
MI3D_API int mi3d_write( mi3d_writer *m , const char *path );           /* todo o nada */

/* ---- por ruta: con .i3d que ya estan en disco ---------------------------------- */
MI3D_API int mi3d_write_files( const char *path , int n , const char **files , const char **tags , int64_t reserve ,
                         const char *comment , int lazykeep );
MI3D_API int mi3d_append( const char *path , int n , const char **files , const char **tags , int64_t reserve ,
                          const char *comment , int lazykeep , int *first );
MI3D_API int mi3d_remove( const char *path , int n , const int *members , const char *comment );
MI3D_API int mi3d_compact( const char *path , int renumber , int64_t reserve , const char *comment );

#ifdef __cplusplus
}
#endif
#endif
