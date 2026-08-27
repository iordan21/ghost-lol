@echo off
setlocal EnableExtensions
title LoL - voltar online

:: ==========================================================================
::  Remove as regras de firewall criadas pelo ficar_offline.bat e devolve
::  o chat do LoL. Limpa tambem os nomes da versao antiga.
:: ==========================================================================

set "REGRA=LoL Offline - chat"
set "ANTIGA1=lolchat"
set "ANTIGA2=lolchat2"

:: --------------------------------------------------------------------------
::  1. Administrador - remover regra exige elevacao igual criar.
:: --------------------------------------------------------------------------
fltmc >nul 2>&1
if errorlevel 1 (
    echo Pedindo permissao de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
    if errorlevel 1 (
        echo.
        echo Permissao negada. As regras continuam ativas - voce segue OFFLINE.
        echo.
        pause
    )
    exit /b
)

:: --------------------------------------------------------------------------
::  2. Remove. "delete rule" devolve erro quando nao existe regra com o nome,
::     e isso e normal aqui - por isso o erro vai pro nada.
:: --------------------------------------------------------------------------
netsh advfirewall firewall delete rule name="%REGRA%"   >nul 2>&1
netsh advfirewall firewall delete rule name="%ANTIGA1%" >nul 2>&1
netsh advfirewall firewall delete rule name="%ANTIGA2%" >nul 2>&1

:: --------------------------------------------------------------------------
::  3. Confere que nenhuma sobrou. "show rule" com codigo 0 = ainda existe.
:: --------------------------------------------------------------------------
set "SOBROU="
for %%R in ("%REGRA%" "%ANTIGA1%" "%ANTIGA2%") do (
    netsh advfirewall firewall show rule name=%%R >nul 2>&1
    if not errorlevel 1 set "SOBROU=%%~R"
)

if defined SOBROU (
    echo.
    echo FALHOU: a regra "%SOBROU%" ainda existe. Voce continua OFFLINE.
    echo.
    pause
    exit /b 1
)

echo.
echo   Nenhuma regra de bloqueio restante.
echo   Voce esta ONLINE no LoL.
echo.
echo   Se o cliente ja estava aberto, o chat pode levar alguns segundos
echo   pra reconectar sozinho.
echo.
pause
