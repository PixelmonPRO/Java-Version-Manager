@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Установщик Java Version Manager (v1.5 - Усиленная сетевая логика)
:: ============================================================================

:: --- Шаг 1: Настройка и очистка лога ---
chcp 65001 > nul
set "LOG_FILE=%~dp0setup_log.txt"
(
    echo Starting log at %TIME% on %DATE%
    echo. & echo === SCRIPT STARTED ===
    echo Script path: %~dp0
    echo Current directory: %cd% & echo.
) > "!LOG_FILE!"

:: --- Шаг 2: Локализация ---
call :localize
call :log_and_echo "!TITLE_INSTALLER!"
echo.

:: --- Шаг 3: Проверка прав администратора ---
net session >nul 2>&1
if errorlevel 1 (
    call :log_and_echo "!PROMPT_ADMIN!"
    pause
    exit /b
)

:: --- Шаг 4: Проверка наличия файлов и восстановление ---
set "SRC_DIR=%~dp0src\"
if exist "%SRC_DIR%set-java.ps1" (
    goto :install_main
)

call :recover_files
if errorlevel 1 (
    pause
    exit /b
)

:: --- Шаг 5: Основная логика установки ---
:install_main
set "java_install_path="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-Content -Path '!SRC_DIR!config.json' -Raw | ConvertFrom-Json).javaInstallPath" 2^>nul`) do (
  set "java_install_path=%%i"
)
if not defined java_install_path set "java_install_path=%ProgramFiles%\Java"
set "scripts_target_dir=%java_install_path%\scripts"

call :log_and_echo "!INFO_INSTALL_TO! -> !scripts_target_dir!"
if not exist "!scripts_target_dir!" ( mkdir "!scripts_target_dir!" & call :log_and_echo "!INFO_DIR_CREATED!" )

call :log_and_echo "!INFO_COPYING!"
xcopy "!SRC_DIR!*" "!scripts_target_dir!\" /E /I /Y /Q >nul

call :log_and_echo "!INFO_ALIASES!"
(
  echo @echo off
  echo chcp 65001 ^>nul
  echo powershell -NoProfile -ExecutionPolicy Bypass -File "%scripts_target_dir%\set-java.ps1" %%*
) > "%scripts_target_dir%\set-java.bat"
copy /y "%scripts_target_dir%\set-java.bat" "%scripts_target_dir%\javas.bat" >nul
copy /y "%scripts_target_dir%\set-java.bat" "%scripts_target_dir%\jav.bat" >nul

call :log_and_echo "!INFO_PATH!"
powershell -NoProfile -Command ^
 "$regKey='HKLM:\System\CurrentControlSet\Control\Session Manager\Environment'; $p=(Get-ItemProperty -Path $regKey).Path; $t='%scripts_target_dir%'; if($p -notlike '*'+$t+'*'){Set-ItemProperty -Path $regKey -Name Path -Value ($p+';'+$t); Write-Host 'Path updated.'} else{Write-Host '!INFO_PATH_EXISTS!'}" >> "!LOG_FILE!"

echo. & call :log_and_echo "!INFO_SUCCESS!" & call :log_and_echo "!INFO_RESTART!" & echo.
pause

:: --- Шаг 6: Открытие нового терминала с запущенным set-java ---
where wt.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start wt.exe powershell.exe -NoExit -Command "& '%scripts_target_dir%\set-java.bat'"
) else (
    start cmd.exe /k "!scripts_target_dir!\set-java.bat"
)

exit /b

:: ============================================================================
:: ПОДПРОГРАММЫ
:: ============================================================================

:log_and_echo
(echo [%TIME%] %*) >> "!LOG_FILE!"
echo %*
goto :eof

