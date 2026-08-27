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
      GET  /lol-gameflow/v1/gameflow-phase        em que ponto o cliente esta
      GET  /lol-lobby/v2/lobby                    as lanes que voce pediu
      GET  /lol-perks/v1/pages                    suas paginas de runa
      PUT  /lol-perks/v1/pages/<id>               grava a runa na pagina
      PUT  /lol-perks/v1/currentpage              seleciona a pagina
      GET  /lol-perks/v1/recommended-pages/...    a runa que a Riot sugere
      GET  /lol-champ-select/v1/session           de quem e a vez, e do que
      PATCH /lol-champ-select/v1/session/actions/<id>  escolher ou banir
      GET  /lol-game-data/assets/v1/champion-summary.json  lista de campeoes
      GET  /lol-game-data/assets/v1/champion-icons/<id>.png  os icones

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

    Auto-pick e auto-ban:
    as filas sao montadas no botao Campeoes, que abre a grade com os icones
    do proprio cliente. Na sua vez o Ghost pega o primeiro da fila que ainda
    estiver livre. Pick passa o mouse primeiro e trava depois de
    -SegundosAteTravar (18 por padrao), pra dar tempo de mudar na mao;
    -SegundosAteTravar 0 vira instalock. Use -Simular na primeira vez: ele
    escreve no log o que faria, sem tocar na selecao.

    Autofill:
    a fila de pick e uma so e nao sabe de lane. Caiu numa lane que voce
    nao pediu, o Ghost para o auto-pick, deixa o botao Pick ambar e diz
    qual lane veio - em vez de travar sozinho um campeao que nao joga ali.
    As lanes pedidas sao lidas no lobby e guardadas, porque no champ
    select o lobby ja nao existe. Sem lane atribuida (cega, ARAM), com
    fill pedido, ou sem conseguir ler a preferencia, ele nao bloqueia
    nada. O ban continua normal: banir nao depende da sua lane.
    -IgnorarAutofill desliga o gate.

    Runas:
    ao travar um campeao - no automatico ou na mao - o Ghost busca no
    op.gg a runa mais jogada daquele campeao naquela lane e grava numa
    pagina sua. Ele so escreve na pagina cujo nome comeca com "Ghost";
    sem ela nao faz nada e avisa. Edita no lugar, nunca apaga e recria.
    A busca roda em processo separado pra nao travar a HUD. op.gg fora
    do ar, campeao sem pagina la, ou modo sem lane: cai na recomendacao
    da propria Riot, que vem do cliente e nao precisa de internet.
    -Runas:$false desliga.

    Tela de abertura:
    o Ghost pergunta antes de subir quais das cinco automacoes voce quer.
    So o que for marcado aparece na HUD, e a altura da janela sai do que
    ficou ligado - quem usa so o status nao ve faixa de auto-pick apagada.
    A escolha fica salva. Clique direito na barra do topo reabre a tela.
    -Direto pula a pergunta e usa o que estava salvo.

    Desmarcar ali nao esconde e sim desliga: recurso invisivel que
    continuasse agindo por tras seria pior que os dois outros estados.

    Ritmo da checagem:
    a fase do gameflow diz quando ready check e impossivel - selecao de
    campeao, partida em andamento, tela de fim. Nessas o Ghost cai de
    -IntervaloMs para um tick a cada ~3s - o valor exato aparece na HUD,
    porque a conta arredonda em ticks inteiros e com 700ms da 2,8s. Isso
    ainda pega qualquer surpresa. Dentro do jogo,
    que e onde CPU importa, isso corta a maioria dos processos de curl.

    Preferencias:
    posicao da janela, estado dos tres automaticos e as filas de campeao
    ficam em
    %APPDATA%\Ghost\ghost.json. Apagar o arquivo volta tudo ao padrao.

    Obs: sem acento no codigo de proposito. PS 5.1 le .ps1 sem BOM como ANSI.

.PARAMETER IntervaloMs
    Frequencia da checagem de ready check. 700ms sobra (o aceite dura ~12s).

.PARAMETER AtrasoSegundos
    Espera N segundos antes de aceitar. A contagem aparece na HUD e nao trava
    a interface - da pra desligar o auto-aceitar no meio dela e cancelar.

.PARAMETER AutoAceitarLigado
    Comeca com o auto-aceitar ja ligado.

.PARAMETER Direto
    Pula a tela de abertura e sobe a HUD com os recursos salvos da ultima
    vez. Util no atalho de quem ja escolheu e nao quer a pergunta.

.PARAMETER Runas
    Grava a runa do campeao travado na sua pagina "Ghost". Ligado por
    padrao - sem uma pagina com esse nome ele nao faz nada de qualquer
    jeito. -Runas:$false desliga de vez.

.PARAMETER IgnorarAutofill
    Desliga o gate de autofill: o auto-pick volta a escolher em qualquer
    lane, inclusive numa que voce nao pediu.

.EXAMPLE
    .\ghost.ps1

.EXAMPLE
    .\ghost.ps1 -AutoAceitarLigado -AtrasoSegundos 2
#>
[CmdletBinding()]
param(
    [ValidateRange(200, 5000)] [int]    $IntervaloMs       = 700,
    [ValidateRange(0, 10)]     [int]    $AtrasoSegundos    = 0,
    [ValidateRange(0, 25)]     [int]    $SegundosAteTravar = 18,
                               [switch] $AutoAceitarLigado,
                               [switch] $Simular,
                               [switch] $IgnorarAutofill,
                               [bool]   $Runas = $true,
                               [switch] $Direto
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

# Uma instancia so. Duas HUDs abertas brigam: o Windows entrega o atalho
# global pra quem registrou primeiro, entao a segunda acusaria "atalho em uso
# por outro app" - apontando pra si mesma - e as duas ficariam mandando PUT de
# status uma por cima da outra.
$script:PrimeiraInstancia = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\GhostLolHud', [ref]$script:PrimeiraInstancia)
if (-not $script:PrimeiraInstancia) {
    [void][System.Windows.Forms.MessageBox]::Show(
        'O Ghost ja esta aberto. Procure a HUD na tela ou no Alt+Tab.', 'Ghost',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
    exit 0
}

# Esconde a janela preta do PowerShell: a HUD e a interface, o console so
# ocuparia espaco na barra de tarefas.
if (-not ([System.Management.Automation.PSTypeName]'Win32Console').Type) {
    Add-Type -Namespace '' -Name 'Win32Console' -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]   public static extern bool IsWindowVisible(System.IntPtr hWnd);
'@
}
$hConsole = [Win32Console]::GetConsoleWindow()
# Guardo se o console estava visivel antes de esconder. Quem chamou com
# -WindowStyle Hidden (o ghost.bat faz isso) nao tem console nenhum pra
# devolver no fim - e um ShowWindow incondicional na saida piscaria uma
# janela preta vazia na cara da pessoa.
$script:ConsoleVisivel = ($hConsole -ne [System.IntPtr]::Zero) -and [Win32Console]::IsWindowVisible($hConsole)
if ($script:ConsoleVisivel) { [void][Win32Console]::ShowWindow($hConsole, 0) }  # SW_HIDE

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
    # Sonda barata primeiro: enquanto o LoL esta fechado esta funcao roda a
    # cada 3s, e o Get-CimInstance abaixo enumera todos os processos da maquina
    # com linha de comando - caro demais so pra perguntar "ja abriu?".
    # Get-Process so olha a tabela de processos.
    if (-not (Get-Process -Name 'LeagueClientUx' -ErrorAction SilentlyContinue)) { return $null }

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
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH')][string] $Method = 'GET',
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
$script:Fase         = $null    # fase do cliente: Lobby, Matchmaking, InProgress...
# Nas fases sem fila a checagem passa a acontecer de N em N ticks. Guardo o
# intervalo que isso da em milissegundos pra HUD poder dizer o numero certo:
# com -IntervaloMs 700 sao 4 ticks, ou seja 2800ms - nao os 3000 redondos.
$script:MsLento      = [math]::Max(1, [int](3000 / $IntervaloMs)) * $IntervaloMs
$script:AceitarEm    = $null    # com -AtrasoSegundos, a hora marcada do aceite

# Fases em que ready check nao existe. Nelas a checagem rapida so gastaria
# processo de curl - e selecao de campeao mais partida sao justo as fases
# longas. Fase fora desta lista, inclusive desconhecida, mantem o ritmo
# rapido: checar demais custa CPU, checar de menos perde a partida.
$script:FasesSemFila = @('None', 'ChampSelect', 'GameStart', 'InProgress',
                         'WaitingForStats', 'PreEndOfGame', 'EndOfGame', 'Reconnect')

# Se o auto-pick ou o auto-ban estiver ligado, selecao de campeao volta pro
# ritmo rapido: la o turno dura poucos segundos e perder a janela e perder a
# vez. Funcao, e nao lista fixa, porque isso muda com o clique do botao.
function Test-RitmoRapido {
    if ($script:Fase -eq 'ChampSelect') { return ($script:AutoPick -or $script:AutoBan) }
    return -not ($script:FasesSemFila -contains $script:Fase)
}

# ---------------------------------------------------------------------------
# Preferencias em disco: onde a janela estava e se o auto-aceitar ficou ligado.
# Ficam no APPDATA e nao no repositorio - e estado da maquina, nao do projeto.
# ---------------------------------------------------------------------------
$script:ArqConfig = Join-Path $env:APPDATA 'Ghost\ghost.json'

function Import-Config {
    if (-not (Test-Path -LiteralPath $script:ArqConfig)) { return $null }
    # Arquivo corrompido nao pode impedir o app de abrir: sem config a HUD
    # volta pro padrao, que e um estado perfeitamente utilizavel.
    try { return (Get-Content -LiteralPath $script:ArqConfig -Raw | ConvertFrom-Json) }
    catch { return $null }
}

function Export-Config {
    param([int]$X, [int]$Y, [bool]$Auto)
    try {
        $dir = Split-Path $script:ArqConfig -Parent
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        $json = [pscustomobject]@{
            X = $X; Y = $Y; AutoAceitar = $Auto
            Picks = @($script:Picks); Bans = @($script:Bans)
            AutoPick = $script:AutoPick; AutoBan = $script:AutoBan
            AutoRuna = $script:AutoRuna
            Recursos = $script:Recursos
        } | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($script:ArqConfig, $json, [System.Text.Encoding]::UTF8)
    }
    catch { }   # nao conseguir salvar preferencia nao e motivo pra estourar erro
}

# --- selecao de campeao ---------------------------------------------------
$script:Campeoes   = @()      # os 173 campeoes: Id, Nome, Alias
$script:PorId      = @{}      # Id -> objeto acima
$script:Picks      = @()      # ids na ordem de preferencia pra escolher
$script:Bans       = @()      # ids na ordem de preferencia pra banir
$script:AutoPick   = $false
$script:AutoBan    = $false
$script:HoverId    = 0        # campeao que o Ghost ja passou pro cliente
$script:HoverEm    = $null    # quando o hover comecou, pra travar depois
$script:LanesPedidas      = @()      # lanes pedidas no lobby, normalizadas
$script:LanesLogadas      = $null    # ultima linha de lane escrita no log
$script:AutofillBloqueado = $false   # autofill parou o pick nesta selecao
$script:AutoRuna       = $true    # gravar a runa ao travar o campeao
$script:RunaJob        = $null    # busca no op.gg em andamento
$script:CacheRunas     = @{}      # 'champId|LANE' -> runa ja buscada
$script:RunaFeitaPara  = ''       # chave ja resolvida, pra nao repetir
$script:AvisouSemPagina = $false  # o aviso de pagina Ghost sai uma vez

# Quais partes da HUD existem nesta sessao. A tela de abertura escreve
# isto e Update-LayoutHud se monta em cima - nada de botao desligado
# ocupando espaco na tela de quem nao usa aquilo.
$script:Recursos = @{ Aceitar = $true; Pick = $true; Ban = $true
                      Runa = $true; Status = $true }
$script:DirIcones  = Join-Path (Split-Path $script:ArqConfig -Parent) 'icones'

$script:Config = Import-Config
# O parametro na linha de comando ganha da preferencia salva.
if ($script:Config -and -not $AutoAceitarLigado -and $script:Config.AutoAceitar) {
    $script:AutoAceitar = $true
}
if ($script:Config) {
    # @() em volta porque ConvertFrom-Json devolve escalar, e nao lista de um
    # item, quando o array salvo tem tamanho 1 - e ai o .Count viria errado.
    if ($script:Config.Picks) { $script:Picks = @($script:Config.Picks | ForEach-Object { [int]$_ }) }
    if ($script:Config.Bans)  { $script:Bans  = @($script:Config.Bans  | ForEach-Object { [int]$_ }) }
    $script:AutoPick = [bool]$script:Config.AutoPick
    $script:AutoBan  = [bool]$script:Config.AutoBan
    # -Runas:$false na linha de comando ganha da preferencia salva.
    if ($script:Config.Recursos) {
        foreach ($k in @($script:Recursos.Keys)) {
            $v = $script:Config.Recursos.$k
            if ($null -ne $v) { $script:Recursos[$k] = [bool]$v }
        }
    }
    # A checagem de $null importa: ghost.json gravado antes deste
    # recurso nao tem a chave, e [bool]$null daria false - desligando
    # a runa sem ninguem ter pedido.
    if (-not $Runas) { $script:AutoRuna = $false }
    elseif ($null -ne $script:Config.AutoRuna) {
        $script:AutoRuna = [bool]$script:Config.AutoRuna
    }
}

# ===========================================================================
# 3. Interface
# ===========================================================================
# CUIDADO: nome de variavel no PowerShell nao diferencia maiuscula de
# minuscula, e o escopo e dinamico - uma funcao le o local de quem a chamou.
# Um "foreach ($c in ...)" em qualquer lugar da pilha apaga esta tabela pra
# tudo que for chamado dali pra baixo, e $C.Verde vira $null sem aviso. Nao
# use $c como variavel de laco neste arquivo.
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
$form.ClientSize      = New-Object System.Drawing.Size(238, 244)
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

function Get-PosicaoPadrao {
    # Canto inferior direito da area de trabalho, com folga pra barra de tarefas.
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    return New-Object System.Drawing.Point(
        ($area.Right - $form.Width - 16), ($area.Bottom - $form.Height - 16))
}

function Test-PosicaoVisivel {
    param([System.Drawing.Point]$P)
    # Exijo que sobre um pedaco do cabecalho dentro de algum monitor: e por ele
    # que se arrasta a janela. Sem borda e sem botao de restaurar, uma HUD fora
    # da tela nao teria como voltar.
    $r = New-Object System.Drawing.Rectangle($P.X, $P.Y, $form.Width, 29)
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $i = [System.Drawing.Rectangle]::Intersect($s.WorkingArea, $r)
        if ($i.Width -ge 80 -and $i.Height -ge 20) { return $true }
    }
    return $false
}

