<#
.SYNOPSIS
  Интерактивный и неинтерактивный скрипт для управления версиями Java от разных поставщиков в Windows.

.DESCRIPTION
  Скрипт предоставляет меню для управления версиями Java (Azul Zulu, Adoptium, Corretto, Oracle GraalVM и др.), а также поддерживает аргументы командной строки для автоматизации. Ключевые возможности: поиск, скачивание и установка OpenJDK от разных поставщиков; переключение между установленными версиями; удаление версий с "умной" очисткой переменной Path; обновление установленных версий до последнего минорного релиза; синхронизация (добавление новых и удаление старых) JDK в конфигурации IntelliJ IDEA; проверка целостности скачаемых файлов по SHA256.

.EXAMPLE
  # Запуск в интерактивном режиме с меню
  .\set-java.ps1

.EXAMPLE
  # Установить последнюю версию Java 21 от Oracle GraalVM и сделать её системной
  .\set-java.ps1 --install 21 --provider "Oracle GraalVM (for JDK 17+)" --permanent

.EXAMPLE
  # Синхронизировать JDK в IntelliJ IDEA (добавить новые, удалить старые)
  .\set-java.ps1 --clean-ide --force
#>

# Принудительная установка кодировки консоли на UTF-8 для корректной работы с кириллицей
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# --- Параметры командной строки ---
param(
    [string]$List,
    [string]$Install,
    [string]$Switch,
    [string]$Uninstall,
    [string]$Provider,
    [switch]$Update,
    [switch]$CleanIde,
    [switch]$Permanent,
    [switch]$Force,
    [switch]$Fx,
    [ValidateSet('jdk', 'jre')]
    [string]$PackageType = 'jdk'
)

# --- Глобальные переменные ---
$scriptDir = $PSScriptRoot
$configPath = Join-Path $scriptDir "config.json"
$langDir = Join-Path $scriptDir "lang"
$config = $null
$javaInstallPath = $null
$L = $null

