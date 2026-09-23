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

function Ensure-Gh {
    $g = Get-Command gh -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $fb = "$env:LOCALAPPDATA\manhwa-tools\gh\gh.exe"
    if (Test-Path $fb) {
        $env:Path = "$env:LOCALAPPDATA\manhwa-tools\gh;" + $env:Path
        return $fb
    }
    Write-Output "  Descargando gh CLI portable (para conectar tu cuenta de GitHub desde el navegador)..."
    $ver = "2.62.0"
    $url = "https://github.com/cli/cli/releases/download/v$ver/gh_${ver}_windows_amd64.zip"
    $zip = Join-Path $env:TEMP "gh-$ver.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip
        $dest = "$env:LOCALAPPDATA\manhwa-tools\gh"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $dest -Force
        $inner = Get-ChildItem "$dest\gh_${ver}_windows_amd64" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($inner) {
            Get-ChildItem $inner.FullName | Move-Item -Destination $dest -Force
            Remove-Item $inner.FullName -Recurse -Force
        }
        $found = Get-ChildItem $dest -Recurse -Filter "gh.exe" | Select-Object -First 1
        if ($found) {
            $bin = Split-Path -Parent $found.FullName
            $env:Path = "$bin;" + $env:Path
            [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$bin", "User")
            Write-Output "  gh listo en $bin"
            return $found.FullName
        }
    } catch {
        Write-Output "  (no pude descargar gh; se puede usar igual con el token)"
    }
    return ""
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
$ghExe = Ensure-Gh

Write-Output "Git:      $git"
$nodePath = (Get-Command node -ErrorAction SilentlyContinue) | ForEach-Object { $_.Source }
Write-Output "Node:     $(if ($nodePath) { $nodePath } else { 'no encontrado (alcanza con git para publicar)' })"
Write-Output "gh:       $(if ($ghExe) { $ghExe } else { 'no disponible' })"
Write-Output ""

if (-not $Token) {
    $ghTok = ""
    if ($ghExe) { $ghTok = & $ghExe auth token 2>$null | Out-String; $ghTok = $ghTok.Trim() }
    if ($ghTok) {
        Write-Output "Encontré tu sesión de GitHub en esta PC. Usándola sin pedir nada."
        $Token = $ghTok
    } else {
        Write-Output "No hay sesión de GitHub en esta PC todavía. Tenés dos opciones:"
        if ($ghExe) {
            Write-Output "  [1] RECOMENDADA: loguearte una vez con el navegador (te asocio tu cuenta y no pegás nada)"
            Write-Output "  [2] Pegar el token (el mismo RELEASE_TOKEN de github.com/settings/tokens)"
            $choice = Read-Host "Elegí 1 o 2"
            if ($choice -eq "1") {
                & $ghExe auth login
                $ghTok = & $ghExe auth token 2>$null | Out-String; $ghTok = $ghTok.Trim()
                if (-not $ghTok) { throw "El login en el navegador no se completó. Volvé a correr el script y elegí pegar el token." }
                $Token = $ghTok
            } else {
                $Token = Read-Host "Token de GitHub (de https://github.com/settings/tokens)"
            }
        } else {
            $Token = Read-Host "Token de GitHub (de https://github.com/settings/tokens)"
        }
        if (-not $Token) { throw "El token no puede estar vacío." }
    }
} else {
    if ($ghExe) {
        try { $Token | & $ghExe auth login --with-token 2>$null } catch { }
    }
}

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
    if ($LASTEXITCODE -ne 0) { throw "El clon falló. Revisá la cuenta/token (debe tener permiso 'repo')." }
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
if ($LASTEXITCODE -ne 0) { throw "No pude autenticarme contra GitHub. Revisá la cuenta/token." }
Write-Output "  Conectado correctamente."

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
Write-Output "  - Credenciales de GitHub guardadas (no vuelve a preguntar)"
Write-Output "  - La compilación del APK la hace GitHub; no hace falta Android Studio en ninguna PC."
Write-Output ""
Write-Output "Para publicar una actualización nueva, entrá a $Dir y corré:"
Write-Output "    .\nueva-version.ps1"