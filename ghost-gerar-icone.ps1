# Gera ghost.ico: metade esquerda em preto e branco, metade direita colorida.
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'IconGrab').Type) {
Add-Type -Namespace '' -Name IconGrab -MemberDefinition @'
  [DllImport("Shell32.dll", CharSet=CharSet.Unicode)]
  public static extern int SHDefExtractIconW(string file, int index, uint flags,
      out System.IntPtr large, out System.IntPtr small, uint size);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);
'@
}

$origem = 'C:\Riot Games\League of Legends\LeagueClient.exe'
if (-not (Test-Path -LiteralPath $origem)) { throw "nao achei $origem" }

# LOWORD = tamanho do icone grande, HIWORD = do pequeno. Peco 256 pra ter
# resolucao de sobra antes de reduzir.
$big = [IntPtr]::Zero; $small = [IntPtr]::Zero
$hr = [IconGrab]::SHDefExtractIconW($origem, 0, 0, [ref]$big, [ref]$small, (256 -bor (32 -shl 16)))
if ($hr -ne 0 -or $big -eq [IntPtr]::Zero) { throw "SHDefExtractIcon falhou (hr=$hr)" }

$ico = [System.Drawing.Icon]::FromHandle($big)
$src = $ico.ToBitmap()
"origem: $($src.Width)x$($src.Height)"

# ---------------------------------------------------------------------------
# Monta a versao meio a meio
# ---------------------------------------------------------------------------
$W = $src.Width; $H = $src.Height; $meio = [int]($W / 2)

$dst = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = 'HighQualityBicubic'
$g.PixelOffsetMode   = 'HighQuality'

# Metade direita: cor original, sem mexer.
$g.DrawImage($src, (New-Object System.Drawing.Rectangle($meio, 0, ($W - $meio), $H)),
             $meio, 0, ($W - $meio), $H, [System.Drawing.GraphicsUnit]::Pixel)

# Metade esquerda: ColorMatrix de luminancia. Uso a formula de brilho
# percebido (0.299/0.587/0.114) em vez de media simples - media chapa o
# dourado do logo e o resultado fica lavado. A linha [3][3]=1 preserva o alfa,
# senao o fundo transparente vira quadrado preto.
$m = New-Object 'float[][]' 5
for ($i = 0; $i -lt 5; $i++) { $m[$i] = New-Object 'float[]' 5 }
$m[0][0] = 0.299; $m[0][1] = 0.299; $m[0][2] = 0.299
$m[1][0] = 0.587; $m[1][1] = 0.587; $m[1][2] = 0.587
$m[2][0] = 0.114; $m[2][1] = 0.114; $m[2][2] = 0.114
$m[3][3] = 1.0
$m[4][4] = 1.0
# A virgula antes de $m e obrigatoria: sem ela o PowerShell desmonta o array
# de arrays em 5 argumentos soltos e nao acha o construtor.
$cm = New-Object System.Drawing.Imaging.ColorMatrix -ArgumentList (, $m)
$ia = New-Object System.Drawing.Imaging.ImageAttributes
$ia.SetColorMatrix($cm)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $meio, $H)),
             0, 0, $meio, $H, [System.Drawing.GraphicsUnit]::Pixel, $ia)
$g.Dispose()

