@echo off
setlocal enabledelayedexpansion

chcp 65001 > nul
set "LOG_FILE=%~dp0setup_log.txt"

powershell -Command "$bom = [System.Text.Encoding]::UTF8.GetPreamble(); [System.IO.File]::WriteAllBytes('!LOG_FILE!', $bom)"
(
    echo Starting log at %TIME% on %DATE%
    echo. & echo === SCRIPT STARTED ===
    echo Script path: %~dp0
    echo Current directory: %cd%
    echo. & echo --- Initial Environment Variables --- & set & echo.
) >> "!LOG_FILE!"

call :main >> "!LOG_FILE!" 2>&1
exit /b

:: ============================================================================
:: Основной блок скрипта
:: ============================================================================
:main
:: --- 1. Определение языка ---
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-UICulture).Name"') do set "SYS_LANG=%%a"

if "!SYS_LANG:~0,2!"=="ru" (
    set "PROMPT_ADMIN=[ОШИБКА] Требуются права администратора."
    set "PROMPT_WARN_MISSING=[ВНИМАНИЕ] Не найдены основные файлы скрипта."
    set "PROMPT_CONFIRM_DOWNLOAD=Попробовать скачать полный пакет с GitHub? (Y/N): "
    set "PROMPT_CANCEL=Установка отменена."
    set "INFO_DOWNLOADING=Скачивание последней версии..."
    set "INFO_INSTALL_TO=Установка в:"
    set "INFO_DIR_CREATED=Целевая директория создана."
    set "INFO_COPYING=Копирование файлов..."
    set "INFO_ALIASES=Создание алиасов (set-java, javas, jav)..."
    set "INFO_PATH=Добавление в системный PATH..."
    set "INFO_PATH_EXISTS=Путь уже добавлен в системный PATH. Пропускаем."
    set "INFO_SUCCESS=--- Установка успешно завершена! ---"
    set "INFO_OPENING=Открытие Java Version Manager в новом окне Терминала Windows..."
) else (
    set "PROMPT_ADMIN=[ERROR] Administrator rights are required."
    set "PROMPT_WARN_MISSING=[WARN] Core script files not found."
    set "PROMPT_CONFIRM_DOWNLOAD=Attempt to download the full package from GitHub? (Y/N): "
    set "PROMPT_CANCEL=Installation cancelled."
    set "INFO_DOWNLOADING=Downloading the latest version..."
    set "INFO_INSTALL_TO=Installing to:"
    set "INFO_DIR_CREATED=Target directory created."
    set "INFO_COPYING=Copying files..."
    set "INFO_ALIASES=Creating aliases (set-java, javas, jav)..."
    set "INFO_PATH=Adding to system PATH..."
    set "INFO_PATH_EXISTS=Path is already in system PATH. Skipping."
    set "INFO_SUCCESS=--- Installation completed successfully! ---"
    set "INFO_OPENING=Opening Java Version Manager in a new Windows Terminal window..."
)
echo !TITLE_INSTALLER! & echo.

:: --- 2. Проверка прав администратора ---
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' ( echo. & echo !PROMPT_ADMIN! & echo. & pause & exit /b )

:: --- 3. Проверка наличия файлов и восстановление ---
set "SRC_DIR=%~dp0"
if not exist "%SRC_DIR%set-java.ps1" ( set "SRC_DIR=%~dp0src\" )
if not exist "%SRC_DIR%set-java.ps1" (
    echo. & echo !PROMPT_WARN_MISSING! & echo.
    set /p "CHOICE=!PROMPT_CONFIRM_DOWNLOAD!"
    if /i "!CHOICE!" neq "Y" ( echo !PROMPT_CANCEL! & pause & exit /b )
    echo !INFO_DOWNLOADING!
    set "TEMP_DIR=%TEMP%\jman-recovery"
    if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
    md "%TEMP_DIR%"
    powershell -NoProfile -Command "& { (New-Object Net.WebClient).DownloadFile('https://github.com/PixelmonPRO/Java-Version-Manager/releases/latest/download/java-manager.zip', '%TEMP_DIR%\release.zip') }" >nul 2>&1
    echo !INFO_UNPACKING!
    powershell -NoProfile -Command "Expand-Archive -Path '%TEMP_DIR%\release.zip' -DestinationPath '%TEMP_DIR%' -Force" >nul 2>&1
    set "SRC_DIR=%TEMP_DIR%\src\"
)

:: --- 4. Основная логика установки ---
set "config_file=!SRC_DIR!config.json"
set "java_install_path="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-Content -Path '!config_file!' -Raw | ConvertFrom-Json).javaInstallPath"`) do set "java_install_path=%%i"

if not defined java_install_path ( set "java_install_path=%ProgramFiles%\Java" )

set "scripts_target_dir=!java_install_path!\scripts"
echo !INFO_INSTALL_TO! "!scripts_target_dir!" & echo.
if not exist "!scripts_target_dir!" ( mkdir "!scripts_target_dir!" & echo !INFO_DIR_CREATED! )

echo !INFO_COPYING!
xcopy "!SRC_DIR!*" "!scripts_target_dir!\" /E /I /Y /Q >nul

echo !INFO_ALIASES!
(echo @echo off & echo chcp 65001 ^>nul & echo powershell -NoProfile -ExecutionPolicy Bypass -File "!scripts_target_dir!\set-java.ps1" %*) > "!scripts_target_dir!\set-java.bat"
(echo @echo off & echo chcp 65001 ^>nul & echo powershell -NoProfile -ExecutionPolicy Bypass -File "!scripts_target_dir!\set-java.ps1" %*) > "!scripts_target_dir!\javas.bat"
(echo @echo off & echo chcp 65001 ^>nul & echo powershell -NoProfile -ExecutionPolicy Bypass -File "!scripts_target_dir!\set-java.ps1" %*) > "!scripts_target_dir!\jav.bat"

echo !INFO_PATH!
powershell -NoProfile -Command "$regPath = 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment'; $currentPath = (Get-ItemProperty -Path $regPath -Name Path).Path; $newDir = '!scripts_target_dir!'; if(-not ($currentPath.ToLower() -split ';' -contains $newDir.ToLower())) { $newPath = $currentPath + ';' + $newDir; Set-ItemProperty -Path $regPath -Name Path -Value $newPath; echo 'Path updated.' } else { echo '!INFO_PATH_EXISTS!' }"

:: --- 5. Завершение и запуск ---
echo. & echo !INFO_SUCCESS! & echo. & echo !INFO_OPENING!
start wt.exe powershell.exe -NoExit -Command "& '!scripts_target_dir!\set-java.bat'"
goto :eof