# Abre onde parou da ultima vez, se aquele lugar ainda existir: desconectar um
# monitor ou trocar de resolucao deixaria a janela num canto invisivel.
$posSalva = $null
if ($script:Config -and $null -ne $script:Config.X -and $null -ne $script:Config.Y) {
    $posSalva = New-Object System.Drawing.Point([int]$script:Config.X, [int]$script:Config.Y)
}
$form.Location = if ($posSalva -and (Test-PosicaoVisivel $posSalva)) { $posSalva } else { Get-PosicaoPadrao }

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

# Minimizar existe porque a janela nao tem barra de titulo pra isso. Ela
# ja aparece na barra de tarefas (ShowInTaskbar), entao o botao devolve o
# caminho de volta que o Windows daria de graca numa janela normal.
$btnMin    = New-Botao -Texto '_' -X 178 -Y 3 -W 24 -H 22 -Cor $C.Painel
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
$soltarArraste = {
    $script:Arrastando = $false
    # Soltou a janela fora de qualquer monitor? Traz de volta pro padrao.
    if (-not (Test-PosicaoVisivel $form.Location)) { $form.Location = Get-PosicaoPadrao }
}
foreach ($ctl in @($header, $titulo, $dot)) {
    $ctl.Add_MouseDown($iniciarArraste)
    $ctl.Add_MouseMove($moverArraste)
    $ctl.Add_MouseUp($soltarArraste)
}

# Clique direito na barra do topo reabre a tela de abertura. Vai aqui e
# nao num botao proprio porque a janela tem 238px de largura: mais um
# botao custaria espaco que os outros precisam mais.
$reabrirSetup = {
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    Invoke-Protegido -Onde 'configuracao' -Bloco {
        if (Show-JanelaSetup) {
            Update-LayoutHud
            Update-BotaoAuto
            Update-BotoesSelecao
            Update-BotoesStatus
            Update-Fase
        }
    }
}
foreach ($ctl in @($header, $titulo, $dot)) { $ctl.Add_MouseUp($reabrirSetup) }

# --- fase do cliente ---
# Sai da mesma consulta que decide o ritmo da checagem (secao 5), entao mostrar
# aqui nao custa chamada nenhuma.
$lblFase           = New-Object System.Windows.Forms.Label
$lblFase.Text      = ''
$lblFase.ForeColor = $C.Fraco
$lblFase.Font      = $FonteMini
$lblFase.Location  = New-Object System.Drawing.Point(13, 34)
$lblFase.Size      = New-Object System.Drawing.Size(214, 14)
$form.Controls.Add($lblFase)

# --- auto-aceitar ---
$btnAuto = New-Botao -Texto 'AUTO-ACEITAR: OFF' -X 12 -Y 54 -W 214 -H 32 -Cor $C.Cinza
$form.Controls.Add($btnAuto)

# --- selecao de campeao ---
$lblSelecao           = New-Object System.Windows.Forms.Label
$lblSelecao.Text      = 'SELECAO DE CAMPEAO'
$lblSelecao.ForeColor = $C.Fraco
$lblSelecao.Font      = $FonteMini
$lblSelecao.Location  = New-Object System.Drawing.Point(13, 94)
$lblSelecao.AutoSize  = $true
$form.Controls.Add($lblSelecao)

# As posicoes aqui sao provisorias: Update-LayoutHud recoloca tudo assim
# que a janela aparece, ja sabendo quais recursos ficaram ligados.
$btnPick     = New-Botao -Texto 'Pick'      -X 12  -Y 112 -W 50  -H 28 -Cor $C.Painel
$btnBan      = New-Botao -Texto 'Ban'       -X 67  -Y 112 -W 50  -H 28 -Cor $C.Painel
$btnRuna     = New-Botao -Texto 'Runa'      -X 122 -Y 112 -W 50  -H 28 -Cor $C.Painel
$btnCampeoes = New-Botao -Texto 'Campeoes'  -X 12  -Y 146 -W 214 -H 28 -Cor $C.Painel
$form.Controls.AddRange(@($btnPick, $btnBan, $btnRuna, $btnCampeoes))

# --- status do chat ---
$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'STATUS NO CHAT'
$lblStatus.ForeColor = $C.Fraco
$lblStatus.Font      = $FonteMini
$lblStatus.Location  = New-Object System.Drawing.Point(13, 146)
$lblStatus.AutoSize  = $true
$form.Controls.Add($lblStatus)

$btnOnline  = New-Botao -Texto 'Online'  -X 12  -Y 164 -W 68 -H 28 -Cor $C.Painel
$btnAusente = New-Botao -Texto 'Ausente' -X 85  -Y 164 -W 68 -H 28 -Cor $C.Painel
$btnOffline = New-Botao -Texto 'Offline' -X 158 -Y 164 -W 68 -H 28 -Cor $C.Painel
$form.Controls.AddRange(@($btnOnline, $btnAusente, $btnOffline))

# --- lembrete dos atalhos ---
$lblAtalhos           = New-Object System.Windows.Forms.Label
$lblAtalhos.Text      = 'Ctrl+Alt+A aceite   |   Ctrl+Alt+O offline'
$lblAtalhos.ForeColor = $C.Fraco
$lblAtalhos.Font      = $FonteMini
$lblAtalhos.Location  = New-Object System.Drawing.Point(13, 202)
$lblAtalhos.Size      = New-Object System.Drawing.Size(214, 14)
$form.Controls.Add($lblAtalhos)

# --- linha de log ---
$lblLog           = New-Object System.Windows.Forms.Label
$lblLog.Text      = ''
$lblLog.ForeColor = $C.Fraco
$lblLog.Font      = $FonteMini
$lblLog.Location  = New-Object System.Drawing.Point(13, 220)
$lblLog.Size      = New-Object System.Drawing.Size(214, 16)
$form.Controls.Add($lblLog)

function Write-Log {
    param([string]$Texto, $Cor = $null)
    $lblLog.Text      = ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Texto)
    $lblLog.ForeColor = if ($Cor) { $Cor } else { $C.Fraco }
}

# Excecao dentro de um handler de evento do WinForms nao aparece em lugar
# nenhum: o console esta escondido e o WinForms engole. O sintoma e a HUD
# parada numa linha de log antiga, sem nada explicando. Toda acao de botao
# passa por aqui, e o erro fica na linha de log e no arquivo.
function Invoke-Protegido {
    param([Parameter(Mandatory)][scriptblock] $Bloco, [string] $Onde = 'acao')
    try { & $Bloco }
    catch {
        $msg = $_.Exception.Message
        Write-Log ("Erro em {0}: {1}" -f $Onde, $msg) $C.Vermelho
        try {
            $arq = Join-Path (Split-Path $script:ArqConfig -Parent) 'erro.txt'
            $txt = ("[{0}] {1}`r`n{2}`r`n`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
                    $Onde, ($_ | Out-String))
            [System.IO.File]::AppendAllText($arq, $txt, [System.Text.Encoding]::UTF8)
        }
        catch { }
    }
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
    # viraria misterio: a pessoa muda o status no cliente e ele "volta sozinho".
    # O caractere vai por codigo porque este arquivo e ASCII de proposito.
    $btnOffline.Text = if ($script:OfflineFixado) { 'Offline ' + [char]0x2713 } else { 'Offline' }
    switch ($script:Availability) {
        'chat'    { $btnOnline.BackColor  = $C.Verde;    $btnOnline.ForeColor  = $C.Texto }
        'away'    { $btnAusente.BackColor = $C.Ambar;    $btnAusente.ForeColor = $C.Texto }
        'offline' { $btnOffline.BackColor = $C.Azul;     $btnOffline.ForeColor = $C.Texto }
        'dnd'     { $btnAusente.BackColor = $C.Vermelho; $btnAusente.ForeColor = $C.Texto }
    }
}

