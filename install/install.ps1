param(
    [string]$Exe
)

$ErrorActionPreference = "Stop"

$PackageDir = $PSScriptRoot

function Resolve-GameExe {
    param([string]$Path)

    if (-not $Path) {
        return $null
    }

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
        $resolved = Join-Path $resolved "Hades2.exe"
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf) -or
        [IO.Path]::GetFileName($resolved) -ne "Hades2.exe") {
        throw "The -Exe path must point to Hades2.exe or its Ship directory: $Path"
    }

    return $resolved
}

if ($Exe) {
    $ExePath = Resolve-GameExe $Exe
} else {
    Add-Type -AssemblyName System.Windows.Forms

    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyComputer')
    Filter = "Executable Files (*.exe)|Hades2.exe"
    Title = "Select your Hades2.exe"
}

    if ($FileBrowser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    exit
    }

    $ExePath = $FileBrowser.FileName
}

$GameExeDir = Split-Path -Path $ExePath -Parent
$GameDir = Split-Path -Path $GameExeDir -Parent
$ModsDir = Join-Path $GameDir "Content/Mods"
$PluginsDir = Join-Path -Path $GameExeDir -ChildPath "plugins"

Write-Host "Target Directory: $GameExeDir" -ForegroundColor Cyan
Write-Host "Package Directory: $PackageDir" -ForegroundColor Cyan

function installPlugin() {
    Write-Host "Installing HadesModNativeExtension.asi" -ForegroundColor Cyan

    if (-not (Test-Path -Path $PluginsDir)) {
        New-Item -ItemType Directory -Path $PluginsDir | Out-Null
        Write-Host "Created plugins folder."
    }

    $nativeExtension = Join-Path $PackageDir "HadesModNativeExtension.asi"
    if (Test-Path -LiteralPath $nativeExtension -PathType Leaf) {
        Copy-Item -LiteralPath $nativeExtension -Destination $PluginsDir -Force
        Write-Host "Copied HadesModNativeExtension.asi to $PluginsDir" -ForegroundColor Green
    } else {
        throw "Source 'HadesModNativeExtension.asi' not found beside install.ps1."
    }
}

function installASILoader() {
    Write-Host "Downloading ASI Loader..." -ForegroundColor Cyan

    $originalDll = Join-Path $GameExeDir "bink2w64Hooked.dll"
    $loaderDll = Join-Path $GameExeDir "bink2w64.dll"
    if (-not (Test-Path -LiteralPath $originalDll -PathType Leaf)) {
        Write-Host "Rename bink2w64.dll to bink2w64Hooked.dll."
        if (-not (Test-Path -LiteralPath $loaderDll -PathType Leaf)) {
            throw "Original bink2w64.dll not found in $GameExeDir."
        }
        Move-Item -LiteralPath $loaderDll -Destination $originalDll -Force
    } else {
        Write-Host "Skip bink2w64Hooked.dll."
    }

    $Url = "https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/x64-latest/bink2w64-x64.zip"
    $ZipPath = Join-Path -Path $env:TEMP -ChildPath "asi_loader.zip"
    $TempExtractPath = Join-Path -Path $env:TEMP -ChildPath "asi_loader_temp"
    
    Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing

    # Unpack and move bink2w64.dll
    if (Test-Path $TempExtractPath) { Remove-Item $TempExtractPath -Recurse -Force }
    Expand-Archive -Path $ZipPath -DestinationPath $TempExtractPath -Force

    $DllSource = Get-ChildItem -Path $TempExtractPath -Filter "bink2w64.dll" -Recurse | Select-Object -First 1

    if ($DllSource) {
        Move-Item -LiteralPath $DllSource.FullName -Destination $loaderDll -Force
        Write-Host "Successfully installed bink2w64.dll to game folder." -ForegroundColor Green
    } else {
        Write-Error "Could not find bink2w64.dll inside the downloaded zip."
    }

    # Cleanup
    Remove-Item $ZipPath -Force
    Remove-Item $TempExtractPath -Recurse -Force
}

function installMod() {
    param (
        $ModName
    )

    Write-Host "Copy $ModName mod files..." -ForegroundColor Cyan
    
    $source = Join-Path $PackageDir $ModName
    $destination = Join-Path $ModsDir $ModName
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Package directory not found: $source"
    }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Force -Recurse
    }
    Copy-Item -LiteralPath $source -Destination $ModsDir -Force -Recurse
}

function install {
    installPlugin;
    if (Test-Path $GameExeDir/ReturnOfModding) {
        Write-Host "`nReturn of modding dedected. Skip custom ASI loader" -ForegroundColor Green
    } else {
        installASILoader
    }

    if (-not (Test-Path -Path $ModsDir)) {
        New-Item -ItemType Directory -Path $ModsDir | Out-Null
        Write-Host "Created Mods folder."
    }

    
    installMod -ModName "TN_Core"
    installMod -ModName "TN_CoopMod"
}


install
if (-not $Exe) {
    Read-Host -Prompt "`nSetup complete. Press Enter to exit."
} else {
    Write-Host "`nSetup complete." -ForegroundColor Green
}
