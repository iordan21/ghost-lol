# Feiticos de invocador: tabela de ids, leitura da pagina do op.gg e a regra
# da tecla (quem ja estava em D ou F fica la). A parte de rede busca de
# verdade no op.gg. NAO toca no cliente: a chamada que escreve e trocada por
# uma falsa que so anota o que teria mandado.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')
Invoke-Expression (Get-FonteFuncao @('ConvertTo-LaneNormal', 'ConvertTo-LaneOpGg', 'Test-RunaSensata',
                'Start-BuscaRunaOpGg', 'Read-RunaOpGg', 'Remove-JobRuna',
                'Get-TabelaFeiticos', 'Get-NomeFeitico', 'Test-FeiticosSensatos',
                'Read-FeiticosOpGg', 'Set-FeiticosGhost'))
$script:Curl = (Get-Command curl.exe).Source
$Simular = $false
$C = @{ Azul = 1; Verde = 2; Vermelho = 3; Ambar = 4; Fraco = 5 }
$script:FlashEm = ''

# Dubles: anotam em vez de mandar pro cliente. O de log nao devolve nada de
# proposito - devolver string aqui contaminaria o retorno da funcao testada.
$script:Chamadas   = @()
$script:StatusFake = 204
function Invoke-Lcu {
    param($Session, $Path, $Method, $JsonBody, $TimeoutSec)
    $script:Chamadas += [pscustomobject]@{ Path = $Path; Method = $Method; Body = $JsonBody }
    return [pscustomobject]@{ Status = $script:StatusFake; Body = '' }
}
function Write-Log { param($Texto, $Cor) $script:Logs += @($Texto) }
$script:Logs = @()

Titulo 'tabela: id e nome conferidos no Data Dragon'
$tab = Get-TabelaFeiticos
Checa 'onze feiticos'        $tab.Count                       11
Checa 'Flash e 4'            $tab.SummonerFlash[0]            4
Checa 'Teleporte e 12'       $tab.SummonerTeleport[0]         12
Checa 'Incendiar e 14'       $tab.SummonerDot[0]              14
Checa 'Golpear e 11'         $tab.SummonerSmite[0]            11
Checa 'nome do 4'            (Get-NomeFeitico 4)              'Flash'
Checa 'nome do 21'           (Get-NomeFeitico 21)             'Barreira'
Checa 'id desconhecido'      (Get-NomeFeitico 99)             'feitico 99'

Titulo 'sanidade: dois ids da tabela, diferentes'
Checa 'aceita Flash + TP'    (Test-FeiticosSensatos @(4, 12))  'True'
Checa 'recusa nulo'          (Test-FeiticosSensatos $null)     'False'
Checa 'recusa um so'         (Test-FeiticosSensatos @(4))      'False'
Checa 'recusa tres'          (Test-FeiticosSensatos @(4,12,7)) 'False'
Checa 'recusa repetido'      (Test-FeiticosSensatos @(4, 4))   'False'
Checa 'recusa id inventado'  (Test-FeiticosSensatos @(4, 99))  'False'

Titulo 'leitura da pagina: cabecalho e a primeira dupla'
$img = '<img src="https://x/spell/{0}.png">'
$ok  = '<th>Summoner spells</th><tr>' + ($img -f 'SummonerFlash') + ($img -f 'SummonerTeleport') +
       '</tr><tr>' + ($img -f 'SummonerExhaust') + ($img -f 'SummonerFlash') + '</tr>'
Checa 'pega a primeira dupla'   ((Read-FeiticosOpGg -Html $ok) -join ',')    '4,12'
Checa 'sem cabecalho -> nada'   ([bool](Read-FeiticosOpGg -Html ($ok -replace 'Summoner spells', 'x'))) 'False'
Checa 'feitico estranho -> nada' ([bool](Read-FeiticosOpGg -Html ($ok -replace 'SummonerTeleport', 'SummonerNovo'))) 'False'
$longe = '<th>Summoner spells</th>' + ($img -f 'SummonerFlash') + ('.' * 3000) + ($img -f 'SummonerTeleport')
Checa 'dupla separada -> nada'  ([bool](Read-FeiticosOpGg -Html $longe))     'False'
Checa 'vazio -> nada'           ([bool](Read-FeiticosOpGg -Html ''))         'False'
# Imagem de feitico ANTES do cabecalho nao conta: o corte comeca no cabecalho.
$antes = ($img -f 'SummonerSmite') + $ok
Checa 'ignora o que vem antes'  ((Read-FeiticosOpGg -Html $antes) -join ',') '4,12'

Titulo 'regra da tecla: quem ja estava em D ou F fica la'
function Manda { param($Novos, $D, $F)
    $script:Chamadas = @()
    $r = Set-FeiticosGhost -Feiticos $Novos -AtualD $D -AtualF $F
    if ($script:Chamadas.Count -eq 0) { return "$r sem chamada" }
    return "$r " + $script:Chamadas[0].Body
}
Checa 'Flash no D fica no D'       (Manda @(4,12) 4 14)  'True {"spell1Id":4,"spell2Id":12}'
Checa 'Flash no F fica no F'       (Manda @(4,12) 14 4)  'True {"spell1Id":12,"spell2Id":4}'
Checa 'TP no D fica no D'          (Manda @(4,12) 12 6)  'True {"spell1Id":12,"spell2Id":4}'
Checa 'TP no F fica no F'          (Manda @(4,12) 6 12)  'True {"spell1Id":4,"spell2Id":12}'
Checa 'nenhum dos dois: ordem op.gg' (Manda @(4,21) 7 14) 'True {"spell1Id":4,"spell2Id":21}'
Checa 'selecao vazia: ordem op.gg' (Manda @(4,12) 0 0)   'True {"spell1Id":4,"spell2Id":12}'
Checa 'ja esta igual: nao manda'   (Manda @(4,12) 4 12)  'True sem chamada'
Checa 'ja esta invertido: nao manda' (Manda @(4,12) 12 4) 'True sem chamada'
Checa 'lixo: nao manda'            (Manda @(4,99) 4 12)  'False sem chamada'

