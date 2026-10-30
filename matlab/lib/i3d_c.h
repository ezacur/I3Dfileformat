/* i3d_c.h -- API en C del lector .i3d. Es la frontera ESTABLE: Python (ctypes),
 * Node (N-API) y el WebAssembly hablan con esto, no con las clases de C++.
 *
 * Reglas de la frontera:
 *   - ninguna excepcion la cruza: cada funcion devuelve 0 si va bien y un
 *     codigo != 0 si no; el mensaje se pide con i3d_last_error();
 *   - la memoria de los DATOS la pone quien llama (i3d_read_data escribe en
 *     un buffer suyo); lo que devuelve la libreria por puntero (rejillas,
 *     cadenas) vive mientras el handle este abierto;
 *   - el fichero abierto es un handle opaco: i3d_open / i3d_close;
 *   - toda ruta es UTF-8 (tambien en Windows).
 *
 *   i3d_file *f = i3d_open( "serie.i3d" );
 *   if( !f ) { puts( i3d_last_error( NULL ) ); ... }
 *   const double *X; size_t n;  i3d_grid( f , 'X' , &X , &n );
 *   int nd; int64_t dims[16];   i3d_data_shape( f , &nd , dims );
 *   i3d_read_data( f , buf , nbytes );
 *   i3d_close( f );
 */
#ifndef I3D_C_H
#define I3D_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(I3D_BUILD_DLL)
#  define I3D_API __declspec(dllexport)
#elif defined(_WIN32) && defined(I3D_USE_DLL)
#  define I3D_API __declspec(dllimport)
#else
#  define I3D_API
#endif

typedef struct i3d_file i3d_file;

/* abre y valida la cabecera; NULL si falla (mensaje en i3d_last_error(NULL)).
 * Un path NULL, o un nombre/valor NULL, es el error "badInput", no un crash */
I3D_API i3d_file   *i3d_open( const char *path );
/* lo mismo, con n variables que MANDAN sobre las $NOMBRE$ del fichero (sin los
 * '$'): asi los .dcm referenciados se pueden mover sin editar el .i3d */
I3D_API i3d_file   *i3d_open_vars( const char *path , int n , const char **names , const char **values );
I3D_API void        i3d_close( i3d_file *f );

/* el ultimo error: de ese handle, o con NULL el del ultimo i3d_open fallido.
 * i3d_last_error_id da el identificador corto ("coverage", "badGrid", ...) */
I3D_API const char *i3d_last_error( const i3d_file *f );
I3D_API const char *i3d_last_error_id( const i3d_file *f );

/* rejillas 'X' 'Y' 'Z' 'T' y la transformacion 4x4 POR FILAS */
I3D_API int i3d_grid( i3d_file *f , char axis , const double **values , size_t *n );
/* lo mismo, copiando en un buffer de quien llama (para las FFI sin punteros a
 * punteros, como calllib de MATLAB): su longitud, -1 si el eje no es XYZT */
I3D_API int64_t i3d_grid_length( i3d_file *f , char axis );
I3D_API int     i3d_grid_copy( i3d_file *f , char axis , double *out , int64_t n );
I3D_API int i3d_transform( i3d_file *f , double out16[16] );

/* data: forma (i j k t c...), tipo ("int16", ...), bytes, y la lectura */
I3D_API int         i3d_data_shape( i3d_file *f , int *ndims , int64_t dims[16] );
I3D_API const char *i3d_data_type( i3d_file *f );
I3D_API size_t      i3d_data_bytes( i3d_file *f );
I3D_API int         i3d_read_data( i3d_file *f , void *out , size_t nbytes );
/* el PRIMER INSTANTE, data(:,:,:,1,c...): la forma de data con t = 1. Solo se
 * leen los bloques que lo cortan (el escritor lo deja en los suyos) */
I3D_API size_t      i3d_first_frame_bytes( i3d_file *f );
I3D_API int         i3d_read_first_frame( i3d_file *f , void *out , size_t nbytes );

/* rescale, window (has_window = 0 si no hay clave window) */
I3D_API int i3d_rescale( i3d_file *f , double *slope , double *intercept );
I3D_API int i3d_window( i3d_file *f , int *has_window , double *center , double *width );

/* bloques <missing>: cuantos, y la caja del m-esimo (0-based, hi exclusivo) */
I3D_API int i3d_missing_count( i3d_file *f );
I3D_API int i3d_missing_box( i3d_file *f , int m , int *ndims , int64_t lo[16] , int64_t hi[16] );