function Update-BotoesSelecao {
    # Um botao de cada vez, sem lista pareada: @($btn, $arrayDeIds) achataria
    # o array de campeoes dentro do par e $par[1] viria o primeiro id.
    $nPick = @($script:Picks).Count
    $nBan  = @($script:Bans).Count

    Set-CorBotaoSelecao -Botao $btnPick -Ligado $script:AutoPick -Quantos $nPick `
                        -Bloqueado:$script:AutofillBloqueado
    Set-CorBotaoSelecao -Botao $btnBan  -Ligado $script:AutoBan  -Quantos $nBan

    # Runa nao tem fila: ligada e ligada, sem estado meio-termo.
    Set-CorBotaoSelecao -Botao $btnRuna -Ligado $script:AutoRuna -Quantos 1

    $btnPick.Text = if ($nPick) { "Pick $nPick" } else { 'Pick' }
    $btnBan.Text  = if ($nBan)  { "Ban $nBan" }   else { 'Ban' }
}

function Set-CorBotaoSelecao {
    param($Botao, [bool]$Ligado, [int]$Quantos, [switch]$Bloqueado)
    if ($Ligado -and $Quantos -gt 0 -and -not $Bloqueado) {
        $Botao.BackColor = $C.Verde;  $Botao.ForeColor = $C.Texto
    }
    elseif ($Ligado) {
        # Ligado com a fila vazia - ou com o pick parado pelo autofill - nao
        # faz nada. Ambar em vez de verde pra nao prometer uma automacao que
        # nao vai acontecer.
        $Botao.BackColor = $C.Ambar;  $Botao.ForeColor = $C.Texto
    }
    else {
        $Botao.BackColor = $C.Painel; $Botao.ForeColor = $C.Fraco
    }
}

# ---------------------------------------------------------------------------
# Layout da HUD.
#
# Ate aqui a janela tinha altura fixa e todo botao sempre visivel. Com os
# recursos escolhidos na abertura isso deixou de servir: quem usa so o status
# nao quer olhar pra uma faixa de auto-pick desligada o tempo todo.
#
# Entao a altura passa a ser resultado do que esta ligado, e nao um numero
# fixo no codigo.
# ---------------------------------------------------------------------------

$script:HudX    = 12    # margem esquerda
$script:HudLarg = 214   # largura util
$script:HudVao  = 5     # espaco entre botoes da mesma linha

# Espalha N botoes na largura util. O ultimo fecha na margem direita em vez de
# usar a largura calculada: 214 dividido por 3 sobra 1px, e sem isso a coluna
# da direita nao alinha com as outras linhas.
function Set-LinhaBotoes {
    param($Botoes, [int]$Y)
    $lista = @($Botoes)
    if ($lista.Count -eq 0) { return }
    $larg = [int](($script:HudLarg - ($script:HudVao * ($lista.Count - 1))) / $lista.Count)
    $x = $script:HudX
    for ($i = 0; $i -lt $lista.Count; $i++) {
        $w = if ($i -eq $lista.Count - 1) { $script:HudX + $script:HudLarg - $x } else { $larg }
        $lista[$i].Location = New-Object System.Drawing.Point($x, $Y)
        $lista[$i].Size     = New-Object System.Drawing.Size($w, 28)
        $lista[$i].Visible  = $true
        $x += $w + $script:HudVao
    }
}

function Update-LayoutHud {
    $y = 54

    # --- auto-aceitar ---
    $btnAuto.Visible = [bool]$script:Recursos.Aceitar
    if ($script:Recursos.Aceitar) {
        $btnAuto.Location = New-Object System.Drawing.Point($script:HudX, $y)
        $btnAuto.Size     = New-Object System.Drawing.Size($script:HudLarg, 32)
        $y += 40
    }

    # --- selecao de campeao ---
    foreach ($b in @($btnPick, $btnBan, $btnRuna, $btnCampeoes)) { $b.Visible = $false }
    $linha = @()
    if ($script:Recursos.Pick) { $linha += $btnPick }
    if ($script:Recursos.Ban)  { $linha += $btnBan }
    if ($script:Recursos.Runa) { $linha += $btnRuna }

    $lblSelecao.Visible = ($linha.Count -gt 0)
    if ($linha.Count -gt 0) {
        $lblSelecao.Location = New-Object System.Drawing.Point(13, $y)
        $y += 18
        Set-LinhaBotoes -Botoes $linha -Y $y
        $y += 34
        # A grade so serve pra montar fila de pick e de ban. Com os dois
        # desligados ela nao teria o que fazer, entao nem aparece.
        if ($script:Recursos.Pick -or $script:Recursos.Ban) {
            Set-LinhaBotoes -Botoes @($btnCampeoes) -Y $y
            $y += 34
        }
    }

    # --- status no chat ---
    $lblStatus.Visible = [bool]$script:Recursos.Status
    foreach ($b in @($btnOnline, $btnAusente, $btnOffline)) {
        $b.Visible = [bool]$script:Recursos.Status
    }
    if ($script:Recursos.Status) {
        $lblStatus.Location = New-Object System.Drawing.Point(13, $y)
        $y += 18
        Set-LinhaBotoes -Botoes @($btnOnline, $btnAusente, $btnOffline) -Y $y
        $y += 38
    }

    # --- atalhos: so lembra o que existe nesta sessao ---
    $atalhos = @()
    if ($script:Recursos.Aceitar) { $atalhos += 'Ctrl+Alt+A aceite' }
    if ($script:Recursos.Status)  { $atalhos += 'Ctrl+Alt+O offline' }
    $lblAtalhos.Visible = ($atalhos.Count -gt 0)
    if ($atalhos.Count -gt 0) {
        $lblAtalhos.Text     = ($atalhos -join '   |   ')
        $lblAtalhos.Location = New-Object System.Drawing.Point(13, $y)
        $y += 18
    }

    $lblLog.Location = New-Object System.Drawing.Point(13, $y)
    $y += 24

    $form.ClientSize = New-Object System.Drawing.Size(238, $y)
    # A borda de 1px sai do handler de Paint: sem invalidar, ela continua
    # desenhada na altura antiga depois que a janela encolhe.
    $form.Invalidate()
    if (-not (Test-PosicaoVisivel $form.Location)) { $form.Location = Get-PosicaoPadrao }
}

# Traduz a fase crua do gameflow. [string] no switch porque switch sobre $null
# nao entra nem no default, e a fase e $null enquanto o cliente esta fechado.
function Update-Fase {
    $texto = switch ([string]$script:Fase) {
        'None'            { 'fora de fila' }
        'Lobby'           { 'no lobby' }
        'Matchmaking'     { 'na fila' }
        'ReadyCheck'      { 'partida encontrada' }
        'ChampSelect'     { 'selecao de campeao' }
        'GameStart'       { 'entrando na partida' }
        'InProgress'      { 'em partida' }
        'Reconnect'       { 'esperando reconexao' }
        'WaitingForStats' { 'fim de partida' }
        'PreEndOfGame'    { 'fim de partida' }
        'EndOfGame'       { 'fim de partida' }
        default           { '' }
    }
    # Nessas fases a checagem cai de proposito. Sem dizer isso a HUD pareceria
    # travada - e dizer "ritmo lento" nao explicava nada a quem le, entao vai o
    # intervalo em segundos.
    if ($script:AutoAceitar -and ($script:FasesSemFila -contains $script:Fase)) {
        $texto = "$texto  -  checando a cada {0:0.#}s" -f ($script:MsLento / 1000)
    }
    $lblFase.Text = $texto
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
    elseif ($r.Status -eq 0 -or $r.Status -eq 401) {
        # 0 = curl nao conectou. 401 = a senha do lockfile mudou, ou seja o
        # cliente reiniciou. Nos dois casos a sessao guardada morreu: derruba e
        # deixa o loop reconectar, em vez de insistir com credencial velha.
        Disconnect-Cliente
        Write-Log 'Perdi o cliente. Reconectando...' $C.Vermelho
    }
    else {
        Write-Log ("Falhou ao trocar status (HTTP {0})." -f $r.Status) $C.Vermelho
    }
}

function Switch-AutoAceitar {
    $script:AutoAceitar = -not $script:AutoAceitar
    Update-BotaoAuto
    Update-Fase
    if ($script:AutoAceitar) { Write-Log 'Auto-aceitar ligado.' $C.Verde }
    else {
        # Desligou no meio da contagem do -AtrasoSegundos: cancela o aceite.
        $script:AceitarEm = $null
        Write-Log 'Auto-aceitar desligado.'
    }
}

# Ctrl+Alt+O e um vai-e-volta: se estou offline, volto pra online; senao,
# vou pra offline. Qualquer outro estado (ausente/dnd) conta como "nao offline".
function Switch-Offline {
    if ($script:Availability -eq 'offline') { Set-Availability -Valor 'chat' }
    else                                    { Set-Availability -Valor 'offline' }
}

$btnAuto.Add_Click({    Switch-AutoAceitar })
$btnCampeoes.Add_Click({ Invoke-Protegido -Onde 'janela de campeoes' -Bloco { Show-JanelaCampeoes } })
$btnPick.Add_Click({ Invoke-Protegido -Onde 'auto-pick' -Bloco {
    $script:AutoPick = -not $script:AutoPick
    Update-BotoesSelecao
    if ($script:AutoPick -and @($script:Picks).Count -eq 0) {
        Write-Log 'Auto-pick ligado, mas a fila esta vazia.' $C.Ambar
    }
    else {
        Write-Log ("Auto-pick {0}." -f $(if ($script:AutoPick) { 'ligado' } else { 'desligado' }))
    }
} })
$btnBan.Add_Click({ Invoke-Protegido -Onde 'auto-ban' -Bloco {
    $script:AutoBan = -not $script:AutoBan
    Update-BotoesSelecao
    if ($script:AutoBan -and @($script:Bans).Count -eq 0) {
        Write-Log 'Auto-ban ligado, mas a fila esta vazia.' $C.Ambar
    }
    else {
        Write-Log ("Auto-ban {0}." -f $(if ($script:AutoBan) { 'ligado' } else { 'desligado' }))
    }
} })
$btnRuna.Add_Click({ Invoke-Protegido -Onde 'runa' -Bloco {
    $script:AutoRuna = -not $script:AutoRuna
    Update-BotoesSelecao
    Write-Log ("Runa automatica {0}." -f $(if ($script:AutoRuna) { 'ligada' } else { 'desligada' }))
} })
$btnMin.Add_Click({ $form.WindowState = 'Minimized' })
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
# 6. Selecao de campeao
#    Dados dos campeoes, cache de icones, janela de escolha e a automacao
#    de pick/ban propriamente dita.
# ===========================================================================

# Carrega os 173 campeoes do proprio cliente. Nada de lista embutida no
# script: campeao novo sai a cada poucas semanas, e uma lista fixa nasceria
# desatualizada. Nomes vem no idioma do cliente ("Nunu e Willump"), o alias
# vem sempre em ingles - por isso a busca olha os dois.
function Import-Campeoes {
    if ($script:Campeoes.Count -gt 0) { return $true }
    if (-not $script:Session) { return $false }

    $r = Invoke-Lcu -Session $script:Session -TimeoutSec 10 `
             -Path '/lol-game-data/assets/v1/champion-summary.json'
    $j = ConvertFrom-LcuBody $r
    if (-not $j) { return $false }

    # id -1 e a entrada "Nenhum". Os 60001+ sao as variantes Jade, que sao
    # arte alternativa do mesmo campeao e nao servem pra escolher nem banir.
    $script:Campeoes = @(
        $j | Where-Object { $_.id -gt 0 -and $_.id -lt 10000 } | ForEach-Object {
            [pscustomobject]@{
                Id    = [int]$_.id
                Nome  = [string]$_.name
                Alias = [string]$_.alias
            }
        } | Sort-Object Nome
    )
    $script:PorId = @{}
    foreach ($camp in $script:Campeoes) { $script:PorId[$camp.Id] = $camp }
    return ($script:Campeoes.Count -gt 0)
}

