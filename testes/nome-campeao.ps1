# Nome e alias do campeao: e o que decide o nome da pagina de runa e se a
# busca no op.gg chega a acontecer. Precisa do cliente do LoL aberto.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')
Invoke-Expression (Get-FonteFuncao @('Invoke-Lcu', 'ConvertFrom-LcuBody',
                                     'Import-Campeoes', 'Get-NomeCampeao'))

$lock = 'C:\Riot Games\League of Legends\lockfile'
if (-not (Test-Path -LiteralPath $lock)) {
    'PULADO: cliente do LoL fechado.'
    exit 0
}
$lf = (Get-Content -LiteralPath $lock -Raw).Trim() -split ':'
$script:Session  = [pscustomobject]@{ Port = $lf[2]; Password = $lf[3] }
$script:Curl     = (Get-Command curl.exe).Source
$script:Campeoes = @()
$script:PorId    = @{}

Titulo 'sem carregar a lista, o nome e o numero'
# Este era o bug: Update-Runa montava "Ghost Runa campeao 103" e, sem alias,
# nem tentava o op.gg.
Checa 'lista comeca vazia'     $script:Campeoes.Count 0
Checa 'nome vira "campeao 103"' (Get-NomeCampeao 103)  'campeao 103'

Titulo 'depois de carregar'
Checa 'carregou'          (Import-Campeoes) 'True'
Checa 'tem campeao'       ($script:Campeoes.Count -gt 100) 'True'
Checa 'e idempotente'     (Import-Campeoes) 'True'

Titulo 'nome e alias de campeoes conhecidos'
foreach ($c in @(@(103,'Ahri'), @(420,'Illaoi'), @(412,'Thresh'), @(222,'Jinx'))) {
    $id = $c[0]; $esperado = $c[1]
    Checa "id $id -> nome"  (Get-NomeCampeao $id) $esperado
    Checa "id $id -> alias" $script:PorId[$id].Alias $esperado
}

Titulo 'todo campeao tem alias em ASCII, que e o que vai pra URL do op.gg'
$semAlias = @($script:Campeoes | Where-Object { -not $_.Alias })
Checa 'nenhum sem alias' $semAlias.Count 0
$naoAscii = @($script:Campeoes | Where-Object { $_.Alias -match '[^\x20-\x7E]' })
Checa 'nenhum alias fora do ASCII' $naoAscii.Count 0

Titulo 'id desconhecido continua caindo no texto de reserva'
Checa 'id 999999' (Get-NomeCampeao 999999) 'campeao 999999'

Fim