/* aux.NAME (thumbnails, ...): cuantos, el nombre del a-esimo (sin 'aux.'), su
 * forma y tipo, y los bytes tal cual (orden columna, como los guardo MATLAB) */
I3D_API int         i3d_aux_count( i3d_file *f );
I3D_API const char *i3d_aux_name( i3d_file *f , int a );
I3D_API int         i3d_aux_shape( i3d_file *f , const char *name , int *ndims , int64_t dims[16] , const char **type );   /* type puede ser NULL */
I3D_API const char *i3d_aux_type( i3d_file *f , const char *name );                 /* "" si no existe */
I3D_API int         i3d_aux_read( i3d_file *f , const char *name , void *out , size_t nbytes );

/* todas las entradas de la cabecera, crudas: clave, subindices y valor */
I3D_API int         i3d_entry_count( i3d_file *f );
I3D_API int         i3d_entry( i3d_file *f , int e , const char **key , const char **subs , const char **value );
/* lo mismo, una cadena cada vez ("" si e no existe) */
I3D_API const char *i3d_entry_key( i3d_file *f , int e );
I3D_API const char *i3d_entry_subs( i3d_file *f , int e );
I3D_API const char *i3d_entry_value( i3d_file *f , int e );
/* la cabecera en claro, tambien de un I3Db, TAL CUAL: una parte <hidden> (SPEC
 * 1.2) sigue oculta en ella -- es el volcado --. i3d_entry si da sus entradas */
I3D_API const char *i3d_header( i3d_file *f );
I3D_API int         i3d_is_hidden( i3d_file *f );   /* 1 si el fichero es la variante I3Db */

/* donde empieza el binario, desde el inicio del fichero (o de la ventana) */
I3D_API int64_t     i3d_binary_start( i3d_file *f );
/* los bytes [offset, offset+length) de path, leidos como un .i3d entero: un
 * miembro de un .mi3d (su rango lo da mi3d_range de mi3d.dll). Las rutas
 * relativas, desde la carpeta de path */
I3D_API i3d_file   *i3d_open_window( const char *path , int64_t offset , int64_t length ,
                                     int n , const char **names , const char **values );

/* ---- el ESCRITOR (SPEC 9: la forma canonica) -------------------------------
 *
 *   i3d_writer *w = i3d_new();
 *   int64_t dims[4] = { 256 , 256 , 12 , 30 };
 *   i3d_set_data( w , p , "int16" , 4 , dims );         COPIA los datos
 *   i3d_set_Xgrid( w , x , 256 );  ...  (Y, Z, T)       sin darla: 0 : 1 : n-1
 *   i3d_add_info_text( w , "SeriesDescription" , "cine" , I3D_VISIBLE , NULL );
 *   if( i3d_write( w , "serie.i3d" ) ) puts( i3d_wlast_error( w ) );
 *   i3d_free( w );
 *
 * Cada funcion devuelve 0 si va bien; si no, el mensaje en i3d_wlast_error(w).
 * El encoding, el reparto en bloques, los crc, la parte <hidden> y la
 * disposicion no se eligen: los decide i3d_write (SPEC 9). Todo texto, UTF-8 y
 * sin caracteres de control. Las opciones (i3d_set_option, todas como texto):
 *   Comment        el comentario de la primera linea (default "i3d <fecha>")
 *   Blocks         auto (default) | volume | t
 *   MaxBlockBytes  el mayor bloque, sin comprimir (default 2^31-9)
 *   Hidden         1: la cabecera comprimida y ofuscada (I3Db, SPEC 1.1)
 *   Visible        default | all: con all, un info.* I3D_DEFAULT queda a la vista
 *   HideKeys       un patron de claves ('*' comodin) que va a la parte oculta,
 *                  uno por llamada: "info.Patient*", "data", "$DICOMDIR$"; "" los quita
 *   Lazy           1: un bloque por plano y $DICOMDIR$ aunque ningun plano sea una
 *                  referencia (con alguna i3d_set_plane_ref ya lo es)
 *   Verify         1 (default): cada referencia de i3d_set_plane_ref se LEE y tiene
 *                  que dar exactamente su plano de data; si no, se materializa
 *   DicomDir       el valor de $DICOMDIR$ (default: la raiz comun de los .dcm) */