:localize
set "SYS_LANG=en"
for /f "tokens=3" %%a in ('reg query "HKCU\Control Panel\International" /v LocaleName 2^>nul') do ( set "SYS_LANG=%%a" )
if "!SYS_LANG:~0,2!"=="ru" (
    set "TITLE_INSTALLER=--- Установщик Java Version Manager ---"
    set "PROMPT_ADMIN=[ОШИБКА] Требуются права администратора."
    set "PROMPT_WARN_MISSING=[ВНИМАНИЕ] Не найдены основные файлы скрипта."
    set "PROMPT_CONFIRM_DOWNLOAD=Попробовать скачать полный пакет с GitHub? (Y/N): "
    set "PROMPT_CANCEL=Установка отменена."
    set "INFO_DOWNLOADING=Скачивание последней версии..."
    set "INFO_UNPACKING=Распаковка..."
    set "INFO_INSTALL_TO=Установка в:"
    set "INFO_DIR_CREATED=Целевая директория создана."
    set "INFO_COPYING=Копирование файлов..."
    set "INFO_ALIASES=Создание алиасов (set-java, javas, jav)..."
    set "INFO_PATH=Добавление в системный PATH..."
    set "INFO_PATH_EXISTS=Путь уже добавлен в системный PATH. Пропускаем."
    set "INFO_SUCCESS=--- Установка успешно завершена! ---"
    set "INFO_RESTART=Перезапустите терминал, чтобы применить изменения."
    set "INFO_OPENING=Открытие Java Version Manager в новом окне Терминала Windows..."
) else (
    set "TITLE_INSTALLER=--- Java Version Manager Installer ---"
    set "PROMPT_ADMIN=[ERROR] Administrator rights are required."
    set "PROMPT_WARN_MISSING=[WARN] Core script files not found."
    set "PROMPT_CONFIRM_DOWNLOAD=Attempt to download the full package from GitHub? (Y/N): "
    set "PROMPT_CANCEL=Installation cancelled."
    set "INFO_DOWNLOADING=Downloading the latest version..."
    set "INFO_UNPACKING=Unpacking..."
    set "INFO_INSTALL_TO=Installing to:"
    set "INFO_DIR_CREATED=Target directory created."
    set "INFO_COPYING=Copying files..."
    set "INFO_ALIASES=Creating aliases (set-java, javas, jav)..."
    set "INFO_PATH=Adding to system PATH..."
    set "INFO_PATH_EXISTS=Path is already in system PATH. Skipping."
    set "INFO_SUCCESS=--- Installation completed successfully! ---"
    set "INFO_RESTART=Please restart your terminal for changes to take effect."
    set "INFO_OPENING=Opening Java Version Manager in a new Windows Terminal window..."
)
goto :eof

:recover_files
call :log_and_echo "!PROMPT_WARN_MISSING!"
set /p "CHOICE=!PROMPT_CONFIRM_DOWNLOAD!"
if /I "!CHOICE!" NEQ "Y" ( call :log_and_echo "!PROMPT_CANCEL!" & exit /b 1 )

set "TEMP_DIR=%TEMP%\jman-recovery"
set "ZIP_PATH=%TEMP_DIR%\release.zip"
set "EXTRACT_DIR=%TEMP_DIR%\extracted"

if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
md "%TEMP_DIR%" & md "%EXTRACT_DIR%"

call :log_and_echo "!INFO_DOWNLOADING! & !INFO_UNPACKING!"...

:: Проверка наличия curl
where curl >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    :: Используем curl для скачивания
    curl -L --ssl-no-revoke -o "%ZIP_PATH%" "https://github.com/PixelmonPRO/Java-Version-Manager/releases/latest/download/java-manager.zip"
    if errorlevel 1 (
        call :log_and_echo "[ERROR] curl failed to download file."
        exit /b 1
    )
) else (
    :: fallback к PowerShell (с TLS 1.2 и User-Agent)
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
     "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls; " ^
     "try { " ^
     " Invoke-WebRequest -Uri 'https://github.com/PixelmonPRO/Java-Version-Manager/releases/latest/download/java-manager.zip' -OutFile '%ZIP_PATH%' -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US)' } -ErrorAction Stop; " ^
     " Add-Type -AssemblyName System.IO.Compression.FileSystem; " ^
     " [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_PATH%', '%EXTRACT_DIR%'); " ^
     "} catch { " ^
     " $logPath = '%LOG_FILE%'; " ^
     " '--- POWERSHELL ERROR ---' | Out-File -FilePath $logPath -Append -Encoding utf8; " ^
     " $_.Exception.ToString() | Out-File -FilePath $logPath -Append -Encoding utf8; " ^
     " if ($_.Exception.InnerException) { " ^
     "  '--- INNER EXCEPTION ---' | Out-File -FilePath $logPath -Append -Encoding utf8; " ^
     "  $_.Exception.InnerException.ToString() | Out-File -FilePath $logPath -Append -Encoding utf8; " ^
     " } " ^
     " exit 1; " ^
     "}"
)

if errorlevel 1 ( call :log_and_echo "!PROMPT_DOWNLOAD_FAIL!" & exit /b 1 )

:: Распаковка zip файла
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Add-Type -AssemblyName System.IO.Compression.FileSystem; " ^
 "try { [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_PATH%', '%EXTRACT_DIR%');  } catch { exit 1 }"
if errorlevel 1 (
    call :log_and_echo "[ERROR] Failed to extract downloaded archive."
    exit /b 1
)

if not exist "%EXTRACT_DIR%\src\config.json" (
    call :log_and_echo "!PROMPT_STRUCTURE_FAIL!"
    exit /b 1
)

set "SRC_DIR=%EXTRACT_DIR%\src\"
call :log_and_echo "!INFO_DOWNLOAD_SUCCESS!"

exit /b