# ---------------------------------------------------------------------------
# Grava o .ico
#
# Todo tamanho vai em BMP (BITMAPINFOHEADER + pixels + mascara AND).
#
# A tentacao e usar PNG nos grandes: 256x256 em BMP sao 256KB crus contra 54KB
# comprimidos. Mas o System.Drawing.Icon do .NET Framework NAO le entrada PNG
# dentro de .ico - testado: nos tamanhos pequenos em BMP a leitura sai certa,
# e nos de PNG ele devolve imagem embaralhada (e ainda entrega 128 quando voce
# pede 256). Como o proprio ghost.ps1 carrega o icone por System.Drawing.Icon,
# 350KB em disco e um preco barato por funcionar em todo tamanho.
# ---------------------------------------------------------------------------
function New-EntradaBmp {
    param([System.Drawing.Bitmap] $Bmp)

    $w = $Bmp.Width; $h = $Bmp.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $dados = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                           [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $dados.Stride
        $bytes  = New-Object byte[] ($stride * $h)
        [System.Runtime.InteropServices.Marshal]::Copy($dados.Scan0, $bytes, 0, $bytes.Length)
    }
    finally { $Bmp.UnlockBits($dados) }

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    # BITMAPINFOHEADER. A altura vai DOBRADA de proposito: o formato conta
    # a imagem de cores mais a mascara AND como se fossem uma so.
    $bw.Write([uint32]40)         # biSize
    $bw.Write([int32]$w)          # biWidth
    $bw.Write([int32]($h * 2))    # biHeight
    $bw.Write([uint16]1)          # biPlanes
    $bw.Write([uint16]32)         # biBitCount
    $bw.Write([uint32]0)          # biCompression = BI_RGB
    $bw.Write([uint32]($w * $h * 4))
    $bw.Write([int32]0); $bw.Write([int32]0)
    $bw.Write([uint32]0); $bw.Write([uint32]0)

    # Pixels de baixo pra cima - BMP guarda a imagem invertida.
    for ($y = $h - 1; $y -ge 0; $y--) {
        $bw.Write($bytes, ($y * $stride), ($w * 4))
    }

    # Mascara AND: obrigatoria mesmo com alfa de 32 bits. Zerada = tudo
    # opaco, e a transparencia real vem do canal alfa. Cada linha e
    # alinhada em 4 bytes.
    $linhaMascara = [int]([math]::Ceiling($w / 8.0))
    $linhaMascara = [int]([math]::Ceiling($linhaMascara / 4.0)) * 4
    $zeros = New-Object byte[] $linhaMascara
    for ($y = 0; $y -lt $h; $y++) { $bw.Write($zeros, 0, $linhaMascara) }

    $bw.Flush()
    $saida = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    # A virgula e obrigatoria: sem ela o PowerShell desenrola o byte[] na
    # saida da funcao e quem recebe pega um Object[] de bytes soltos.
    return ,$saida
}

function New-EntradaPng {
    param([System.Drawing.Bitmap] $Bmp)
    $ms = New-Object System.IO.MemoryStream
    $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $saida = $ms.ToArray()
    $ms.Dispose()
    return ,$saida
}

$tamanhos = @(16, 24, 32, 48, 64, 128, 256)
$entradas = @()
foreach ($t in $tamanhos) {
    $bmp = New-Object System.Drawing.Bitmap($t, $t, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg  = [System.Drawing.Graphics]::FromImage($bmp)
    $gg.InterpolationMode = 'HighQualityBicubic'
    $gg.PixelOffsetMode   = 'HighQuality'
    $gg.DrawImage($dst, 0, 0, $t, $t)
    $gg.Dispose()

    $dados = New-EntradaBmp -Bmp $bmp
    $entradas += ,@{ Size = $t; Bytes = $dados; Tipo = 'BMP' }
    $bmp.Dispose()
}

# Grava ao lado do proprio script, nao em caminho absoluto: caminho chumbado
# com nome de usuario vaza pra quem clonar o repositorio.
$destino = Join-Path $PSScriptRoot 'ghost.ico'
$fs = [System.IO.File]::Create($destino)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    $bw.Write([uint16]0)                 # reservado
    $bw.Write([uint16]1)                 # 1 = icone
    $bw.Write([uint16]$entradas.Count)

    # Cada entrada precisa saber onde seus dados comecam: cabecalho de 6 bytes
    # + 16 bytes por entrada, e dai em diante os blocos em sequencia.
    $offset = 6 + (16 * $entradas.Count)
    foreach ($e in $entradas) {
        $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }   # 0 significa 256
        $bw.Write([byte]$dim)            # largura
        $bw.Write([byte]$dim)            # altura
        $bw.Write([byte]0)               # cores da paleta (0 = truecolor)
        $bw.Write([byte]0)               # reservado
        $bw.Write([uint16]1)             # planos
        $bw.Write([uint16]32)            # bits por pixel
        $bw.Write([uint32]$e.Bytes.Length)
        $bw.Write([uint32]$offset)
        $offset += $e.Bytes.Length
    }
    # Cast explicito: garante a sobrecarga Write(byte[]) e nao Write(byte),
    # que foi como esse arquivo saiu com 125 bytes na primeira tentativa.
    foreach ($e in $entradas) { $bw.Write([byte[]]$e.Bytes, 0, $e.Bytes.Length) }
}
finally { $bw.Dispose(); $fs.Dispose() }

$previa = Join-Path $PSScriptRoot 'ghost-previa.png'
$dst.Save($previa, [System.Drawing.Imaging.ImageFormat]::Png)

$dst.Dispose(); $src.Dispose(); $ico.Dispose()
[void][IconGrab]::DestroyIcon($big)
if ($small -ne [IntPtr]::Zero) { [void][IconGrab]::DestroyIcon($small) }

"gravado: $destino ($((Get-Item $destino).Length) bytes)"
($entradas | ForEach-Object { "  $($_.Size)px $($_.Tipo) - $($_.Bytes.Length) bytes" }) -join "`n"