typedef struct i3d_writer i3d_writer;
#define I3D_DEFAULT 0          /* visibilidad de un info.*: oculta, salvo Visible = all */
#define I3D_VISIBLE 1
#define I3D_HIDDEN  2
I3D_API i3d_writer *i3d_new( void );
I3D_API void        i3d_free( i3d_writer *w );
I3D_API const char *i3d_wlast_error( const i3d_writer *w );
I3D_API const char *i3d_wlast_error_id( const i3d_writer *w );
/* data: i j k t c..., en orden columna; type "int8" .. "uint64", "single", "double" */
I3D_API int i3d_set_data( i3d_writer *w , const void *data , const char *type , int ndims , const int64_t *dims );
/* las rejillas, una funcion por eje; sin darla: 0 : 1 : n-1 */
I3D_API int i3d_set_Xgrid( i3d_writer *w , const double *values , int64_t n );
I3D_API int i3d_set_Ygrid( i3d_writer *w , const double *values , int64_t n );
I3D_API int i3d_set_Zgrid( i3d_writer *w , const double *values , int64_t n );
I3D_API int i3d_set_Tgrid( i3d_writer *w , const double *values , int64_t n );
I3D_API int i3d_set_transform( i3d_writer *w , const double rows16[16] );    /* 4x4 POR FILAS */
I3D_API int i3d_set_rescale( i3d_writer *w , double slope , double intercept , const char *comment );
I3D_API int i3d_set_window( i3d_writer *w , double center , double width , const char *comment );
/* info.KEY (sin el 'info.'), con un comentario al final de la linea (NULL ninguno) */
I3D_API int i3d_add_info_text( i3d_writer *w , const char *key , const char *value , int visibility , const char *comment );
I3D_API int i3d_add_info_numbers( i3d_writer *w , const char *key , const double *values , int64_t n , int visibility , const char *comment );
/* una lista con UN VALOR POR FILA y un comentario por fila. comments NULL y
 * n = nk*nt: una fila por PLANO (k la mas rapida) y el comentario lo pone el
 * escritor (el bloque de data de ese plano). integer: los valores como enteros */
I3D_API int i3d_add_info_rows_text( i3d_writer *w , const char *key , int64_t n , const char **values , const char **comments , int visibility );
I3D_API int i3d_add_info_rows_numbers( i3d_writer *w , const char *key , int64_t n , const double *values , int integer , const char **comments , int visibility );
/* un comentario EN EL SITIO donde se pide (la cabecera sale en el orden canonico,
 * no en el de las llamadas):
 *   "texto"     una linea '# texto' ENCIMA de lo SIGUIENTE que se de (rejilla,
 *               transform, data, rescale, window, aux, info.*); si no se da nada
 *               mas, al final de la cabecera
 *   "\btexto"   con un BACKSPACE delante (sprintf('\b...') en MATLAB): '  # texto'
 *               al FINAL de la linea de lo ULTIMO que se dio (de una entrada de
 *               varias lineas, la primera)
 * El de la primera linea es la opcion Comment */
I3D_API int i3d_add_comment( i3d_writer *w , const char *text );
/* aux.NAME: un thumbnail uint8 gris {filas cols} o {filas cols 1 frames}, como UNA
 * imagen PNG (los frames uno al lado de otro). Otra cosa no se escribe: queda un
 * comentario "skipped" (type, el nombre de la clase: "double", ...) */
I3D_API int i3d_add_aux( i3d_writer *w , const char *name , const void *data , const char *type , int ndims , const int64_t *dims );
/* 'Lazy': el plano (k,t), 1-based, es una referencia a un .dcm sin perdida de
 * un componente (ruta absoluta). path "" o NULL: el plano no tiene fichero --
 * <missing> si data es entera y el plano es de ceros; si no, se materializa */
I3D_API int i3d_set_plane_ref( i3d_writer *w , int64_t k , int64_t t , const char *path );
I3D_API int i3d_set_option( i3d_writer *w , const char *name , const char *value );
I3D_API int i3d_write( i3d_writer *w , const char *path );          /* todo o nada */

/* la cabecera de src en claro y su binario byte a byte, a dst: hidden 1, oculta
 * (I3Db, SPEC 1.1); 0, en texto. dst puede ser src. Error: i3d_last_error(NULL) */
I3D_API int i3d_rewrite( const char *src , const char *dst , int hidden );

/* un double como lo escribe la cabecera: la forma mas corta que vuelve EXACTA,
 * con ".0" si es entero (SPEC 2). La cadena vive hasta la siguiente llamada en
 * el mismo hilo */
I3D_API const char *i3d_num2str( double x );

#ifdef __cplusplus
}
#endif
#endif
