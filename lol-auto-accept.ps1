#Requires -Version 5.1
<#
.SYNOPSIS
    Aceita automaticamente o ready check (partida encontrada) do League of Legends.

.DESCRIPTION
    Conversa com a LCU API: a API REST local que o proprio cliente do LoL expoe
    em https://127.0.0.1:<porta>. Nao le memoria do jogo, nao move o mouse, nao
    procura pixel na tela. Faz o mesmo POST que o botao "Aceitar" faz.

    Como descobre porta e senha:
    o cliente grava um arquivo "lockfile" na pasta de instalacao, no formato
    LeagueClient:PID:PORTA:SENHA:https . A senha muda a cada vez que o cliente
    abre, entao nada fica hardcoded aqui.

    Por que curl.exe e nao Invoke-RestMethod:
    o LCU exige TLS 1.3. O PowerShell 5.1 roda sobre .NET Framework, que nao
    fecha handshake TLS 1.3 (o valor Tls13 existe no enum mas nao funciona) -
    testado, da "conexao subjacente fechada". O curl.exe ja vem no Windows 10
    1803+ e no Windows 11, e conecta sem problema.

    Obs: comentarios e mensagens sem acento de proposito. O PowerShell 5.1 le
    arquivo .ps1 sem BOM como ANSI, e acento viraria caractere quebrado.

.PARAMETER IntervaloMs
    De quanto em quanto tempo perguntar ao cliente. 700ms sobra: o ready check
    dura ~12 segundos.

.PARAMETER AtrasoSegundos
    Espera N segundos antes de aceitar. Util pra nao aceitar em 0ms sempre.

.EXAMPLE
    .\lol-auto-accept.ps1

.EXAMPLE
    .\lol-auto-accept.ps1 -AtrasoSegundos 3
#>
[CmdletBinding()]
param(
    [ValidateRange(200, 5000)] [int] $IntervaloMs    = 700,
    [ValidateRange(0, 10)]     [int] $AtrasoSegundos = 0
)

# ---------------------------------------------------------------------------
# 0. Pre-requisito: curl.exe
#    Atencao: em PS 5.1 "curl" e alias de Invoke-WebRequest. Tem que ser
#    curl.exe com o .exe explicito, senao chama a coisa errada.
# ---------------------------------------------------------------------------
$CurlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $CurlPath) {
    Write-Host 'curl.exe nao encontrado. Ele vem no Windows 10 1803+ / Windows 11.' -ForegroundColor Red
    Write-Host 'Alternativa: instalar PowerShell 7 e adaptar para Invoke-RestMethod -SkipCertificateCheck.' -ForegroundColor DarkGray
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Achar o lockfile
# ---------------------------------------------------------------------------
function Get-LockfilePath {
    # Caminho mais confiavel: tirar da linha de comando do processo do cliente.
    # Funciona mesmo se o jogo estiver instalado em outro disco.
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
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }

    return $null
}

# O cliente mantem o lockfile aberto. Get-Content simples pode dar
# "arquivo em uso por outro processo", entao abro com FileShare ReadWrite.
function Read-LockfileRaw {
    param([Parameter(Mandatory)][string] $Path)

    $fs = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    }
    finally { $fs.Dispose() }
}

# Devolve Port + Password, ou $null se o cliente nao esta rodando.
function Get-LcuSession {
    $path = Get-LockfilePath
    if (-not $path) { return $null }

    try   { $raw = Read-LockfileRaw -Path $path }
    catch { return $null }

    $parts = $raw.Trim() -split ':'
    if ($parts.Count -lt 4) { return $null }

    return [pscustomobject]@{
        Port     = $parts[2]
        Password = $parts[3]   # usuario e sempre "riot"
    }
}

# ---------------------------------------------------------------------------
# 2. Chamada generica na LCU
#    Devolve Status (0 = nem conectou) e Body.
#    A senha vai no -u, ou seja, aparece na linha de comando do processo curl
#    por instantes. Numa maquina pessoal isso nao muda nada, e ela expira
#    quando o cliente fecha.
# ---------------------------------------------------------------------------
function Invoke-Lcu {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)][string] $Path,
        [ValidateSet('GET', 'POST')][string] $Method = 'GET'
    )

    $curlArgs = @(
        '-s',                                   # silencioso: sem barra de progresso, sem texto de erro
        '-k',                                   # certificado do cliente e auto-assinado (Riot Games CA)
        '--max-time', '6',
        '-u', "riot:$($Session.Password)",
        '-w', '\n%{http_code}'                  # ultima linha da saida = codigo HTTP
    )
    if ($Method -eq 'POST') {
        $curlArgs += @('-X', 'POST', '-H', 'Content-Type: application/json', '-d', '{}')
    }
    $curlArgs += "https://127.0.0.1:$($Session.Port)$Path"

    $lines = @(& $script:CurlPath @curlArgs)

    if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) {
        return [pscustomobject]@{ Status = 0; Body = $null }
    }

    $status = 0
    [void][int]::TryParse(($lines[-1] -as [string]).Trim(), [ref]$status)
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)] -join '') } else { '' }

    return [pscustomobject]@{ Status = $status; Body = $body }
}