Titulo 'tecla do Flash escolhida: ganha da regra de ficar onde estava'
$script:FlashEm = 'D'
Checa 'D: Flash estava no F, vai pro D' (Manda @(4,12) 14 4)  'True {"spell1Id":4,"spell2Id":12}'
Checa 'D: ja estava no D, nao manda'   (Manda @(4,12) 4 12)   'True sem chamada'
Checa 'D: par invertido, corrige'      (Manda @(4,12) 12 4)   'True {"spell1Id":4,"spell2Id":12}'
Checa 'D: op.gg mandou Flash em 2o'    (Manda @(21,4) 7 14)   'True {"spell1Id":4,"spell2Id":21}'
Checa 'D: dupla sem Flash, regra velha' (Manda @(11,6) 6 4)   'True {"spell1Id":6,"spell2Id":11}'
$script:FlashEm = 'F'
Checa 'F: Flash estava no D, vai pro F' (Manda @(4,12) 4 14)  'True {"spell1Id":12,"spell2Id":4}'
Checa 'F: ja estava no F, nao manda'   (Manda @(4,12) 12 4)   'True sem chamada'
Checa 'F: selecao vazia'               (Manda @(4,12) 0 0)    'True {"spell1Id":12,"spell2Id":4}'
$script:FlashEm = 'X'
Checa 'valor invalido = onde estava'  (Manda @(4,12) 14 4)  'True {"spell1Id":12,"spell2Id":4}'
$script:FlashEm = ''
[void](Manda @(4,12) 4 14)
Checa 'PATCH em my-selection' ("{0} {1}" -f $script:Chamadas[0].Method, $script:Chamadas[0].Path) `
      'PATCH /lol-champ-select/v1/session/my-selection'
$script:StatusFake = 500
Checa 'HTTP 500 -> False'          (Manda @(4,12) 4 14)  'False {"spell1Id":4,"spell2Id":12}'
$script:StatusFake = 204
$Simular = $true
Checa 'simulado: so log'           (Manda @(4,12) 4 14)  'True sem chamada'
Checa '  ..e o log diz SIMULADO'   ([bool]($script:Logs -match '^SIMULADO: feiticos Flash \(D\) \+ Teleporte \(F\)')) 'True'
$Simular = $false

Titulo 'busca de verdade no op.gg: a dupla vem junto com a runa'
# Lee Sin sem lane e o caso do treino: o op.gg tem que escolher jungle, e
# jungle e a unica lane em que Golpear aparece - se vier, a escolha foi certa.
foreach ($c in @(@('Illaoi','top',4), @('LeeSin','jungle',11), @('Lulu','utility',4),
                 @('Jinx','bottom',4), @('LeeSin','',11))) {
    $alias = $c[0]; $lane = $c[1]; $temQueTer = $c[2]
    $job = Start-BuscaRunaOpGg -Alias $alias -Lane $lane
    if (-not $job) { Checa "$alias/$lane iniciou" 'nao' 'sim'; continue }
    $ini = Get-Date
    while (-not $job.Proc.HasExited -and ((Get-Date) - $ini).TotalSeconds -lt 20) {
        Start-Sleep -Milliseconds 200
    }
    $r = Read-RunaOpGg $job.Arquivo
    Remove-JobRuna $job
    if (-not $r) { Checa "$alias/$lane trouxe runa" 'nao' 'sim'; continue }
    $f = @($r.Feiticos)
    Checa "$alias/$lane veio com dois feiticos" $f.Count 2
    Checa "  ..passam na sanidade"  (Test-FeiticosSensatos $f) 'True'
    Checa ("  ..tem {0}" -f (Get-NomeFeitico $temQueTer)) ($f -contains $temQueTer) 'True'
    "      -> {0} + {1}" -f (Get-NomeFeitico $f[0]), (Get-NomeFeitico $f[1])
}

Titulo 'o cliente expoe o endpoint (so com o cliente aberto)'
$lock = 'C:\Riot Games\League of Legends\lockfile'
if (-not (Test-Path -LiteralPath $lock)) {
    'PULADO: cliente do LoL fechado.'
}
else {
    $lf = (Get-Content -LiteralPath $lock -Raw).Trim() -split ':'
    # O /help lista as operacoes em CamelCase, nao pela URL. E o tipo do corpo
    # tem que ter spell1Id e spell2Id - e o que o Ghost manda.
    $ajuda = (& $script:Curl -s -k --max-time 20 -u "riot:$($lf[3])" "https://127.0.0.1:$($lf[2])/help?format=Full") -join ''
    Checa 'help lista PatchLolChampSelectV1SessionMySelection' ([bool]($ajuda -match 'PatchLolChampSelectV1SessionMySelection')) 'True'
    Checa 'corpo aceita spell1Id e spell2Id' ([bool]($ajuda -match '"spell1Id"' -and $ajuda -match '"spell2Id"')) 'True'
}

Fim
