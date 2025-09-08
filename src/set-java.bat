@echo off
rem Этот скрипт является оберткой для удобного вызова set-java.ps1 из командной строки cmd.

rem Устанавливаем кодовую страницу UTF-8 для корректного отображения в текущем окне cmd.
chcp 65001 > nul

rem Прямой вызов ps1-файла. Это гарантирует, что переменная $PSScriptRoot будет определена корректно.
rem %* передает все аргументы, полученные этим bat-файлом, дальше в PowerShell-скрипт.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-java.ps1" %*
