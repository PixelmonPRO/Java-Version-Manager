![Java Version Manager Logo](docs/images/banner.gif)

# Java Version Manager [set-java]

![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![OS](https://img.shields.io/badge/OS-Windows-blue.svg)

---

### 🇺🇸 English
**Java Version Manager** is a powerful PowerShell script for Windows that simplifies finding, installing, switching, and managing multiple JDK/JRE versions from various providers.

#### ✨ Key Features

* **Multi-Provider Support:** Works with Azul Zulu, Adoptium Temurin, Amazon Corretto, BellSoft Liberica, Oracle GraalVM, and more.
* **Installation:** Find and install the required Java version in just a few clicks.
* **Version Switching:** Instantly switch the active `JAVA_HOME` for the current session or the entire system.
* **Updates:** Automatically find and install minor updates for your installed JDKs.
* **Cleanup:** Uninstall old versions with smart `Path` variable cleaning.
* **IDE Integration:** Synchronize installed JDKs with your IntelliJ IDEA configuration and remove orphaned entries.
* **Security:** Verifies the integrity of downloaded archives using SHA256 checksums.

#### 🚀 Installation (Step-by-Step)
1. **Download:** Go to the [Releases](https://github.com/PixelmonPRO/Java-Version-Manager/releases) page (on the right side of the repository) and download the latest `java-manager.zip` file.
2. **Unzip:** Locate the downloaded zip file, right-click it, and select **"Extract All..."**. Extract it to any folder (e.g., your Desktop or Downloads).
   * *Important: Do not run files directly from inside the zip archive without extracting them first.*
3. **Run Setup:** Open the extracted folder. Find the `setup.bat` file. Right-click it and select **"Run as administrator"**.
   * *Why Admin?* The script needs permission to copy files to `Program Files` and update your system `Path` variable so you can use the command from anywhere.
   * *SmartScreen Warning:* If Windows prevents the startup, click **"More info"** and then **"Run anyway"**.
4. **Finish:** The script will automatically install the tool to `C:\Program Files\Java\scripts`.
5. **Restart:** Close **ALL** currently open terminal windows (Command Prompt, PowerShell, Windows Terminal, IDEs). Open a new terminal to apply changes.

After this, the `set-java`, `javas`, or `jav` commands will be available system-wide.

#### 🎮 Usage
**Interactive Mode (Menu):**
Simply type this command in your terminal:
```powershell
set-java
```

**Non-Interactive Mode (Examples):**
```powershell
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

---

### 🇷🇺 Русский

**Java Version Manager** — это мощный PowerShell-скрипт для Windows, который упрощает поиск, установку, переключение и управление несколькими версиями JDK/JRE от разных поставщиков.

#### ✨ Ключевые возможности
* **Мульти-провайдер:** Поддержка Azul Zulu, Adoptium Temurin, Amazon Corretto, BellSoft Liberica, Oracle GraalVM и других.
* **Установка:** Поиск и установка нужной версии Java в несколько кликов.
* **Переключение:** Мгновенное переключение активной версии `JAVA_HOME` для сессии или для всей системы.
* **Обновление:** Автоматический поиск и установка минорных обновлений для установленных JDK.
* **Очистка:** Удаление старых версий и "умная" очистка переменной `Path`.
* **Интеграция с IDE:** Синхронизация установленных JDK с конфигурацией IntelliJ IDEA, удаление "осиротевших" записей.
* **Безопасность:** Проверка целостности скачиваемых архивов по контрольной сумме SHA256.

#### 🚀 Подробная установка
1. **Скачивание:** Перейдите на страницу [Releases](https://github.com/PixelmonPRO/Java-Version-Manager/releases) (раздел "Releases" справа на странице) и скачайте последний файл `java-manager.zip`.
2. **Распаковка:** Найдите скачанный архив, нажмите на него правой кнопкой мыши и выберите **"Извлечь все..."**. Распакуйте файлы в любую удобную папку (например, на Рабочий стол).
* *Важно: Не запускайте файлы прямо из архива, сначала обязательно распакуйте их.*
3. **Запуск установки:** Откройте папку с распакованными файлами. Найдите файл `setup.bat`. Нажмите на него правой кнопкой мыши и выберите **"Запуск от имени администратора"**.
* *Зачем права админа?* Скрипт копирует файлы в `Program Files` и прописывает путь к программе в систему, чтобы команда работала везде.
* *SmartScreen:* Если Windows покажет синее окно "Система защитила ваш компьютер", нажмите **"Подробнее"**, а затем **"Выполнить в любом случае"**.
4. **Завершение:** Скрипт скопирует все необходимые файлы в `C:\Program Files\Java\scripts`.
5. **Перезапуск:** Закройте **ВСЕ** открытые окна терминалов (CMD, PowerShell, IDE). Откройте новый терминал, чтобы изменения вступили в силу.

После этого вам будут доступны команды `set-java`, `javas` или `jav` из любой точки системы.

#### 🎮 Использование
**Интерактивный режим (меню):**
Просто введите команду в терминале:

```powershell
set-java
```

**Неинтерактивный режим (примеры):**
```powershell
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