# Java Version Manager [set-java]

![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![OS](https://img.shields.io/badge/OS-Windows-blue.svg)

---

### 🇷🇺 Русский

**Java Version Manager** — это мощный PowerShell-скрипт для Windows, который упрощает поиск, установку, переключение и управление несколькими версиями JDK/JRE от разных поставщиков.

#### ✨ Ключевые возможности

*   **Мульти-провайдер:** Поддержка Azul Zulu, Adoptium Temurin, Amazon Corretto, Oracle GraalVM и других.
*   **Установка:** Поиск и установка нужной версии Java в несколько кликов.
*   **Переключение:** Мгновенное переключение активной версии `JAVA_HOME` для сессии или для всей системы.
*   **Обновление:** Автоматический поиск и установка минорных обновлений для установленных JDK.
*   **Очистка:** Удаление старых версий и "умная" очистка переменной `Path`.
*   **Интеграция с IDE:** Синхронизация установленных JDK с конфигурацией IntelliJ IDEA, удаление "осиротевших" записей.
*   **Безопасность:** Проверка целостности скачиваемых архивов по контрольной сумме SHA256.

#### 🚀 Установка

1.  Скачайте последний релиз со страницы [Releases](https://github.com/PixelmonPRO/Java-Version-Manager/releases).
2.  Распакуйте архив в любую временную папку.
3.  Щелкните правой кнопкой мыши по файлу `setup.bat` и выберите **"Запуск от имени администратора"**.
4.  Скрипт скопирует все необходимые файлы в `C:\Program Files\Java\scripts` и добавит эту папку в системный `Path`.
5.  **Перезапустите ваш терминал (CMD / PowerShell / другие).**

После этого вам будут доступны команды `set-java`, `javas` или `jav` из любой точки системы.

#### 🎮 Использование

**Интерактивный режим (меню):**
```
set-java
```

**Неинтерактивный режим (примеры):**
```
# Показать доступные для установки версии Java 21 от Adoptium
set-java --list 21 --provider "Eclipse Adoptium (Temurin)"

# Установить последнюю версию Java 17 от Azul Zulu и сделать ее системной
set-java --install 17 --provider "Azul Zulu" --permanent

# Переключить активную версию на уже установленную
set-java --switch "zulu21.32.17-ca-fx-jdk21.0.2-win_x64"

# Обновить все установленные JDK до последних минорных версий
set-java --update --force

# Синхронизировать JDK в IntelliJ IDEA
set-java --clean-ide --force
```
---

### 🇺🇸 English

**Java Version Manager** is a powerful PowerShell script for Windows that simplifies finding, installing, switching, and managing multiple JDK/JRE versions from various providers.

#### ✨ Key Features

*   **Multi-Provider Support:** Works with Azul Zulu, Adoptium Temurin, Amazon Corretto, Oracle GraalVM, and more.
*   **Installation:** Find and install the required Java version in just a few clicks.
*   **Version Switching:** Instantly switch the active `JAVA_HOME` for the current session or the entire system.
*   **Updates:** Automatically find and install minor updates for your installed JDKs.
*   **Cleanup:** Uninstall old versions with smart `Path` variable cleaning.
*   **IDE Integration:** Synchronize installed JDKs with your IntelliJ IDEA configuration and remove orphaned entries.
*   **Security:** Verifies the integrity of downloaded archives using SHA256 checksums.

#### 🚀 Installation

1.  Download the latest release from the [Releases](https://github.com/PixelmonPRO/Java-Version-Manager/releases) page.
2.  Unzip the archive to any temporary folder.
3.  Right-click on `setup.bat` and select **"Run as administrator"**.
4.  The script will copy all necessary files to `C:\Program Files\Java\scripts` and add this directory to the system `Path`.
5.  **Restart your terminal (CMD/PowerShell/etc).**

After this, the `set-java`, `javas`, and `jav` commands will be available system-wide.

#### 🎮 Usage

**Interactive Mode (Menu):**
```
set-java
```

**Non-Interactive Mode (Examples):**
```
# List available Java 21 versions from Adoptium
set-java --list 21 --provider "Eclipse Adoptium (Temurin)"

# Install the latest Java 17 from Azul Zulu and set it as the system default
set-java --install 17 --provider "Azul Zulu" --permanent

# Switch the active version to an already installed one
set-java --switch "zulu21.32.17-ca-fx-jdk21.0.2-win_x64"

# Update all installed JDKs to their latest minor versions
set-java --update --force

# Synchronize JDKs with IntelliJ IDEA
set-java --clean-ide --force
```