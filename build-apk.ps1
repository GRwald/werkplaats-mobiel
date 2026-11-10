$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LabRoot    = 'D:\Anitgravity-Lab'
$BlocksDir  = Join-Path $LabRoot 'bouwblokken'
$JdkDir     = Join-Path $BlocksDir 'jdk'
$SdkDir     = Join-Path $BlocksDir 'android-sdk'
$ProjectDir = Join-Path $LabRoot 'projecten\werkplaats-mobiel'
$ProductDir = Join-Path $LabRoot 'producten'

Write-Host "=== 1. Voorbereiden Werkplaats Mobiel APK-bouw ==="
$javac = Get-ChildItem -Path $JdkDir -Filter 'javac.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $javac) { throw "javac.exe niet gevonden in $JdkDir" }

$JavaHome = $javac.Directory.Parent.FullName
$env:JAVA_HOME = $JavaHome
$env:PATH = "$($javac.Directory.FullName);$env:PATH"

$androidJar = Join-Path $SdkDir 'platforms\android-34\android.jar'
$btDir      = Join-Path $SdkDir 'build-tools\34.0.0'
$aapt2      = Join-Path $btDir 'aapt2.exe'
$d8         = Join-Path $btDir 'd8.bat'
$zipalign   = Join-Path $btDir 'zipalign.exe'
$apksigner  = Join-Path $btDir 'apksigner.bat'

# Zorg dat res/drawable-nodpi/ic_launcher.png en assets/ klaarstaan met de nieuwste web-app
$ResDrawable = Join-Path $ProjectDir 'res\drawable-nodpi'
$AssetsDir   = Join-Path $ProjectDir 'assets'
New-Item -ItemType Directory -Force -Path $ResDrawable, $AssetsDir, $ProductDir | Out-Null

Copy-Item -Path (Join-Path $ProjectDir 'icon-192.png') -Destination (Join-Path $ResDrawable 'ic_launcher.png') -Force
foreach ($assetName in @('index.html', 'manifest.json', 'sw.js', 'icon-192.png', 'icon-512.png')) {
    $srcPath = Join-Path $ProjectDir $assetName
    if (Test-Path $srcPath) {
        Copy-Item -Path $srcPath -Destination (Join-Path $AssetsDir $assetName) -Force
    }
}

$BuildDir = Join-Path $ProjectDir 'build'
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$BuildDir\compiled_res", "$BuildDir\gen", "$BuildDir\classes", "$BuildDir\dex" | Out-Null

Write-Host "=== 2. Compileer Android resources (aapt2) ==="
$resFiles = Get-ChildItem -Path (Join-Path $ProjectDir 'res') -File -Recurse
foreach ($f in $resFiles) {
    & $aapt2 compile $f.FullName -o "$BuildDir\compiled_res"
    if ($LASTEXITCODE -ne 0) { throw "aapt2 compile mislukt op $($f.FullName)" }
}

Write-Host "=== 3. Link APK + ingebakken offline assets (aapt2 link) ==="
$flatFiles   = Get-ChildItem -Path "$BuildDir\compiled_res" -Filter '*.flat' | ForEach-Object { $_.FullName }
$unsignedApk = Join-Path $BuildDir 'werkplaats-mobiel-unaligned.apk'
& $aapt2 link -o $unsignedApk -I $androidJar --manifest (Join-Path $ProjectDir 'AndroidManifest.xml') -A $AssetsDir --java "$BuildDir\gen" $flatFiles
if ($LASTEXITCODE -ne 0) { throw "aapt2 link mislukt" }

Write-Host "=== 4. Compileer Java-broncode (javac) ==="
$javaSources = Get-ChildItem -Path (Join-Path $ProjectDir 'src'), "$BuildDir\gen" -Filter '*.java' -Recurse | ForEach-Object { $_.FullName }
& $javac.FullName -source 1.8 -target 1.8 -bootclasspath $androidJar -classpath $androidJar -d "$BuildDir\classes" -encoding UTF-8 $javaSources
if ($LASTEXITCODE -ne 0) { throw "javac mislukt" }

Write-Host "=== 5. Vertaal naar Dalvik bytecode (d8) ==="
$classFiles = Get-ChildItem -Path "$BuildDir\classes" -Filter '*.class' -Recurse | ForEach-Object { $_.FullName }
& $d8 --lib $androidJar --output "$BuildDir\dex" $classFiles
if ($LASTEXITCODE -ne 0) { throw "d8 mislukt" }

Write-Host "=== 6. Voeg classes.dex toe en onderteken APK ==="
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($unsignedApk, 'Update')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$BuildDir\dex\classes.dex", 'classes.dex', [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
$zip.Dispose()

$alignedApk = Join-Path $BuildDir 'werkplaats-mobiel-aligned.apk'
& $zipalign -f -p 4 $unsignedApk $alignedApk
if ($LASTEXITCODE -ne 0) { throw "zipalign mislukt" }

$keystore = Join-Path $BlocksDir 'gerwald-debug.keystore'
$finalApk = Join-Path $ProductDir 'werkplaats-mobiel.apk'
& $apksigner sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out $finalApk $alignedApk
if ($LASTEXITCODE -ne 0) { throw "apksigner mislukt" }

# Ruim tijdelijke build- en assets-kopie op zodat git schoon blijft
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $AssetsDir -Recurse -Force -ErrorAction SilentlyContinue

$apkInfo = Get-Item $finalApk
Write-Host "=== KLAAR! APK gebakken: $($apkInfo.FullName) ($([math]::Round($apkInfo.Length / 1KB, 1)) KB) ==="
