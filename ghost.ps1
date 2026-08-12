#Requires -Version 5.1
<#
.SYNOPSIS
    Ghost - HUD flutuante pro League of Legends: liga/desliga o auto-aceitar e
    troca entre Online / Ausente / Offline sem sair do cliente.

.DESCRIPTION
    Tudo pela LCU API, a API REST local do proprio cliente (https://127.0.0.1).
    Nao le memoria do jogo, nao clica na tela.

    Endpoints usados:
      GET  /lol-summoner/v1/current-summoner      quem esta logado
      GET  /lol-matchmaking/v1/ready-check        tem partida encontrada?
      POST /lol-matchmaking/v1/ready-check/accept aceita (o mesmo do botao)
      GET  /lol-chat/v1/me                        status atual do chat
      PUT  /lol-chat/v1/me                        troca o status

    Atalhos globais (funcionam com o LoL em primeiro plano):
      Ctrl+Alt+A   liga/desliga o auto-aceitar
      Ctrl+Alt+O   alterna entre Offline e Online

    Offline fixado:
    entrar em fila, selecao de campeao ou partida faz o cliente trocar o status
    sozinho para ausente. Escolher Offline na HUD fixa a escolha - o Ghost
    devolve para offline sempre que perceber a mudanca, e o botao mostra um
    visto enquanto isso vale. Escolher Online ou Ausente solta a fixacao.

    Por que curl.exe e nao Invoke-RestMethod:
    o LCU exige TLS 1.3 e o .NET Framework (base do PS 5.1) nao fecha esse
    handshake - da "conexao subjacente fechada". curl.exe ja vem no Windows.

    Por que o corpo do PUT vai por arquivo (-d @arquivo):
    passar JSON com aspas na linha de comando de um .exe pelo PowerShell e
    ponte quebrada - o proprio LCU respondeu 400 nos meus primeiros testes por
    corpo mal formado. Com arquivo nao tem quoting nenhum pra dar errado.

    Obs: sem acento no codigo de proposito. PS 5.1 le .ps1 sem BOM como ANSI.

.PARAMETER IntervaloMs
    Frequencia da checagem de ready check. 700ms sobra (o aceite dura ~12s).

.PARAMETER AtrasoSegundos
    Espera N segundos antes de aceitar.

.PARAMETER AutoAceitarLigado
    Comeca com o auto-aceitar ja ligado.

.EXAMPLE
    .\lol-hud.ps1

.EXAMPLE
    .\lol-hud.ps1 -AutoAceitarLigado -AtrasoSegundos 2
#>
[CmdletBinding()]
param(
    [ValidateRange(200, 5000)] [int]    $IntervaloMs       = 700,
    [ValidateRange(0, 10)]     [int]    $AtrasoSegundos    = 0,
                               [switch] $AutoAceitarLigado
)

# ===========================================================================
# 0. Pre-requisitos, tipos nativos, esconder o console
# ===========================================================================

# Em PS 5.1 "curl" e alias de Invoke-WebRequest. Tem que ser curl.exe mesmo.
$script:Curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $script:Curl) {
    Write-Host 'curl.exe nao encontrado (vem no Windows 10 1803+ / 11).' -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Esconde a janela preta do PowerShell: a HUD e a interface, o console so
# ocuparia espaco na barra de tarefas.
if (-not ([System.Management.Automation.PSTypeName]'Win32Console').Type) {
    Add-Type -Namespace '' -Name 'Win32Console' -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
}
$hConsole = [Win32Console]::GetConsoleWindow()
if ($hConsole -ne [System.IntPtr]::Zero) { [void][Win32Console]::ShowWindow($hConsole, 0) }  # SW_HIDE

# Atalho global = RegisterHotKey do Windows. O sistema manda WM_HOTKEY pra
# janela registrada, entao funciona mesmo com o LoL em primeiro plano.
# O PowerShell nao consegue sobrescrever o WndProc de um Form, entao uso um
# IMessageFilter em C#: ele ve as mensagens da fila antes do form tratar.
if (-not ([System.Management.Automation.PSTypeName]'HotkeyFilter').Type) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms' -TypeDefinition @'
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class HotkeyFilter : IMessageFilter
{
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int WM_HOTKEY = 0x0312;

    public event Action<int> Pressed;

    public bool PreFilterMessage(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            Action<int> h = Pressed;
            if (h != null) h(m.WParam.ToInt32());
            return true;
        }
        return false;
    }
}
'@
}