function Get-NomeCampeao {
    param([int]$Id)
    if ($script:PorId.ContainsKey($Id)) { return $script:PorId[$Id].Nome }
    return "campeao $Id"
}

# Baixa os icones que faltam. Sao 128x128 servidos pela propria LCU, entao
# nao ha download da internet - o cliente ja tem tudo em disco.
#
# Uma chamada de curl com todos os pares url/output, e nao uma por icone:
# medido aqui, 20 icones um a um levam 1218ms e numa chamada so, 145ms. O
# custo e quase todo em subir o processo, nao em baixar.
#
# A lista vai por arquivo (-K) e nao por linha de comando: 173 pares passam
# de 22 mil caracteres, perto demais do teto de 32767 do CreateProcess.
function Sync-Icones {
    param([int[]]$Ids)
    if (-not $script:Session) { return 0 }
    if (-not (Test-Path -LiteralPath $script:DirIcones)) {
        [void](New-Item -ItemType Directory -Path $script:DirIcones -Force)
    }

    $faltando = @($Ids | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $script:DirIcones "$_.png"))
    })
    if ($faltando.Count -eq 0) { return 0 }

    $lista = Join-Path $env:TEMP ("ghost-icones-" + [guid]::NewGuid().ToString('N') + ".txt")
    $sb = New-Object System.Text.StringBuilder
    foreach ($id in $faltando) {
        # Barra normal no caminho de saida, e nao a do Windows: dentro de aspas
        # num arquivo -K, o curl trata \ como inicio de escape. Com o caminho
        # em C:\Users\... ele nao grava nada e sai calado - medido aqui, 0 de
        # 173 arquivos com barra invertida e 173 de 173 com barra normal. A
        # API de arquivo do Windows aceita as duas.
        $saida = (Join-Path $script:DirIcones "$id.png") -replace '\\', '/'
        [void]$sb.AppendLine('url = "https://127.0.0.1:' + $script:Session.Port +
                             '/lol-game-data/assets/v1/champion-icons/' + $id + '.png"')
        [void]$sb.AppendLine('output = "' + $saida + '"')
    }
    [System.IO.File]::WriteAllText($lista, $sb.ToString(), [System.Text.Encoding]::ASCII)

    try {
        # O -u fica na linha de comando, fora do arquivo: assim a senha do
        # lockfile nao chega a ser gravada em disco.
        & $script:Curl @('-s', '-k', '--max-time', '90',
                         '-u', "riot:$($script:Session.Password)", '-K', $lista) | Out-Null
    }
    catch { }
    finally { Remove-Item $lista -Force -ErrorAction SilentlyContinue }

    return @($faltando | Where-Object {
        Test-Path -LiteralPath (Join-Path $script:DirIcones "$_.png")
    }).Count
}

# Le o PNG por MemoryStream e desenha num Bitmap novo. Image.FromFile deixaria
# o arquivo travado enquanto a imagem viver, e sao 173 arquivos.
function Get-IconeCampeao {
    param([int]$Id, [int]$Tam)
    $p = Join-Path $script:DirIcones "$Id.png"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $ms   = New-Object System.IO.MemoryStream(,[System.IO.File]::ReadAllBytes($p))
        $orig = [System.Drawing.Image]::FromStream($ms)
        $bmp  = New-Object System.Drawing.Bitmap($Tam, $Tam)
        $g    = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($orig, 0, 0, $Tam, $Tam)
        $g.Dispose(); $orig.Dispose(); $ms.Dispose()
        return $bmp
    }
    catch { return $null }
}

# ---------------------------------------------------------------------------
# Janela de escolha: grade com os icones do cliente, busca por nome, e as duas
# filas (escolher / banir) em ordem de preferencia.
#
# Tudo que os eventos precisam mora em escopo de script. No PowerShell o
# scriptblock de um evento do WinForms nao enxerga a variavel local da funcao
# que o criou - ele dispara da fila de mensagens, muito depois. Por isso os
# handlers so leem $script:... e chamam funcao por nome.
# ---------------------------------------------------------------------------
$script:GradeCampeoes = $null
$script:FilaPickPanel = $null
$script:FilaBanPanel  = $null
$script:MiniCache     = @{}
$script:CelulasGrade  = @()
# Um ToolTip para todos os icones. Um por controle tambem funciona, mas sao
# 173 componentes com recurso nativo cada: medido, 79ms contra 25ms.
$script:DicaCampeoes  = $null

