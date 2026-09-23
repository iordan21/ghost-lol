# Layout da HUD: a altura e as posicoes saem do que ficou ligado na abertura,
# e a HUD recolhe pra barra do topo quando o jogo abre.
# Nao mostra janela nenhuma e nao precisa do cliente.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Invoke-Expression (Get-FonteFuncao @('Set-LinhaBotoes', 'Update-LayoutHud', 'Get-TextoFase',
    'Update-Titulo', 'Set-TamanhoPilula', 'Get-PosicaoPilula', 'Set-Compacta', 'Update-Fase'))

$script:LargCheia = 238; $script:HudX = 12; $script:HudLarg = 214
$script:HudVao = 6; $script:HudAlt = 28
function Test-PosicaoVisivel { param($p) $true }
function Get-PosicaoPadrao   { New-Object System.Drawing.Point(0, 0) }

$C = @{
    Texto    = [System.Drawing.Color]::FromArgb(228, 232, 240)
    Verde    = [System.Drawing.Color]::FromArgb(42, 157, 90)
    Azul     = [System.Drawing.Color]::FromArgb(58, 118, 204)
    Ambar    = [System.Drawing.Color]::FromArgb(186, 132, 34)
    Vermelho = [System.Drawing.Color]::FromArgb(198, 62, 62)
}
$script:Session       = [pscustomobject]@{ Port = 1 }
$script:Availability  = 'offline'
$script:OfflineFixado = $true
$script:AutoAceitar   = $true
$script:Fase          = 'Lobby'
$script:MsLento       = 2800
$script:Nick          = 'Invocador#0000'
$script:AvisoAtalho   = ''
$script:FasesSemFila  = @('None', 'ChampSelect', 'GameStart', 'InProgress',
                          'WaitingForStats', 'PreEndOfGame', 'EndOfGame', 'Reconnect')
$script:FasesDeJogo   = @('GameStart', 'InProgress')
$script:Compacta = $false; $script:RecolheuNoJogo = $false; $script:EmJogo = $false
$script:PosCheia = $null;  $script:PosPilula = $null; $script:FormIni = $null
$script:Dica = New-Object System.Windows.Forms.ToolTip

$form = New-Object System.Windows.Forms.Form
# Os controles ficam FORA do form de proposito. Visible num filho devolve a
# visibilidade efetiva, e num form que nunca foi mostrado isso e sempre False,
# mesmo depois de Visible = $true. Soltos, a propriedade vale o que foi escrito.
$script:Todos = @()
function Ctl { param($Tipo)
    $novo = New-Object "System.Windows.Forms.$Tipo"
    $script:Todos += $novo
    $novo
}
$btnAuto = Ctl Button; $btnPick = Ctl Button; $btnBan = Ctl Button
$btnRuna = Ctl Button; $btnCampeoes = Ctl Button
$btnOnline = Ctl Button; $btnAusente = Ctl Button; $btnOffline = Ctl Button
$lblAtalhos = Ctl Label; $lblLog = Ctl Label
# A barra do topo nao entra em $script:Todos: ela e a unica coisa que fica.
$header = New-Object System.Windows.Forms.Panel
$titulo = New-Object System.Windows.Forms.Label
$dot    = New-Object System.Windows.Forms.Label
$btnMin = New-Object System.Windows.Forms.Button
$btnFechar = New-Object System.Windows.Forms.Button
$titulo.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Update-LayoutHud posiciona os rotulos mas nao mexe na altura deles - quem
# define isso e a criacao no ghost.ps1. Os mesmos numeros aqui, senao o teste
# mede um Label de 23px que na HUD real tem 14.
$lblAtalhos.Size = New-Object System.Drawing.Size(214, 14)
$lblLog.Size     = New-Object System.Drawing.Size(214, 16)

function Monta { param($Aceitar, $Pick, $Ban, $Runa, $Status)
    $script:Recursos = @{ Aceitar = $Aceitar; Pick = $Pick; Ban = $Ban
                          Runa = $Runa; Status = $Status }
    Update-LayoutHud
}

# Nada visivel pode invadir a linha de log nem sair da janela.
function SemColisao {
    foreach ($ctl in $script:Todos) {
        if (-not $ctl.Visible -or $ctl -eq $lblLog) { continue }
        if (($ctl.Location.Y + $ctl.Height) -gt $lblLog.Location.Y) { return "invade o log: $($ctl.Text)" }
        if (($ctl.Location.Y + $ctl.Height) -gt $form.ClientSize.Height) { return "sai embaixo: $($ctl.Text)" }
        if (($ctl.Location.X + $ctl.Width) -gt $form.ClientSize.Width) { return "sai pela direita: $($ctl.Text)" }
    }
    if (($lblLog.Location.Y + $lblLog.Height) -gt $form.ClientSize.Height) { return 'log sai embaixo' }
    return 'ok'
}

