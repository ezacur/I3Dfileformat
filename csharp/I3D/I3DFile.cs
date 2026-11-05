// I3DFile.cs -- el lector .i3d (SPEC.md) para .NET 8, sobre la API en C de
// cpp/i3d_c.h (i3d.dll). Es un envoltorio fino: toda la logica del formato esta
// en la DLL, la misma que usan MATLAB (MEX) y Python (ctypes).
//
//   using var f = I3DFile.Open( "serie.i3d" );
//   double[] X = f.X;                      // las rejillas, exactas
//   var ( data , shape ) = f.ReadData();    // Array tipado, orden columna (i el mas rapido)
//   var ( first , s1 ) = f.ReadFirstFrame();   // solo data(:,:,:,1,c...)
//
// Reglas de la frontera (i3d_c.h): toda cadena -- rutas, cabecera, entradas --
// es UTF-8 en los dos sentidos; lo que la DLL devuelve por puntero vive mientras
// el handle; un error es un codigo != 0 y su mensaje se pide aparte. Aqui eso es
// una I3DException con el identificador corto (Id) de la DLL.
using System.Runtime.InteropServices;

namespace I3D;

/// <summary>Un error de la libreria .i3d: <see cref="Id"/> es el identificador corto
/// de la DLL ("badHeader", "coverage", "badCRC", ...).</summary>
public sealed class I3DException : Exception
{
    public string Id { get; }
    public I3DException( string id , string message ) : base( $"[{id}] {message}" ) { Id = id; }
}

/// <summary>Una caja de data (0-based, Hi exclusivo), como la de un bloque &lt;missing&gt;.</summary>
public readonly record struct I3DBox( long[] Lo , long[] Hi );

/// <summary>Una entrada de la cabecera, cruda: clave, subindices (sin parentesis) y valor.</summary>
public readonly record struct I3DEntry( string Key , string Subs , string Value );

/// <summary>El handle opaco de la DLL; se cierra con i3d_close.</summary>
internal sealed class I3DHandle : SafeHandle
{
    public I3DHandle() : base( IntPtr.Zero , true ) { }
    public override bool IsInvalid => handle == IntPtr.Zero;
    protected override bool ReleaseHandle() { Native.i3d_close( handle ); return true; }
}

