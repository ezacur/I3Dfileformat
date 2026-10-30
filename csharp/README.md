# I3D para .NET 8

Lector `.i3d` (ver `SPEC.md`) para C#. Es un envoltorio fino de la API en C de
`cpp/i3d_c.h`, es decir de `i3d.dll`. La lógica del formato está toda en la DLL,
la misma que usan MATLAB (MEX) y Python (ctypes): aquí sólo se pasan argumentos
y se convierten los errores en excepciones.

```
csharp/
  I3D/          la biblioteca: I3DFile.cs  (ensamblado I3D.Net.dll)
  I3D.Tests/    pruebas de consola, bit a bit contra el lector de referencia en Python
```

## Uso

```csharp
using I3D;

using var f = I3DFile.Open( @"D:\datos\serie.i3d" );
double[] X = f.X, Y = f.Y, Z = f.Z, T = f.T;   // rejillas exactas
double[,] A = f.Transform;                      // 4x4 [fila, columna]: world = A * [X(i); Y(j); Z(k); 1]
long[] shape = f.Shape;                         // i j k t c...
string tipo = f.DataType;                       // "int16", "single", ...

var ( data , s ) = f.ReadData();                // Array tipado (short[], float[], ...), ORDEN COLUMNA
var ( first , s1 ) = f.ReadFirstFrame();        // sólo data(:,:,:,1,c...); s1[3] == 1

// sin copia, en un buffer propio (T tiene que ser el tipo de data, y el tamaño exacto)
var buf = new short[f.DataBytes / sizeof( short )];
f.ReadData<short>( buf );

var ( slope , intercept ) = f.Rescale;
var win = f.Window;                             // (Center, Width)? -- null si no hay window
I3DBox[] huecos = f.Missing;                    // cajas 0-based, Hi exclusivo

foreach( var nombre in f.AuxNames ) { var aux = f.ReadAux( nombre ); }
var nada = f.ReadAux( "noExiste" );            // null, no excepción

foreach( var e in f.Entries ) Console.WriteLine( $"{e.Key}({e.Subs}) = {e.Value}" );
string cabecera = f.Header;                     // en claro, también la de un I3Db
bool oculta = f.IsHidden;
```

**Orden de los datos.** `ReadData` devuelve un array 1-D en el orden de MATLAB:
`i` es el índice más rápido, luego `j`, `k`, `t`, `c`… El elemento `(i,j,k,t)`
(0-based) está en `i + I*(j + J*(k + K*t))`.

**Variables.** Las `$NOMBRE$` de la cabecera se pueden sobrescribir al abrir, por
ejemplo para seguir a unos `.dcm` que se han movido sin editar el `.i3d`:

```csharp
using var f = I3DFile.Open( ruta , new Dictionary<string, string> { ["DICOMDIR"] = @"E:\nuevo\sitio" } );
```

Los nombres se pasan sin `$`; si llevan `$`, se quitan.

**Errores.** Todo fallo de la DLL llega como una `I3DException` cuyo `Id` es el
identificador corto de la DLL: `cannotOpen`, `badHeader`, `coverage`,
`badBlock`, `badCRC`… El `Message` empieza por `[Id]`. Hay además dos `Id`
propios de este envoltorio:

- `badBuffer`: un `Span<T>` del tipo o del tamaño equivocado. Se rechaza antes
  de llamar a la DLL, así que nunca se escribe fuera del buffer.
- `badData`: la DLL dice que una caja `missing` tiene más de 16 dimensiones.

Las cadenas (rutas, cabecera, entradas, nombres de aux) son UTF-8 en los dos
sentidos, así que `"Muñoz^José"` llega intacto.

## Compilar

Hace falta el SDK de .NET 8, y antes `cpp/build.bat`, porque la biblioteca no
compila la DLL nativa: la **copia**. `I3D.csproj` coge `..\..\cpp\build\i3d.dll`
y la deja junto al ensamblado. Cualquier proyecto que referencie `I3D.csproj`
la recibe también en su carpeta de salida.

```
cd C:\repos\I3Dfileformat\csharp
dotnet build I3D.Tests -c Release
```

Sólo x64, que es lo que es la DLL (`PlatformTarget` x64).

**Por qué el ensamblado se llama `I3D.Net.dll` y no `I3D.dll`.** Windows no
distingue mayúsculas en los nombres de fichero. Un `I3D.dll` gestionado pisaría
al `i3d.dll` nativo en la carpeta de salida, y el P/Invoke cargaría el
gestionado: `EntryPointNotFoundException: 'i3d_open'`. El espacio de nombres
sigue siendo `I3D`.

## Pruebas

```
dotnet run --project I3D.Tests -c Release --no-build -- <dir de referencias> <dir de especiales>
```

Las referencias las escribe un script de Python que lee cada `.i3d` con el lector
de **referencia** (`tests/read_i3d.py`) y vuelca:

- `<tag>.json`: tipo, forma, rejillas y transform en hexadecimal, info, aux y variables;
- `<tag>.data.bin` y `<tag>.first.bin`: data y primer instante, en orden columna;
- `<tag>.aux.NOMBRE.bin`: cada aux.

El script también fabrica los ficheros especiales: info UTF-8, I3Db oculto, aux
PNG, una ruta `$DICOMDIR$` rota (para probar la sobrescritura) y dos inválidos.

Lo que se compara, para cada `.i3d` de `tests/out_piechnik_canon` y los
especiales:

- **bit a bit:** tipo, forma, X/Y/Z/T, transform, data, primer instante, las
  dos sobrecargas `Span<T>`, cada aux (bytes y forma) y cada `info.*`;
- además: que un aux inexistente dé `null`, el UTF-8, `IsHidden`, la PNG
  decodificada, la variable sobrescrita (y que sin sobrescribir falle con
  `cannotOpen`), `coverage`, `badBlock`, un fichero inexistente y `badBuffer`.

Termina con `N checks ok, M failed`, y con código de salida 1 si algo falla.
