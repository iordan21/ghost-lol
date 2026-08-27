# Gate de autofill: decide se o auto-pick pode agir na lane que veio.
# Nao precisa do cliente aberto nem de internet.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')
Invoke-Expression (Get-FonteFuncao @('ConvertTo-LaneNormal', 'Test-PickLiberado'))

$IgnorarAutofill     = $false
$script:LanesPedidas = @()

Titulo 'normalizacao dos dois jeitos que o cliente escreve lane'
Checa "middle vira MIDDLE"  (ConvertTo-LaneNormal 'middle')  'MIDDLE'
Checa "MID vira MIDDLE"     (ConvertTo-LaneNormal 'MID')     'MIDDLE'
Checa "support vira UTILITY" (ConvertTo-LaneNormal 'support') 'UTILITY'
Checa "adc vira BOTTOM"     (ConvertTo-LaneNormal 'adc')     'BOTTOM'

Titulo 'tabela de decisao'
# pedidas, atribuida, pode picar?, o que e
$casos = @(
    @(@('MIDDLE','JUNGLE'),  'middle',  $true,  'pediu mid, veio mid'),
    @(@('MIDDLE','JUNGLE'),  'jungle',  $true,  'pediu jg, veio jg'),
    @(@('MIDDLE','JUNGLE'),  'utility', $false, 'AUTOFILL suporte'),
    @(@('MIDDLE','JUNGLE'),  'top',     $false, 'AUTOFILL topo'),
    @(@('FILL'),             'utility', $true,  'pediu fill, aceita tudo'),
    @(@(),                   'utility', $true,  'sem leitura do lobby'),
    @($null,                 'utility', $true,  'lobby devolveu null'),
    @(@('MIDDLE','JUNGLE'),  '',        $true,  'cega/ARAM, sem lane'),
    @(@('BOTTOM','UTILITY'), 'bottom',  $true,  'adc, veio adc'),
    @(@('MID','SUPPORT'),    'middle',  $true,  'apelido MID casa com MIDDLE'),
    @(@('MIDDLE','JUNGLE'),  'MIDDLE',  $true,  'maiuscula tambem casa')
)
foreach ($c in $casos) {
    # @($null) tem um item, nao zero - e justo o caso de leitura falha.
    $script:LanesPedidas = if ($null -eq $c[0]) { @($null) } else { @($c[0]) }
    Checa $c[3] (Test-PickLiberado -Atribuida $c[1]) $c[2]
}

Titulo '-IgnorarAutofill destrava tudo'
$IgnorarAutofill = $true
$script:LanesPedidas = @('MIDDLE')
Checa 'autofill liberado pelo parametro' (Test-PickLiberado -Atribuida 'utility') 'True'

Fim