# MOD_ALT 0x1 | MOD_CONTROL 0x2 | MOD_NOREPEAT 0x4000 (nao repete se segurar)
$script:ModCtrlAlt = 0x0001 -bor 0x0002 -bor 0x4000
$script:VK_A       = 0x41
$script:VK_O       = 0x4F
$script:HK_AUTO    = 1
$script:HK_OFFLINE = 2

# ===========================================================================
# 1. Camada LCU
# ===========================================================================

function Get-LockfilePath {
    # Descobre a pasta pelo processo do cliente, nao por caminho fixo: assim
    # funciona com o jogo instalado em qualquer disco.
    $proc = Get-CimInstance Win32_Process -Filter "Name = 'LeagueClientUx.exe'" `
                -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        if ($proc.CommandLine -match '--install-directory=([^"]+)') {
            $lf = Join-Path ($Matches[1].TrimEnd('\', ' ')) 'lockfile'
            if (Test-Path -LiteralPath $lf) { return $lf }
        }
        if ($proc.ExecutablePath) {
            $lf = Join-Path (Split-Path $proc.ExecutablePath -Parent) 'lockfile'
            if (Test-Path -LiteralPath $lf) { return $lf }
        }
    }
    foreach ($p in @(
        'C:\Riot Games\League of Legends\lockfile',
        'D:\Riot Games\League of Legends\lockfile',
        "${env:ProgramFiles}\Riot Games\League of Legends\lockfile",
        "${env:ProgramFiles(x86)}\Riot Games\League of Legends\lockfile"
    )) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

function Get-LcuSession {
    $path = Get-LockfilePath
    if (-not $path) { return $null }

    # O cliente mantem o lockfile aberto; sem FileShare::ReadWrite da
    # "arquivo em uso por outro processo".
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open,
                  [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs)
            try { $raw = $sr.ReadToEnd() } finally { $sr.Dispose() }
        } finally { $fs.Dispose() }
    } catch { return $null }

    $parts = $raw.Trim() -split ':'
    if ($parts.Count -lt 4) { return $null }

    # Formato: LeagueClient:PID:PORTA:SENHA:https - senha nova a cada abertura.
    return [pscustomobject]@{ Port = $parts[2]; Password = $parts[3] }
}

function Invoke-Lcu {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)][string] $Path,
        [ValidateSet('GET', 'POST', 'PUT')][string] $Method = 'GET',
        [string] $JsonBody,
        [int]    $TimeoutSec = 3          # curto: a chamada roda na thread da UI
    )

    $a = @('-s', '-k', '--max-time', "$TimeoutSec",
           '-u', "riot:$($Session.Password)",
           '-w', '\n%{http_code}')        # ultima linha da saida = codigo HTTP

    $tmp = $null
    if ($Method -ne 'GET') {
        $a += @('-X', $Method, '-H', 'Content-Type: application/json')
        if ($JsonBody) {
            $tmp = Join-Path $env:TEMP ("lcu-" + [guid]::NewGuid().ToString('N') + ".json")
            [System.IO.File]::WriteAllText($tmp, $JsonBody, [System.Text.Encoding]::ASCII)
            $a += @('-d', "@$tmp")
        }
        else { $a += @('-d', '{}') }
    }
    $a += "https://127.0.0.1:$($Session.Port)$Path"

    try   { $lines = @(& $script:Curl @a) }
    catch { $lines = @() }
    finally { if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }

    if ($lines.Count -eq 0) { return [pscustomobject]@{ Status = 0; Body = $null } }

    $st = 0
    [void][int]::TryParse(($lines[-1] -as [string]).Trim(), [ref]$st)
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)] -join '') } else { '' }
    return [pscustomobject]@{ Status = $st; Body = $body }
}

function ConvertFrom-LcuBody {
    param($Resposta)
    if ($Resposta.Status -lt 200 -or $Resposta.Status -ge 300) { return $null }
    try { return ($Resposta.Body | ConvertFrom-Json) } catch { return $null }
}

# ===========================================================================
# 2. Estado
# ===========================================================================
$script:Session      = $null
$script:AutoAceitar  = [bool]$AutoAceitarLigado
$script:Availability = $null
$script:Tick         = 0
# Offline "fixado": entrar em selecao de campeao ou em partida faz o cliente
# trocar o status sozinho para ausente. Enquanto isso estiver ligado, o Ghost
# devolve para offline toda vez que perceber a mudanca.
$script:OfflineFixado = $false
$script:AvisouReforco = $false   # evita repetir a mesma linha de log
$script:Ocupado      = $false   # trava reentrancia: um tick nao entra no outro

# ===========================================================================
# 3. Interface
# ===========================================================================
$C = @{
    Fundo    = [System.Drawing.Color]::FromArgb(18, 20, 26)
    Painel   = [System.Drawing.Color]::FromArgb(30, 33, 43)
    Borda    = [System.Drawing.Color]::FromArgb(48, 53, 66)
    Texto    = [System.Drawing.Color]::FromArgb(228, 232, 240)
    Fraco    = [System.Drawing.Color]::FromArgb(124, 132, 150)
    Verde    = [System.Drawing.Color]::FromArgb(42, 157, 90)
    Azul     = [System.Drawing.Color]::FromArgb(58, 118, 204)
    Ambar    = [System.Drawing.Color]::FromArgb(186, 132, 34)
    Cinza    = [System.Drawing.Color]::FromArgb(88, 94, 110)
    Vermelho = [System.Drawing.Color]::FromArgb(198, 62, 62)
}
$FonteTitulo = New-Object System.Drawing.Font('Segoe UI', 9,   [System.Drawing.FontStyle]::Bold)
$FonteBotao  = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
$FonteMini   = New-Object System.Drawing.Font('Segoe UI', 7.5)

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'Ghost'      # nome na barra de tarefas e no Alt+Tab
$form.FormBorderStyle = 'None'
$form.StartPosition   = 'Manual'
$form.TopMost         = $true           # fica sobre o cliente do LoL
$form.ClientSize      = New-Object System.Drawing.Size(238, 178)
$form.BackColor       = $C.Fundo
$form.ShowInTaskbar   = $true

# Icone proprio (metade preto e branco, metade colorida) na barra de tarefas
# e no Alt+Tab. Busco ao lado do script em vez de caminho fixo, pra sobreviver
# se a pasta mudar de lugar. Sem o icone o app ainda roda, so fica com o
# icone generico do PowerShell.
$iconePath = Join-Path $PSScriptRoot 'ghost.ico'
if (Test-Path -LiteralPath $iconePath) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconePath) } catch { }
}

# Canto inferior direito da area de trabalho, com folga pra barra de tarefas.
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(
    ($area.Right - $form.Width - 16), ($area.Bottom - $form.Height - 16))

# Sem FormBorderStyle nao existe borda: desenho uma de 1px pra separar do fundo.
$form.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($C.Borda)
    try { $e.Graphics.DrawRectangle($pen, 0, 0, $form.ClientSize.Width - 1, $form.ClientSize.Height - 1) }
    finally { $pen.Dispose() }
})

function New-Botao {
    param([string]$Texto, [int]$X, [int]$Y, [int]$W, [int]$H, $Cor)
    $b                           = New-Object System.Windows.Forms.Button
    $b.Text                      = $Texto
    $b.Location                  = New-Object System.Drawing.Point($X, $Y)
    $b.Size                      = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle                 = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor                 = $Cor
    $b.ForeColor                 = $C.Texto
    $b.Font                      = $FonteBotao
    $b.TabStop                   = $false
    $b.Cursor                    = [System.Windows.Forms.Cursors]::Hand
    return $b
}

# --- barra de titulo (area de arrastar) ---
$header           = New-Object System.Windows.Forms.Panel
$header.Location  = New-Object System.Drawing.Point(1, 1)
$header.Size      = New-Object System.Drawing.Size(236, 28)
$header.BackColor = $C.Painel
$form.Controls.Add($header)

$dot           = New-Object System.Windows.Forms.Label
$dot.Text      = [char]0x25CF          # bolinha: verde conectado, vermelho nao
$dot.ForeColor = $C.Vermelho
$dot.Font      = New-Object System.Drawing.Font('Segoe UI', 11)
$dot.Location  = New-Object System.Drawing.Point(8, 4)
$dot.AutoSize  = $true
$header.Controls.Add($dot)

$titulo           = New-Object System.Windows.Forms.Label
$titulo.Text      = 'conectando...'
$titulo.ForeColor = $C.Texto
$titulo.Font      = $FonteTitulo
$titulo.Location  = New-Object System.Drawing.Point(28, 7)
$titulo.Size      = New-Object System.Drawing.Size(168, 16)
$header.Controls.Add($titulo)

$btnFechar = New-Botao -Texto 'X' -X 206 -Y 3 -W 24 -H 22 -Cor $C.Painel
$btnFechar.Font      = $FonteMini
$btnFechar.ForeColor = $C.Fraco
$btnFechar.Add_MouseEnter({ $btnFechar.BackColor = $C.Vermelho; $btnFechar.ForeColor = $C.Texto })
$btnFechar.Add_MouseLeave({ $btnFechar.BackColor = $C.Painel;   $btnFechar.ForeColor = $C.Fraco })
$btnFechar.Add_Click({ $form.Close() })
$header.Controls.Add($btnFechar)

# Arrastar pelo cabecalho: guardo onde o mouse pegou e movo por diferenca.
$script:Arrastando = $false
$script:MouseIni   = $null
$script:FormIni    = $null
$iniciarArraste = {
    $script:Arrastando = $true
    $script:MouseIni   = [System.Windows.Forms.Cursor]::Position
    $script:FormIni    = $form.Location
}
$moverArraste = {
    if ($script:Arrastando) {
        $cur = [System.Windows.Forms.Cursor]::Position
        $form.Location = New-Object System.Drawing.Point(
            ($script:FormIni.X + $cur.X - $script:MouseIni.X),
            ($script:FormIni.Y + $cur.Y - $script:MouseIni.Y))
    }
}
$soltarArraste = { $script:Arrastando = $false }
foreach ($ctl in @($header, $titulo, $dot)) {
    $ctl.Add_MouseDown($iniciarArraste)
    $ctl.Add_MouseMove($moverArraste)
    $ctl.Add_MouseUp($soltarArraste)
}

# --- auto-aceitar ---
$btnAuto = New-Botao -Texto 'AUTO-ACEITAR: OFF' -X 12 -Y 40 -W 214 -H 32 -Cor $C.Cinza
$form.Controls.Add($btnAuto)

# --- status do chat ---
$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'STATUS NO CHAT'
$lblStatus.ForeColor = $C.Fraco
$lblStatus.Font      = $FonteMini
$lblStatus.Location  = New-Object System.Drawing.Point(13, 80)
$lblStatus.AutoSize  = $true
$form.Controls.Add($lblStatus)

$btnOnline  = New-Botao -Texto 'Online'  -X 12  -Y 98 -W 68 -H 28 -Cor $C.Painel
$btnAusente = New-Botao -Texto 'Ausente' -X 85  -Y 98 -W 68 -H 28 -Cor $C.Painel
$btnOffline = New-Botao -Texto 'Offline' -X 158 -Y 98 -W 68 -H 28 -Cor $C.Painel
$form.Controls.AddRange(@($btnOnline, $btnAusente, $btnOffline))

# --- lembrete dos atalhos ---
$lblAtalhos           = New-Object System.Windows.Forms.Label
$lblAtalhos.Text      = 'Ctrl+Alt+A aceite   |   Ctrl+Alt+O offline'
$lblAtalhos.ForeColor = $C.Fraco
$lblAtalhos.Font      = $FonteMini
$lblAtalhos.Location  = New-Object System.Drawing.Point(13, 136)
$lblAtalhos.Size      = New-Object System.Drawing.Size(214, 14)
$form.Controls.Add($lblAtalhos)

# --- linha de log ---
$lblLog           = New-Object System.Windows.Forms.Label
$lblLog.Text      = ''
$lblLog.ForeColor = $C.Fraco
$lblLog.Font      = $FonteMini
$lblLog.Location  = New-Object System.Drawing.Point(13, 154)
$lblLog.Size      = New-Object System.Drawing.Size(214, 16)
$form.Controls.Add($lblLog)

function Write-Log {
    param([string]$Texto, $Cor = $null)
    $lblLog.Text      = ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Texto)
    $lblLog.ForeColor = if ($Cor) { $Cor } else { $C.Fraco }
}

function Update-BotaoAuto {
    if ($script:AutoAceitar) {
        $btnAuto.Text      = 'AUTO-ACEITAR: ON'
        $btnAuto.BackColor = $C.Verde
    }
    else {
        $btnAuto.Text      = 'AUTO-ACEITAR: OFF'
        $btnAuto.BackColor = $C.Cinza
    }
    $btnAuto.ForeColor = $C.Texto
}

# Pinta o botao do status que esta ativo de verdade no cliente - inclusive se
# voce mudou pela interface do LoL, nao pela HUD.
function Update-BotoesStatus {
    foreach ($b in @($btnOnline, $btnAusente, $btnOffline)) {
        $b.BackColor = $C.Painel
        $b.ForeColor = $C.Fraco
    }
    # O visto avisa que o offline esta fixado. Sem essa marca o comportamento
    # viraria mistério: a pessoa muda o status no cliente e ele "volta sozinho".
    # O caractere vai por codigo porque este arquivo e ASCII de proposito.
    $btnOffline.Text = if ($script:OfflineFixado) { 'Offline ' + [char]0x2713 } else { 'Offline' }
    switch ($script:Availability) {
        'chat'    { $btnOnline.BackColor  = $C.Verde;    $btnOnline.ForeColor  = $C.Texto }
        'away'    { $btnAusente.BackColor = $C.Ambar;    $btnAusente.ForeColor = $C.Texto }
        'offline' { $btnOffline.BackColor = $C.Azul;     $btnOffline.ForeColor = $C.Texto }
        'dnd'     { $btnAusente.BackColor = $C.Vermelho; $btnAusente.ForeColor = $C.Texto }
    }
}

# ===========================================================================
# 4. Acoes
#    Cada acao e uma funcao, e tanto o clique quanto o atalho global chamam a
#    mesma funcao. Sem logica duplicada em dois lugares.
# ===========================================================================

function Set-Availability {
    param(
        [Parameter(Mandatory)][ValidateSet('chat', 'away', 'offline')][string] $Valor,
        # Chamada automatica de reforco, nao escolha da pessoa: nao mexe no
        # "fixado" e nao escreve no log a cada vez.
        [switch] $Interno
    )

    if (-not $script:Session) { Write-Log 'Cliente do LoL nao esta aberto.' $C.Vermelho; return }

    # Escolher qualquer status pela HUD e o que liga e desliga o fixado.
    # Assim a regra e simples de prever: fixa em Offline, solta em Online
    # ou Ausente.
    if (-not $Interno) {
        $script:OfflineFixado = ($Valor -eq 'offline')
        $script:AvisouReforco = $false
    }

    $r = Invoke-Lcu -Session $script:Session -Path '/lol-chat/v1/me' -Method PUT `
                    -JsonBody ('{"availability":"' + $Valor + '"}')

    if ($r.Status -ge 200 -and $r.Status -lt 300) {
        $script:Availability = $Valor
        Update-BotoesStatus
        if (-not $Interno) {
            $nome = switch ($Valor) { 'chat' { 'Online' } 'away' { 'Ausente' } 'offline' { 'Offline' } }
            if ($Valor -eq 'offline') { Write-Log 'Offline fixado.' $C.Azul }
            else                      { Write-Log ("Status: {0}." -f $nome) $C.Texto }
        }
    }
    else {
        Write-Log ("Falhou ao trocar status (HTTP {0})." -f $r.Status) $C.Vermelho
    }
}