function Visiveis { @($script:Todos | Where-Object { $_.Visible }).Count }

Titulo 'tudo ligado'
Monta $true $true $true $true $true
Checa 'auto-aceitar no topo'           $btnAuto.Location.Y 37
Checa 'auto-aceitar da largura toda'   $btnAuto.Width 214
Checa 'Pick, Ban, Runa e + na mesma linha' "$($btnPick.Location.Y),$($btnBan.Location.Y),$($btnRuna.Location.Y),$($btnCampeoes.Location.Y)" '71,71,71,71'
Checa '+ quadrado'                     "$($btnCampeoes.Width)x$($btnCampeoes.Height)" '28x28'
Checa '+ fecha na direita'             ($btnCampeoes.Location.X + $btnCampeoes.Width) 226
Checa 'Runa para antes do +'           ($btnRuna.Location.X + $btnRuna.Width + 6) $btnCampeoes.Location.X
Checa 'status embaixo'                 $btnOnline.Location.Y 105
Checa 'linha de 3 fecha na direita'    ($btnOffline.Location.X + $btnOffline.Width) 226
Checa 'aviso de atalho escondido'      $lblAtalhos.Visible 'False'
Checa 'altura'                         $form.ClientSize.Height 162
Checa 'barra do topo diz a fase'       $titulo.Text 'no lobby'
Checa 'sem colisao'                    (SemColisao) 'ok'

Titulo 'atalho tomado: a linha aparece, e so ai'
$script:AvisoAtalho = 'Atalho em uso por outro app: Ctrl+Alt+A'
Monta $true $true $true $true $true
Checa 'aviso visivel'                  $lblAtalhos.Visible 'True'
Checa 'aviso logo depois do status'    $lblAtalhos.Location.Y 139
Checa 'janela cresceu so o aviso'      $form.ClientSize.Height 178
Checa 'sem colisao'                    (SemColisao) 'ok'
$script:AvisoAtalho = ''

Titulo 'so status no chat'
Monta $false $false $false $false $true
Checa 'auto-aceitar escondido'   $btnAuto.Visible     'False'
Checa 'Pick escondido'           $btnPick.Visible     'False'
Checa 'Runa escondido'           $btnRuna.Visible     'False'
Checa '+ escondido'              $btnCampeoes.Visible 'False'
Checa 'status subiu pro topo'    $btnOnline.Location.Y 37
Checa 'janela encolheu'          $form.ClientSize.Height 94
Checa 'sem colisao'              (SemColisao) 'ok'

Titulo 'aceitar + status'
Monta $true $false $false $false $true
Checa 'status logo abaixo'   $btnOnline.Location.Y 71
Checa 'altura'               $form.ClientSize.Height 128
Checa 'sem colisao'          (SemColisao) 'ok'

Titulo 'so runa: um botao ocupa a linha, e o + nao aparece'
Monta $false $false $false $true $false
Checa 'Runa sozinho ocupa tudo'    $btnRuna.Width 214
Checa '+ some sem pick/ban'        $btnCampeoes.Visible 'False'
Checa 'sem colisao'                (SemColisao) 'ok'

Titulo 'pick sem ban: linha de dois, mais o +'
Monta $false $true $false $true $false
Checa 'larguras iguais'         "$($btnPick.Width),$($btnRuna.Width)" '87,87'
Checa 'Runa para antes do +'    ($btnRuna.Location.X + $btnRuna.Width + 6) $btnCampeoes.Location.X
Checa '+ volta com o pick'      $btnCampeoes.Visible 'True'
Checa 'sem colisao'             (SemColisao) 'ok'

Titulo 'tudo desligado: sobra a linha de log'
Monta $false $false $false $false $false
Checa 'nenhum botao'    (Visiveis) 1
Checa 'altura minima'   $form.ClientSize.Height 60
Checa 'sem colisao'     (SemColisao) 'ok'

