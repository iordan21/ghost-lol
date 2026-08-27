# Base compartilhada dos testes do Ghost.
#
# Os testes puxam as funcoes de dentro do ghost.ps1 em vez de duplicar codigo.
# O script e um arquivo so, com janela e loop no nivel de cima - dot-source
# abriria a HUD. Entao aqui a funcao pedida e recortada do texto e avaliada
# sozinha. Muda o ghost.ps1, o teste ve na hora, e nao existe copia pra sair
# de sincronia.

$script:Ghost = Join-Path (Split-Path $PSScriptRoot -Parent) 'ghost.ps1'

# Devolve o TEXTO das funcoes, em vez de defini-las aqui dentro: uma funcao
# definida por Invoke-Expression nasce no escopo de quem chamou o
# Invoke-Expression. Feito la dentro, ela morreria junto com esta funcao e o
# teste nao enxergaria nada. Quem chama avalia no nivel de cima.
function Get-FonteFuncao {
    param([Parameter(Mandatory)][string[]] $Nomes)
    $fonte = Get-Content -LiteralPath $script:Ghost -Raw
    $saida = New-Object System.Text.StringBuilder
    foreach ($n in $Nomes) {
        $re = [regex]("(?ms)^function\s+" + [regex]::Escape($n) + "\s*\{.*?^\}")
        $m  = $re.Match($fonte)
        if (-not $m.Success) { throw "nao achei a funcao $n em ghost.ps1" }
        [void]$saida.AppendLine($m.Value)
    }
    return $saida.ToString()
}

$script:Falhas = 0

function Checa {
    param([string] $Rotulo, $Obtido, $Esperado)
    $ok = ("$Obtido" -eq "$Esperado")
    if (-not $ok) { $script:Falhas++ }
    "{0}  {1,-40} {2}" -f $(if ($ok) { 'ok  ' } else { 'FALHA' }), $Rotulo, $Obtido
}

function Titulo { param([string] $T) ''; "--- $T ---" }

function Fim {
    ''
    if ($script:Falhas) { "$script:Falhas FALHA(S)"; exit 1 }
    'todos passaram'
    exit 0
}
