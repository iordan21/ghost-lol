@echo off
setlocal EnableExtensions
title LoL - ficar offline

:: ==========================================================================
::  Corta a conexao do chat do LoL pelo Firewall do Windows.
::  Voce fica offline pra todo mundo - e tambem sem receber nada.
::  Pra voltar: ficar_online.bat
::  Sem acento de proposito: o console do cmd nao usa a mesma tabela do editor.
:: ==========================================================================

set "REGRA=LoL Offline - chat"
set "ANTIGA1=lolchat"
set "ANTIGA2=lolchat2"

:: --------------------------------------------------------------------------
::  1. Administrador
::  netsh advfirewall so cria regra elevado. Sem esta checagem a regra falha
::  e o script diz que voce esta invisivel do mesmo jeito - foi o que a
::  versao antiga fazia.
:: --------------------------------------------------------------------------
fltmc >nul 2>&1
if errorlevel 1 (
    echo Pedindo permissao de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
    if errorlevel 1 (
        echo.
        echo Permissao negada. Nada foi alterado - voce continua ONLINE.
        echo.
        pause
    )
    exit /b
)

:: --------------------------------------------------------------------------
::  2. O firewall esta ligado?
::  Regra de bloqueio em firewall desligado nao bloqueia nada. Aviso, nao erro:
::  o perfil pode ser reativado depois.
:: --------------------------------------------------------------------------
powershell -NoProfile -Command "if ((Get-NetFirewallProfile -PolicyStore ActiveStore | Where-Object { $_.Enabled }).Count -eq 0) { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo.
    echo AVISO: o Firewall do Windows esta desligado em todos os perfis.
    echo A regra vai ser criada, mas so vale quando o firewall estiver ligado.
    echo.
)

:: --------------------------------------------------------------------------
::  3. Limpa antes de criar
::  O netsh aceita varias regras com o mesmo nome: rodar duas vezes empilharia
::  duplicata. Tambem remove os nomes da versao antiga, se sobraram na maquina.
:: --------------------------------------------------------------------------
netsh advfirewall firewall delete rule name="%REGRA%"   >nul 2>&1
netsh advfirewall firewall delete rule name="%ANTIGA1%" >nul 2>&1
netsh advfirewall firewall delete rule name="%ANTIGA2%" >nul 2>&1

:: --------------------------------------------------------------------------
::  4. Bloqueia a porta do chat
::  5223 e a porta do XMPP com TLS - por onde o chat do LoL fala. So ela
::  basta. A versao antiga bloqueava tambem o range 172.65.0.0/16, que e da
::  Cloudflare: derrubaria junto qualquer outro servico hospedado la.
:: --------------------------------------------------------------------------
netsh advfirewall firewall add rule name="%REGRA%" dir=out action=block protocol=TCP remoteport=5223 >nul

:: --------------------------------------------------------------------------
::  5. Confere que a regra existe mesmo antes de dizer que deu certo
:: --------------------------------------------------------------------------
netsh advfirewall firewall show rule name="%REGRA%" >nul 2>&1
if errorlevel 1 (
    echo.
    echo FALHOU: a regra nao foi criada. Voce continua ONLINE.
    echo.
    pause
    exit /b 1
)

echo.
echo   Regra criada e confirmada: "%REGRA%"
echo   Voce esta INVISIVEL no LoL.
echo.
echo   O chat fica fora do ar por completo: nao chega mensagem nem
echo   convite de grupo enquanto isso valer.
echo.
echo   A regra sobrevive a reiniciar o PC. Rode ficar_online.bat pra soltar.
echo.
pause