# ---------------------------------------------------------------------------
Titulo 'recolhida: so a barra, com o status'
Monta $true $true $true $true $true
$form.Location = New-Object System.Drawing.Point(100, 100)
Set-Compacta $true
Checa 'nada do corpo visivel'   (Visiveis) 0
Checa 'sem _ e sem X'           "$($btnMin.Visible),$($btnFechar.Visible)" 'False,False'
Checa 'altura da barra'         $form.ClientSize.Height 30
Checa 'estreita'                ($form.ClientSize.Width -lt 130) 'True'
Checa 'barra na largura toda'   $header.Width ($form.ClientSize.Width - 2)
Checa 'mostra o status'         $titulo.Text ('Offline ' + [char]0x2713)
Checa 'cor clareada'            ($titulo.ForeColor.B -gt $C.Azul.B) 'True'
$script:Availability = 'chat'; Update-Titulo
Checa 'acompanha o status'      $titulo.Text 'Online'
$script:Recursos.Status = $false; $script:Fase = 'InProgress'; Update-Titulo
Checa 'sem status: a fase'      $titulo.Text 'em partida'
$script:Recursos.Status = $true; $script:Availability = 'offline'; $script:Fase = 'Lobby'
$script:Session = $null; Update-Titulo
Checa 'sem cliente diz isso'    $titulo.Text 'cliente fechado'
$script:Session = [pscustomobject]@{ Port = 1 }
Set-Compacta $false
Checa 'abriu de novo'           $form.ClientSize.Height 162
Checa 'botoes de volta'         (Visiveis) 9
Checa '_ e X de volta'          "$($btnMin.Visible),$($btnFechar.Visible)" 'True,True'
Checa 'barra de volta'          $header.Width 236
Checa 'voltou pro mesmo lugar'  "$($form.Location.X),$($form.Location.Y)" '100,100'
Checa 'barra volta pra fase'    $titulo.Text 'no lobby'

Titulo 'a partida recolhe e devolve sozinha'
$script:Fase = 'Lobby';       Update-Fase
Checa 'lobby: aberta'           $script:Compacta 'False'
$script:Fase = 'ChampSelect'; Update-Fase
Checa 'selecao: aberta'         $script:Compacta 'False'
$script:Fase = 'GameStart';   Update-Fase
Checa 'jogo abrindo: recolhe'   $script:Compacta 'True'
$script:Fase = 'InProgress';  Update-Fase
Checa 'em partida: recolhida'   $script:Compacta 'True'
$script:Fase = 'EndOfGame';   Update-Fase
Checa 'fim: abre sozinha'       $script:Compacta 'False'
Checa '..no lugar de antes'     "$($form.Location.X),$($form.Location.Y)" '100,100'

Titulo 'o clique duplo manda'
Set-Compacta $true                                  # recolheu na mao no lobby
$script:Fase = 'InProgress'; Update-Fase
$script:Fase = 'EndOfGame';  Update-Fase
Checa 'recolhida no lobby fica'  $script:Compacta 'True'
Set-Compacta $false
$script:Fase = 'InProgress'; Update-Fase
Set-Compacta $false                                 # abriu no meio da partida
$script:Fase = 'InProgress'; Update-Fase
Checa 'aberta na partida fica'   $script:Compacta 'False'
Set-Compacta $true                                  # e recolheu de novo, ainda nela
$script:Fase = 'EndOfGame';  Update-Fase
Checa 'recolhida no jogo volta'  $script:Compacta 'False'
$script:Fase = 'InProgress'; Update-Fase
Set-Compacta $false
$script:Fase = 'EndOfGame';  Update-Fase
Checa 'aberta no jogo continua'  $script:Compacta 'False'
$script:Fase = 'Reconnect';  Update-Fase
Checa 'reconexao nao recolhe'   $script:Compacta 'False'
$script:Fase = $null;        Update-Fase
Checa 'cliente caiu: aberta'    $script:Compacta 'False'

Titulo 'posicao da barra'
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($area.Right - 238 - 16), ($area.Top + 200))
Set-Compacta $true
Checa 'na direita, encosta na direita' ($form.Location.X + $form.Width) ($area.Right - 16)
Checa '..na mesma altura'              $form.Location.Y ($area.Top + 200)
Set-Compacta $false
$form.Location = New-Object System.Drawing.Point(($area.Left + 16), ($area.Top + 200))
Set-Compacta $true
Checa 'na esquerda, fica na esquerda'  $form.Location.X ($area.Left + 16)
Set-Compacta $false
$script:PosPilula = New-Object System.Drawing.Point(700, 20)
Set-Compacta $true
Checa 'arrastada uma vez, volta pra la' "$($form.Location.X),$($form.Location.Y)" '700,20'
Set-Compacta $false
Checa 'a HUD aberta nao vai junto'     "$($form.Location.X),$($form.Location.Y)" "$($area.Left + 16),$($area.Top + 200)"

$form.Dispose()
Fim
