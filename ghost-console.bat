@echo off
rem Sobe a HUD com o console a mostra, ao contrario do ghost.bat.
rem Serve pra quando o script nao abre e voce quer ver o erro.
rem   %~dp0   pasta deste .bat, e nao a pasta atual: sem isso, clicar duas
rem           vezes de um atalho em outro lugar nao acha o ghost.ps1
rem   %*      repassa parametros (-Simular, -Direto, -Runas:$false)
rem   pause   segura a janela aberta: sem ele, script que estoura na
rem           primeira linha fecha o console antes de voce ler o motivo
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ghost.ps1" %*
pause