# Busca sem acento e sem pontuacao: quem digita "kaisa" quer achar "Kai'Sa",
# quem digita "leblanc" quer "LeBlanc", quem digita "nunu" quer "Nunu e
# Willump". Normalizo a busca e o nome do mesmo jeito e comparo.
function ConvertTo-ChaveBusca {
    param([string]$T)
    if (-not $T) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $T.Normalize([System.Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return ($sb.ToString().ToLower() -replace '[^a-z0-9]', '')
}

function Get-MiniIcone {
    param([int]$Id)
    if (-not $script:MiniCache.ContainsKey($Id)) {
        $script:MiniCache[$Id] = Get-IconeCampeao -Id $Id -Tam 40
    }
    return $script:MiniCache[$Id]
}

function Clear-Painel {
    param($Painel)
    # Solto a imagem antes de descartar o controle: o bitmap e compartilhado
    # com o cache, e um Dispose dele deixaria a fila em branco no proximo
    # redesenho.
    while ($Painel.Controls.Count -gt 0) {
        $ctl = $Painel.Controls[0]
        $Painel.Controls.RemoveAt(0)
        $ctl.Image = $null
        $ctl.Dispose()
    }
}

function Update-FilasCampeoes {
    foreach ($lado in @('pick', 'ban')) {
        if ($lado -eq 'pick') { $painel = $script:FilaPickPanel; $ids = @($script:Picks) }
        else                  { $painel = $script:FilaBanPanel;  $ids = @($script:Bans) }
        if (-not $painel) { continue }

        Clear-Painel $painel
        foreach ($id in $ids) {
            $pb          = New-Object System.Windows.Forms.PictureBox
            $pb.Size     = New-Object System.Drawing.Size(40, 40)
            $pb.SizeMode = 'Zoom'
            $pb.Image    = Get-MiniIcone -Id $id
            $pb.Cursor   = [System.Windows.Forms.Cursors]::Hand
            $pb.Tag      = $id
            $pb.Margin   = New-Object System.Windows.Forms.Padding(2)
            if ($script:DicaCampeoes) {
                $script:DicaCampeoes.SetToolTip($pb, ((Get-NomeCampeao $id) + ' - clique pra tirar da fila'))
            }
            $pb.Add_Click({ param($s, $e) Remove-DaFila -Ctl $s })
            $painel.Controls.Add($pb)
        }
    }
    Update-BotoesSelecao
}

function Remove-DaFila {
    param($Ctl)
    $id = [int]$Ctl.Tag
    # De qual fila veio sai do proprio controle, e nao de variavel capturada.
    if ($Ctl.Parent -eq $script:FilaPickPanel) {
        $script:Picks = @($script:Picks | Where-Object { $_ -ne $id })
    }
    else {
        $script:Bans = @($script:Bans | Where-Object { $_ -ne $id })
    }
    Update-FilasCampeoes
}

function Add-NaFila {
    param($Ctl, $Botao)
    $id = [int]$Ctl.Tag
    if ($Botao -eq [System.Windows.Forms.MouseButtons]::Right) {
        if (@($script:Bans) -notcontains $id) { $script:Bans = @($script:Bans) + $id }
    }
    else {
        if (@($script:Picks) -notcontains $id) { $script:Picks = @($script:Picks) + $id }
    }
    Update-FilasCampeoes
}

function Update-FiltroGrade {
    param([string]$Texto)
    if (-not $script:GradeCampeoes) { return }
    $q = ConvertTo-ChaveBusca $Texto
    $script:GradeCampeoes.SuspendLayout()
    foreach ($cel in $script:CelulasGrade) {
        $cel.Ctl.Visible = ($q -eq '' -or $cel.Busca.Contains($q))
    }
    $script:GradeCampeoes.ResumeLayout()
}

function New-FilaPainel {
    param($Janela, [string]$Titulo, [int]$X, [int]$Y)
    $l           = New-Object System.Windows.Forms.Label
    $l.Text      = $Titulo
    $l.ForeColor = $C.Fraco
    $l.Font      = $FonteMini
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.AutoSize  = $true
    $Janela.Controls.Add($l)

    $f           = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Location  = New-Object System.Drawing.Point($X, ($Y + 18))
    $f.Size      = New-Object System.Drawing.Size(714, 52)
    $f.BackColor = $C.Painel
    $f.Padding   = New-Object System.Windows.Forms.Padding(4)
    $f.WrapContents = $false
    $f.AutoScroll   = $true
    $Janela.Controls.Add($f)
    return $f
}

# ---------------------------------------------------------------------------
# Tela de abertura.
#
# O Ghost cresceu de "aceita partida sozinho" pra cinco automacoes diferentes,
# e ninguem usa as cinco. Quem so quer aparecer offline nao tem por que olhar
# pra uma faixa de auto-pick apagada em toda partida.
#
# Entao a janela pergunta antes: marca o que quer, OK, e a HUD sobe so com
# aquilo. A escolha fica salva - na proxima abertura os mesmos itens ja vem
# marcados. -Direto pula a tela e usa o que estava salvo.
#
# Desmarcar aqui nao e so esconder botao: Sync-Automacoes desliga a automacao
# junto. Recurso escondido que continua agindo por tras seria a pior das duas
# opcoes.
# ---------------------------------------------------------------------------

# Recurso desmarcado nao pode continuar rodando escondido.
function Sync-Automacoes {
    if (-not $script:Recursos.Aceitar) { $script:AutoAceitar = $false }
    if (-not $script:Recursos.Pick)    { $script:AutoPick    = $false }
    if (-not $script:Recursos.Ban)     { $script:AutoBan     = $false }
    if (-not $script:Recursos.Runa)    { $script:AutoRuna    = $false }
    if (-not $script:Recursos.Status)  { $script:OfflineFixado = $false }
}

function New-CaixaSetup {
    param($Janela, [string]$Titulo, [string]$Ajuda, [bool]$Marcado, [int]$Y)

    $cx           = New-Object System.Windows.Forms.CheckBox
    $cx.Text      = $Titulo
    $cx.Checked   = $Marcado
    $cx.ForeColor = $C.Texto
    $cx.BackColor = $C.Fundo
    $cx.FlatStyle = 'Flat'
    $cx.Font      = $FonteBotao
    $cx.Location  = New-Object System.Drawing.Point(18, $Y)
    $cx.Size      = New-Object System.Drawing.Size(300, 20)
    $Janela.Controls.Add($cx)

    $lb           = New-Object System.Windows.Forms.Label
    $lb.Text      = $Ajuda
    $lb.ForeColor = $C.Fraco
    $lb.Font      = $FonteMini
    $lb.Location  = New-Object System.Drawing.Point(37, ($Y + 19))
    $lb.Size      = New-Object System.Drawing.Size(285, 15)
    $Janela.Controls.Add($lb)

    return $cx
}

# Devolve $true se a pessoa confirmou, $false se fechou ou cancelou.
function Show-JanelaSetup {
    $jan                 = New-Object System.Windows.Forms.Form
    $jan.Text            = 'Ghost'
    $jan.FormBorderStyle = 'FixedDialog'
    $jan.MaximizeBox     = $false
    $jan.MinimizeBox     = $false
    $jan.StartPosition   = 'CenterScreen'
    $jan.BackColor       = $C.Fundo
    $jan.ClientSize      = New-Object System.Drawing.Size(340, 322)
    if ($form.Icon) { $jan.Icon = $form.Icon }

    $tit           = New-Object System.Windows.Forms.Label
    $tit.Text      = 'O que voce quer usar?'
    $tit.ForeColor = $C.Texto
    $tit.Font      = $FonteTitulo
    $tit.Location  = New-Object System.Drawing.Point(18, 16)
    $tit.AutoSize  = $true
    $jan.Controls.Add($tit)

    $sub           = New-Object System.Windows.Forms.Label
    $sub.Text      = 'So o que estiver marcado aparece na HUD.'
    $sub.ForeColor = $C.Fraco
    $sub.Font      = $FonteMini
    $sub.Location  = New-Object System.Drawing.Point(18, 36)
    $sub.Size      = New-Object System.Drawing.Size(304, 15)
    $jan.Controls.Add($sub)

    $cxAceitar = New-CaixaSetup $jan 'Aceitar partida sozinho' `
        'Fecha o ready check por voce. Ctrl+Alt+A liga e desliga.' `
        ([bool]$script:Recursos.Aceitar) 62
    $cxStatus  = New-CaixaSetup $jan 'Status no chat' `
        'Online, ausente e offline - inclusive o offline fixado.' `
        ([bool]$script:Recursos.Status) 106
    $cxPick    = New-CaixaSetup $jan 'Escolher campeao (auto-pick)' `
        'Pega o primeiro da sua fila que ainda estiver livre.' `
        ([bool]$script:Recursos.Pick) 150
    $cxBan     = New-CaixaSetup $jan 'Banir campeao (auto-ban)' `
        'Mesma ideia, na sua vez de banir.' `
        ([bool]$script:Recursos.Ban) 194
    $cxRuna    = New-CaixaSetup $jan 'Runa automatica' `
        'Grava a runa do op.gg na sua pagina chamada Ghost.' `
        ([bool]$script:Recursos.Runa) 238

    $btnOk       = New-Botao -Texto 'OK'        -X 176 -Y 282 -W 70 -H 28 -Cor $C.Verde
    $btnCancelar = New-Botao -Texto 'Cancelar'  -X 252 -Y 282 -W 70 -H 28 -Cor $C.Painel
    $jan.Controls.AddRange(@($btnOk, $btnCancelar))
    $jan.AcceptButton = $btnOk
    $jan.CancelButton = $btnCancelar

    $btnOk.Add_Click({ param($s, $e)
        $j = $s.FindForm(); $j.DialogResult = 'OK'; $j.Close()
    })
    $btnCancelar.Add_Click({ param($s, $e)
        $j = $s.FindForm(); $j.DialogResult = 'Cancel'; $j.Close()
    })

    $r = $jan.ShowDialog()
    $ok = ($r -eq [System.Windows.Forms.DialogResult]::OK)
    if ($ok) {
        $script:Recursos.Aceitar = [bool]$cxAceitar.Checked
        $script:Recursos.Status  = [bool]$cxStatus.Checked
        $script:Recursos.Pick    = [bool]$cxPick.Checked
        $script:Recursos.Ban     = [bool]$cxBan.Checked
        $script:Recursos.Runa    = [bool]$cxRuna.Checked
        Sync-Automacoes
    }
    $jan.Dispose()
    return $ok
}

function Show-JanelaCampeoes {
    if (-not $script:Session) {
        Write-Log 'Abra o cliente do LoL primeiro.' $C.Vermelho
        return
    }

    Write-Log 'Carregando campeoes...'
    $lblLog.Refresh()
    if (-not (Import-Campeoes)) {
        Write-Log 'Nao consegui ler a lista de campeoes.' $C.Vermelho
        return
    }

    # Primeira abertura baixa os 173 icones; da segunda em diante ja estao em
    # disco e isso custa zero.
    $baixados = Sync-Icones -Ids @($script:Campeoes.Id)

    # Conferir o que ficou em disco, e nao confiar no que o curl disse. Foi
    # exatamente aqui que o bug do backslash se escondeu: o curl saiu com
    # sucesso, gravou os arquivos com o caminho virando nome e na pasta de
    # trabalho errada, e a grade so apareceu com quadrados vazios. Download
    # que falha calado custa caro pra achar.
    $faltam = @($script:Campeoes.Id | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $script:DirIcones "$_.png"))
    }).Count

    if ($faltam -gt 0) {
        Write-Log ("{0} de {1} icones nao baixaram." -f $faltam, @($script:Campeoes).Count) $C.Ambar
    }
    elseif ($baixados -gt 0) {
        Write-Log ("{0} icones baixados." -f $baixados)
    }
    $lblLog.Refresh()

    $jan                 = New-Object System.Windows.Forms.Form
    $jan.Text            = 'Ghost - campeoes'
    $jan.FormBorderStyle = 'FixedDialog'
    $jan.MaximizeBox     = $false
    $jan.MinimizeBox     = $false
    $jan.StartPosition   = 'CenterScreen'
    $jan.ClientSize      = New-Object System.Drawing.Size(742, 600)
    $jan.BackColor       = $C.Fundo
    $jan.ForeColor       = $C.Texto
    if ($form.Icon) { $jan.Icon = $form.Icon }

    $lblBusca           = New-Object System.Windows.Forms.Label
    $lblBusca.Text      = 'BUSCAR'
    $lblBusca.ForeColor = $C.Fraco
    $lblBusca.Font      = $FonteMini
    $lblBusca.Location  = New-Object System.Drawing.Point(14, 14)
    $lblBusca.AutoSize  = $true
    $jan.Controls.Add($lblBusca)

    $txtBusca             = New-Object System.Windows.Forms.TextBox
    $txtBusca.Location    = New-Object System.Drawing.Point(14, 32)
    $txtBusca.Size        = New-Object System.Drawing.Size(280, 24)
    $txtBusca.BackColor   = $C.Painel
    $txtBusca.ForeColor   = $C.Texto
    $txtBusca.BorderStyle = 'FixedSingle'
    $txtBusca.Font        = $FonteBotao
    $txtBusca.Add_TextChanged({ param($s, $e) Update-FiltroGrade -Texto $s.Text })
    $jan.Controls.Add($txtBusca)

    $lblAjuda           = New-Object System.Windows.Forms.Label
    # Texto curto o bastante pra caber em duas linhas nesta largura: com o
    # anterior ele quebrava em tres e a ultima saia cortada.
    $lblAjuda.Text      = ("Clique escolhe, clique direito bane." + [char]10 +
                           "Clique na fila tira. A ordem da fila e a preferencia.")
    $lblAjuda.ForeColor = $C.Fraco
    $lblAjuda.Font      = $FonteMini
    $lblAjuda.Location  = New-Object System.Drawing.Point(306, 26)
    $lblAjuda.Size      = New-Object System.Drawing.Size(324, 34)
    $jan.Controls.Add($lblAjuda)

    $btnOk = New-Botao -Texto 'Fechar' -X 638 -Y 28 -W 90 -H 30 -Cor $C.Azul
    # FindForm em vez de capturar $jan: o handler roda fora deste escopo.
    $btnOk.Add_Click({ param($s, $e) $s.FindForm().Close() })
    $jan.Controls.Add($btnOk)

    $script:GradeCampeoes            = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:GradeCampeoes.Location   = New-Object System.Drawing.Point(14, 70)
    $script:GradeCampeoes.Size       = New-Object System.Drawing.Size(714, 366)
    $script:GradeCampeoes.AutoScroll = $true
    $script:GradeCampeoes.BackColor  = $C.Painel
    $script:GradeCampeoes.Padding    = New-Object System.Windows.Forms.Padding(6)
    $jan.Controls.Add($script:GradeCampeoes)

    $script:FilaPickPanel = New-FilaPainel -Janela $jan -Titulo 'ESCOLHER, NESTA ORDEM' -X 14 -Y 446
    $script:FilaBanPanel  = New-FilaPainel -Janela $jan -Titulo 'BANIR, NESTA ORDEM'    -X 14 -Y 518

    $script:CelulasGrade = @()
    $script:DicaCampeoes = New-Object System.Windows.Forms.ToolTip
    $script:GradeCampeoes.SuspendLayout()
    foreach ($camp in $script:Campeoes) {
        $pb          = New-Object System.Windows.Forms.PictureBox
        $pb.Size     = New-Object System.Drawing.Size(56, 56)
        $pb.SizeMode = 'Zoom'
        $pb.Image    = Get-IconeCampeao -Id $camp.Id -Tam 56
        $pb.Cursor   = [System.Windows.Forms.Cursors]::Hand
        $pb.Tag      = $camp.Id
        $pb.Margin   = New-Object System.Windows.Forms.Padding(3)
        $script:DicaCampeoes.SetToolTip($pb, $camp.Nome)
        $pb.Add_MouseUp({ param($s, $e) Add-NaFila -Ctl $s -Botao $e.Button })
        $script:GradeCampeoes.Controls.Add($pb)
        $script:CelulasGrade += [pscustomobject]@{
            Ctl   = $pb
            Busca = (ConvertTo-ChaveBusca ($camp.Nome + $camp.Alias))
        }
    }
    $script:GradeCampeoes.ResumeLayout()

    Update-FilasCampeoes
    [void]$jan.ShowDialog($form)

    # Limpeza: os bitmaps sao meus, o GC do .NET nao solta handle de GDI+.
    Clear-Painel $script:FilaPickPanel
    Clear-Painel $script:FilaBanPanel
    foreach ($cel in $script:CelulasGrade) {
        if ($cel.Ctl.Image) { $cel.Ctl.Image.Dispose() }
        $cel.Ctl.Image = $null
    }
    foreach ($b in $script:MiniCache.Values) { if ($b) { $b.Dispose() } }
    if ($script:DicaCampeoes) { $script:DicaCampeoes.Dispose(); $script:DicaCampeoes = $null }
    $script:MiniCache     = @{}
    $script:CelulasGrade  = @()
    $script:GradeCampeoes = $null
    $script:FilaPickPanel = $null
    $script:FilaBanPanel  = $null
    $jan.Dispose()

    Update-BotoesSelecao
    Write-Log ("Filas: {0} pra escolher, {1} pra banir." -f @($script:Picks).Count, @($script:Bans).Count)
}

