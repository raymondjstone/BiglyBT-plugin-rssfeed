# PowerShell build script for BiglyBT-plugin-rssfeed (sortable fork).
# Use this when Ant is not installed. Produces dist/rssfeed.jar.

$ErrorActionPreference = 'Stop'
$root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = Join-Path $root 'lib'
$buildDir  = Join-Path $root 'build'
$classDir  = Join-Path $buildDir 'classes'
$distDir   = Join-Path $root 'dist'
$resDir    = Join-Path $root 'org\kmallan\resource'

$biglybt = Join-Path $libDir 'BiglyBT.jar'
if (-not (Test-Path $biglybt)) {
    throw "Missing $biglybt. Copy BiglyBT.jar (sits next to the BiglyBT executable on a typical install) into $libDir\."
}

# Locate javac/jar. PowerShell often doesn't pick up jar.exe even when javac is on PATH.
function Find-JdkTool($name) {
    $cmd = Get-Command "$name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($base in @('C:\Program Files\Java', 'C:\Program Files (x86)\Java', 'C:\Program Files\Common Files\Oracle\Java\javapath')) {
        if (-not (Test-Path $base)) { continue }
        $hit = Get-ChildItem $base -Recurse -Filter "$name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "Could not locate $name.exe - make sure a JDK is installed."
}

$javac = Find-JdkTool 'javac'
$jar   = Find-JdkTool 'jar'
Write-Host "javac: $javac"
Write-Host "jar:   $jar"

# Load plugin.properties for version stamping.
$plugin = @{}
Get-Content (Join-Path $root 'plugin.properties') |
    Where-Object { $_ -match '^\s*([^#=][^=]*)=(.*)$' } |
    ForEach-Object {
        $kv = $_ -split '=', 2
        $plugin[$kv[0].Trim()] = $kv[1].Trim()
    }
$pluginId  = $plugin['plugin.id']
$pluginVer = $plugin['plugin.version']

Write-Host "Building $pluginId $pluginVer"

if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
if (Test-Path $distDir)  { Remove-Item -Recurse -Force $distDir }
New-Item -ItemType Directory -Force -Path $classDir | Out-Null
New-Item -ItemType Directory -Force -Path $distDir  | Out-Null

# Build classpath: BiglyBT + json-io.
$cpEntries = @($biglybt)
Get-ChildItem $root -Filter 'json-io*.jar' | ForEach-Object { $cpEntries += $_.FullName }
$cp = $cpEntries -join ';'

$javaSources = Get-ChildItem (Join-Path $root 'org\kmallan\azureus\rssfeed') -Filter '*.java' |
    ForEach-Object { $_.FullName }

Write-Host "Compiling $($javaSources.Count) Java files (release 8)..."
& $javac -encoding UTF-8 --release 8 -d $classDir -cp $cp $javaSources
if ($LASTEXITCODE -ne 0) { throw "javac failed with exit code $LASTEXITCODE" }

# Copy non-class resources into the classes dir so they're inside the jar.
$resDest = Join-Path $classDir 'org\kmallan\resource'
New-Item -ItemType Directory -Force -Path $resDest | Out-Null
Copy-Item -Recurse -Force "$resDir\*" $resDest

# Copy plugin.properties to the classes dir so it lands at the jar root.
Copy-Item (Join-Path $root 'plugin.properties') $classDir

$jarVer  = Join-Path $distDir "${pluginId}_${pluginVer}.jar"
$jarMain = Join-Path $distDir "${pluginId}.jar"

Write-Host "Packing jar: $jarMain"
& $jar --create --file $jarVer  -C $classDir .
if ($LASTEXITCODE -ne 0) { throw "jar (versioned) failed with exit code $LASTEXITCODE" }
& $jar --create --file $jarMain -C $classDir .
if ($LASTEXITCODE -ne 0) { throw "jar (main) failed with exit code $LASTEXITCODE" }

Write-Host "Done."
Write-Host "  $jarMain"
Write-Host "  $jarVer"
