// MI3DFile.cs -- el contenedor .mi3d (SPEC 14) para .NET 8, sobre la API en C de
// cpp/mi3d_c.h (mi3d.dll). Como I3DFile, un envoltorio fino: mi3d.dll lee la
// cabecera del contenedor y da el rango de cada miembro, y el miembro lo lee
// i3d.dll en su sitio, dentro del .mi3d (i3d_open_window), sin copiarlo.
//
//   using var c = MI3DFile.Open( "estudio.mi3d" );
//   for( int n = 1 ; n <= c.Count ; n++ )
//   {
//       using var f = c.Member( n );        // null si n es un hueco
//       if( f is null ) continue;
//       Console.WriteLine( $"{n}: {c.Tag( n )}  [{string.Join( " x " , f.Shape )}]" );
//   }
using System.Runtime.InteropServices;

namespace I3D;

/// <summary>El handle opaco de mi3d.dll; se cierra con mi3d_close.</summary>
internal sealed class MI3DHandle : SafeHandle
{
    public MI3DHandle() : base( IntPtr.Zero , true ) { }
    public override bool IsInvalid => handle == IntPtr.Zero;
    protected override bool ReleaseHandle() { MNative.mi3d_close( handle ); return true; }
}

internal static class MNative
{
    const string Lib = "mi3d";
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern MI3DHandle mi3d_open( [MarshalAs( UnmanagedType.LPUTF8Str )] string path );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern void mi3d_close( IntPtr m );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_last_error( MI3DHandle m );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_last_error_id( MI3DHandle m );
    // las de un open fallido: con NULL
    [DllImport( Lib , EntryPoint = "mi3d_last_error" , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_last_error_null( IntPtr m );
    [DllImport( Lib , EntryPoint = "mi3d_last_error_id" , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_last_error_id_null( IntPtr m );

    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int mi3d_count( MI3DHandle m );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int mi3d_present( MI3DHandle m , int n );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int mi3d_range( MI3DHandle m , int n , out long offset , out long length );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_tag( MI3DHandle m , int n );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern int mi3d_entry_count( MI3DHandle m );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_entry_key( MI3DHandle m , int e );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_entry_subs( MI3DHandle m , int e );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_entry_value( MI3DHandle m , int e );
    [DllImport( Lib , CallingConvention = CallingConvention.Cdecl )]
    public static extern IntPtr mi3d_header( MI3DHandle m );
}

/// <summary>Un contenedor .mi3d abierto: varios .i3d (los miembros 1..Count, con
/// huecos) en un fichero. Abrirlo solo lee su cabecera; cada miembro se abre con
/// <see cref="Member"/>, un <see cref="I3DFile"/> como cualquier otro.</summary>
public sealed class MI3DFile : IDisposable
{
    readonly MI3DHandle h;
    readonly string path;
    MI3DFile( MI3DHandle handle , string p ) { h = handle; path = p; }

    public static MI3DFile Open( string path )
    {
        ArgumentNullException.ThrowIfNull( path );
        var hd = MNative.mi3d_open( path );
        if( hd.IsInvalid )
        {
            hd.Dispose();
            throw new I3DException( Str( MNative.mi3d_last_error_id_null( IntPtr.Zero ) ) ,
                                    Str( MNative.mi3d_last_error_null( IntPtr.Zero ) ) );
        }
        return new MI3DFile( hd , path );
    }

    public void Dispose() => h.Dispose();

    static string Str( IntPtr p ) => p == IntPtr.Zero ? "" : Marshal.PtrToStringUTF8( p ) ?? "";

    /// <summary>N: el mayor n declarado. Los miembros son 1..N, algunos huecos.</summary>
    public int Count => MNative.mi3d_count( h );

    /// <summary>True si n es un miembro; false si es un hueco. Fuera de 1..N, badIndex.</summary>
    public bool Present( int n )
    {
        int p = MNative.mi3d_present( h , n );
        if( p < 0 ) throw new I3DException( "badIndex" , $"member {n} is not in 1..{Count}" );
        return p == 1;
    }

    /// <summary>El rango de bytes del miembro n, desde el inicio del FICHERO.</summary>
    public (long Offset, long Length) Range( int n )
    {
        if( MNative.mi3d_range( h , n , out long o , out long l ) != 0 )
            throw new I3DException( Str( MNative.mi3d_last_error_id( h ) ) , Str( MNative.mi3d_last_error( h ) ) );
        return (o, l);
    }

    /// <summary>La etiqueta del miembro n (el comentario de su linea i3d(n), sin las
    /// dimensiones): solo para personas; "" si no tiene.</summary>
    public string Tag( int n ) => Str( MNative.mi3d_tag( h , n ) );

    /// <summary>El miembro n, leido en su sitio dentro del .mi3d; null si es un hueco.
    /// <paramref name="variables"/>, como en <see cref="I3DFile.Open"/>.</summary>
    public I3DFile? Member( int n , IReadOnlyDictionary<string, string>? variables = null )
    {
        if( !Present( n ) ) return null;
        var (o, l) = Range( n );
        return I3DFile.OpenWindow( path , o , l , variables );
    }

    /// <summary>Las entradas de la cabecera del contenedor, crudas: i3d(n), header y el
    /// resumen info.* (lo comun a todos los miembros, SPEC 14.3).</summary>
    public I3DEntry[] Entries
    {
        get
        {
            int n = MNative.mi3d_entry_count( h );
            var r = new I3DEntry[Math.Max( 0 , n )];
            for( int e = 0 ; e < r.Length ; e++ )
                r[e] = new I3DEntry( Str( MNative.mi3d_entry_key( h , e ) ) , Str( MNative.mi3d_entry_subs( h , e ) ) ,
                                     Str( MNative.mi3d_entry_value( h , e ) ) );
            return r;
        }
    }

    /// <summary>La cabecera del contenedor tal cual (sin desplegar su parte &lt;hidden&gt;).</summary>
    public string Header => Str( MNative.mi3d_header( h ) );
}