# ---------------------------------------------------------------------------
# A automacao em si.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Autofill: a lane que o cliente deu contra a lane que voce pediu.
#
# A fila de pick e uma so e nao sabe de lane. Sem esta checagem, cair de
# autofill no suporte com uma fila montada pra mid faz o Ghost travar sozinho
# um campeao que nao joga ali - e o estrago acontece com voce olhando, porque
# a automacao age antes de voce entender o que aconteceu.
#
# O gate so BLOQUEIA quando tem certeza. Sem lane atribuida (cega, ARAM), sem
# preferencia lida, ou com fill pedido, ele libera. Falhar liberando mantem o
# comportamento de hoje; falhar bloqueando tiraria o pick de quem contava com
# ele, no meio da selecao, sem motivo visivel.
#
# O ban nao passa pelo gate: banir campeao nao depende da sua lane.
# ---------------------------------------------------------------------------

# O cliente escreve a mesma lane de dois jeitos - 'MIDDLE' na preferencia do
# lobby, 'middle' no champ select -, entao normalizo os dois lados antes de
# comparar. Os apelidos entram porque aparecem em modo e versao diferente.
function ConvertTo-LaneNormal {
    param([string]$Lane)
    $l = ([string]$Lane).Trim().ToUpperInvariant()
    switch ($l) {
        'MID'     { return 'MIDDLE' }
        'SUPPORT' { return 'UTILITY' }
        'BOT'     { return 'BOTTOM' }
        'ADC'     { return 'BOTTOM' }
        default   { return $l }
    }
}

function Get-NomeLane {
    param([string]$Lane)
    switch (ConvertTo-LaneNormal $Lane) {
        'TOP'     { return 'topo' }
        'JUNGLE'  { return 'selva' }
        'MIDDLE'  { return 'meio' }
        'BOTTOM'  { return 'atirador' }
        'UTILITY' { return 'suporte' }
        default   { return 'lane desconhecida' }
    }
}

# Le as duas posicoes escolhidas no lobby. Nao da pra ler isso durante o champ
# select, porque o lobby ja nao existe mais la - por isso o loop guarda o
# valor enquanto ainda da.
#
# Os nomes desses campos nao sao documentados e ja mudaram entre versoes do
# cliente, entao a sonda tenta mais de um. Nenhum encontrado devolve $null, e
# $null libera o pick.
function Get-LanesPedidas {
    $r = Invoke-Lcu -Session $script:Session -Path '/lol-lobby/v2/lobby'
    if ($r.Status -ne 200) { return $null }
    $lobby = ConvertFrom-LcuBody $r
    if (-not $lobby -or -not $lobby.localMember) { return $null }

    $m     = $lobby.localMember
    $lanes = $null
    foreach ($par in @(@('firstPositionPreference', 'secondPositionPreference'),
                       @('firstPreference',         'secondPreference'))) {
        $p1 = $m.($par[0])
        $p2 = $m.($par[1])
        if ($null -eq $p1 -and $null -eq $p2) { continue }

        $lanes = @()
        foreach ($p in @($p1, $p2)) {
            $n = ConvertTo-LaneNormal $p
            # FILL e UNSELECTED nao sao lane, sao "qualquer uma": quem pediu
            # isso nao pode ser surpreendido por autofill.
            if ($n -eq 'FILL' -or $n -eq 'UNSELECTED' -or $n -eq '') {
                $lanes = @('FILL'); break
            }
            $lanes += $n
        }
        break
    }
    if (-not $lanes) { return $null }

    # Escreve no log so quando muda. A leitura acontece a cada ~3s no lobby, e
    # repetir a mesma linha faria a HUD parecer travada nela.
    $chave = ($lanes -join ',')
    if ($chave -ne $script:LanesLogadas) {
        $script:LanesLogadas = $chave
        $texto = if ($lanes -contains 'FILL') { 'qualquer uma (fill)' } else { $lanes -join ' e ' }
        Write-Log ("Lanes pedidas: {0}." -f $texto) $C.Fraco
    }
    return $lanes
}

# $true = pode escolher. Todo caminho de duvida devolve $true, de proposito.
function Test-PickLiberado {
    param([string]$Atribuida)

    if ($IgnorarAutofill) { return $true }

    $a = ConvertTo-LaneNormal $Atribuida
    # Cega, ARAM e o que mais nao tem lane vem com o campo vazio.
    if ($a -eq '' -or $a -eq 'NONE') { return $true }

    # O Where-Object nao e enfeite: @($null) tem um item, nao zero, e sem ele
    # uma leitura falha do lobby viraria bloqueio em vez de liberacao.
    # Normalizo de novo aqui de proposito: a comparacao nao pode depender de
    # quem guardou a lista ter lembrado de normalizar antes.
    $pedidas = @($script:LanesPedidas | Where-Object { $_ } |
                 ForEach-Object { ConvertTo-LaneNormal $_ })
    if ($pedidas.Count -eq 0)      { return $true }
    if ($pedidas -contains 'FILL') { return $true }
    return ($pedidas -contains $a)
}

# ---------------------------------------------------------------------------
# Runas.
#
# Ao travar um campeao - no automatico ou na mao - o Ghost busca a runa mais
# jogada daquele campeao naquela lane e grava numa pagina sua.
#
# Duas regras de seguranca mandam no resto do desenho:
#
# 1. Ele so escreve na pagina cujo nome comeca com "Ghost". Sem ela, nao faz
#    nada e avisa. Sobrescrever uma pagina que voce montou a mao nao tem
#    desfazer, e um bug aqui custaria seu trabalho, nao o meu.
# 2. Ele EDITA a pagina no lugar (PUT), nunca apaga e recria. Apagar dando
#    certo e recriar falhando te deixaria com um slot a menos.
#
# Fonte: op.gg. Nao e API publica, e raspagem - o dia que eles mudarem a
# estrutura, quebra. Por isso existe a queda pra recomendacao da propria Riot,
# que vem do cliente e nao depende de internet: o recurso piora em vez de
# parar.
# ---------------------------------------------------------------------------

function ConvertTo-LaneOpGg {
    param([string]$Lane)
    switch (ConvertTo-LaneNormal $Lane) {
        'TOP'     { return 'top' }
        'JUNGLE'  { return 'jungle' }
        'MIDDLE'  { return 'mid' }
        'BOTTOM'  { return 'adc' }
        'UTILITY' { return 'support' }
        default   { return '' }
    }
}