function Switch-AutoAceitar {
    $script:AutoAceitar = -not $script:AutoAceitar
    Update-BotaoAuto
    if ($script:AutoAceitar) { Write-Log 'Auto-aceitar ligado.' $C.Verde }
    else                     { Write-Log 'Auto-aceitar desligado.' }
}

# Ctrl+Alt+O e um vai-e-volta: se estou offline, volto pra online; senao,
# vou pra offline. Qualquer outro estado (ausente/dnd) conta como "nao offline".
function Switch-Offline {
    if ($script:Availability -eq 'offline') { Set-Availability -Valor 'chat' }
    else                                    { Set-Availability -Valor 'offline' }
}

$btnAuto.Add_Click({    Switch-AutoAceitar })
$btnOnline.Add_Click({  Set-Availability -Valor 'chat' })
$btnAusente.Add_Click({ Set-Availability -Valor 'away' })
$btnOffline.Add_Click({ Set-Availability -Valor 'offline' })

# --- atalhos globais ---
$script:Hotkeys = New-Object HotkeyFilter
$script:Hotkeys.add_Pressed({
    param($id)
    # Esse scriptblock roda vindo da fila de mensagens do Windows. Se ele
    # estourar excecao pra fora, o comportamento fica imprevisivel - por isso
    # o try/catch engole e reporta no log.
    try {
        switch ($id) {
            1 { Switch-AutoAceitar }
            2 { Switch-Offline }
        }
    }
    catch { Write-Log ("Erro no atalho: {0}" -f $_.Exception.Message) $C.Vermelho }
})
[System.Windows.Forms.Application]::AddMessageFilter($script:Hotkeys)

