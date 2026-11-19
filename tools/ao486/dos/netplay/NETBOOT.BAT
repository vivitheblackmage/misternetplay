@ECHO OFF
REM Netplay for the MiSTer ao486 core. AUTOEXEC.BAT calls this with BOOT:
REM with the network card on the PC asks online or single player (single
REM player after 10 s); single player and a card that is off go on booting
REM as before, nothing loaded. NP.BAT calls it without BOOT: then the menu
REM comes up at once.
REM The drivers are loaded once: loading them again resets the card under
REM the loaded driver and nothing is received any more. No environment
REM variables (the ready-made disks have no room left for them): the check
REM writes NPLOAD.BAT, F10 leaves NPSKIP.FLG for AUTOEXEC.BAT.
IF EXIST C:\NETPLAY\NPSKIP.FLG DEL C:\NETPLAY\NPSKIP.FLG
IF "%1"=="BOOT" GOTO BOOT
C:\NETPLAY\NPMENU.EXE /CHECK
IF ERRORLEVEL 1 GOTO LOAD
GOTO MENU
:BOOT
C:\NETPLAY\NPMENU.EXE /BOOT
IF ERRORLEVEL 1 GOTO LOAD
GOTO END
:LOAD
IF EXIST C:\NETPLAY\NPLOAD.BAT CALL C:\NETPLAY\NPLOAD.BAT
:MENU
C:\NETPLAY\NPMENU.EXE
IF ERRORLEVEL 3 GOTO DOS
IF ERRORLEVEL 2 GOTO RUN
GOTO END
:RUN
CALL C:\NETPLAY\RUN.BAT
GOTO MENU
:DOS
ECHO.>C:\NETPLAY\NPSKIP.FLG
:END