# A busca sai num processo separado de proposito. Invoke-Lcu roda na thread da
# UI, o que serve pra resposta local de 2 KB - mas a pagina do op.gg tem ~640
# KB e viria de fora: fazer isso na mesma thread congelaria a HUD no meio da
# selecao, que e justo quando ela precisa responder.
function Start-BuscaRunaOpGg {
    param([string]$Alias, [string]$Lane)

    $pos = ConvertTo-LaneOpGg $Lane
    if (-not $pos -or -not $Alias) { return $null }

    $base = Join-Path $env:TEMP ('ghost-opgg-' + [guid]::NewGuid().ToString('N'))
    $arq  = "$base.html"
    $cfg  = "$base.curl"

    # Opcoes por arquivo (-K) em vez de linha de comando: o user-agent tem
    # espaco e parentese, e passar isso por Start-Process chega quebrado do
    # outro lado. Aqui nao tem quoting nenhum pra dar errado.
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
          '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
    $url = 'https://op.gg/lol/champions/{0}/build/{1}' -f $Alias.ToLowerInvariant(), $pos
    # Barra normal na saida, mesma pegadinha que Sync-Icones ja documenta:
    # dentro de aspas num arquivo -K o curl trata a barra invertida como
    # escape, e o caminho do Windows chega destruido. O sintoma engana -
    # HTTP 200, bytes baixados, e arquivo nenhum no disco.
    $linhas = @('silent', 'location', 'compressed', 'max-time = 12',
                ('user-agent = "{0}"' -f $ua),
                ('output = "{0}"' -f ($arq -replace '\\', '/')),
                ('url = "{0}"' -f $url))
    try { [System.IO.File]::WriteAllLines($cfg, $linhas, [System.Text.Encoding]::ASCII) }
    catch { return $null }

    try {
        $p = Start-Process -FilePath $script:Curl -ArgumentList @('-K', ('"{0}"' -f $cfg)) `
                 -NoNewWindow -PassThru -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue
        return $null
    }
    return [pscustomobject]@{ Proc = $p; Arquivo = $arq; Config = $cfg; Em = (Get-Date) }
}

function Remove-JobRuna {
    param($Job)
    if (-not $Job) { return }
    try { if (-not $Job.Proc.HasExited) { $Job.Proc.Kill() } } catch { }
    foreach ($f in @($Job.Arquivo, $Job.Config)) {
        if ($f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

# O op.gg e Next.js: os dados chegam escapados dentro do stream de render, nao
# num JSON solto na pagina. Mas o bloco que interessa e o mesmo que o botao
# "importar" deles manda pro cliente - ids ja prontos, sem nome de runa pra
# traduzir. Por isso da pra pegar com uma expressao regular em cima do HTML
# cru, sem remontar o stream inteiro.
#
# A barra invertida opcional no padrao cobre os dois casos: escapado dentro do
# stream (hoje) e JSON limpo, se um dia mudarem.
# O cliente aceita qualquer numero como id de runa - testei mandando 1,2,3 e
# ele gravou 1,2,3,-1,-1,-1 sem reclamar. Ou seja: quem tem que barrar lixo
# sou eu. Um casamento parcial da expressao regular do op.gg produziria ids
# fora de faixa, e eles iriam parar na pagina da pessoa.
#
# Faixas reais: estilo e 8000-8500; runa comum tem 4 digitos comecando em 8 ou
# 9; fragmento e 5001-5011.
function Test-RunaSensata {
    param($Runa)

    if (-not $Runa) { return $false }
    foreach ($e in @([int]$Runa.Primary, [int]$Runa.Sub)) {
        if ($e -lt 8000 -or $e -gt 8500) { return $false }
    }
    if ([int]$Runa.Primary -eq [int]$Runa.Sub) { return $false }

    $ids = @($Runa.Perks)
    if ($ids.Count -lt 6 -or $ids.Count -gt 12) { return $false }
    foreach ($i in $ids) {
        $n = [int]$i
        $comum     = ($n -ge 8000 -and $n -le 9999)
        $fragmento = ($n -ge 5001 -and $n -le 5011)
        if (-not ($comum -or $fragmento)) { return $false }
    }
    return $true
}

function Read-RunaOpGg {
    param([string]$Arquivo)

    if (-not $Arquivo -or -not (Test-Path -LiteralPath $Arquivo)) { return $null }
    try { $html = [System.IO.File]::ReadAllText($Arquivo) } catch { return $null }
    if ($html.Length -lt 2000) { return $null }   # pagina de erro ou bloqueio

    $re = '\\?"primaryStyleId\\?":(\d+),\\?"subStyleId\\?":(\d+),' +
          '\\?"selectedPerkIds\\?":\[([\d,]+)\]'
    # O primeiro casamento e o build mais jogado: o op.gg ja entrega em ordem
    # de pick rate.
    $m = [regex]::Match($html, $re)
    if (-not $m.Success) { return $null }

    $ids = @($m.Groups[3].Value -split ',' | ForEach-Object { [int]$_ })
    # 6 e o minimo plausivel (4 primarias + 2 secundarias); o normal sao 9 com
    # os fragmentos. Menos que isso e sinal de casamento parcial, nao de runa.
    if ($ids.Count -lt 6) { return $null }

    $runa = [pscustomobject]@{
        Primary = [int]$m.Groups[1].Value
        Sub     = [int]$m.Groups[2].Value
        Perks   = $ids
        Fonte   = 'op.gg'
    }
    if (-not (Test-RunaSensata $runa)) { return $null }
    return $runa
}

# A queda: a recomendacao da propria Riot, servida pelo cliente. Nao e a build
# de maior winrate, mas nao depende de internet nem de site nenhum no ar.
function Get-RunaRiot {
    param([int]$ChampId, [string]$Lane)

    $pos = ConvertTo-LaneNormal $Lane
    if (-not $pos) { $pos = 'NONE' }
    $r = Invoke-Lcu -Session $script:Session -Path `
             ('/lol-perks/v1/recommended-pages/champion/{0}/position/{1}/map/11' -f $ChampId, $pos)
    $d = @(ConvertFrom-LcuBody $r)
    if ($d.Count -eq 0 -or -not $d[0]) { return $null }

    $p   = $d[0]
    $ids = @($p.perks | ForEach-Object { [int]$_.id } | Where-Object { $_ -gt 0 })
    if ($ids.Count -lt 6) { return $null }

    $runa = [pscustomobject]@{
        Primary = [int]$p.primaryPerkStyleId
        Sub     = [int]$p.secondaryPerkStyleId
        Perks   = $ids
        Fonte   = 'Riot'
    }
    if (-not (Test-RunaSensata $runa)) { return $null }
    return $runa
}

function Set-RunaGhost {
    param($Runa, [string]$Campeao)

    # Segunda checagem de proposito. As duas fontes ja filtram, mas esta e a
    # unica funcao que escreve na conta da pessoa - ela nao confia em ninguem.
    if (-not (Test-RunaSensata $Runa)) { return $false }

    $pgs = @(ConvertFrom-LcuBody (Invoke-Lcu -Session $script:Session -Path '/lol-perks/v1/pages'))
    if ($pgs.Count -eq 0) { return $false }

    $alvo = @($pgs | Where-Object {
        $_.isEditable -and ([string]$_.name).StartsWith('Ghost',
            [System.StringComparison]::OrdinalIgnoreCase)
    })[0]
    if (-not $alvo) {
        if (-not $script:AvisouSemPagina) {
            $script:AvisouSemPagina = $true
            Write-Log 'Renomeie uma pagina de runa pra "Ghost" pra eu poder usar.' $C.Ambar
        }
        return $false
    }

    # O corpo vai pro curl em ASCII, e nome de campeao em portugues pode ter
    # acento - tiro antes pra nao gravar caractere trocado no nome da pagina.
    $limpo = ($Campeao -replace '[^\x20-\x7E]', '')
    $nome  = "Ghost Runa $limpo"
    # 50 e folga, nao limite do cliente: medi mandando 45 caracteres e ele
    # guardou os 45. O maior nome real e "Ghost Runa Nunu e Willump", 25 - o
    # corte em 24 que estava aqui antes era chute meu, e mutilava justo esse.
    if ($nome.Length -gt 50) { $nome = $nome.Substring(0, 50).TrimEnd() }

    $corpo = [pscustomobject]@{
        name            = $nome
        primaryStyleId  = [int]$Runa.Primary
        subStyleId      = [int]$Runa.Sub
        selectedPerkIds = @($Runa.Perks)
    } | ConvertTo-Json -Compress

    if ($Simular) {
        Write-Log ("SIMULADO: {0} pela {1}." -f $nome, $Runa.Fonte) $C.Azul
        return $true
    }

    $put = Invoke-Lcu -Session $script:Session -Method PUT -JsonBody $corpo `
               -Path ('/lol-perks/v1/pages/{0}' -f $alvo.id)
    if ($put.Status -lt 200 -or $put.Status -ge 300) {
        Write-Log ("Falhou ao gravar a runa (HTTP {0})." -f $put.Status) $C.Vermelho
        return $false
    }

    # Gravar nao seleciona. Sem este segundo PUT voce entra na partida com a
    # pagina que estava marcada antes - com a runa certa gravada e nao usada,
    # que e o pior dos dois mundos.
    [void](Invoke-Lcu -Session $script:Session -Method PUT -JsonBody ([string][int]$alvo.id) `
               -Path '/lol-perks/v1/currentpage')

    Write-Log ("Runa aplicada: {0} pela {1}." -f $nome, $Runa.Fonte) $C.Verde
    return $true
}

# Maquina de estado, chamada a cada tick da selecao. Nao trava a UI em momento
# nenhum: comeca a busca num tick e colhe o resultado em outro.
function Update-Runa {
    param($Sessao)

    if (-not $script:AutoRuna) { return }

    $eu = [int]$Sessao.localPlayerCellId
    if ($eu -lt 0) { return }

    $champ = 0
    $lane  = ''
    foreach ($p in @($Sessao.myTeam)) {
        if ([int]$p.cellId -eq $eu) {
            $champ = [int]$p.championId
            $lane  = [string]$p.assignedPosition
            break
        }
    }
    # championId so fica diferente de zero quando o campeao esta travado, o que
    # serve igual pro pick automatico e pro que voce escolheu na mao.
    if ($champ -le 0) { return }

    $chave = '{0}|{1}' -f $champ, (ConvertTo-LaneNormal $lane)
    if ($chave -eq $script:RunaFeitaPara) { return }

    # A lista de campeoes era carregada so ao abrir a janela de Campeoes, que
    # e por onde se monta fila de pick e de ban. A runa nao precisa de fila
    # nenhuma: quem so liga a runa nunca abria aquela janela, e chegava aqui
    # com a lista vazia. O estrago era duplo - o nome da pagina saia
    # "campeao 103" em vez de "Ahri", e sem alias a busca no op.gg nem
    # comecava, caindo calada na recomendacao da Riot.
    #
    # Carregar aqui custa uma chamada local, uma vez por sessao: a funcao sai
    # na primeira linha se a lista ja estiver em pe.
    [void](Import-Campeoes)

    $nome = Get-NomeCampeao $champ

    # 1. Ja busquei isso nesta sessao do app.
    if ($script:CacheRunas.ContainsKey($chave)) {
        [void](Set-RunaGhost -Runa $script:CacheRunas[$chave] -Campeao $nome)
        $script:RunaFeitaPara = $chave   # deu ou nao, nao insiste a cada tick
        return
    }

    # 2. Busca em andamento: so olho se ja terminou.
    if ($script:RunaJob) {
        $venceu = ((Get-Date) - $script:RunaJob.Em).TotalSeconds -gt 15
        $pronto = $false
        try { $pronto = $script:RunaJob.Proc.HasExited } catch { $pronto = $true }
        if (-not $pronto -and -not $venceu) { return }

        $runa = if ($pronto -and -not $venceu) { Read-RunaOpGg $script:RunaJob.Arquivo } else { $null }
        Remove-JobRuna $script:RunaJob
        $script:RunaJob = $null

        if (-not $runa) {
            Write-Log 'op.gg nao respondeu. Usando a recomendada da Riot.' $C.Ambar
            $runa = Get-RunaRiot -ChampId $champ -Lane $lane
        }
        if ($runa) { $script:CacheRunas[$chave] = $runa }
        else {
            Write-Log ("Nao achei runa pra {0}." -f $nome) $C.Ambar
            $script:RunaFeitaPara = $chave
            return
        }
        [void](Set-RunaGhost -Runa $runa -Campeao $nome)
        $script:RunaFeitaPara = $chave
        return
    }

    # 3. Comeca a busca.
    $alias = $null
    if ($script:PorId.ContainsKey($champ)) { $alias = $script:PorId[$champ].Alias }
    $script:RunaJob = Start-BuscaRunaOpGg -Alias $alias -Lane $lane
    if (-not $script:RunaJob) {
        # Sem lane (cega, ARAM) ou sem alias: vai direto pra Riot.
        $runa = Get-RunaRiot -ChampId $champ -Lane $lane
        if ($runa) { $script:CacheRunas[$chave] = $runa; [void](Set-RunaGhost -Runa $runa -Campeao $nome) }
        else { Write-Log ("Nao achei runa pra {0}." -f $nome) $C.Ambar }
        $script:RunaFeitaPara = $chave
        return
    }
    Write-Log ("Buscando runa de {0} no op.gg..." -f $nome) $C.Fraco
}