# ===========================================================================
# 5. Loop (timer da UI)
# ===========================================================================

function Connect-Cliente {
    $s = Get-LcuSession
    if (-not $s) { return $false }

    $me = ConvertFrom-LcuBody (Invoke-Lcu -Session $s -Path '/lol-summoner/v1/current-summoner')
    if (-not $me) { return $false }   # processo no ar mas API ainda subindo

    $script:Session = $s
    $titulo.Text    = if ($me.tagLine) { "$($me.gameName)#$($me.tagLine)" } else { "$($me.gameName)" }
    $dot.ForeColor  = $C.Verde
    return $true
}

function Disconnect-Cliente {
    $script:Session      = $null
    $script:Availability = $null
    $titulo.Text         = 'cliente fechado'
    $dot.ForeColor       = $C.Vermelho
    Update-BotoesStatus
}

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = $IntervaloMs
$timer.Add_Tick({
    # As chamadas rodam na thread da UI. Sao localhost (~27ms medidos: 13ms de
    # requisicao mais o custo de subir o processo do curl), mas se o
    # cliente morrer no meio o --max-time 3 seguraria a janela por 3s - por
    # isso a trava: nunca dois ticks ao mesmo tempo.
    if ($script:Ocupado) { return }
    $script:Ocupado = $true
    try {
        $script:Tick++
        $cada3s = [math]::Max(1, [int](3000 / $IntervaloMs))

        if (-not $script:Session) {
            # Reconectar e caro (consulta WMI): so tenta a cada ~3s.
            if (($script:Tick % $cada3s) -ne 0) { return }
            if (Connect-Cliente) { Write-Log 'Conectado ao cliente.' $C.Verde }
            return
        }

        # Ready check: so consulta se o auto-aceitar estiver ligado.
        if ($script:AutoAceitar) {
            $rc = Invoke-Lcu -Session $script:Session -Path '/lol-matchmaking/v1/ready-check'

            if ($rc.Status -eq 0) { Disconnect-Cliente; Write-Log 'Perdi o cliente.' $C.Vermelho; return }

            if ($rc.Status -eq 200) {
                $j = ConvertFrom-LcuBody $rc
                # playerResponse = 'None' evita repetir POST depois de aceitar.
                if ($j -and $j.state -eq 'InProgress' -and $j.playerResponse -eq 'None') {
                    Write-Log 'PARTIDA ENCONTRADA!' $C.Verde
                    $lblLog.Refresh()
                    if ($AtrasoSegundos -gt 0) { Start-Sleep -Seconds $AtrasoSegundos }

                    $ok = Invoke-Lcu -Session $script:Session `
                              -Path '/lol-matchmaking/v1/ready-check/accept' -Method POST
                    if ($ok.Status -ge 200 -and $ok.Status -lt 300) {
                        Write-Log 'Aceito.' $C.Verde
                    }
                    else {
                        Write-Log 'FALHOU - ACEITE NA MAO!' $C.Vermelho
                    }
                }
            }
            # 404 aqui e normal: "Not attached to a matchmaking queue".
        }

        # Status do chat a cada ~3s, pra refletir mudanca feita no proprio LoL.
        if (($script:Tick % $cada3s) -eq 0) {
            $chat = Invoke-Lcu -Session $script:Session -Path '/lol-chat/v1/me'
            if ($chat.Status -eq 0) { Disconnect-Cliente; return }
            $j = ConvertFrom-LcuBody $chat
            if ($j) {
                if ($j.availability -eq 'offline') { $script:AvisouReforco = $false }

                if ($script:OfflineFixado -and $j.availability -ne 'offline') {
                    # Foi o cliente que mudou (entrou em fila, selecao de
                    # campeao ou partida). Devolve pro offline.
                    if (-not $script:AvisouReforco) {
                        Write-Log 'O cliente saiu do offline. Devolvendo.' $C.Azul
                        $script:AvisouReforco = $true
                    }
                    Set-Availability -Valor 'offline' -Interno
                }
                elseif ($j.availability -ne $script:Availability) {
                    $script:Availability = $j.availability
                    Update-BotoesStatus
                }
            }
        }
    }
    catch {
        # Um erro solto nao pode matar o timer, senao a HUD vira enfeite.
        Write-Log ("Erro: {0}" -f $_.Exception.Message) $C.Vermelho
    }
    finally { $script:Ocupado = $false }
})

$form.Add_Shown({
    Update-BotaoAuto
    Update-BotoesStatus

    # Registrar aqui, e nao antes: RegisterHotKey precisa da janela ja criada.
    $okA = [HotkeyFilter]::RegisterHotKey($form.Handle, $script:HK_AUTO,    $script:ModCtrlAlt, $script:VK_A)
    $okO = [HotkeyFilter]::RegisterHotKey($form.Handle, $script:HK_OFFLINE, $script:ModCtrlAlt, $script:VK_O)

    # Se outro programa ja usa a combinacao, RegisterHotKey so devolve false.
    # Melhor dizer isso na cara do que o atalho "nao funcionar" em silencio.
    if (-not $okA -or -not $okO) {
        $ocupados = @()
        if (-not $okA) { $ocupados += 'Ctrl+Alt+A' }
        if (-not $okO) { $ocupados += 'Ctrl+Alt+O' }
        $lblAtalhos.Text      = ("Atalho em uso por outro app: {0}" -f ($ocupados -join ', '))
        $lblAtalhos.ForeColor = $C.Ambar
    }

    if (Connect-Cliente) {
        $chat = ConvertFrom-LcuBody (Invoke-Lcu -Session $script:Session -Path '/lol-chat/v1/me')
        if ($chat) { $script:Availability = $chat.availability; Update-BotoesStatus }
        Write-Log 'Pronto.' $C.Verde
    }
    else {
        Disconnect-Cliente
        Write-Log 'Esperando o cliente do LoL abrir...' $C.Ambar
    }

    $timer.Start()
})

# FormClosing e nao FormClosed: aqui o Handle ainda existe pra desregistrar.
$form.Add_FormClosing({
    [void][HotkeyFilter]::UnregisterHotKey($form.Handle, $script:HK_AUTO)
    [void][HotkeyFilter]::UnregisterHotKey($form.Handle, $script:HK_OFFLINE)
    [System.Windows.Forms.Application]::RemoveMessageFilter($script:Hotkeys)
    $timer.Stop()
})

$form.Add_FormClosed({
    $timer.Dispose()
    # Devolve o console pra quem rodou de um terminal aberto.
    if ($hConsole -ne [System.IntPtr]::Zero) { [void][Win32Console]::ShowWindow($hConsole, 5) }
})

[void]$form.ShowDialog()