# Retorna: objeto JSON | 'none' (404, sem ready check) | 'down' (cliente fechou)
function Get-ReadyCheck {
    param([Parameter(Mandatory)] $Session)

    $r = Invoke-Lcu -Session $Session -Path '/lol-matchmaking/v1/ready-check'

    if ($r.Status -eq 0)   { return 'down' }
    if ($r.Status -eq 404) { return 'none' }   # normal: nao tem partida encontrada
    if ($r.Status -ne 200) { return 'none' }

    try   { return ($r.Body | ConvertFrom-Json) }
    catch { return 'none' }
}

function Invoke-Accept {
    param([Parameter(Mandatory)] $Session)

    $r = Invoke-Lcu -Session $Session `
                    -Path '/lol-matchmaking/v1/ready-check/accept' -Method POST
    return ($r.Status -ge 200 -and $r.Status -lt 300)
}

# ---------------------------------------------------------------------------
# 3. Loop principal
# ---------------------------------------------------------------------------
function Write-Status {
    param([string] $Texto, [string] $Cor = 'Gray')
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Texto) -ForegroundColor $Cor
}

Write-Host ''
Write-Host '  LoL auto-accept  ' -ForegroundColor Black -BackgroundColor Cyan
Write-Host ("  intervalo {0}ms | atraso ao aceitar {1}s" -f $IntervaloMs, $AtrasoSegundos) -ForegroundColor DarkGray
Write-Host '  Ctrl+C para parar.' -ForegroundColor DarkGray
Write-Host ''

$session      = $null
$avisouEspera = $false   # pra nao repetir a mesma linha no console
$avisouFila   = $false

while ($true) {

    # (Re)conecta se ainda nao tem sessao, ou se o cliente caiu e reabriu.
    if (-not $session) {
        $session = Get-LcuSession
        if (-not $session) {
            if (-not $avisouEspera) {
                Write-Status 'Cliente do LoL nao encontrado. Esperando abrir...' 'DarkYellow'
                $avisouEspera = $true
            }
            Start-Sleep -Seconds 3
            continue
        }

        $eu = Invoke-Lcu -Session $session -Path '/lol-summoner/v1/current-summoner'
        if ($eu.Status -eq 200) {
            $s = $eu.Body | ConvertFrom-Json
            Write-Status ("Conectado como {0}#{1} (porta {2})." -f $s.gameName, $s.tagLine, $session.Port) 'Green'
        }
        else {
            # Acontece nos primeiros segundos: processo no ar, API ainda subindo.
            Write-Status 'Cliente achado, mas a API ainda nao respondeu. Tentando de novo...' 'DarkYellow'
            $session = $null
            Start-Sleep -Seconds 3
            continue
        }

        $avisouEspera = $false
        $avisouFila   = $false
    }

    $rc = Get-ReadyCheck -Session $session

    if ($rc -eq 'down') {
        Write-Status 'Perdi a conexao com o cliente. Vou reconectar.' 'DarkYellow'
        $session = $null
        Start-Sleep -Seconds 2
        continue
    }

    if ($rc -eq 'none') {
        if (-not $avisouFila) {
            Write-Status 'Aguardando partida...' 'DarkGray'
            $avisouFila = $true
        }
        Start-Sleep -Milliseconds $IntervaloMs
        continue
    }

    # Tem ready check ativo.
    # state:          'InProgress' enquanto a janela de aceite esta aberta
    # playerResponse: 'None' = ainda nao respondi | 'Accepted' | 'Declined'
    if ($rc.state -eq 'InProgress' -and $rc.playerResponse -eq 'None') {

        Write-Status 'PARTIDA ENCONTRADA!' 'Cyan'

        if ($AtrasoSegundos -gt 0) {
            Write-Status ("Aceitando em {0}s..." -f $AtrasoSegundos) 'DarkGray'
            Start-Sleep -Seconds $AtrasoSegundos
        }

        if (Invoke-Accept -Session $session) {
            Write-Status 'Aceito.' 'Green'
        }
        else {
            Write-Status 'Falhei em aceitar. ACEITE NA MAO AGORA.' 'Red'
        }

        $avisouFila = $false
    }

    Start-Sleep -Milliseconds $IntervaloMs
}