function Set-AcaoSelecao {
    param([int]$AcaoId, [int]$CampeaoId, [switch]$Travar)

    $corpo = if ($Travar) { '{"championId":' + $CampeaoId + ',"completed":true}' }
             else         { '{"championId":' + $CampeaoId + '}' }

    if ($Simular) { return $true }   # modo simulacao: so o log, sem mexer no jogo

    $r = Invoke-Lcu -Session $script:Session -Method PATCH `
             -Path ("/lol-champ-select/v1/session/actions/{0}" -f $AcaoId) -JsonBody $corpo
    return ($r.Status -ge 200 -and $r.Status -lt 300)
}

function Invoke-SelecaoCampeao {
    if (-not ($script:AutoPick -or $script:AutoBan -or $script:AutoRuna)) { return }

    $r = Invoke-Lcu -Session $script:Session -Path '/lol-champ-select/v1/session'
    if ($r.Status -ne 200) {
        # 404 "No active delegate" = fora do champ select. Zera o hover pra
        # proxima selecao nao comecar achando que ja passou o mouse em algo.
        $script:HoverId = 0; $script:HoverEm = $null
        $script:RunaFeitaPara = ''
        if ($script:RunaJob) { Remove-JobRuna $script:RunaJob; $script:RunaJob = $null }
        if ($script:AutofillBloqueado) {
            $script:AutofillBloqueado = $false
            Update-BotoesSelecao
        }
        return
    }
    $s = ConvertFrom-LcuBody $r
    if (-not $s) { return }

    # Antes do pick e do ban: a runa vale mesmo quando os dois estao
    # desligados e voce escolheu o campeao na mao.
    Update-Runa -Sessao $s

    $eu = [int]$s.localPlayerCellId
    if ($eu -lt 0) { return }   # -1 = espectador, nao tem vez pra jogar

    # As acoes vem em grupos, na ordem em que acontecem. O grupo da vez e o
    # primeiro que ainda tem alguma coisa incompleta; so nele a minha acao
    # pode ser executada.
    $minha = $null
    foreach ($grupo in $s.actions) {
        $abertas = @($grupo | Where-Object { -not $_.completed })
        if ($abertas.Count -eq 0) { continue }
        $minha = $abertas | Where-Object { [int]$_.actorCellId -eq $eu } | Select-Object -First 1
        break
    }
    if (-not $minha) { return }   # nao e a minha vez

    # Campeao ja fechado por alguem (banido ou escolhido) nao pode ser repetido.
    # Os que aliados so estao passando o mouse tambem saem da lista de pick,
    # pra nao roubar a escolha de quem ja sinalizou.
    $ocupados = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($grupo in $s.actions) {
        foreach ($a in $grupo) {
            $cid = [int]$a.championId
            if ($cid -le 0) { continue }
            if ($a.completed) { [void]$ocupados.Add($cid) }
            elseif ([int]$a.actorCellId -ne $eu -and $a.type -eq 'pick') { [void]$ocupados.Add($cid) }
        }
    }

    $acaoId = [int]$minha.id
    $marca  = if ($Simular) { 'SIMULADO: ' } else { '' }

    # ---- banir ----
    if ($minha.type -eq 'ban') {
        if (-not $script:AutoBan) { return }
        $alvo = @($script:Bans | Where-Object { -not $ocupados.Contains($_) })[0]
        if (-not $alvo) {
            Write-Log 'Sua vez de banir - a fila acabou.' $C.Ambar
            return
        }
        if (Set-AcaoSelecao -AcaoId $acaoId -CampeaoId $alvo -Travar) {
            Write-Log ("{0}Banido: {1}." -f $marca, (Get-NomeCampeao $alvo)) $C.Azul
        }
        else {
            Write-Log ("Falhou ao banir {0}." -f (Get-NomeCampeao $alvo)) $C.Vermelho
        }
        return
    }

    # ---- escolher ----
    if ($minha.type -ne 'pick' -or -not $script:AutoPick) { return }

    # A lane veio no myTeam, na minha propria celula. Se nao e uma das que eu
    # pedi, a fila de pick foi montada pensando em outra coisa e nao serve
    # aqui: melhor nao escolher nada do que travar o campeao errado.
    $minhaLane = ''
    foreach ($p in @($s.myTeam)) {
        if ([int]$p.cellId -eq $eu) { $minhaLane = [string]$p.assignedPosition; break }
    }
    if (-not (Test-PickLiberado -Atribuida $minhaLane)) {
        if (-not $script:AutofillBloqueado) {
            $script:AutofillBloqueado = $true
            Update-BotoesSelecao
            Write-Log ("Autofill: {0}. Auto-pick parado - escolha na mao." -f (Get-NomeLane $minhaLane)) $C.Ambar
        }
        return
    }
    if ($script:AutofillBloqueado) {
        $script:AutofillBloqueado = $false
        Update-BotoesSelecao
    }

    $alvo = @($script:Picks | Where-Object { -not $ocupados.Contains($_) })[0]
    if (-not $alvo) {
        Write-Log 'Sua vez de escolher - a fila acabou.' $C.Ambar
        return
    }

    # Passa o mouse primeiro e trava depois, em vez de trancar de cara: o
    # hover avisa o time o que voce vai pegar, e ate travar da tempo de mudar
    # de ideia na mao. -SegundosAteTravar 0 volta ao comportamento de instalock.
    if ($script:HoverId -ne $alvo) {
        if (Set-AcaoSelecao -AcaoId $acaoId -CampeaoId $alvo) {
            $script:HoverId = $alvo
            $script:HoverEm = Get-Date
            Write-Log ("{0}{1} marcado." -f $marca, (Get-NomeCampeao $alvo)) $C.Verde
        }
        return
    }

    $decorrido = ((Get-Date) - $script:HoverEm).TotalSeconds
    $falta     = [int][math]::Ceiling($SegundosAteTravar - $decorrido)
    if ($falta -gt 0) {
        Write-Log ("{0} - travando em {1}s" -f (Get-NomeCampeao $alvo), $falta) $C.Verde
        return
    }

    if (Set-AcaoSelecao -AcaoId $acaoId -CampeaoId $alvo -Travar) {
        Write-Log ("{0}Travado: {1}." -f $marca, (Get-NomeCampeao $alvo)) $C.Verde
    }
    else {
        Write-Log ("Falhou ao travar {0}." -f (Get-NomeCampeao $alvo)) $C.Vermelho
    }
    $script:HoverId = 0
    $script:HoverEm = $null
}

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
    $script:Fase         = $null
    $script:AceitarEm    = $null
    $titulo.Text         = 'cliente fechado'
    $dot.ForeColor       = $C.Vermelho
    Update-BotoesStatus
    Update-Fase
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
        $cada3s = $script:MsLento / $IntervaloMs

        if (-not $script:Session) {
            # Reconectar e caro (consulta WMI): so tenta a cada ~3s.
            if (($script:Tick % $cada3s) -ne 0) { return }
            if (Connect-Cliente) { Write-Log 'Conectado ao cliente.' $C.Verde }
            return
        }

        # Ready check: so consulta se o auto-aceitar estiver ligado, e no ritmo
        # rapido so nas fases em que ready check pode acontecer. Em selecao de
        # campeao e em partida - as fases longas - cai pro ritmo lento
        # ($script:MsLento), que continua como rede de seguranca caso a fase
        # lida esteja atrasada em relacao ao cliente.
        $rapido = Test-RitmoRapido
        if ($script:AutoAceitar -and ($rapido -or ($script:Tick % $cada3s) -eq 0)) {
            $rc = Invoke-Lcu -Session $script:Session -Path '/lol-matchmaking/v1/ready-check'

            if ($rc.Status -eq 0 -or $rc.Status -eq 401) {
                Disconnect-Cliente; Write-Log 'Perdi o cliente.' $C.Vermelho; return
            }

            if ($rc.Status -eq 200) {
                $j = ConvertFrom-LcuBody $rc
                # playerResponse = 'None' evita repetir POST depois de aceitar.
                if ($j -and $j.state -eq 'InProgress' -and $j.playerResponse -eq 'None') {
                    if (-not $script:AceitarEm) {
                        Write-Log 'PARTIDA ENCONTRADA!' $C.Verde
                        $script:AceitarEm = (Get-Date).AddSeconds($AtrasoSegundos)
                    }

                    # Contagem por relogio, e nao por Start-Sleep: dormir aqui e
                    # dormir na thread da UI. A HUD congelaria e os atalhos
                    # parariam de responder justo nos segundos que importam.
                    $falta = [int][math]::Ceiling(($script:AceitarEm - (Get-Date)).TotalSeconds)
                    if ($falta -gt 0) {
                        Write-Log ("Aceitando em {0}s..." -f $falta) $C.Verde
                    }
                    else {
                        $ok = Invoke-Lcu -Session $script:Session `
                                  -Path '/lol-matchmaking/v1/ready-check/accept' -Method POST
                        $script:AceitarEm = $null
                        if ($ok.Status -ge 200 -and $ok.Status -lt 300) {
                            Write-Log 'Aceito.' $C.Verde
                        }
                        else {
                            Write-Log 'FALHOU - ACEITE NA MAO!' $C.Vermelho
                        }
                    }
                }
                else { $script:AceitarEm = $null }
            }
            # 404 aqui e normal: "Not attached to a matchmaking queue".
            else { $script:AceitarEm = $null }
        }

        # Selecao de campeao: so entra quando o cliente esta mesmo nessa fase.
        if ($script:Fase -eq 'ChampSelect') { Invoke-SelecaoCampeao }

        # A cada ~3s: fase do cliente e status do chat.
        if (($script:Tick % $cada3s) -eq 0) {
            # A fase vem primeiro: e ela que decide o ritmo da checagem acima.
            # A resposta e uma string JSON crua ("Lobby"), nao um objeto - por
            # isso tiro as aspas na mao em vez de passar pelo ConvertFrom-Json.
            $fase = Invoke-Lcu -Session $script:Session -Path '/lol-gameflow/v1/gameflow-phase'
            if ($fase.Status -eq 0 -or $fase.Status -eq 401) { Disconnect-Cliente; return }
            if ($fase.Status -eq 200) {
                $nova = ($fase.Body -as [string]).Trim().Trim('"')
                if ($nova -ne $script:Fase) { $script:Fase = $nova; Update-Fase }
            }

            # As lanes pedidas so existem no lobby, e o gate de autofill
            # precisa delas la no champ select - entao leio enquanto da e
            # guardo. Em Matchmaking a escolha ja esta fechada; fora de fila
            # zero, pra proxima fila nao herdar a preferencia da anterior.
            if ($script:Fase -eq 'Lobby') {
                $lanes = Get-LanesPedidas
                $script:LanesPedidas = if ($lanes) { @($lanes) } else { @() }
            }
            elseif ($script:Fase -eq 'None') {
                $script:LanesPedidas = @()
                $script:LanesLogadas = $null
            }

            $chat = Invoke-Lcu -Session $script:Session -Path '/lol-chat/v1/me'
            if ($chat.Status -eq 0 -or $chat.Status -eq 401) { Disconnect-Cliente; return }
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
    Update-LayoutHud
    Update-BotaoAuto
    Update-BotoesStatus
    Update-BotoesSelecao
    Update-Fase

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
        $fase = Invoke-Lcu -Session $script:Session -Path '/lol-gameflow/v1/gameflow-phase'
        if ($fase.Status -eq 200) {
            $script:Fase = ($fase.Body -as [string]).Trim().Trim('"')
            Update-Fase
        }
        if ($Simular) { Write-Log 'SIMULACAO: nao vou mexer na selecao.' $C.Ambar }
        else           { Write-Log 'Pronto.' $C.Verde }
    }
    else {
        Disconnect-Cliente
        Write-Log 'Esperando o cliente do LoL abrir...' $C.Ambar
    }

    $timer.Start()
})

# FormClosing e nao FormClosed: aqui o Handle ainda existe pra desregistrar.
$form.Add_FormClosing({
    # Guarda onde a janela ficou e como o auto-aceitar estava, pra proxima vez.
    Export-Config -X $form.Location.X -Y $form.Location.Y -Auto $script:AutoAceitar

    [void][HotkeyFilter]::UnregisterHotKey($form.Handle, $script:HK_AUTO)
    [void][HotkeyFilter]::UnregisterHotKey($form.Handle, $script:HK_OFFLINE)
    [System.Windows.Forms.Application]::RemoveMessageFilter($script:Hotkeys)
    $timer.Stop()
})

$form.Add_FormClosed({
    $timer.Dispose()
    # Devolve o console so pra quem rodou de um terminal aberto (ver secao 0).
    if ($script:ConsoleVisivel) { [void][Win32Console]::ShowWindow($hConsole, 5) }  # SW_SHOW
})

# A tela de abertura vem antes da HUD: e ela que decide o que a HUD tem.
# Cancelar ali fecha o programa sem abrir janela nenhuma - quem cancelou
# nao pediu pra continuar.
Sync-Automacoes
$abrir = $true
if (-not $Direto) { $abrir = Show-JanelaSetup }
if ($abrir) { [void]$form.ShowDialog() }

# Solta o mutex depois da janela fechar. Sem isso uma reabertura rapida ainda
# encontraria a instancia "aberta" ate o processo morrer de vez.
if ($script:Mutex) {
    try { $script:Mutex.ReleaseMutex() } catch { }
    $script:Mutex.Dispose()
}