internal static class Native
{
    const string Lib = "i3d";
    // las cadenas de entrada, UTF-8 explicito (no ANSI); las de salida llegan
    // como IntPtr y se leen con PtrToStringUTF8
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern I3DHandle i3d_open( [MarshalAs( UnmanagedType.LPUTF8Str )] string path );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    // los arrays de cadenas van como punteros a UTF-8 hechos a mano: el marshaller
    // clasico no admite LPUTF8Str como ArraySubType (MarshalDirectiveException)
    public static extern I3DHandle i3d_open_vars( [MarshalAs( UnmanagedType.LPUTF8Str )] string path , int n ,
                                                  IntPtr[] names , IntPtr[] values );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern void i3d_close( IntPtr f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_last_error( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_last_error_id( I3DHandle f );
    // las de un open fallido: con NULL
    [DllImport( Lib , EntryPoint = "i3d_last_error" , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_last_error_null( IntPtr f );
    [DllImport( Lib , EntryPoint = "i3d_last_error_id" , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_last_error_id_null( IntPtr f );

    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_grid( I3DHandle f , byte axis , out IntPtr values , out nuint n );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_transform( I3DHandle f , [Out] double[] out16 );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_data_shape( I3DHandle f , out int ndims , [Out] long[] dims16 );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_data_type( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern nuint i3d_data_bytes( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern unsafe int i3d_read_data( I3DHandle f , void* out_ , nuint nbytes );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern nuint i3d_first_frame_bytes( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern unsafe int i3d_read_first_frame( I3DHandle f , void* out_ , nuint nbytes );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_missing_count( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_missing_box( I3DHandle f , int m , out int ndims , [Out] long[] lo16 , [Out] long[] hi16 );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_thumbnail_shape( I3DHandle f , out int ndims , [Out] long[] dims16 );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern unsafe int i3d_thumbnail_read( I3DHandle f , void* out_ , nuint nbytes );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_entry_count( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_entry( I3DHandle f , int e , out IntPtr key , out IntPtr subs , out IntPtr value );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_header( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_is_hidden( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_info_count( I3DHandle f );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_info_key( I3DHandle f , int i );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_info_type( I3DHandle f , int i );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern long i3d_info_length( I3DHandle f , int i );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int i3d_info_numbers( I3DHandle f , int i , [Out] double[] out_ , long n );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr i3d_info_text( I3DHandle f , int i , long j );
}

/// <summary>Un fichero .i3d abierto. Abrirlo solo lee y valida la cabecera; el
/// binario se lee al pedir data, el primer instante o el thumbnail.</summary>
public sealed class I3DFile : IDisposable
{
    /// <summary>Lo maximo que admite la API C por forma (i3d_c.h: dims[16]).</summary>
    public const int MaxDims = 16;

    readonly I3DHandle h;
    I3DFile( I3DHandle handle ) { h = handle; }

    /// <summary>Abre y valida la cabecera. <paramref name="variables"/>: valores que
    /// MANDAN sobre las $NOMBRE$ del fichero (nombres sin '$'), para que los .dcm
    /// referenciados se puedan mover sin editar el .i3d.</summary>
    public static I3DFile Open( string path , IReadOnlyDictionary<string, string>? variables = null )
    {
        // la auditoria: un NULL a i3d_open tira el proceso; aqui nunca llega
        ArgumentNullException.ThrowIfNull( path );
        I3DHandle hd;
        if( variables is { Count: > 0 } )
        {
            var names = new IntPtr[variables.Count];
            var values = new IntPtr[variables.Count];
            try
            {
                int k = 0;
                foreach( var kv in variables )
                {
                    ArgumentNullException.ThrowIfNull( kv.Key );
                    ArgumentNullException.ThrowIfNull( kv.Value );
                    names[k] = Marshal.StringToCoTaskMemUTF8( kv.Key.Trim( '$' ) );   // la DLL espera el nombre sin '$'
                    values[k] = Marshal.StringToCoTaskMemUTF8( kv.Value );
                    k++;
                }
                hd = Native.i3d_open_vars( path , names.Length , names , values );
            }
            finally
            {
                foreach( var p in names ) if( p != IntPtr.Zero ) Marshal.FreeCoTaskMem( p );
                foreach( var p in values ) if( p != IntPtr.Zero ) Marshal.FreeCoTaskMem( p );
            }
        }
        else
        {
            hd = Native.i3d_open( path );
        }
        if( hd.IsInvalid )
        {
            hd.Dispose();
            throw new I3DException( Str( Native.i3d_last_error_id_null( IntPtr.Zero ) ) ,
                                    Str( Native.i3d_last_error_null( IntPtr.Zero ) ) );
        }
        return new I3DFile( hd );
    }

    public void Dispose() => h.Dispose();

    static string Str( IntPtr p ) => p == IntPtr.Zero ? "" : Marshal.PtrToStringUTF8( p ) ?? "";

    void Check( int rc )
    {
        if( rc != 0 ) throw new I3DException( Str( Native.i3d_last_error_id( h ) ) , Str( Native.i3d_last_error( h ) ) );
    }

    // ------------------------------------------------------------ geometria
    double[] Grid( char axis )
    {
        Check( Native.i3d_grid( h , (byte)axis , out var p , out var n ) );
        var v = new double[(int)n];
        if( n > 0 ) Marshal.Copy( p , v , 0 , (int)n );
        return v;
    }
    public double[] X => Grid( 'X' );
    public double[] Y => Grid( 'Y' );
    public double[] Z => Grid( 'Z' );
    public double[] T => Grid( 'T' );

    /// <summary>La afin 4x4, [fila, columna]: world = A * [X(i); Y(j); Z(k); 1].</summary>
    public double[,] Transform
    {
        get
        {
            var a = new double[16];
            Check( Native.i3d_transform( h , a ) );
            var m = new double[4, 4];
            for( int r = 0 ; r < 4 ; r++ ) for( int c = 0 ; c < 4 ; c++ ) m[r, c] = a[4 * r + c];   // por filas
            return m;
        }
    }

    // ------------------------------------------------------------ data
    /// <summary>La forma de data: i j k t c...</summary>
    public long[] Shape
    {
        get
        {
            var d = new long[MaxDims];
            Check( Native.i3d_data_shape( h , out int nd , d ) );
            return d[..nd];
        }
    }

    /// <summary>"int8" "uint8" "int16" "uint16" "int32" "uint32" "int64" "uint64" "single" "double".</summary>
    public string DataType => Str( Native.i3d_data_type( h ) );

    /// <summary>El tipo .NET de un tipo del formato.</summary>
    public static Type ClrType( string i3dType ) => i3dType switch
    {
        "int8" => typeof( sbyte ),  "uint8" => typeof( byte ),
        "int16" => typeof( short ), "uint16" => typeof( ushort ),
        "int32" => typeof( int ),   "uint32" => typeof( uint ),
        "int64" => typeof( long ),  "uint64" => typeof( ulong ),
        "single" => typeof( float ), "double" => typeof( double ),
        _ => throw new I3DException( "badType" , $"unknown type '{i3dType}'" ),
    };

    public long DataBytes => (long)Native.i3d_data_bytes( h );
    public long FirstFrameBytes => (long)Native.i3d_first_frame_bytes( h );

    /// <summary>La forma del primer instante: la de data con t = 1.</summary>
    public long[] FirstFrameShape { get { var s = Shape; s[3] = 1; return s; } }

    static Array NewArray( Type t , long n ) => Array.CreateInstance( t , checked( (int)n ) );

    unsafe void ReadInto( Array a , long nbytes , bool firstFrame )
    {
        var g = GCHandle.Alloc( a , GCHandleType.Pinned );
        try
        {
            void* p = (void*)g.AddrOfPinnedObject();
            Check( firstFrame ? Native.i3d_read_first_frame( h , p , (nuint)nbytes )
                              : Native.i3d_read_data( h , p , (nuint)nbytes ) );
        }
        finally { g.Free(); }
    }

    static long Count( long[] shape ) { long n = 1; foreach( var s in shape ) n *= s; return n; }

    /// <summary>Todo data: un array 1-D del tipo .NET correcto, en ORDEN COLUMNA
    /// (i el mas rapido, luego j, k, t, c...), y su forma.</summary>
    public (Array Data, long[] Shape) ReadData()
    {
        var s = Shape;
        var a = NewArray( ClrType( DataType ) , Count( s ) );
        ReadInto( a , DataBytes , false );
        return (a, s);
    }

    /// <summary>Solo el PRIMER INSTANTE, data(:,:,:,1,c...): la DLL decodifica
    /// unicamente los bloques que lo cortan.</summary>
    public (Array Data, long[] Shape) ReadFirstFrame()
    {
        var s = FirstFrameShape;
        var a = NewArray( ClrType( DataType ) , Count( s ) );
        ReadInto( a , FirstFrameBytes , true );
        return (a, s);
    }

    unsafe void ReadSpan<T>( Span<T> out_ , long nbytes , bool firstFrame ) where T : unmanaged
    {
        if( typeof( T ) != ClrType( DataType ) )
            throw new I3DException( "badBuffer" , $"data is {DataType}, the buffer is {typeof( T ).Name}" );
        if( (long)out_.Length * sizeof( T ) != nbytes )
            throw new I3DException( "badBuffer" , $"the buffer has {(long)out_.Length * sizeof( T )} bytes; it needs {nbytes}" );
        fixed( T* p = out_ )
            Check( firstFrame ? Native.i3d_read_first_frame( h , p , (nuint)nbytes ) : Native.i3d_read_data( h , p , (nuint)nbytes ) );
    }

    /// <summary>Todo data en un buffer de quien llama, sin copia. T tiene que ser el tipo de data.</summary>
    public void ReadData<T>( Span<T> out_ ) where T : unmanaged => ReadSpan( out_ , DataBytes , false );

    /// <summary>El primer instante en un buffer de quien llama, sin copia.</summary>
    public void ReadFirstFrame<T>( Span<T> out_ ) where T : unmanaged => ReadSpan( out_ , FirstFrameBytes , true );

    // ------------------------------------------------------------ missing
    /// <summary>Los bloques &lt;missing&gt;, como cajas 0-based con Hi exclusivo.</summary>
    public I3DBox[] Missing
    {
        get
        {
            int n = Native.i3d_missing_count( h );
            if( n < 0 ) throw new I3DException( "badInput" , "invalid handle" );
            var r = new I3DBox[n];
            for( int m = 0 ; m < n ; m++ )
            {
                var lo = new long[MaxDims];
                var hi = new long[MaxDims];
                Check( Native.i3d_missing_box( h , m , out int nd , lo , hi ) );
                // la auditoria: la DLL puede decir nd > 16 y escribir solo 16
                if( nd > MaxDims ) throw new I3DException( "badData" , $"more than {MaxDims} dimensions" );
                r[m] = new I3DBox( lo[..nd] , hi[..nd] );
            }
            return r;
        }
    }

    // ------------------------------------------------------------ thumbnail
    /// <summary>El thumbnail (SPEC 7): uint8 en orden columna y su {shape}: gris
    /// {filas cols} o {filas cols 1 frames}, o RGB {filas cols 3 frames}; null si el fichero no tiene.</summary>
    public (byte[] Data, long[] Shape)? ReadThumbnail()
    {
        var d = new long[MaxDims];
        Check( Native.i3d_thumbnail_shape( h , out int nd , d ) );
        if( nd == 0 ) return null;
        var shape = d[..nd];
        var a = new byte[Count( shape )];
        unsafe
        {
            fixed( byte* p = a ) Check( Native.i3d_thumbnail_read( h , p , (nuint)a.Length ) );
        }
        return (a, shape);
    }

    // ------------------------------------------------------------ cabecera
    /// <summary>Todas las entradas de la cabecera, crudas (info.*, claves desconocidas...).</summary>
    public I3DEntry[] Entries
    {
        get
        {
            int n = Native.i3d_entry_count( h );
            var r = new I3DEntry[Math.Max( 0 , n )];
            for( int e = 0 ; e < r.Length ; e++ )
            {
                Check( Native.i3d_entry( h , e , out var k , out var s , out var v ) );
                r[e] = new I3DEntry( Str( k ) , Str( s ) , Str( v ) );
            }
            return r;
        }
    }

    /// <summary>Los info.* interpretados por la DLL (SPEC 7), por su nombre sin
    /// 'info.': <c>double[]</c> (numeros), <c>string[]</c> (textos, sin escapes y con
    /// las $VARIABLES$ sustituidas) o <c>string</c> (otra cosa: el valor crudo). Los
    /// que no se pueden leer (un $ suelto, una variable que no existe) no estan:
    /// van a <see cref="InfoErrors"/>.</summary>
    public IReadOnlyDictionary<string, object> Info => Infos().info;

    /// <summary>Los info.* que no se pueden leer: nombre -> motivo.</summary>
    public IReadOnlyDictionary<string, string> InfoErrors => Infos().errors;

    (Dictionary<string, object> info, Dictionary<string, string> errors) Infos()
    {
        var info = new Dictionary<string, object>();
        var errors = new Dictionary<string, string>();
        int n = Native.i3d_info_count( h );
        for( int i = 0 ; i < n ; i++ )
        {
            string key = Str( Native.i3d_info_key( h , i ) );
            string type = Str( Native.i3d_info_type( h , i ) );
            long len = Native.i3d_info_length( h , i );
            switch( type )
            {
                case "numbers":
                    var x = new double[len];
                    Check( Native.i3d_info_numbers( h , i , x , len ) );
                    info[key] = x;
                    break;
                case "text":
                    var s = new string[len];
                    for( long j = 0 ; j < len ; j++ ) s[j] = Str( Native.i3d_info_text( h , i , j ) );
                    info[key] = s;
                    break;
                case "other":
                    info[key] = Str( Native.i3d_info_text( h , i , 0 ) );
                    break;
                default:
                    errors[key] = Str( Native.i3d_last_error( h ) );
                    break;
            }
        }
        return (info, errors);
    }

    /// <summary>La cabecera en claro (UTF-8 decodificado), tambien la de un I3Db.</summary>
    public string Header => Str( Native.i3d_header( h ) );

    /// <summary>True si el fichero es la variante con la cabecera oculta (I3Db).</summary>
    public bool IsHidden => Native.i3d_is_hidden( h ) == 1;
}
