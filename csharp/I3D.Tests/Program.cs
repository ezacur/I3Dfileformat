// Pruebas del wrapper C#: cada .i3d de referencia, leido por la DLL a traves de
// I3DFile, contra lo que leyo el lector de REFERENCIA en Python
// (tests/read_i3d.py), BIT A BIT: data, primer instante, rejillas, transform,
// thumbnail e info. Mas los errores con su Id.
//
//   dotnet run --project I3D.Tests -- <dir de referencias> <dir de especiales>
//
// Las referencias las genera tests/make_cs_refs.py (con read_i3d.py) que, para cada
// fichero, escribe <tag>.json (tipo, forma, rejillas y transform en hex, info,
// thumbnail) y <tag>.data.bin / <tag>.first.bin / <tag>.thumbnail.bin en orden columna.
// Sale con 1 si algo falla.
using System.Runtime.InteropServices;
using System.Text.Json;
using I3D;

static class Program
{
    static int nbad = 0 , nok = 0;

    static void Ok( bool cond , string what )
    {
        if( cond ) { nok++; return; }
        nbad++;
        Console.WriteLine( $"  FAIL {what}" );
    }

    static byte[] Bytes( Array a )
    {
        int n = Buffer.ByteLength( a );
        var b = new byte[n];
        Buffer.BlockCopy( a , 0 , b , 0 , n );
        return b;
    }

    static byte[] Hex( string s ) => Convert.FromHexString( s );

    static byte[] Doubles( double[] v ) { var b = new byte[v.Length * 8]; Buffer.BlockCopy( v , 0 , b , 0 , b.Length ); return b; }

    static string NetType( string numpyName ) => numpyName switch
    {
        "int8" => "int8", "uint8" => "uint8", "int16" => "int16", "uint16" => "uint16",
        "int32" => "int32", "uint32" => "uint32", "int64" => "int64", "uint64" => "uint64",
        "float32" => "single", "float64" => "double", _ => numpyName,
    };

    // un info.* de I3DFile.Info contra el de read_i3d.py: lista de numeros ->
    // double[] (bit a bit); un texto o una lista -> string[]; 'other' -> string
    static bool SameInfo( object got , JsonElement want )
    {
        if( want.ValueKind == JsonValueKind.Array && want.EnumerateArray().All( e => e.ValueKind == JsonValueKind.Number ) )
            return got is double[] d && Doubles( d ).SequenceEqual( Doubles( want.EnumerateArray().Select( e => e.GetDouble() ).ToArray() ) );
        if( want.ValueKind == JsonValueKind.Array )
            return got is string[] s && s.SequenceEqual( want.EnumerateArray().Select( e => e.GetString()! ) );
        // un solo texto (read_i3d da str) o el valor crudo ('other')
        return ( got is string[] one && one.Length == 1 && one[0] == want.GetString() ) || ( got is string raw && raw == want.GetString() );
    }