# --- Функция инициализации конфигурации и локализации ---
function Initialize-Configuration {
    # 1. Загрузка config.json (создание, если не найден)
    if (-not (Test-Path $configPath)) {
        Write-Host "Configuration file not found. Creating a new config.json..." -ForegroundColor Cyan
        $defaultConfig = @{
            language        = "ru-RU"
            javaInstallPath = (Join-Path $env:ProgramFiles "Java")
            displayLimit    = 20
            providers       = @(
                @{ name = "Azul Zulu"; apiType = "Azul"; apiUrl = "https://api.azul.com/metadata/v1/zulu/packages"; enabled = $true; namePrefix = "zulu" },
                @{ name = "Eclipse Adoptium (Temurin)"; apiType = "Adoptium"; apiUrl = "https://api.adoptium.net/v3/assets/feature_releases/{java_version}/ga"; enabled = $true; namePrefix = "temurin" },
                @{ name = "Amazon Corretto"; apiType = "Foojay"; apiUrl = "https://api.foojay.io/disco/v3.0/packages"; distributionName = "corretto"; enabled = $true; namePrefix = "amazon-corretto" },
                @{ name = "BellSoft Liberica"; apiType = "Foojay"; apiUrl = "https://api.foojay.io/disco/v3.0/packages"; distributionName = "liberica"; enabled = $true; namePrefix = "liberica" },
                @{ name = "Oracle GraalVM (for JDK 17+)"; apiType = "OracleDirectLink"; urlTemplate = "https://download.oracle.com/graalvm/{java_version}/latest/graalvm-jdk-{java_version}_windows-x64_bin.zip"; enabled = $true; namePrefix = "graalvm" },
                @{ name = "GraalVM Community (Legacy)"; apiType = "GitHubReleases"; apiUrl = "https://api.github.com/repos/graalvm/graalvm-ce-builds/releases"; assetFilterPatterns = @("graalvm-ce-java{java_version}-windows-amd64*.zip", "graalvm-community-java{java_version}-windows-amd64*.zip", "graalvm-community-jdk-{java_version}_windows-x64_bin.zip"); enabled = $true; namePrefix = "graalvm-ce" }
            )
        }
        try {
            $defaultConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding utf8 -ErrorAction Stop
        } catch { throw "Failed to create config.json at '$configPath'. Check permissions." }
    }
    try {
        $script:config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch { throw "Failed to read or parse config.json. Please ensure it is a valid JSON file." }

    $script:javaInstallPath = [System.Environment]::ExpandEnvironmentVariables($config.javaInstallPath)

    # 2. Загрузка файла локализации
    $langCode = $config.language
    $langFilePath = Join-Path $langDir "$langCode.json"
    if (-not (Test-Path $langFilePath)) {
        Write-Warning "Language file for '$langCode' not found. Falling back to en-US."
        $langFilePath = Join-Path $langDir "en-US.json"
        if (-not (Test-Path $langFilePath)) { throw "Default language file 'en-US.json' is missing." }
    }
    
    try {
        $script:L = Get-Content -LiteralPath $langFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { throw "Failed to parse language file '$langFilePath'." }
}

# --- Функция самообновления ---
function Invoke-SelfUpdate {
    Write-Host "Checking for script updates..." -ForegroundColor DarkGray
    $repoUrl = "https://raw.githubusercontent.com/PixelmonPRO/Java-Version-Manager/main/version.json"
    
    try {
        $remoteVersionInfo = Invoke-RestMethod -Uri $repoUrl -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Warning "Could not check for script updates. Maybe no internet connection."
        return
    }

    $localVersion = [version]$config.scriptVersion
    $remoteVersion = [version]$remoteVersionInfo.latestVersion

    if ($remoteVersion -gt $localVersion) {
        Write-Host ""
        Write-Host ($L.UpdateAvailable -f $remoteVersion, $localVersion) -ForegroundColor Green
        
        $confirmation = 'n'
        if ($PSBoundParameters.Count -eq 0) {
            $confirmation = Read-ValidatedChoice -Prompt $L.ConfirmScriptUpdate -ValidOptions 'y', 'n' -DefaultOption 'y'
        }

        if ($confirmation -ne 'y') { return }

        $zipUrl = $remoteVersionInfo.downloadUrl
        $tempDir = Join-Path $env:TEMP "java-manager-update"
        $zipPath = Join-Path $tempDir "update.zip"

        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        New-Item -Path $tempDir -ItemType Directory | Out-Null

        Write-Host "Downloading update from $zipUrl..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        
        Write-Host "Extracting update..."
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
        
        $updaterScriptPath = Join-Path $tempDir "updater.ps1"
        $targetDir = $PSScriptRoot

        $updaterContent = @"
Start-Sleep -Seconds 1
Write-Host 'Copying new files...'
Copy-Item -Path "$tempDir\*" -Destination "$targetDir" -Recurse -Force
Remove-Item -Path "$tempDir" -Recurse -Force
Write-Host "Update complete! Please restart your terminal." -ForegroundColor Green
"@
        $updaterContent | Out-File -FilePath $updaterScriptPath -Encoding utf8

        Write-Host "Finalizing update... The script will now exit and update itself." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$updaterScriptPath`""
        exit
    }
}

# --- API Адаптеры и Диспетчер ---
function Find-RemotePackages {
    param( [psobject]$Provider, [string]$PackageType, [switch]$IncludeFx, [string]$JavaVersion, [switch]$Silent )
    if (-not $Silent) {
        Write-Host "`n$($L.ApiQuery -f $Provider.name)" -ForegroundColor Cyan
    }
    switch ($Provider.apiType) {
        "Azul"             { return Get-RemotePackagesFromAzul -Provider $Provider -PackageType $PackageType -IncludeFx $IncludeFx -JavaVersion $JavaVersion }
        "Adoptium"         { if ($IncludeFx) { Write-Warning ($L.FxNotSupportedWarning -f $Provider.name) }; return Get-RemotePackagesFromAdoptium -Provider $Provider -PackageType $PackageType -JavaVersion $JavaVersion }
        "Foojay"           { if ($IncludeFx) { Write-Warning ($L.FxNotSupportedWarning -f $Provider.name) }; return Get-RemotePackagesFromFoojay -Provider $Provider -PackageType $PackageType -JavaVersion $JavaVersion }
        "OracleDirectLink" { if ($PackageType -ne 'jdk') { Write-Warning ($L.JreNotSupportedWarning -f $Provider.name) }; return Get-RemotePackagesFromOracleDirectLink -Provider $Provider -JavaVersion $JavaVersion }
        "GitHubReleases"   { if ($PackageType -ne 'jdk') { Write-Warning ($L.JreNotSupportedWarning -f $Provider.name) }; return Get-RemotePackagesFromGitHubReleases -Provider $Provider -JavaVersion $JavaVersion }
        default            { throw "Unknown API type '$($Provider.apiType)' for provider '$($Provider.name)'." }
    }
}

function Get-RemotePackagesFromGitHubReleases {
    param($Provider, $JavaVersion)
    if ([string]::IsNullOrWhiteSpace($JavaVersion)) { throw ($L.ApiRequiresVersion -f $Provider.name) }
    
    $allReleases = [System.Collections.Generic.List[object]]::new()
    $uri = $Provider.apiUrl + "?per_page=100" 

    while ($uri) {
        try {
            $response = Invoke-WebRequest -Uri $uri -Headers @{ "User-Agent" = "PowerShell-Java-Manager-Script" } -UseBasicParsing -ErrorAction Stop
            $pageReleases = $response.Content | ConvertFrom-Json
            $allReleases.AddRange($pageReleases)

            $linkHeader = $response.Headers.Link
            $uri = $null 
            if ($linkHeader) {
                $nextLinkMatch = [regex]::Match($linkHeader, '(?<=<)([^>]+)(?=>; rel="next")')
                if ($nextLinkMatch.Success) {
                    $uri = $nextLinkMatch.Value
                }
            }
        } catch {
            Write-Warning "Failed to fetch a page of releases from GitHub API. Some versions may be missing. Error: $($_.Exception.Message)"
            $uri = $null
        }
    }
    $releases = $allReleases
    $filterPatterns = $Provider.PSObject.Properties.Where({$_.Name -eq 'assetFilterPatterns'}).Value
    if (-not $filterPatterns) {
        $filterPatterns = @($Provider.PSObject.Properties.Where({$_.Name -eq 'assetFilter'}).Value)
        if (-not $filterPatterns) {
            throw "Для провайдера '$($Provider.name)' не заданы обязательные параметры 'assetFilterPatterns' или 'assetFilter' в config.json"
        }
    }
    $unifiedPackages = [System.Collections.Generic.List[object]]::new()
    foreach ($release in $releases) {
        $zipAsset = $null
        foreach ($pattern in $filterPatterns) {
            $currentFilter = $pattern -replace "{java_version}", $JavaVersion
            $foundAsset = $release.assets | Where-Object { $_.name -like $currentFilter } | Sort-Object -Property created_at -Descending | Select-Object -First 1
            if ($foundAsset) {
                $zipAsset = $foundAsset
                break 
            }
        }

        if ($zipAsset) {
            $shaAsset = $release.assets | Where-Object { $_.name -eq "$($zipAsset.name).sha256" }
            $ShaHash = if ($shaAsset) { 
                try { (Invoke-WebRequest -Uri $shaAsset.browser_download_url -UseBasicParsing).Content.Trim().Split(' ')[0] } catch { "" }
            } else { "" }

            $versionMatch = [regex]::Match($zipAsset.name, "(\d+(\.\d+)*)\.zip")
            $displayVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { $release.tag_name }

            $unifiedPackages.Add([PSCustomObject]@{
                ProviderName    = $Provider.name
                PackageName     = $zipAsset.name -replace '\.zip$'
                DisplayVersion  = $displayVersion
                DownloadUrl     = $zipAsset.browser_download_url
                ShaHash         = $ShaHash
                ChecksumType    = 'sha256'
                SupportsFx      = $false
                OriginalPackage = $release
            })
        }
    }
    return $unifiedPackages
}

function Get-RemotePackagesFromOracleDirectLink {
    param($Provider, $JavaVersion)

    if ([string]::IsNullOrWhiteSpace($JavaVersion)) { throw ($L.ApiRequiresVersion -f $Provider.name) }
    
    $downloadUrl = $Provider.urlTemplate -replace "{java_version}", $JavaVersion
    $checksumUrl = $downloadUrl + ".sha256"

    $ShaHash = try {
        (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -ErrorAction Stop).Content.Trim()
    } catch {
        return @()
    }

    $fileName = [System.IO.Path]::GetFileName($downloadUrl)
    $packageName = $fileName -replace '\.zip$'
    
    $versionMatch = [regex]::Match($fileName, "jdk-?(\d+(\.\d+)*)")
    $displayVersion = if($versionMatch.Success) { $versionMatch.Groups[1].Value } else { $JavaVersion }

    $package = [PSCustomObject]@{
        ProviderName    = $Provider.name
        PackageName     = $packageName
        DisplayVersion  = $displayVersion
        DownloadUrl     = $downloadUrl
        ShaHash         = $ShaHash
        ChecksumType    = 'sha256'
        SupportsFx      = $false
        OriginalPackage = $null
    }
    
    return @($package)
}

function Get-RemotePackagesFromAzul {
    param($Provider, $PackageType, $IncludeFx, $JavaVersion)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x86_64' } else { 'x86' }
    $apiUrl = "$($Provider.apiUrl)?os=windows&arch=$($arch)&archive_type=zip&java_package_type=$($PackageType)&release_status=ga&javafx_bundled=$($IncludeFx.IsPresent.ToString().ToLower())"
    if (-not [string]::IsNullOrWhiteSpace($JavaVersion)) { $apiUrl += "&java_version=$($JavaVersion)" }
    $headers = @{ "User-Agent" = "PowerShell-Java-Manager-Script" }
    
    $apiResult = try { 
        @(Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing -ErrorAction Stop)
    } catch [System.Net.WebException] {
        $statusCode = ""
        if ($_.Exception.Response) { $statusCode = " (Status: $([int]$_.Exception.Response.StatusCode) '$($_.Exception.Response.StatusDescription)')" }
        throw ($L.ApiFetchFail -f $statusCode)
    } catch { 
        throw $L.ApiUnexpectedError
    }

    return $apiResult | ForEach-Object {
        [PSCustomObject]@{ 
            ProviderName    = $Provider.name
            PackageName     = $_.name -replace '\.zip$'
            DisplayVersion  = ($_.java_version -join '.')
            DownloadUrl     = $_.download_url
            ShaHash         = $_.sha256_hash
            ChecksumType    = 'sha256'
            SupportsFx      = $_.javafx_bundled
            OriginalPackage = $_ 
        }
    }
}

function Get-RemotePackagesFromAdoptium {
    param($Provider, $PackageType, $JavaVersion)
    if ([string]::IsNullOrWhiteSpace($JavaVersion)) { throw ($L.ApiRequiresVersion -f $Provider.name) }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
    $apiUrl = ($Provider.apiUrl -replace "{java_version}", $JavaVersion) + "?os=windows&architecture=$($arch)&image_type=$($PackageType)&jvm_impl=hotspot&release_type=ga"
    $headers = @{ "User-Agent" = "PowerShell-Java-Manager-Script" }
    $apiResult = try { @(Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing) } catch { @() }
    $unifiedPackages = [System.Collections.Generic.List[object]]::new()
    foreach ($release in $apiResult) {
        $binary = $release.binaries | Where-Object { $_.os -eq 'windows' -and $_.architecture -eq $arch -and $_.image_type -eq $PackageType } | Select-Object -First 1
        if ($binary) { $unifiedPackages.Add([PSCustomObject]@{ ProviderName = $Provider.name; PackageName = $binary.package.name -replace '\.zip$'; DisplayVersion = $release.version_data.semver; DownloadUrl = $binary.package.link; ShaHash = $binary.package.checksum; ChecksumType = 'sha256'; SupportsFx = $false; OriginalPackage = $release }) }
    }
    return $unifiedPackages
}

function Get-RemotePackagesFromFoojay {
    param($Provider, $PackageType, $JavaVersion)
    if ([string]::IsNullOrWhiteSpace($JavaVersion)) { throw ($L.ApiRequiresVersion -f $Provider.name) }
    if ([string]::IsNullOrWhiteSpace($Provider.distributionName)) {
        throw "Provider '$($Provider.name)' is configured to use the 'Foojay' API type but is missing the 'distributionName' property in config.json."
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
    
    $distributionName = [uri]::EscapeDataString($Provider.distributionName)
    $apiUrl = "$($Provider.apiUrl)?distro=$($distributionName)&version=$($JavaVersion)&release_status=ga&latest=available&os=windows&architecture=$arch&archive_type=zip&package_type=$($PackageType)"
    
    $headers = @{ "User-Agent" = "PowerShell-Java-Manager-Script" }
    $apiResult = try { Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing } catch { return @() }
    $unifiedPackages = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $apiResult.result) {
        if ($package.distribution -ne $Provider.distributionName -or $package.operating_system -ne 'windows') { continue }
        
        $detailsResult = try { Invoke-RestMethod -Uri $package.links.pkg_info_uri -Headers $headers -UseBasicParsing } catch { continue }
        $packageDetails = $detailsResult.result[0]
        
        $shaHash = ""
        $checksumType = ""
        if ($packageDetails.checksum_type -eq 'sha256') {
            $shaHash = $packageDetails.checksum
            $checksumType = 'sha256'
        }

        # --- FIX START: Improved checksum fetching for BellSoft Liberica with logging ---
        if ([string]::IsNullOrWhiteSpace($shaHash) -and $Provider.name -eq 'BellSoft Liberica') {
            $parentUri = $packageDetails.direct_download_uri.Substring(0, $packageDetails.direct_download_uri.LastIndexOf('/'))
            
            $checksumFiles = @(
                @{ Url = "$parentUri/sha256sum.txt"; Algo = "sha256"; HashLength = 64 },
                @{ Url = "$parentUri/sha1sum.txt"; Algo = "sha1"; HashLength = 40 }
            )

            foreach ($fileInfo in $checksumFiles) {
                Write-Host "[DEBUG] Attempting to find checksum in $($fileInfo.Url)" -ForegroundColor DarkGray
                try {
                    $checksumsContent = (Invoke-WebRequest -Uri $fileInfo.Url -UseBasicParsing -ErrorAction Stop -Headers @{ "User-Agent" = "PowerShell-Java-Manager-Script" } -MaximumRedirection 5).Content
                    Write-Host "[DEBUG] Successfully downloaded checksum file. Content snippet:" -ForegroundColor DarkGray
                    Write-Host ($checksumsContent.Split("`n") | Select-Object -First 5 | Out-String) -ForegroundColor DarkGray

                    $escapedFilename = [regex]::Escape($packageDetails.filename)
                    $pattern = "^\s*([a-fA-F0-9]{$($fileInfo.HashLength)})\s+\*?$($escapedFilename)\s*$"
                    Write-Host "[DEBUG] Using regex pattern: $pattern" -ForegroundColor DarkGray
                    
                    $lines = $checksumsContent -split '(\r?\n)' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    foreach ($line in $lines) {
                        $trimmedLine = $line.Trim()
                        Write-Host "[DEBUG] Checking line: '$trimmedLine'" -ForegroundColor DarkGray
                        if ($trimmedLine -match $pattern) {
                            $shaHash = $matches[1].ToLower()
                            $checksumType = $fileInfo.Algo
                            Write-Host "[DEBUG] SUCCESS: Found hash '$shaHash' for '$($packageDetails.filename)'" -ForegroundColor Green
                            break 
                        }
                    }
                } catch {
                    Write-Host "[DEBUG] FAILED to download or process $($fileInfo.Url). Error: $($_.Exception.Message)" -ForegroundColor Yellow
                }
                
                if (-not [string]::IsNullOrWhiteSpace($shaHash)) {
                    Write-Host "[DEBUG] Found hash, breaking from checksum file loop." -ForegroundColor DarkGray
                    break
                } else {
                    Write-Host "[DEBUG] No hash found in $($fileInfo.Url), trying next file if available." -ForegroundColor DarkGray
                }
            }
        }
        # --- FIX END ---

        $unifiedPackages.Add([PSCustomObject]@{ 
            ProviderName    = $Provider.name
            PackageName     = $packageDetails.filename -replace '\.zip$'
            DisplayVersion  = $package.java_version
            DownloadUrl     = $packageDetails.direct_download_uri
            ShaHash         = $shaHash
            ChecksumType    = $checksumType
            SupportsFx      = $false
            OriginalPackage = $package 
        })
    }
    return $unifiedPackages
}

# --- Вспомогательные и общие функции ---
function Get-InstalledJdks {
    if (-not (Test-Path -Path $javaInstallPath -PathType Container)) { return @() }
    $i = 1
    Get-ChildItem -Path $javaInstallPath -Directory -Exclude 'scripts' | ForEach-Object {
        try {
            $item = Get-Item -LiteralPath $_.FullName -ErrorAction Stop
            [PSCustomObject]@{ Index = $i++; Name = $item.Name; Path = $item.FullName }
        } catch {
            Write-Warning "Could not resolve path for item '$($_.FullName)'. It might be a broken link. Skipping."
        }
    }
}

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-SortableVersion {
    param([string]$VersionString)
    $cleanVersion = ($VersionString -split '\+')[0]
    $cleanVersion = $cleanVersion -replace '_', '.' -replace 'vm-',''
    if ($cleanVersion -notlike '*.*') {
        $cleanVersion = "$cleanVersion.0"
    }
    try {
        return [version]$cleanVersion
    }
    catch {
        return [version]'0.0'
    }
}

function Read-ValidatedChoice {
    param(
        [string]$Prompt,
        [string[]]$ValidOptions,
        [string]$DefaultOption
    )
    $promptWithOptions = $Prompt
    if ($ValidOptions -contains 'y' -and $ValidOptions -contains 'n') {
        $promptWithOptions = if ($DefaultOption -eq 'y') { "$Prompt [Y/n]" } else { "$Prompt [y/N]" }
    }

    while ($true) {
        $finalPrompt = $promptWithOptions.TrimEnd(':').Trim() + ": "
        Write-Host -NoNewline $finalPrompt
        $input = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($input) -and -not [string]::IsNullOrWhiteSpace($DefaultOption)) {
            Write-Host $DefaultOption
            return $DefaultOption
        }
        if ($ValidOptions -contains $input.ToLower()) {
            return $input.ToLower()
        }
        Write-Warning $L.InvalidOption
    }
}

function Download-And-Extract-Package {
    param(
        [Parameter(Mandatory=$true)] [psobject]$UnifiedPackage,
        [Parameter(Mandatory=$true)] [string]$PackageType
    )
    
    $zipFileName = "$($UnifiedPackage.PackageName).zip"
    $zipFilePath = Join-Path $env:TEMP $zipFileName
    $extractPath = Join-Path $javaInstallPath $UnifiedPackage.PackageName
    $expectedChecksum = $UnifiedPackage.ShaHash
    $checksumAlgo = $UnifiedPackage.ChecksumType
    
    if (Test-Path $extractPath) { throw ($L.JdkAlreadyInstalled -f $UnifiedPackage.PackageName) }
    if ([string]::IsNullOrWhiteSpace($expectedChecksum)) { Write-Warning "Checksum is missing for package '$($UnifiedPackage.PackageName)'. Proceeding without verification." }

    Write-Host ("`n" + ($L.Downloading -f $zipFileName)) -ForegroundColor Cyan
    Write-Host ($L.FromUrl -f $UnifiedPackage.DownloadUrl)

    try {
        Invoke-WebRequest -Uri $UnifiedPackage.DownloadUrl -OutFile $zipFilePath -UseBasicParsing -ErrorAction Stop
    } catch { 
        if (Test-Path $zipFilePath) { Remove-Item $zipFilePath -Force }
        throw ($L.DownloadFailed -f $_.Exception.Message) 
    }

    if (-not (Test-Path $zipFilePath)) {
        throw $L.DownloadFileMissing
    }
    
    if (-not [string]::IsNullOrWhiteSpace($expectedChecksum)) {
        Write-Host "`n$($L.VerifyingChecksum.Replace('SHA256', $checksumAlgo.ToUpper()))" -ForegroundColor Cyan
        $calculatedHash = $null
        $retryCount = 5
        $retryDelay = 1 
        for ($i = 1; $i -le $retryCount; $i++) {
            $fileHashObject = Get-FileHash -Path $zipFilePath -Algorithm $checksumAlgo -ErrorAction SilentlyContinue
            if ($fileHashObject -and -not [string]::IsNullOrWhiteSpace($fileHashObject.Hash)) {
                $calculatedHash = $fileHashObject.Hash.ToLower()
                break
            }
            if($i -lt $retryCount) {
                Write-Host ($L.DebugHashFail -f $retryDelay) -ForegroundColor DarkGray
                Start-Sleep -Seconds $retryDelay
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($calculatedHash)) {
            throw $L.FileHashUnavailable
        }
        
        if ($calculatedHash -ne $expectedChecksum.ToLower()) {
            Remove-Item -Path $zipFilePath -Force
            throw ($L.ChecksumMismatch -f $expectedChecksum, $calculatedHash)
        }
        Write-Host $L.ChecksumOK -ForegroundColor Green
    }

    Write-Host ("`n" + ($L.Extracting -f $javaInstallPath)) -ForegroundColor Cyan
    Expand-Archive -Path $zipFilePath -DestinationPath $javaInstallPath -Force
    Remove-Item $zipFilePath

    # --- НОВОЕ: Создание файла метаданных ---
    try {
        $metaData = @{
            providerName = $UnifiedPackage.ProviderName
            fullVersion  = $UnifiedPackage.DisplayVersion
            majorVersion = ([regex]::Match($UnifiedPackage.DisplayVersion, '^\d+')).Value
            packageType  = $PackageType
            hasFx        = $UnifiedPackage.SupportsFx
            installDate  = (Get-Date -Format 'o')
        }
        $metaFilePath = Join-Path $extractPath ".jvm_meta.json"
        $metaData | ConvertTo-Json | Out-File -FilePath $metaFilePath -Encoding utf8
    } catch {
        Write-Warning "Could not create metadata file for $($UnifiedPackage.PackageName). Update checks for this JDK may fail."
    }
    # --- КОНЕЦ НОВОГО БЛОКА ---

    Write-Host "`n$($L.InstallComplete -f $UnifiedPackage.PackageName)" -ForegroundColor Green
    return $extractPath
}

function Set-JavaEnvironment {
    param( [Parameter(Mandatory=$true)] [string]$JavaPath, [switch]$IsPermanent )
    if ($IsPermanent -and -not (Test-Admin)) { throw $L.RequiresAdmin }
    
    $newJavaBin = Join-Path -Path $JavaPath -ChildPath "bin"
    Write-Host ("`n" + ($L.Activating -f (Split-Path $JavaPath -Leaf))) -ForegroundColor Cyan
    
    $currentPath = $env:Path
    $pathEntries = $currentPath.Split(';') | Where-Object { $_ -and -not $_.StartsWith($javaInstallPath) }
    $env:Path = "$newJavaBin;$($pathEntries -join ';')"
    $env:JAVA_HOME = $JavaPath
    $env:JDK_HOME = $JavaPath
    Write-Host $L.SessionUpdated -ForegroundColor Green

    if ($IsPermanent) {
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $machinePathEntries = $machinePath.Split(';') | Where-Object { $_ -and -not $_.StartsWith($javaInstallPath) }
        $newMachinePath = "$newJavaBin;$($machinePathEntries -join ';')"
        [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaPath, "Machine")
        [Environment]::SetEnvironmentVariable("JDK_HOME", $JavaPath, "Machine")
        Write-Host $L.SystemUpdated -ForegroundColor Green
    }
    Write-Host "`n$($L.Verification)"; & java -version
}

function Invoke-PathCleanup {
    param([switch]$SystemScope, [switch]$Silent)

    $scope = if ($SystemScope) { "Machine" } else { "Process" }
    $pathTarget = if ($SystemScope) { [System.EnvironmentVariableTarget]::Machine } else { [System.EnvironmentVariableTarget]::Process }
    if ($SystemScope -and -not (Test-Admin)) { return }

    $currentPath = [Environment]::GetEnvironmentVariable("Path", $pathTarget)
    $pathEntries = $currentPath.Split(';')
    
    $orphanedPaths = $pathEntries | Where-Object { $_.StartsWith($javaInstallPath) -and $_.Length -gt $javaInstallPath.Length -and -not (Test-Path ($_.TrimEnd('\', '/'))) }
    
    if ($orphanedPaths.Count -eq 0) { return }

    $confirmation = 'y'
    if (-not $Silent) {
        Write-Host ("`n" + $L.PathCleanupPrompt) -ForegroundColor Yellow
        Write-Host $L.PathCleanupInfo
        $orphanedPaths | ForEach-Object { Write-Host " - $_" }
        $confirmation = Read-ValidatedChoice -Prompt $L.ConfirmAction -ValidOptions 'y','n' -DefaultOption 'y'
    }

    if ($confirmation -eq 'y') {
        $newPathEntries = $pathEntries | Where-Object { $_ -notin $orphanedPaths }
        $newPath = $newPathEntries -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, $pathTarget)
        
        if($SystemScope) { $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") }

        if (-not $Silent) { Write-Host $L.PathCleanupComplete -ForegroundColor Green }
    } else {
        if (-not $Silent) { Write-Host $L.PathCleanupCancelled }
    }
}

# --- Функции интерактивного меню ---
function Select-Provider {
    $enabledProviders = $config.providers | Where-Object { $_.enabled }
    if ($enabledProviders.Count -eq 0) { throw $L.NoProvidersEnabled }
    if ($enabledProviders.Count -eq 1) { Write-Host "`n$($L.AutoSelectingProvider -f $enabledProviders[0].name)"; return $enabledProviders[0] }
    
    Write-Host "`n$($L.SelectProviderTitle)" -ForegroundColor Yellow
    for ($i = 0; $i -lt $enabledProviders.Count; $i++) { Write-Host ("{0}. {1}" -f ($i + 1), $enabledProviders[$i].name) }
    
    $choice = ""
    $prompt = "`n$($L.SelectProviderPrompt)"
    # Use Read-ValidatedChoice to handle the prompt cleanly
    $validIndices = 1..($enabledProviders.Count) | ForEach-Object { "$_" }
    $choice = Read-ValidatedChoice -Prompt $prompt -ValidOptions $validIndices
    
    $selectedIndex = [int]$choice - 1

    if ($selectedIndex -ge 0 -and $selectedIndex -lt $enabledProviders.Count) { return $enabledProviders[$selectedIndex] } 
    else { throw $L.InvalidSelection }
}

function Invoke-ListAvailableMenu {
    Invoke-InstallMenu -ListOnly
}

function Invoke-InstallMenu {
    param([switch]$ListOnly)
    Clear-Host
    if (-not $ListOnly -and -not (Test-Admin)) { throw $L.RequiresAdmin }
    
    $provider = Select-Provider
    
    $title = if ($ListOnly) { $L.ListTitle } else { $L.InstallTitle }
    Write-Host "`n$($title) ($($provider.name))" -ForegroundColor Yellow
    
    $pkgInput = Read-ValidatedChoice -Prompt $L.ChoosePackageType -ValidOptions '1', '2' -DefaultOption '1'
    $currentPkgType = if ($pkgInput -eq '2') { 'jre' } else { 'jdk' }
    
    $includeFx = $false
    if (($provider.apiType -eq 'Azul')) { 
        $fxInput = Read-ValidatedChoice -Prompt $L.IncludeFX -ValidOptions 'y', 'n' -DefaultOption 'n'
        $includeFx = ($fxInput -eq 'y')
    }
    
    # --- FIX: Prevent double colons in Read-Host prompt ---
    $promptText = $L.EnterMajorVersion.TrimEnd(':')
    $javaVersion = Read-Host -Prompt "$promptText:"
    
    if ([string]::IsNullOrWhiteSpace($javaVersion) -and ($provider.apiType -match '^(OracleDirectLink|Adoptium|Foojay|GitHubReleases)$')) {
        throw ($L.ApiRequiresVersion -f $Provider.name)
    }
    
    $remotePackages = Find-RemotePackages -Provider $provider -PackageType $currentPkgType -IncludeFx:$includeFx -JavaVersion $javaVersion
    if ($remotePackages.Count -eq 0) { throw ($L.NoJdksFound -f "$javaVersion ($($currentPkgType))") }
    
    $remotePackages = $remotePackages | Sort-Object -Property @{Expression={ConvertTo-SortableVersion -VersionString $_.DisplayVersion}} -Descending
    
    $limit = $config.displayLimit
    if ($limit -gt 0 -and $remotePackages.Count -gt $limit) {
        $remotePackages = $remotePackages | Select-Object -First $limit
    }

    $installedNames = @(Get-InstalledJdks).Name
    
    $i = 1
    $displayItems = @()
    $validChoices = [System.Collections.Generic.List[string]]::new()

    foreach ($package in $remotePackages) {
        $isInstalled = $package.PackageName -in $installedNames
        $checksumIndicator = if ([string]::IsNullOrWhiteSpace($package.ShaHash)) { [char]0x274C } else { [char]0x2713 } # ❌ or ✔
        $displayPackageName = "$($package.PackageName) [checksum: $checksumIndicator]"
        
        $itemIndex = if ($isInstalled) { '-' } else { "$i" }
        if(-not $isInstalled) { $validChoices.Add("$i"); $i++ }

        $displayItems += [PSCustomObject]@{
            Index       = $itemIndex
            PackageName = $displayPackageName
            IsInstalled = $isInstalled
            Package     = $package
        }
    }
    
    if ($validChoices.Count -eq 0) { Write-Host ($L.AllBuildsInstalled -f $javaVersion) -ForegroundColor Green; return }
    
    $displayItems | ForEach-Object {
        $line = "{0,-4} {1}" -f $_.Index, $_.PackageName
        if ($_.IsInstalled) { 
            Write-Host $line -ForegroundColor Gray -NoNewline
            Write-Host (" {0}" -f $L.StatusInstalled) -ForegroundColor DarkGray 
        } 
        else { Write-Host $line }
    }
    
    if ($ListOnly) { return }

    $input = Read-ValidatedChoice -Prompt "`n$($L.EnterBuildToInstall)" -ValidOptions $validChoices
    if ([string]::IsNullOrWhiteSpace($input)) { Write-Host "`n$($L.InstallationCancelled)"; return }
    
    $selectionNumber = try { [int]$input } catch { -1 }
    $packageToInstall = ($displayItems | Where-Object { $_.Index -eq $selectionNumber -and -not $_.IsInstalled }).Package
    
    if (-not $packageToInstall) { throw $L.InvalidSelection }
    Download-And-Extract-Package -UnifiedPackage $packageToInstall -PackageType $currentPkgType | Out-Null
}

function Invoke-SwitchMenu {
    Clear-Host
    Write-Host $L.SwitchTitle -ForegroundColor Yellow
    $installedJdks = @(Get-InstalledJdks)
    if ($installedJdks.Count -eq 0) { throw ($L.NoJdksInstalled -f $javaInstallPath) }
    $installedJdks | Format-Table -AutoSize -Property Index, Name
    
    $validChoices = 1..($installedJdks.Count) | ForEach-Object { "$_" }
    $input = Read-ValidatedChoice -Prompt "`n$($L.EnterJdkToActivate)" -ValidOptions $validChoices
    if ([string]::IsNullOrWhiteSpace($input)) { return }

    $selectionNumber = try { [int]$input } catch { -1 }
    $chosenJdk = $installedJdks | Where-Object { $_.Index -eq $selectionNumber }
    if (-not $chosenJdk) { throw $L.InvalidSelection }

    $permanentChoice = Read-ValidatedChoice -Prompt $L.MakePermanent -ValidOptions 'y', 'n' -DefaultOption 'n'
    Set-JavaEnvironment -JavaPath $chosenJdk.Path -IsPermanent:($permanentChoice -eq 'y')
}

function Invoke-UninstallMenu {
    Clear-Host
    if (-not (Test-Admin)) { throw $L.RequiresAdmin }
    Write-Host $L.UninstallTitle -ForegroundColor Yellow
    $installedJdks = @(Get-InstalledJdks)
    if ($installedJdks.Count -eq 0) { throw $L.NoJdksToUninstall }
    $installedJdks | Format-Table -AutoSize -Property Index, Name
    
    $validChoices = 1..($installedJdks.Count) | ForEach-Object { "$_" }
    $input = Read-ValidatedChoice -Prompt "`n$($L.EnterJdkToUninstall)" -ValidOptions $validChoices
    if ([string]::IsNullOrWhiteSpace($input)) { Write-Host "`n$($L.UninstallationCancelled)"; return }
    
    $selectionNumber = try { [int]$input } catch { -1 }
    $jdkToUninstall = $installedJdks | Where-Object { $_.Index -eq $selectionNumber }
    if (-not $jdkToUninstall) { throw $L.InvalidSelection }

    $confirmation = Read-ValidatedChoice -Prompt ($L.ConfirmDelete -f $jdkToUninstall.Name) -ValidOptions 'y', 'n' -DefaultOption 'n'
    if ($confirmation -ne 'y') { Write-Host "`n$($L.UninstallationCancelled)"; return }
    
    Uninstall-SingleJdk -JdkName $jdkToUninstall.Name -Silent:$false
}

function Uninstall-SingleJdk {
    param ([string]$JdkName, [switch]$Silent)
    
    $jdkPath = Join-Path $javaInstallPath $JdkName
    if (-not (Test-Path $jdkPath)) { throw "Path for '$JdkName' does not exist." }
    
    if (-not $Silent) { Write-Host ("`n" + ($L.Deleting -f $JdkName)) -ForegroundColor Yellow }
    
    try {
        Remove-Item -Path $jdkPath -Recurse -Force -ErrorAction Stop
    }
    catch [System.UnauthorizedAccessException], [System.IO.IOException] {
        Write-Warning ("`n" + ($L.ProcessLockDetected -f $jdkPath))
        $processes = Get-Process | Where-Object { $_.Modules.FileName -like "$jdkPath\*" } | Select-Object ProcessName, Id
        if ($processes) {
            $processes | Format-Table
            $killChoice = Read-ValidatedChoice -Prompt $L.KillProcessesPrompt -ValidOptions 'y', 'n' -DefaultOption 'n'
            if ($killChoice -eq 'y') {
                Write-Host "`n$($L.TerminatingProcesses)"
                $processes | ForEach-Object {
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                    if ($?) { Write-Host "Terminated $($_.ProcessName) (PID: $($_.Id))" } 
                    else { Write-Warning ($L.TerminationFailed -f $_.ProcessName, $_.Id) }
                }
                Write-Host "`n$($L.RetryingDelete)"
                Start-Sleep -Seconds 1
                try {
                    Remove-Item -Path $jdkPath -Recurse -Force -ErrorAction Stop
                } catch { throw ($L.DeletionFailedAgain) }
            }
        } else {
            Write-Warning $L.NoProcessesFound
            throw $_.Exception
        }
    }
    
    if (-not $Silent) { Write-Host "`n$($L.UninstallComplete)" -ForegroundColor Green }
    
    Invoke-PathCleanup -Silent
    Invoke-PathCleanup -SystemScope -Silent
    
    if ($env:JAVA_HOME -eq $jdkPath) {
        $env:JAVA_HOME = $null; $env:JDK_HOME = $null
        if (-not $Silent) { Write-Host $L.SessionCleared -ForegroundColor Yellow }
    }
    if ([Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine") -eq $jdkPath) {
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "Machine")
        [Environment]::SetEnvironmentVariable("JDK_HOME", $null, "Machine")
        if (-not $Silent) { Write-Host $L.SystemCleared -ForegroundColor Yellow }
    }
}

function Invoke-UpdateMenu {
    Clear-Host
    if (-not (Test-Admin)) { throw $L.RequiresAdmin }
    Write-Host $L.UpdateTitle -ForegroundColor Yellow

    $updates = Find-AvailableUpdates
    if ($updates.Count -eq 0) { Write-Host "`n$($L.NoUpdatesFound)" -ForegroundColor Green; return }

    Write-Host "`n$($L.UpdatesAvailable)"
    $updates | ForEach-Object {
        Write-Host ("{0}. {1} -> {2}" -f $_.Index, $_.InstalledJdk.Name, $_.NewPackageName)
    }

    $validChoices = 1..($updates.Count) | ForEach-Object { "$_" }
    $validChoices += 'a'
    $input = Read-ValidatedChoice -Prompt "`n$($L.EnterUpdateSelection)" -ValidOptions $validChoices
    if ([string]::IsNullOrWhiteSpace($input)) { Write-Host "`n$($L.UpdateCancelled)"; return }
    
    $selections = if ($input -eq 'a') { $updates } else { $indices = $input -split ',' | ForEach-Object { $_.Trim() }; $updates | Where-Object { $_.Index -in $indices } }
    if ($selections.Count -eq 0) { Write-Host "`n$($L.UpdateCancelled)"; return }

    foreach ($update in $selections) {
        Write-Host ("`n" + ($L.UpdatingJdk -f $update.InstalledJdk.Name, $update.NewPackageName)) -ForegroundColor Cyan
        Perform-Update -OldJdk $update.InstalledJdk -NewPackageInfo $update.LatestPackage
    }
    Write-Host "`n$L.UpdateComplete" -ForegroundColor Green
}

function Find-AvailableUpdates {
    Write-Host "`n$($L.CheckingForUpdates)" -ForegroundColor Cyan
    $installedJdks = @(Get-InstalledJdks)
    $updates = [System.Collections.Generic.List[object]]::new()

    foreach ($jdk in $installedJdks) {
        Write-Host ($L.CheckingForUpdateFor -f $jdk.Name) -ForegroundColor DarkGray
        
        $metaPath = Join-Path $jdk.Path ".jvm_meta.json"
        $provider = $null
        $majorVersion = $null
        $packageType = 'jdk'
        $hasFx = $false
        $installedVersion = $null

        if (Test-Path $metaPath) {
            # НОВАЯ ЛОГИКА: Читаем метаданные
            $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
            $provider = $config.providers | Where-Object { $_.name -eq $meta.providerName }
            $majorVersion = $meta.majorVersion
            $packageType = $meta.packageType
            $hasFx = $meta.hasFx
            $installedVersion = ConvertTo-SortableVersion -VersionString $meta.fullVersion
        } else {
            # СТАРАЯ ЛОГИКА (для обратной совместимости): Угадываем по имени папки
            $provider = $config.providers | Where-Object { $jdk.Name -like "$($_.namePrefix)*" } | Select-Object -First 1
            if (-not $provider) { continue }

            $versionMatch = [regex]::Match($jdk.Name, '(\d+(\.\d+)+)')
            if (-not $versionMatch.Success) { continue }
            $installedVersion = ConvertTo-SortableVersion -VersionString $versionMatch.Groups[1].Value
            $majorVersion = $installedVersion.Major
            $packageType = if ($jdk.Name -like '*jre*') { 'jre' } else { 'jdk' }
            $hasFx = $jdk.Name -like '*-fx*'
        }

        if (-not $provider) { continue }

        $remotePackages = Find-RemotePackages -Provider $provider -PackageType $packageType -IncludeFx:$hasFx -JavaVersion $majorVersion -Silent
        if ($remotePackages.Count -eq 0) { continue }

        $latestPackage = $remotePackages | Sort-Object -Property @{Expression={ConvertTo-SortableVersion -VersionString $_.DisplayVersion}} -Descending | Select-Object -First 1
        if ($null -eq $latestPackage) { continue }

        $latestVersion = ConvertTo-SortableVersion -VersionString $latestPackage.DisplayVersion
        
        if (($latestVersion.Major -eq $majorVersion) -and ($latestVersion -gt $installedVersion)) {
            $updates.Add([PSCustomObject]@{
                Index          = $updates.Count + 1
                InstalledJdk   = $jdk
                NewPackageName = $latestPackage.PackageName
                LatestPackage  = $latestPackage
            })
        }
    }
    return $updates
}

function Perform-Update {
    param ([psobject]$OldJdk, [psobject]$NewPackageInfo)
    $wasSessionHome = ($env:JAVA_HOME -eq $OldJdk.Path)
    $systemJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    $wasSystemHome = ($systemJavaHome -eq $OldJdk.Path)

    # Определяем тип пакета для нового JDK/JRE на основе старого
    $oldMetaPath = Join-Path $OldJdk.Path ".jvm_meta.json"
    $pkgTypeForNew = 'jdk' # По умолчанию
    if (Test-Path $oldMetaPath) {
        $oldMeta = Get-Content -LiteralPath $oldMetaPath -Raw | ConvertFrom-Json
        $pkgTypeForNew = $oldMeta.packageType
    } else {
        # Легаси-проверка для старых установок
        if ($OldJdk.Name -like '*jre*') { $pkgTypeForNew = 'jre' }
    }

    $newJdkPath = Download-And-Extract-Package -UnifiedPackage $NewPackageInfo -PackageType $pkgTypeForNew
    if (-not $newJdkPath) { Write-Error "Failed to install new package, aborting update."; return }

    Uninstall-SingleJdk -JdkName $OldJdk.Name -Silent
    
    if ($wasSessionHome -or $wasSystemHome) {
        Set-JavaEnvironment -JavaPath $newJdkPath -IsPermanent:($wasSystemHome)
    }
}

# --- Функции очистки IDE ---
function Resolve-IdePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ($Path.Contains('$APPLICATION_HOME_DIR$')) { return "UNRESOLVABLE_IDE_PATH" }
    
    $resolvedPath = $Path.Replace('$USER_HOME$', $env:USERPROFILE)
    $resolvedPath = [System.Environment]::ExpandEnvironmentVariables($resolvedPath)
    
    try {
        return (Get-Item -LiteralPath $resolvedPath).FullName
    } catch {
        return $resolvedPath.Replace('/', '\')
    }
}

function Get-JavaVersionFromPath {
    param([string]$JdkPath)
    $javaExe = Join-Path $JdkPath "bin\java.exe"
    if (-not (Test-Path $javaExe)) { return "Unknown" }
    
    try {
        $versionInfo = & $javaExe -version 2>&1
        $match = [regex]::Match(($versionInfo -join " "), 'version "([^"]+)"')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
        $match = [regex]::Match(($versionInfo -join " "), '(\d+\.\d+\.\S+)')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
        return ($versionInfo -join ' ')
    } catch {
        return "Error getting version"
    }
}

function Find-IntelliJConfigs {
    $configs = [System.Collections.Generic.List[string]]::new()
    $basePath = Join-Path $env:APPDATA "JetBrains"
    if (-not (Test-Path $basePath)) { return $configs }
    $ideDirPatterns = @("IntelliJIdea*", "IdeaIC*", "AndroidStudio*")
    Get-ChildItem -Path $basePath -Directory | ForEach-Object {
        $ideDir = $_
        $ideDirPatterns | ForEach-Object {
            if ($ideDir.Name -like $_) {
                $configFile = Join-Path $ideDir.FullName "options\jdk.table.xml"
                if (Test-Path $configFile) {
                    if ($configs -notcontains $configFile) { $configs.Add($configFile) }
                }
            }
        }
    }
    return $configs
}

function Get-JdkStructure {
    param([string]$JdkPath)

    $classPaths = [System.Collections.Generic.List[string]]::new()
    $sourcePaths = [System.Collections.Generic.List[string]]::new()
    $jmodsPath = Join-Path $JdkPath "jmods"
    $srcZipPath = Join-Path $JdkPath "lib\src.zip"

    if (Test-Path $jmodsPath) {
        $jmodFiles = Get-ChildItem -Path $jmodsPath -Filter "*.jmod"

        foreach ($jmod in $jmodFiles) {
            $moduleName = $jmod.BaseName
            $classPaths.Add("jrt://$($JdkPath.Replace('\', '/'))/!/$moduleName")
        }
        
        if (Test-Path $srcZipPath) {
            foreach ($jmod in $jmodFiles) {
                $moduleName = $jmod.BaseName
                $sourcePaths.Add("jar://$($srcZipPath.Replace('\', '/'))!/$moduleName")
            }
        }

    } else {
        $jreLibPath = Join-Path $JdkPath "jre\lib"
        if (Test-Path $jreLibPath) {
            Get-ChildItem -Path $jreLibPath -Filter "*.jar" -Recurse | ForEach-Object {
                $classPaths.Add("jar://$($_.FullName.Replace('\', '/'))!/")
            }
        }
        $toolsJarPath = Join-Path $JdkPath "lib\tools.jar"
        if (Test-Path $toolsJarPath) {
            $toolsUrl = "jar://$($toolsJarPath.Replace('\', '/'))!/"
            if (-not $classPaths.Contains($toolsUrl)) {
                $classPaths.Add($toolsUrl)
            }
        }
        
        if (Test-Path $srcZipPath) {
            $sourcePaths.Add("jar://$($srcZipPath.Replace('\', '/'))!/")
        }
    }

    return @{ ClassPath = ($classPaths | Sort-Object); SourcePath = ($sourcePaths | Sort-Object) }
}

function Invoke-IdeCleanup {
    param([switch]$Force)
    Clear-Host
    Write-Host $L.CleanIdeTitle -ForegroundColor Yellow
    $installedJdks = Get-InstalledJdks
    Write-Host "`n$($L.CleanIdeScanning)"

    $configFiles = Find-IntelliJConfigs
    if ($configFiles.Count -eq 0) {
        Write-Host "`n$($L.CleanIdeNoConfigsFound)" -ForegroundColor Green
        return
    }

    $anyActionTaken = $false
    
    foreach ($file in $configFiles) {
        Write-Host "" 
        Write-Host ($L.CleanIdeConfigFileFound -f $file)
        
        try {
            [xml]$xml = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        } catch {
            Write-Warning "Не удалось прочитать XML-файл '$file'. Пропуск. Ошибка: $($_.Exception.Message)"
            continue
        }

        $componentNode = $xml.application.component | Where-Object { $_.name -eq 'ProjectJdkTable' }
        if (-not $componentNode) {
            $appNode = $xml.SelectSingleNode('//application')
            if(-not $appNode) { $appNode = $xml.AppendChild($xml.CreateElement("application")) }
            $componentNode = $appNode.AppendChild($xml.CreateElement("component"))
            $componentNode.SetAttribute("name", "ProjectJdkTable")
        }

        $nodesToRemove = [System.Collections.Generic.List[object]]::new()
        $orphanedDisplayInfo = [System.Collections.Generic.List[string]]::new()
        $comparer = [System.StringComparer]::InvariantCultureIgnoreCase
        $validConfiguredPaths = [System.Collections.Generic.HashSet[string]]::new($comparer)

        foreach ($jdkNode in $componentNode.jdk) {
            $originalPath = $jdkNode.SelectSingleNode("homePath") | Select-Object -ExpandProperty value -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($originalPath)) { continue }

            $resolvedPath = Resolve-IdePath -Path $originalPath
            if ($resolvedPath -eq "UNRESOLVABLE_IDE_PATH") { continue }

            if ($null -eq $resolvedPath -or -not(Test-Path -LiteralPath $resolvedPath -PathType Container)) {
                $nodesToRemove.Add($jdkNode)
                $jdkName = $jdkNode.SelectSingleNode("name") | Select-Object -ExpandProperty value
                $orphanedDisplayInfo.Add(" - $jdkName ($originalPath)")
            } else {
                $validConfiguredPaths.Add($resolvedPath) | Out-Null
            }
        }

        $jdksToAdd = $installedJdks | Where-Object { $_.Path -and -not $validConfiguredPaths.Contains($_.Path) }

        if ($nodesToRemove.Count -eq 0 -and $jdksToAdd.Count -eq 0) {
            Write-Host ($L.CleanIdeNoChangesFound) -ForegroundColor Green
            continue
        }

        if ($jdksToAdd.Count -gt 0) {
            Write-Host "`n$($L.CleanIdeDetectedJdksFound)" -ForegroundColor Cyan
            $jdksToAdd | ForEach-Object { Write-Host " + $($_.Name) " }
        }
        if ($nodesToRemove.Count -gt 0) {
            Write-Host "`n$($L.CleanIdeOrphanedJdksFound)" -ForegroundColor Yellow
            $orphanedDisplayInfo | ForEach-Object { Write-Host $_ }
        }
        
        $confirmation = if ($Force) { 'y' } else { Read-ValidatedChoice -Prompt "`n$($L.ConfirmAction)" -ValidOptions 'y','n' -DefaultOption 'n' }

        if ($confirmation -eq 'y') {
            $anyActionTaken = $true
            $backupPath = "$file.$(Get-Date -Format 'yyyyMMddHHmmss').bak"
            try {
                Copy-Item -Path $file -Destination $backupPath -Force
                Write-Host "`n" -NoNewline; Write-Host ($L.CleanIdeBackupCreated -f $backupPath) -ForegroundColor DarkGray
            } catch { Write-Warning "Не удалось создать резервную копию файла '$file'." }

            foreach ($node in $nodesToRemove) { $node.ParentNode.RemoveChild($node) | Out-Null }

            foreach ($jdk in $jdksToAdd) {
                $provider = $config.providers | Where-Object { $jdk.Name -like "$($_.namePrefix)*" } | Select-Object -First 1
                $providerName = if ($provider) { $provider.name } else { "" }
                if ($providerName -match '^(.*?)\s*\(') { $providerName = $matches[1].Trim() }
                $versionNumber = Get-JavaVersionFromPath -JdkPath $jdk.Path
                $fullVersionString = if ($providerName) { "$providerName $versionNumber" } else { $versionNumber }
                $jdkStructure = Get-JdkStructure -JdkPath $jdk.Path
                
                $newJdk = $xml.CreateElement("jdk"); $newJdk.SetAttribute("version", "2")
                
                $type = $xml.CreateElement("type"); $type.SetAttribute("value", "JavaSDK"); $newJdk.AppendChild($type) | Out-Null
                $name = $xml.CreateElement("name"); $name.SetAttribute("value", $jdk.Name); $newJdk.AppendChild($name) | Out-Null
                $version = $xml.CreateElement("version"); $version.SetAttribute("value", $fullVersionString); $newJdk.AppendChild($version) | Out-Null
                $homePath = $xml.CreateElement("homePath"); $homePath.SetAttribute("value", ($jdk.Path -replace '\\', '/')); $newJdk.AppendChild($homePath) | Out-Null
                
                $roots = $xml.CreateElement("roots")
                
                $annotationsPath = $xml.CreateElement("annotationsPath")
                $rootCompositeAnnotations = $xml.CreateElement("root"); $rootCompositeAnnotations.SetAttribute("type", "composite")
                $rootSimple = $xml.CreateElement("root")
                $rootSimple.SetAttribute("url", 'jar://$APPLICATION_HOME_DIR$/plugins/java/lib/resources/jdkAnnotations.jar!/')
                $rootSimple.SetAttribute("type", "simple")
                $rootCompositeAnnotations.AppendChild($rootSimple) | Out-Null; $annotationsPath.AppendChild($rootCompositeAnnotations) | Out-Null; $roots.AppendChild($annotationsPath) | Out-Null
                
                # --- Class Path ---
                $classPath = $xml.CreateElement("classPath"); $rootCompositeClasspath = $xml.CreateElement("root"); $rootCompositeClasspath.SetAttribute("type", "composite")
                foreach($pathUrl in $jdkStructure.ClassPath) { 
                    $root = $xml.CreateElement("root")
                    $root.SetAttribute("url", $pathUrl)
                    $root.SetAttribute("type", "simple")
                    $rootCompositeClasspath.AppendChild($root) | Out-Null
                }
                $classPath.AppendChild($rootCompositeClasspath) | Out-Null; $roots.AppendChild($classPath) | Out-Null

                # --- Javadoc Path ---
                $javadocPath = $xml.CreateElement("javadocPath"); $rootCompositeJavadoc = $xml.CreateElement("root"); $rootCompositeJavadoc.SetAttribute("type", "composite"); $javadocPath.AppendChild($rootCompositeJavadoc) | Out-Null; $roots.AppendChild($javadocPath) | Out-Null
                
                # --- Source Path ---
                $sourcePath = $xml.CreateElement("sourcePath"); $rootCompositeSourcepath = $xml.CreateElement("root"); $rootCompositeSourcepath.SetAttribute("type", "composite")
                foreach($pathUrl in $jdkStructure.SourcePath) { 
                    $root = $xml.CreateElement("root")
                    $root.SetAttribute("url", $pathUrl)
                    $root.SetAttribute("type", "simple")
                    $rootCompositeSourcepath.AppendChild($root) | Out-Null
                }
                $sourcePath.AppendChild($rootCompositeSourcepath) | Out-Null; $roots.AppendChild($sourcePath) | Out-Null

                $newJdk.AppendChild($roots) | Out-Null
                $newJdk.AppendChild($xml.CreateElement("additional")) | Out-Null
                $componentNode.AppendChild($newJdk) | Out-Null
            }

            try {
                $settings = New-Object System.Xml.XmlWriterSettings; $settings.Indent = $true; $settings.IndentChars = "  "; $settings.NewLineChars = "`r`n"; $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
                $writer = [System.Xml.XmlWriter]::Create($file, $settings); $xml.Save($writer); $writer.Close()
                Write-Host "`n$($L.CleanIdeEntriesUpdated)" -ForegroundColor Green
            } catch {
                 $errorMessage = "КРИТИЧЕСКАЯ ОШИБКА: Не удалось сохранить изменения в '$file'.`n" + "ВОЗМОЖНАЯ ПРИЧИНА: Файл заблокирован запущенным экземпляром IntelliJ IDEA. Пожалуйста, закройте IDE и попробуйте снова.`n"
                 if (Test-Path $backupPath) { $errorMessage += "Исходные настройки находятся в резервной копии: '$backupPath'`n" }
                 $errorMessage += "Системная ошибка: $($_.Exception.Message)"; Write-Error $errorMessage
            }
        } else {
            Write-Host "`n$($L.PathCleanupCancelled)"
        }
    }
    
    if ($anyActionTaken) {
        Write-Host "`n$($L.CleanIdeComplete)" -ForegroundColor Green
        Write-Host "`n$($L.CleanIdeRestartIde)" -ForegroundColor Yellow
    }
}

# --- Неинтерактивный режим ---
function Invoke-NonInteractiveMode {
    if ($PSBoundParameters.ContainsKey('List')) { Invoke-NonInteractiveList }
    elseif ($PSBoundParameters.ContainsKey('Install')) { Invoke-NonInteractiveInstall }
    elseif ($PSBoundParameters.ContainsKey('Switch')) { Invoke-NonInteractiveSwitch }
    elseif ($PSBoundParameters.ContainsKey('Uninstall')) { Invoke-NonInteractiveUninstall }
    elseif ($PSBoundParameters.ContainsKey('Update')) { Invoke-NonInteractiveUpdate }
    elseif ($PSBoundParameters.ContainsKey('CleanIde')) { Invoke-IdeCleanup -Force:$Force }
}

function Invoke-NonInteractiveList {
    if (-not $Provider) { throw $L.NonInteractiveProviderRequired }
    $providerObj = $config.providers | Where-Object { $_.name -eq $Provider -and $_.enabled }
    if (-not $providerObj) { throw ($L.NonInteractiveProviderNotFound -f $Provider) }

    $remotePackages = Find-RemotePackages -Provider $providerObj -PackageType $PackageType -IncludeFx:$Fx -JavaVersion $List
    if ($remotePackages.Count -eq 0) { throw ($L.NoJdksFound -f $List) }

    $remotePackages | Sort-Object -Property @{Expression={ConvertTo-SortableVersion -VersionString $_.DisplayVersion}} -Descending | Select-Object PackageName, DisplayVersion | Format-Table
}

function Invoke-NonInteractiveInstall {
    if (-not $Provider) { throw $L.NonInteractiveProviderRequired }
    $providerObj = $config.providers | Where-Object { $_.name -eq $Provider -and $_.enabled }
    if (-not $providerObj) { throw ($L.NonInteractiveProviderNotFound -f $Provider) }
    if ($Permanent -and -not (Test-Admin)) { throw $L.RequiresAdmin }

    $remotePackages = Find-RemotePackages -Provider $providerObj -PackageType $PackageType -IncludeFx:$Fx -JavaVersion $Install
    if ($remotePackages.Count -eq 0) { throw ($L.NoJdksFound -f $Install) }

    $latestPackage = $remotePackages | Sort-Object -Property @{Expression={ConvertTo-SortableVersion -VersionString $_.DisplayVersion}} -Descending | Select-Object -First 1
    
    Write-Host ("`n" + ($L.NonInteractiveLatest -f $remotePackages.Count, $latestPackage.PackageName)) -ForegroundColor Cyan
    
    $installedPath = Download-And-Extract-Package -UnifiedPackage $latestPackage -PackageType $PackageType
    if ($Permanent) {
        Set-JavaEnvironment -JavaPath $installedPath -IsPermanent
    }
}

function Invoke-NonInteractiveSwitch {
    if ($Permanent -and -not (Test-Admin)) { throw $L.RequiresAdmin }
    $installedJdks = @(Get-InstalledJdks)
    $chosenJdk = $installedJdks | Where-Object { $_.Name -eq $Switch }
    if (-not $chosenJdk) { throw ($L.NonInteractiveVersionNotFound -f $Switch) }

    Write-Host ("`n" + ($L.NonInteractiveSwitchingTo -f $chosenJdk.Name)) -ForegroundColor Cyan
    Set-JavaEnvironment -JavaPath $chosenJdk.Path -IsPermanent:$Permanent
}

function Invoke-NonInteractiveUninstall {
    if (-not (Test-Admin)) { throw $L.RequiresAdmin }
    if (-not $Force) { Write-Warning ("`n" + ($L.NonInteractiveUninstallForce -f $Uninstall)); return }

    Uninstall-SingleJdk -JdkName $Uninstall -Silent
    Write-Host "`n$($L.UninstallComplete)" -ForegroundColor Green
}

function Invoke-NonInteractiveUpdate {
    if (-not (Test-Admin)) { throw $L.RequiresAdmin }
    $updates = Find-AvailableUpdates
    if ($updates.Count -eq 0) { Write-Host "`n$($L.NoUpdatesFound)" -ForegroundColor Green; return }

    Write-Host "`n$($L.UpdatesAvailable)"
    $updates | ForEach-Object { Write-Host ("  * {0} -> {1}" -f $_.InstalledJdk.Name, $_.NewPackageName) }
    if (-not $Force) {
        $confirmation = Read-ValidatedChoice -Prompt $L.ConfirmUpdateAll -ValidOptions 'y','n' -DefaultOption 'n'
        if ($confirmation -ne 'y') { Write-Host "`n$($L.UpdateCancelled)"; return }
    }

    foreach ($update in $updates) {
        Write-Host ("`n" + ($L.UpdatingJdk -f $update.InstalledJdk.Name, $update.NewPackageName)) -ForegroundColor Cyan
        Perform-Update -OldJdk $update.InstalledJdk -NewPackageInfo $update.LatestPackage
    }
    Write-Host "`n$L.UpdateComplete" -ForegroundColor Green
}

# --- Основная логика ---
function Invoke-InteractiveMode {
    Invoke-PathCleanup -SystemScope -Silent:$false
    $running = $true
    while ($running) {
        Clear-Host
        Write-Host $L.MainMenuTitle -ForegroundColor Yellow
        $installedCount = @(Get-InstalledJdks).Count
        Write-Host ($L.MainMenuInfo -f $installedCount, $javaInstallPath)
        $currentJavaHome = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { "not set" }
        Write-Host ($L.CurrentJavaHome -f $currentJavaHome) -ForegroundColor Cyan; Write-Host ""
        Write-Host $L.MenuSwitch; Write-Host $L.MenuList; Write-Host $L.MenuInstall
        Write-Host $L.MenuUninstall; Write-Host $L.MenuUpdate; Write-Host $L.MenuCleanIde; Write-Host $L.MenuQuit; Write-Host ""
        
        $choice = Read-ValidatedChoice -Prompt $L.SelectOption -ValidOptions '1', '2', '3', '4', '5', '6', 'q'

        try {
            switch ($choice) {
                '1' { Invoke-SwitchMenu }
                '2' { Invoke-ListAvailableMenu }
                '3' { Invoke-InstallMenu }
                '4' { Invoke-UninstallMenu }
                '5' { Invoke-UpdateMenu }
                '6' { Invoke-IdeCleanup }
                'q' { $running = $false }
                default { Write-Warning $L.InvalidOption }
            }
        } catch { Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red }
        if ($running -and $choice -ne 'q') { Write-Host "`n$($L.PressEnter)" -NoNewline; Read-Host | Out-Null }
    }
}

# --- Точка входа в скрипт ---
try {
    Initialize-Configuration
    
    if ($PSBoundParameters.Count -eq 0) {
        Invoke-SelfUpdate
    }

    if (-not (Test-Path -Path $javaInstallPath -PathType Container)) {
        $createChoice = Read-ValidatedChoice -Prompt ($L.DirNotFound -f $javaInstallPath) -ValidOptions 'y','n' -DefaultOption 'y'
        if ($createChoice -eq 'y') { 
            if(-not (Test-Admin)) { throw $L.RequiresAdmin }
            New-Item -Path $javaInstallPath -ItemType Directory -Force | Out-Null 
            Write-Host ($L.DirCreated -f $javaInstallPath) -ForegroundColor Green
        }
        else { Write-Warning "Cannot proceed."; exit }
    }

    if ($PSBoundParameters.Count > 0) { Invoke-NonInteractiveMode } 
    else { Invoke-InteractiveMode }
}
catch {
    Write-Host "`nCRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($PSBoundParameters.Count -eq 0) { Write-Host "`n$($L.PressEnterContinue)" -NoNewline; Read-Host | Out-Null }
    exit 1
}