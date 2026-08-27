@echo off
rem Sobe a HUD e devolve o prompt na hora.
rem   start ""            desgruda do cmd, senao a janela preta fica aberta
rem                       do lado da HUD ate ela fechar
rem   -WindowStyle Hidden evita o console do PowerShell piscar atras
rem   %~dp0               pasta deste .bat, e nao a pasta atual: assim
rem                       funciona chamado de qualquer lugar
rem   %*                  repassa parametros (-AutoAceitarLigado, -AtrasoSegundos N)
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ghost.ps1" %*