    static int Main( string[] args )
    {
        string refDir = args.Length > 0 ? args[0] : throw new ArgumentException( "usage: I3D.Tests <refDir> <specialDir>" );
        string specialDir = args.Length > 1 ? args[1] : throw new ArgumentException( "usage: I3D.Tests <refDir> <specialDir>" );

        var jsons = Directory.GetFiles( refDir , "*.json" ).OrderBy( x => x ).ToArray();
        Console.WriteLine( $"{jsons.Length} reference files" );
        foreach( var j in jsons )
        {
            string tag = Path.GetFileNameWithoutExtension( j );
            using var doc = JsonDocument.Parse( File.ReadAllText( j ) );
            var r = doc.RootElement;
            string file = r.GetProperty( "file" ).GetString()!;
            var vars = r.GetProperty( "variables" ).EnumerateObject().ToDictionary( p => p.Name , p => p.Value.GetString()! );
            int before = nbad;
            try
            {
                using var f = I3DFile.Open( file , vars );
                // tipo y forma
                Ok( f.DataType == NetType( r.GetProperty( "dtype" ).GetString()! ) , $"{tag}: type {f.DataType}" );
                var shape = r.GetProperty( "shape" ).EnumerateArray().Select( e => e.GetInt64() ).ToArray();
                Ok( f.Shape.SequenceEqual( shape ) , $"{tag}: shape [{string.Join( ' ' , f.Shape )}] vs [{string.Join( ' ' , shape )}]" );
                // rejillas y transform, bit a bit
                Ok( Doubles( f.X ).SequenceEqual( Hex( r.GetProperty( "X" ).GetString()! ) ) , $"{tag}: X" );
                Ok( Doubles( f.Y ).SequenceEqual( Hex( r.GetProperty( "Y" ).GetString()! ) ) , $"{tag}: Y" );
                Ok( Doubles( f.Z ).SequenceEqual( Hex( r.GetProperty( "Z" ).GetString()! ) ) , $"{tag}: Z" );
                Ok( Doubles( f.T ).SequenceEqual( Hex( r.GetProperty( "T" ).GetString()! ) ) , $"{tag}: T" );
                var A = f.Transform;
                var flat = new double[16];
                for( int i = 0 ; i < 4 ; i++ ) for( int c = 0 ; c < 4 ; c++ ) flat[4 * i + c] = A[i, c];
                Ok( Doubles( flat ).SequenceEqual( Hex( r.GetProperty( "transform" ).GetString()! ) ) , $"{tag}: transform" );
                // data y primer instante, bit a bit
                var (data, _) = f.ReadData();
                Ok( Bytes( data ).SequenceEqual( File.ReadAllBytes( Path.Combine( refDir , tag + ".data.bin" ) ) ) , $"{tag}: data" );
                var (first, s1) = f.ReadFirstFrame();
                Ok( s1[3] == 1 && Bytes( first ).SequenceEqual( File.ReadAllBytes( Path.Combine( refDir , tag + ".first.bin" ) ) ) , $"{tag}: first frame" );
                // las sobrecargas sin copia, por el tipo de data
                Ok( SpanMatches( f , data , first ) , $"{tag}: Span<T> overloads" );
                // thumbnail: el de la referencia, o null si no hay
                var got = f.ReadThumbnail();
                if( r.TryGetProperty( "thumbnail" , out var th ) && th.ValueKind == JsonValueKind.Object )
                {
                    Ok( got is not null && got.Value.Data.SequenceEqual( File.ReadAllBytes( Path.Combine( refDir , $"{tag}.thumbnail.bin" ) ) ) , $"{tag}: thumbnail" );
                    var tshape = th.GetProperty( "shape" ).EnumerateArray().Select( e => e.GetInt64() ).ToArray();
                    Ok( got is not null && got.Value.Shape.SequenceEqual( tshape ) , $"{tag}: thumbnail shape" );
                }
                else Ok( got is null , $"{tag}: no thumbnail is null" );
                // info.*: los valores crudos, UTF-8 incluido
                var entries = f.Entries.Where( e => e.Key.StartsWith( "info." ) ).ToDictionary( e => e.Key , e => e.Value );
                foreach( var i in r.GetProperty( "info" ).EnumerateObject() )
                    Ok( entries.TryGetValue( i.Name , out var v ) && v == i.Value.GetString() , $"{tag}: {i.Name}" );
                // info.* interpretados (SPEC 7): numeros bit a bit, textos con las
                // $VARIABLES$ sustituidas, y los ilegibles en InfoErrors
                var info = f.Info;
                var parsed = r.GetProperty( "infoParsed" );
                Ok( info.Count == parsed.EnumerateObject().Count() , $"{tag}: Info has {info.Count} entries" );
                foreach( var i in parsed.EnumerateObject() )
                    Ok( info.TryGetValue( i.Name , out var v ) && SameInfo( v , i.Value ) , $"{tag}: Info[{i.Name}]" );
                var errs = r.GetProperty( "infoErrors" ).EnumerateArray().Select( e => e.GetString()! ).OrderBy( x => x );
                Ok( f.InfoErrors.Keys.OrderBy( x => x ).SequenceEqual( errs ) , $"{tag}: InfoErrors" );
            }
            catch( I3DException e )
            {
                Ok( false , $"{tag}: {e.Message}" );
            }
            Console.WriteLine( $"  {( nbad == before ? "ok  " : "FAIL" )} {tag}  {Path.GetFileName( file )}" );
        }

        // ---- lo especifico
        Console.WriteLine( "specific:" );
        using( var f = I3DFile.Open( Path.Combine( specialDir , "utf8.i3d" ) ) )
        {
            var e = f.Entries.Where( x => x.Key.StartsWith( "info." ) ).ToDictionary( x => x.Key , x => x.Value );
            Ok( e["info.PatientName"] == "\"Muñoz^José\"" , $"utf8: PatientName = {e["info.PatientName"]}" );
            Ok( f.Header.Contains( "Muñoz^José" ) , "utf8: header" );
            Console.WriteLine( $"  utf8: info.PatientName = {e["info.PatientName"]}" );
        }
        using( var f = I3DFile.Open( Path.Combine( specialDir , "hidden.i3d" ) ) )
        {
            Ok( f.IsHidden , "hidden: IsHidden" );
            Ok( f.Header.StartsWith( "I3D" ) , "hidden: header in clear" );
        }
        using( var f = I3DFile.Open( Path.Combine( specialDir , "png.i3d" ) ) )
        {
            var a = f.ReadThumbnail();
            Ok( a is not null && a.Value.Shape.SequenceEqual( new long[] { 5 , 4 , 1 , 2 } ) , "png: shape" );
            // el thumbnail que hizo make_refs.py: arange(40)*3 en orden columna
            var exp = Enumerable.Range( 0 , 40 ).Select( v => (byte)( v * 3 ) ).ToArray();
            Ok( a is not null && a.Value.Data.SequenceEqual( exp ) , "png: values" );
        }
        // variables: sin sobrescribir, la ruta del fichero no existe
        try
        {
            using var f = I3DFile.Open( Path.Combine( specialDir , "vars.i3d" ) );
            f.ReadData();
            Ok( false , "vars: should fail without the override" );
        }
        catch( I3DException e ) { Ok( e.Id == "cannotOpen" , $"vars: no override -> {e.Id}" ); Console.WriteLine( $"  vars without override -> [{e.Id}]" ); }
        // errores con su Id: al abrir, y al leer
        try { using var f = I3DFile.Open( Path.Combine( specialDir , "invalid_coverage.i3d" ) ); Ok( false , "coverage: accepted" ); }
        catch( I3DException e ) { Ok( e.Id == "coverage" , $"coverage: got {e.Id}" ); Console.WriteLine( $"  invalid_coverage -> [{e.Id}] {e.Message}" ); }
        try { using var f = I3DFile.Open( Path.Combine( specialDir , "invalid_rawlen.i3d" ) ); f.ReadData(); Ok( false , "rawlen: accepted" ); }
        catch( I3DException e ) { Ok( e.Id == "badBlock" , $"rawlen: got {e.Id}" ); Console.WriteLine( $"  invalid_rawlen -> [{e.Id}]" ); }
        try { using var f = I3DFile.Open( Path.Combine( specialDir , "no_such_file.i3d" ) ); Ok( false , "nofile: accepted" ); }
        catch( I3DException e ) { Ok( e.Id == "cannotOpen" , $"nofile: got {e.Id}" ); Console.WriteLine( $"  no such file -> [{e.Id}]" ); }
        // un buffer del tipo o tamano equivocado: error, no escritura fuera
        using( var f = I3DFile.Open( Path.Combine( specialDir , "utf8.i3d" ) ) )
        {
            try { f.ReadData( new float[24].AsSpan() ); Ok( false , "wrong T accepted" ); } catch( I3DException e ) { Ok( e.Id == "badBuffer" , "wrong T" ); }
            try { f.ReadData( new ushort[23].AsSpan() ); Ok( false , "short buffer accepted" ); } catch( I3DException e ) { Ok( e.Id == "badBuffer" , "short buffer" ); }
        }

        Console.WriteLine( $"{nok} checks ok, {nbad} failed" );
        return nbad == 0 ? 0 : 1;
    }

    // ReadData<T>(Span<T>) y ReadFirstFrame<T>(Span<T>), para el T de data
    static bool SpanMatches( I3DFile f , Array data , Array first ) => f.DataType switch
    {
        "int8" => Same<sbyte>( f , data , first ), "uint8" => Same<byte>( f , data , first ),
        "int16" => Same<short>( f , data , first ), "uint16" => Same<ushort>( f , data , first ),
        "int32" => Same<int>( f , data , first ), "uint32" => Same<uint>( f , data , first ),
        "int64" => Same<long>( f , data , first ), "uint64" => Same<ulong>( f , data , first ),
        "single" => Same<float>( f , data , first ), "double" => Same<double>( f , data , first ),
        _ => false,
    };

    static bool Same<T>( I3DFile f , Array data , Array first ) where T : unmanaged
    {
        var d = new T[data.Length];
        f.ReadData<T>( d );
        var s = new T[first.Length];
        f.ReadFirstFrame<T>( s );
        return MemoryMarshal.AsBytes( d.AsSpan() ).SequenceEqual( Bytes( data ) ) &&
               MemoryMarshal.AsBytes( s.AsSpan() ).SequenceEqual( Bytes( first ) );
    }
}
