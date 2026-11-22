param(
    [switch]$Deploy = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Flutter Web muhiti sozlanmoqda ===" -ForegroundColor Cyan
$env:Path = "C:\dev\flutter\bin;$env:Path"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MobileDir = "$RootDir\mobile"
$BuildWebDir = "$MobileDir\build\web"
$DataWebappDir = "$RootDir\data\webapp"
$DistDir = "$RootDir\dist"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Push-Location $MobileDir

try {
    Write-Host "=== 2. Kod tahlili (flutter analyze) ===" -ForegroundColor Cyan
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        throw "flutter analyze xatolik bilan tugadi!"
    }

    Write-Host "=== 3. Flutter Web (Mini App) yig'ilmoqda ===" -ForegroundColor Cyan
    flutter build web --release --base-href /webapp/ --web-content-hash
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build web xatolik bilan tugadi!"
    }

    if (-not (Test-Path "$BuildWebDir\index.html")) {
        throw "Build natijasi topilmadi: $BuildWebDir\index.html"
    }

    if (Test-Path $DataWebappDir) {
        Remove-Item -Recurse -Force $DataWebappDir
    }
    New-Item -ItemType Directory -Force -Path $DataWebappDir | Out-Null

    Get-ChildItem -Path $BuildWebDir -Force | Where-Object {
        $_.Name -ne "canvaskit" -and
        $_.Name -ne ".last_build_id" -and
        $_.Name -ne "flutter.js.map"
    } | ForEach-Object {
        Copy-Item -Recurse -Force $_.FullName -Destination (Join-Path $DataWebappDir $_.Name)
    }

    $Files = Get-ChildItem -Path $DataWebappDir -Recurse -File
    $TotalBytes = ($Files | Measure-Object -Property Length -Sum).Sum
    $TotalMb = [math]::Round($TotalBytes / 1MB, 2)
    Write-Host "✅ Flutter Web Mini App tayyor: $DataWebappDir ($($Files.Count) ta fayl, $TotalMb MB)" -ForegroundColor Green

    if ($Deploy) {
        $TargetFile = "$RootDir\.deploy_target"
        $DeployTarget = if ($env:HISOBCHI_DEPLOY_TARGET) {
            $env:HISOBCHI_DEPLOY_TARGET.Trim()
        } elseif (Test-Path $TargetFile) {
            (Get-Content $TargetFile -Raw).Trim()
        } else {
            throw ".deploy_target fayli yoki HISOBCHI_DEPLOY_TARGET o'zgaruvchisi topilmadi!"
        }
        $ColonIdx = $DeployTarget.IndexOf(':')
        if ($ColonIdx -le 0) {
            throw "Deploy target formati noto'g'ri!"
        }
        $HostPart = $DeployTarget.Substring(0, $ColonIdx).Trim()
        $RemoteDataDir = $DeployTarget.Substring($ColonIdx + 1).Trim().TrimEnd('/')

        Write-Host "=== 4. Serverga Flutter Web (Mini App) yuklanmoqda ===" -ForegroundColor Cyan
        $TarPath = "$DistDir\webapp.tar.gz"
        if (Test-Path $TarPath) {
            Remove-Item -Force $TarPath
        }
        tar -czf $TarPath -C $DataWebappDir .
        if ($LASTEXITCODE -ne 0) {
            throw "tar arxivlashda xatolik!"
        }
        scp $TarPath "${HostPart}:${RemoteDataDir}/webapp.tar.gz"
        if ($LASTEXITCODE -ne 0) {
            throw "scp yuklashda xatolik!"
        }
        ssh $HostPart "mkdir -p '${RemoteDataDir}/webapp' && rm -rf '${RemoteDataDir}/webapp'/* && tar -xzf '${RemoteDataDir}/webapp.tar.gz' -C '${RemoteDataDir}/webapp' && rm -f '${RemoteDataDir}/webapp.tar.gz'"
        if ($LASTEXITCODE -ne 0) {
            throw "Serverda webapp ochishda xatolik!"
        }
        Write-Host "🚀 Serverdagi Flutter Web Mini App yangilandi!" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
