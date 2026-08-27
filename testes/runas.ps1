# Runas: mapa de lane, validacao de sanidade e busca de verdade no op.gg.
# Precisa de internet. NAO toca no cliente nem em pagina de runa nenhuma.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')
Invoke-Expression (Get-FonteFuncao @('ConvertTo-LaneNormal', 'ConvertTo-LaneOpGg', 'Test-RunaSensata',
                'Start-BuscaRunaOpGg', 'Read-RunaOpGg', 'Remove-JobRuna'))
$script:Curl = (Get-Command curl.exe).Source

Titulo 'lane do cliente para a lane do op.gg'
Checa 'MIDDLE  -> mid'     (ConvertTo-LaneOpGg 'middle')  'mid'
Checa 'UTILITY -> support' (ConvertTo-LaneOpGg 'utility') 'support'
Checa 'BOTTOM  -> adc'     (ConvertTo-LaneOpGg 'bottom')  'adc'
Checa 'TOP     -> top'     (ConvertTo-LaneOpGg 'TOP')     'top'
Checa 'JUNGLE  -> jungle'  (ConvertTo-LaneOpGg 'jungle')  'jungle'
Checa 'sem lane -> vazio'  (ConvertTo-LaneOpGg '')        ''

Titulo 'sanidade: o cliente aceita id inventado, entao quem barra somos nos'
$ILLAOI = @(8437,8446,8473,8451,8009,8299,5008,5008,5001)
Checa 'recusa ids 1..6'          (Test-RunaSensata ([pscustomobject]@{Primary=8100;Sub=8200;Perks=@(1,2,3,4,5,6)})) 'False'
Checa 'recusa estilo fora da faixa' (Test-RunaSensata ([pscustomobject]@{Primary=1;Sub=8200;Perks=$ILLAOI}))       'False'
Checa 'recusa primario igual ao sub' (Test-RunaSensata ([pscustomobject]@{Primary=8100;Sub=8100;Perks=$ILLAOI}))   'False'
Checa 'recusa lista curta'       (Test-RunaSensata ([pscustomobject]@{Primary=8100;Sub=8200;Perks=@(8112,8139)}))  'False'
Checa 'recusa nulo'              (Test-RunaSensata $null)                                                          'False'
Checa 'aceita runa de verdade'   (Test-RunaSensata ([pscustomobject]@{Primary=8400;Sub=8000;Perks=$ILLAOI}))       'True'

Titulo 'lixo no arquivo nao pode virar runa'
$tmp = Join-Path $env:TEMP 'ghost-teste-lixo.html'
Set-Content -LiteralPath $tmp -Value ('<html>bloqueado</html>' * 200) -Encoding ASCII
Checa 'HTML sem runa -> nada'   ([bool](Read-RunaOpGg $tmp))                'False'
Set-Content -LiteralPath $tmp -Value 'curto' -Encoding ASCII
Checa 'arquivo curto -> nada'   ([bool](Read-RunaOpGg $tmp))                'False'
Checa 'arquivo ausente -> nada' ([bool](Read-RunaOpGg 'C:\nao\existe.html')) 'False'
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Titulo 'busca de verdade no op.gg'
# Naotem nao existe: o op.gg devolve pagina, mas sem runa. Tem que falhar
# limpo, porque e esse caminho que leva pra recomendacao da Riot.
foreach ($c in @(@('Illaoi','top'), @('Ahri','middle'), @('Thresh','utility'),
                 @('Jinx','bottom'), @('Naotem','top'))) {
    $alias = $c[0]; $lane = $c[1]
    $job = Start-BuscaRunaOpGg -Alias $alias -Lane $lane
    if (-not $job) { Checa "$alias/$lane iniciou" 'nao' 'sim'; continue }

    $ini = Get-Date
    while (-not $job.Proc.HasExited -and ((Get-Date) - $ini).TotalSeconds -lt 20) {
        Start-Sleep -Milliseconds 200
    }
    $r = Read-RunaOpGg $job.Arquivo
    Remove-JobRuna $job

    if ($alias -eq 'Naotem') {
        Checa "$alias/$lane inexistente -> nada" ([bool]$r) 'False'
    }
    elseif ($r) {
        Checa "$alias/$lane" ("{0}/{1} perks={2}" -f $r.Primary, $r.Sub, $r.Perks.Count) `
              ("{0}/{1} perks={2}" -f $r.Primary, $r.Sub, $r.Perks.Count)
        Checa "  ..passa na sanidade" (Test-RunaSensata $r) 'True'
    }
    else { Checa "$alias/$lane trouxe runa" 'nao' 'sim' }
}

Fim
