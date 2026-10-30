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
 * Escribir (por ruta; el error, en mi3d_last_error(NULL)):
 *   const char *files[] = { "a.i3d" , "" , "c.i3d" };    "" es un HUECO
 *   mi3d_write( "estudio.mi3d" , 3 , files , NULL , 0 , NULL , 0 );
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

MI3D_API int mi3d_write( const char *path , int n , const char **files , const char **tags , int64_t reserve ,
                         const char *comment , int lazykeep );
MI3D_API int mi3d_append( const char *path , int n , const char **files , const char **tags , int64_t reserve ,
                          const char *comment , int lazykeep , int *first );
MI3D_API int mi3d_remove( const char *path , int n , const int *members , const char *comment );
MI3D_API int mi3d_compact( const char *path , int renumber , int64_t reserve , const char *comment );

#ifdef __cplusplus
}
#endif
#endif
