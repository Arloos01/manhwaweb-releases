param(
    [string]$Token = "",
    [string]$Name = "Arloos01",
    [string]$Email = "",
    [string]$Dir = "",
    [switch]$SkipClone
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if ($env:OS -ne "Windows_NT") {
    throw "Este script está pensado para Windows. En Mac/Linux alcanza con: git clone https://github.com/Arloos01/manhwaWeb-app.git y configurar git."
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}

function Get-Git {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $fallbacks = @(
        "C:\Program Files\Git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe"
    )
    foreach ($p in $fallbacks) { if (Test-Path $p) { return $p } }
    return ""
}

function Ensure-Node {
    $n = Get-Command node -ErrorAction SilentlyContinue
    if ($n) { return }
    $installed = "$env:LOCALAPPDATA\manhwa-tools\node\node.exe"
    if (Test-Path $installed) {
        $env:Path = "$env:LOCALAPPDATA\manhwa-tools\node;" + $env:Path
        return
    }
    Write-Output "  Node no está instalado. Descargando Node portable (sin permisos de admin)..."
    $nodeVer = "v22.14.0"
    $url = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-win-x64.zip"
    $zip = Join-Path $env:TEMP "node-$nodeVer-win-x64.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip
    $dest = "$env:LOCALAPPDATA\manhwa-tools\node"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    $inner = Get-ChildItem $dest -Directory | Select-Object -First 1
    if ($inner) {
        Get-ChildItem $inner.FullName | Move-Item -Destination $dest -Force
        Remove-Item $inner.FullName -Recurse -Force
    }
    $env:Path = "$dest;" + $env:Path
    [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$dest", "User")
    Write-Output "  Node listo en $dest"
}

Write-Output "=== Preparar esta PC para trabajar con manhwaWeb ==="
Write-Output ""

Refresh-Path
$git = Get-Git
if (-not $git) {
    Write-Output "Git no está instalado. Intentando instalarlo automáticamente..."
    $w = Get-Command winget -ErrorAction SilentlyContinue
    if ($w) {
        winget install -e --id Git.Git --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
        Refresh-Path
        $git = Get-Git
    }
}
if (-not $git) {
    $c = Get-Command choco -ErrorAction SilentlyContinue
    if ($c) {
        choco install git -y | Out-Null
        Refresh-Path
        $git = Get-Git
    }
}
if (-not $git) {
    throw "No pude instalar Git solo. Instalalo desde https://git-scm.com/download/win y volvé a correr este script."
}

Ensure-Node

Write-Output "Git:      $git"
$nodePath = (Get-Command node -ErrorAction SilentlyContinue) | ForEach-Object { $_.Source }
Write-Output "Node:     $(if ($nodePath) { $nodePath } else { 'no encontrado (alcanza con git para publicar)' })"
Write-Output ""

if (-not $Token) {
    $Token = Read-Host "Token de GitHub (de https://github.com/settings/tokens)"
}
if (-not $Token) { throw "El token no puede estar vacío." }

if (-not $Dir) { $Dir = Join-Path $env:USERPROFILE "manhwaWeb-app" }

if (Test-Path -LiteralPath $Dir) {
    $isRepo = Test-Path -LiteralPath (Join-Path $Dir ".git")
} else {
    $isRepo = $false
}

if (-not $isRepo) {
    if ($SkipClone) { throw "-SkipClone especificado pero no hay repo en $Dir" }
    $parent = Split-Path -Parent $Dir
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Write-Output "Clonando repositorio privado en $Dir ..."
    & $git clone "https://$Name`:$Token@github.com/Arloos01/manhwaWeb-app.git" $Dir
    if ($LASTEXITCODE -ne 0) { throw "El clon falló. Revisá el token (debe tener permiso 'repo')." }
    & $git -C $Dir remote set-url origin "https://github.com/Arloos01/manhwaWeb-app.git"
} else {
    Write-Output "El repo ya está en $Dir. Sincronizando con GitHub (pull)..."
    & $git -C $Dir remote set-url origin "https://github.com/Arloos01/manhwaWeb-app.git"
    & $git -C $Dir pull origin main
    if ($LASTEXITCODE -ne 0) { throw "El pull falló. Revisá las credenciales." }
}

& $git -C $Dir config user.name $Name
if (-not $Email) {
    $Email = Read-Host "Correo de tu cuenta de GitHub"
    if (-not $Email) { $Email = "$Name@users.noreply.github.com" }
}
& $git -C $Dir config user.email $Email

Write-Output "Guardando credenciales de GitHub en esta PC (una sola vez, no vuelve a preguntar)..."
$credFile = Join-Path $env:USERPROFILE ".git-credentials"
& $git -C $Dir config --local credential.helper "store --file=$credFile"
$credLine = "https://$Name`:$Token@github.com"
if (Test-Path $credFile) {
    $lines = @([System.IO.File]::ReadAllLines($credFile) | Where-Object { $_ -notmatch 'https://[^/@]+@github\.com' })
    $lines += $credLine
    [System.IO.File]::WriteAllText($credFile, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, (New-Object System.Text.ASCIIEncoding))
} else {
    Set-Content -Path $credFile -Value $credLine -NoNewline -Encoding Ascii
}

Write-Output "Verificando conexión a GitHub..."
& $git -C $Dir ls-remote origin HEAD | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No pude autenticarme contra GitHub. Revisá el token." }
Write-Output "  Conectado correctamente."

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    Write-Output "gh detectado: autenticando también gh CLI..."
    $Token | gh auth login --with-token
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if ($npm) {
    Write-Output "Instalando dependencias de la app (node_modules)..."
    Push-Location $Dir
    try {
        npm install --no-fund --no-audit
        if ($LASTEXITCODE -ne 0) { Write-Output "  ADVERTENCIA: npm install falló (igual podés publicar; git alcanza)." }
    } catch {
        Write-Output "  ADVERTENCIA: npm install falló (igual podés publicar; git alcanza)."
    }
    Pop-Location
}

Write-Output ""
Write-Output "Listo. Esta PC ya quedó igual que la de tu casa:"
Write-Output "  - Repositorio sincronizado: $Dir"
Write-Output "  - Credenciales de GitHub guardadas (guardadas en texto plano en ~/.git-credentials)"
Write-Output "  - La compilación del APK la hace GitHub; no hace falta Android Studio en ninguna PC."
Write-Output ""
Write-Output "Para publicar una actualización nueva, entrá a $Dir y corré:"
Write-Output "    .\nueva-version.ps1"