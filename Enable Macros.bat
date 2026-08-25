@echo off

setlocal EnableExtensions EnableDelayedExpansion
title Environment Setup

:: Get ANSI ESC character
for /F "delims=" %%E in ('echo prompt $E^| cmd') do set "ESC=%%E"

set "GREEN=!ESC![92m"
set "RED=!ESC![91m"
set "YELLOW=!ESC![93m"
set "GRAY=!ESC![90m"
set "RESET=!ESC![0m"

echo.
echo !GRAY!  Environment Setup!RESET!
echo !GRAY!  -----------------!RESET!
echo.


echo [33m:: ===================================================[0m
echo [33m:: Instalador de Powershell y Habilitador de Macros[0m
echo [33m:: ===================================================[0m
echo [33m:: Desarrollado por Rodrigo Jimenez[0m
echo [36m:: ======================== Revisando dependencias de powershell ===============================[0m

where pwsh >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%i in ('where pwsh') do set "PSPATH=%%i"
) else (
    :: Buscar en rutas comunes
    if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PSPATH=%ProgramFiles%\PowerShell\7\pwsh.exe"
    if exist "%LOCALAPPDATA%\Microsoft\PowerShell\7\pwsh.exe" set "PSPATH=%LOCALAPPDATA%\Microsoft\PowerShell\7\pwsh.exe"
)

if defined PSPATH (
    echo PowerShell encontrado en: %PSPATH%
    pwsh -NoProfile -Command "Write-Host 'PowerShell Funcionando correctamente' -ForegroundColor Green"
) else (
    echo [31mPowerShell no encontrado. Instalando...[0m
    winget install --id Microsoft.PowerShell --scope user --accept-package-agreements --accept-source-agreements -e
)

:: ==================================================
:: Python 3.14
:: ==================================================

set "PYTHON_DIR=%LocalAppData%\Programs\Python\Python314"
set "PYTHON_EXE=%PYTHON_DIR%\python.exe"

echo.
echo !GRAY!  Python 3.14!RESET!

:: --------------------------------------------------
:: Check existing installation
:: --------------------------------------------------

if exist "%PYTHON_EXE%" (
    "%PYTHON_EXE%" --version >nul 2>&1

    if !errorlevel! equ 0 (
        echo !GREEN!  [OK]!RESET! Python 3.14
        goto :PYTHON_DONE
    )
)

echo !RED!  [MISSING]!RESET! Python 3.14

:: --------------------------------------------------
:: Install Python Install Manager
:: --------------------------------------------------

where py >nul 2>&1

if !errorlevel! neq 0 (
    echo !YELLOW!  [....]!RESET! Installing Python Install Manager...

    winget install 9NQ7512CXL7T -e ^
        --accept-package-agreements ^
        --accept-source-agreements ^
        --disable-interactivity

    if !errorlevel! neq 0 (
        echo !RED!  [FAIL]!RESET! Python Install Manager installation failed
        goto :END
    )
)

:: --------------------------------------------------
:: Install Python 3.14 into LocalAppData
:: --------------------------------------------------

echo !YELLOW!  [....]!RESET! Installing Python 3.14...

py install 3.14 --target="%PYTHON_DIR%"

if !errorlevel! neq 0 (
    echo !RED!  [FAIL]!RESET! Python 3.14 installation failed
    goto :END
)

:: --------------------------------------------------
:: Verify
:: --------------------------------------------------

if not exist "%PYTHON_EXE%" (
    echo !RED!  [FAIL]!RESET! Python was not found at:
    echo         %PYTHON_EXE%
    goto :END
)

"%PYTHON_EXE%" --version >nul 2>&1

if !errorlevel! neq 0 (
    echo !RED!  [FAIL]!RESET! Python executable cannot run
    goto :END
)

echo !GREEN!  [OK]!RESET! Python 3.14 installed
echo !GRAY!       %PYTHON_EXE%!RESET!

:PYTHON_DONE


:: ==================================================
:: pip
:: ==================================================


echo.
echo !GRAY!  PIP!RESET!

:: Check if Python 3.14 launcher / command works directly
"%LocalAppData%\Programs\Python\Python314\python.exe" -m pip --version >nul 2>&1


if !errorlevel! neq 0 (
    echo !RED!  [MISSING]!RESET! PIP
    echo !YELLOW!  [....]!RESET! Installing...

"%LocalAppData%\Programs\Python\Python314\python.exe" -m ensurepip

if !errorlevel! equ 0 (
        echo !GREEN!  [OK]!RESET! PIP installed
    ) else (
        echo !YELLOW!  [WARN]!RESET! PIP installation failed
        goto :END
    )
) else (
    echo !GREEN!  [OK]!RESET! PIP 3.14
)


:: ==================================================
:: Dependencies
:: ==================================================

for %%P in (
    pikepdf
    reportlab
    pandas
    websocket-client
) do (
    "%LocalAppData%\Programs\Python\Python314\python.exe" -m pip show %%P >nul 2>&1

    if !errorlevel! equ 0 (
        echo !GREEN!  [OK]!RESET! %%P
    ) else (
        echo !YELLOW!  [....]!RESET! Installing %%P...

        "%LocalAppData%\Programs\Python\Python314\python.exe" -m pip install %%P ^
            --disable-pip-version-check >nul 2>&1

        if !errorlevel! equ 0 (
            echo !GREEN!  [OK]!RESET! %%P
        ) else (
            echo !YELLOW!  [WARN]!RESET! %%P installation failed
        )
    )
)

:: ==================================================
:: Done
:: ==================================================

echo.
echo !GRAY!  -----------------!RESET!
echo !GREEN!  Done.!RESET!
echo.

:END
endlocal



echo [36m:: ======================== HABILITAR MACROS ===============================[0m
:: Obtener carpeta donde está el BAT
set "CURRENT_FOLDER=%~dp0"
:: Eliminar barra final
if "%CURRENT_FOLDER:~-1%"=="\" set "CURRENT_FOLDER=%CURRENT_FOLDER:~0,-1%"

echo Carpeta actual del script: %CURRENT_FOLDER%

:: Ruta del registro para trusted locations de Excel
set "REG_PATH=HKCU\Software\Microsoft\Office\16.0\Excel\Security\Trusted Locations"

:: Buscar el último LocationX
set NEXT=1
for /f "tokens=*" %%i in ('reg query "%REG_PATH%" 2^>nul ^| findstr /r /c:"Location[0-9]*"') do (
    set "LAST_LOC=%%~nxi"
)

if defined LAST_LOC (
    :: Extraer solo el número de LocationX
    for /f "tokens=2 delims=Location" %%n in ("%LAST_LOC%") do set /a NEXT=%%n+1
)

echo Siguiente Location: %NEXT%

:: Añadir trusted location
echo Añadiendo %CURRENT_FOLDER% a lugares de confianza...
reg add "%REG_PATH%\Location%NEXT%" /v Path /t REG_SZ /d "%CURRENT_FOLDER%" /f
echo Añadiendo Subcarpetas a lugares de confianza...
reg add "%REG_PATH%\Location%NEXT%" /v AllowSubFolders /t REG_DWORD /d 1 /f

echo [32mMacros activadas en: %CURRENT_FOLDER%[0m
echo ya puede cerrar la ventana u oprima ENTER
pause
