@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM ============================================================
REM  Deploy-Printer.cmd
REM  Deploys a TCP/IP printer via an existing print driver.
REM  Designed for Intune deployment (Win32 app or remediation).
REM
REM  Author  : Dillon Iverson
REM  Version : 1.1
REM
REM  REQUIREMENTS:
REM    - Print driver must already be installed before running
REM    - Supports Version-3 and Version-4 drivers
REM    - Run as SYSTEM
REM
REM  INTUNE DETECTION:
REM    Marker file written on success:
REM    C:\ProgramData\IntuneScripts\Printers\printer_<PORT>.json
REM ============================================================

REM ====== CONFIG ======
set "PRINTER_NAME=WorkRoom Printer"
set "PRINTER_IP=10.0.0.210"
set "DRIVER_NAME=HP Universal Printing PCL 6"
REM ====================

set "BASEDIR=C:\ProgramData\IntuneScripts\Printers"
set "MARKFILE=%BASEDIR%\printer_%PRINTER_IP:.=_%\.json"
set "LOGFILE=%BASEDIR%\printer_%PRINTER_IP:.=_%_log.txt"
set "PORT_NAME=IP_%PRINTER_IP:.=_%"

REM --- If marker exists, already installed ---
if exist "%MARKFILE%" exit /b 0

REM --- Ensure base directory exists ---
if not exist "%BASEDIR%" mkdir "%BASEDIR%" >nul 2>&1

REM --- Start log ---
echo [%date% %time%] Starting printer deployment: %PRINTER_NAME% (%PRINTER_IP%) >> "%LOGFILE%"

REM --- Ensure spooler is running ---
sc query spooler | find "RUNNING" >nul
if errorlevel 1 (
    echo [%date% %time%] Spooler not running, attempting start... >> "%LOGFILE%"
    net start spooler >nul 2>&1
)
echo [%date% %time%] Spooler running. >> "%LOGFILE%"

REM --- Ensure driver exists (Version-3 or Version-4) ---
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-3\%DRIVER_NAME%" >nul 2>&1
if errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-4\%DRIVER_NAME%" >nul 2>&1
    if errorlevel 1 (
        echo [%date% %time%] ERROR: Driver not found: %DRIVER_NAME% >> "%LOGFILE%"
        exit /b 1
    )
)
echo [%date% %time%] Driver verified: %DRIVER_NAME% >> "%LOGFILE%"

REM --- Create TCP/IP port (ignore if exists) ---
cscript //nologo "%WINDIR%\System32\Printing_Admin_Scripts\en-US\prnport.vbs" ^
    -a -r "%PORT_NAME%" -h "%PRINTER_IP%" -o raw -n 9100 >nul 2>&1
echo [%date% %time%] Port created or already exists: %PORT_NAME% >> "%LOGFILE%"

REM --- Add printer ---
rundll32 printui.dll,PrintUIEntry ^
    /if /q /b "%PRINTER_NAME%" ^
    /r "%PORT_NAME%" ^
    /m "%DRIVER_NAME%" >nul 2>&1
echo [%date% %time%] Printer add command executed. >> "%LOGFILE%"

REM --- Give spooler a moment to register ---
timeout /t 3 /nobreak >nul

REM --- Verify port registry key ---
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports\%PORT_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] ERROR: Port registry key not found after install. >> "%LOGFILE%"
    exit /b 1
)

REM --- Verify printer registry key ---
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Print\Printers\%PRINTER_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] ERROR: Printer registry key not found after install. >> "%LOGFILE%"
    exit /b 1
)

REM --- Write marker JSON (note: timestamp format may vary by locale) ---
echo [%date% %time%] Writing marker file: %MARKFILE% >> "%LOGFILE%"
> "%MARKFILE%" (
    echo { "app":"printer", "status":"installed", "name":"%PRINTER_NAME%", "ip":"%PRINTER_IP%", "port":"%PORT_NAME%", "timestamp":"%date% %time%" }
)

echo [%date% %time%] Deployment complete: %PRINTER_NAME% >> "%LOGFILE%"
exit /b 0
