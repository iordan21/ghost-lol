# Layout da HUD: a altura e as posicoes saem do que ficou ligado na abertura.
# Nao mostra janela nenhuma e nao precisa do cliente.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Invoke-Expression (Get-FonteFuncao @('Set-LinhaBotoes', 'Update-LayoutHud'))

$script:HudX = 12; $script:HudLarg = 214; $script:HudVao = 5
function Test-PosicaoVisivel { param($p) $true }
function Get-PosicaoPadrao   { New-Object System.Drawing.Point(0, 0) }

$form = New-Object System.Windows.Forms.Form
# Os controles ficam FORA do form de proposito. Visible num filho devolve a
# visibilidade efetiva, e num form que nunca foi mostrado isso e sempre False,
# mesmo depois de Visible = $true. Soltos, a propriedade vale o que foi escrito.
$script:Todos = @()
function Ctl { param($Tipo)
    $c = New-Object "System.Windows.Forms.$Tipo"
    $script:Todos += $c
    $c
}
$btnAuto = Ctl Button; $btnPick = Ctl Button; $btnBan = Ctl Button
$btnRuna = Ctl Button; $btnCampeoes = Ctl Button
$btnOnline = Ctl Button; $btnAusente = Ctl Button; $btnOffline = Ctl Button
$lblSelecao = Ctl Label; $lblStatus = Ctl Label; $lblAtalhos = Ctl Label; $lblLog = Ctl Label

# Update-LayoutHud posiciona os rotulos mas nao mexe na altura deles - quem
# define isso e a criacao no ghost.ps1. Os mesmos numeros aqui, senao o teste
# mede um Label de 23px que na HUD real tem 14.
$lblAtalhos.Size = New-Object System.Drawing.Size(214, 14)
$lblLog.Size     = New-Object System.Drawing.Size(214, 16)
$lblSelecao.Size = New-Object System.Drawing.Size(214, 15)
$lblStatus.Size  = New-Object System.Drawing.Size(214, 15)

function Monta { param($Aceitar, $Pick, $Ban, $Runa, $Status)
    $script:Recursos = @{ Aceitar = $Aceitar; Pick = $Pick; Ban = $Ban
                          Runa = $Runa; Status = $Status }
    Update-LayoutHud
}

# Nada visivel pode invadir a linha de log nem sair da janela.
function SemColisao {
    foreach ($c in $script:Todos) {
        if (-not $c.Visible -or $c -eq $lblLog) { continue }
        if (($c.Location.Y + $c.Height) -gt $lblLog.Location.Y) { return "invade o log: $($c.Text)" }
        if (($c.Location.Y + $c.Height) -gt $form.ClientSize.Height) { return "sai embaixo: $($c.Text)" }
        # O limite e a largura da janela, nao os 226 dos botoes: os rotulos ja
        # iam ate 227 no layout original e continuam indo.
        if (($c.Location.X + $c.Width) -gt $form.ClientSize.Width) { return "sai pela direita: $($c.Text)" }
    }
    return 'ok'
}

Titulo 'tudo ligado'
Monta $true $true $true $true $true
Checa 'auto-aceitar visivel'          $btnAuto.Visible 'True'
Checa 'Pick, Ban e Runa na mesma linha' "$($btnPick.Location.Y),$($btnBan.Location.Y),$($btnRuna.Location.Y)" '112,112,112'
Checa 'Campeoes na linha de baixo'    $btnCampeoes.Location.Y 146
Checa 'Campeoes ocupa a largura'      $btnCampeoes.Width 214
Checa 'linha de 3 fecha na direita'   ($btnRuna.Location.X + $btnRuna.Width) 226
Checa 'sem colisao'                   (SemColisao) 'ok'

Titulo 'so status no chat'
Monta $false $false $false $false $true
Checa 'auto-aceitar escondido'   $btnAuto.Visible     'False'
Checa 'Pick escondido'           $btnPick.Visible     'False'
Checa 'Runa escondido'           $btnRuna.Visible     'False'
Checa 'Campeoes escondido'       $btnCampeoes.Visible 'False'
Checa 'rotulo da selecao sumiu'  $lblSelecao.Visible  'False'
Checa 'status subiu pro topo'    $btnOnline.Location.Y 72
Checa 'atalho so o de offline'   $lblAtalhos.Text 'Ctrl+Alt+O offline'
Checa 'janela encolheu'          $form.ClientSize.Height 152
Checa 'sem colisao'              (SemColisao) 'ok'

Titulo 'aceitar + status'
Monta $true $false $false $false $true
Checa 'os dois atalhos'  $lblAtalhos.Text 'Ctrl+Alt+A aceite   |   Ctrl+Alt+O offline'
Checa 'sem bloco de selecao' $lblSelecao.Visible 'False'
Checa 'sem colisao'      (SemColisao) 'ok'

Titulo 'so runa: um botao ocupa a linha, e a grade nao aparece'
Monta $false $false $false $true $false
Checa 'Runa sozinho ocupa tudo'    $btnRuna.Width 214
Checa 'Campeoes some sem pick/ban' $btnCampeoes.Visible 'False'
Checa 'sem colisao'                (SemColisao) 'ok'

Titulo 'pick sem ban: linha de dois'
Monta $false $true $false $true $false
Checa 'larguras somam a linha'  "$($btnPick.Width),$($btnRuna.Width)" '104,105'
Checa 'fecha na direita'        ($btnRuna.Location.X + $btnRuna.Width) 226
Checa 'grade volta com o pick'  $btnCampeoes.Visible 'True'
Checa 'sem colisao'             (SemColisao) 'ok'

Titulo 'tudo desligado: sobra a linha de log'
Monta $false $false $false $false $false
Checa 'atalhos sumiram' $lblAtalhos.Visible 'False'
Checa 'altura minima'   $form.ClientSize.Height 78
Checa 'sem colisao'     (SemColisao) 'ok'

$form.Dispose()
Fim
