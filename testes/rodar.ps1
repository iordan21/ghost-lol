# Roda todos os testes desta pasta e devolve codigo de saida 1 se algum falhar.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\testes\rodar.ps1
#
# Cada teste roda num processo proprio: eles recortam funcoes do ghost.ps1 com
# Invoke-Expression, e no mesmo processo um redefiniria o outro.
$ErrorActionPreference = 'Stop'

$arquivos = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' |
            Where-Object { $_.Name -notin @('rodar.ps1', 'comum.ps1') } |
            Sort-Object Name

$ruins = @()
foreach ($f in $arquivos) {
    ''
    "=============================== $($f.Name)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $f.FullName
    if ($LASTEXITCODE -ne 0) { $ruins += $f.Name }
}

''
'==============================='
if ($ruins.Count -eq 0) {
    "$($arquivos.Count) arquivos, todos passaram."
    exit 0
}
"FALHOU: $($ruins -join ', ')"
exit 1
