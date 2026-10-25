# The build pipeline: from disc images to a native PC game, driven by a game profile (games/<id>/game.toml).
# The launcher's Install tab runs it; build.cmd runs it from a terminal. Stages (run in this order, any subset):
#   fetch      engine/runtime: clone engine/runtime.toml's repository at its commit, apply engine/patches/*.patch
#   discs      -Discs "<iso>|<iso>": tools/disc/prepare.py -> data/<game>/discs/*, languages.json, one memory card
#   configure  CMake + Ninja in -BuildRoot (a short path: the runtime's dependencies exceed MAX_PATH in long folders),
#              with the recorded VU1 microcode (data/<game>/vu1_capture) when there is some
#   recomp     ps2_recomp: the profile's executable (languages.json: recompile_elf) -> C++ (data/<game>/recomp)
#   sync       generated C++ + the profile's overrides into the runtime's runner (only changed files)
#   build      ps2EntryRunner (log: data/<game>/logs/build.log)
#   pgo        clang only: an instrumented build plays the [optimize] pad script, its profile goes to
#              data/<game>/pgo/gow.profdata, and the game is rebuilt with it (profile-guided optimisation)
#   optimize   the game plays itself (profile [optimize]: pad script, seconds) recording the VU1 microcode and IOP
#              modules it uses, then "native"
#   native     the recorded VU1 microcode and IOP modules compiled into the game (the launcher records new microcode
#              while you play, so this makes visited areas faster); configure + build
#   launcher   the Qt launcher from launcher/ into launcher/build (Qt 6 downloaded once into data/_tools), plus the
#              shortcut "God of War Launcher.lnk" in the repository root to start it
#   package    the release zip for GitHub Releases (data/_package): launcher/bin + tools, games, engine (no runtime), docs
#   installer  the release setup (data/_package/gow-native-pc-setup.exe): installer/ built and packed with the package
# Output protocol for the launcher: "=== <step> ===", "@@progress <done> <all>", "@@status <text>", other lines = log.
# usage: powershell -ExecutionPolicy Bypass -File tools\pipeline\build.ps1 [-Game gow1] [-Stages fetch,discs,configure,
#        recomp,sync,build] [-Discs "<iso>|<iso>"] [-Config Release|RelWithDebInfo] [-Ltcg] [-Pdb] [-BuildRoot <folder>]
# -BuildRoot: default C:\gow-build (or C:\gow-build-<hash> when another copy uses it), kept in data\build-root.txt
# -Pdb: Release with debug information (ps2EntryRunner.pdb) for profilers; the optimised code is the same
# -Codegen locals (default): recomp stage with register-locals code generation (engine/patches/08, ~22 % less EE
#        thread time); -Codegen classic generates the code as before patch 08
# -Toolchain msvc|clang: the C++ compiler. msvc = Visual Studio Build Tools (cl.exe, 45-60 min for a full build);
#        clang = llvm-mingw (downloaded once into data\_tools, no Visual Studio needed for the game, ~15 min, static
#        exe; needs engine/patches/12). clang builds go to <build root>-clang, so switching keeps both. The choice is
#        remembered in data\toolchain.txt (the launcher's runs use it too). With data\<game>\pgo\gow.profdata (the pgo
#        stage) clang builds are profile-guided.
param(
    [string]$Game = 'gow1',
    [string[]]$Stages = @('fetch', 'discs', 'configure', 'recomp', 'sync', 'build'),
    [string]$Discs = '',
    [ValidateSet('Release', 'RelWithDebInfo')][string]$Config = 'Release',
    [switch]$Ltcg,
    [switch]$Pdb,
    [ValidateSet('classic', 'locals')][string]$Codegen = 'locals',
    [string]$BuildRoot = '',
    [ValidateSet('', 'msvc', 'clang')][string]$Toolchain = '',
    [int]$Seconds = 0
)
$ErrorActionPreference = 'Stop'
trap { Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Stages = @(($Stages -join ',') -split ',' | Where-Object { $_ })
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Need($p, $what) { if (-not (Test-Path $p)) { throw "Missing $what : $p" } }
function Barra($p) { $p -replace '\\', '/' }
# native tools print progress on stderr; under 'Stop' PowerShell 5.1 may turn that into an exception
function Native($exe, [string[]]$a, $what) {
    $ErrorActionPreference = 'Continue'
    & $exe @a 2>&1 | ForEach-Object { $s = "$_"; if ($s -ne 'System.Management.Automation.RemoteException') { Write-Host $s } }
    if ($LASTEXITCODE -ne 0) { throw "$what failed (rc=$LASTEXITCODE)" }
}

# --- tools -----------------------------------------------------------------------------------------------------------
# a Python 3 that really runs: the Microsoft Store's python.exe stub (WindowsApps) is a command but not a Python
$python = $null
$stub = $false
foreach ($name in 'python', 'py') {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { continue }
    & $cmd.Source -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' *> $null
    if ($LASTEXITCODE -eq 0) { $python = $cmd.Source; break }
    if ($cmd.Source -like '*\WindowsApps\*') { $stub = $true }
}
if (-not $python) {
    if ($stub) { throw 'Python 3 not found: "python" is the Microsoft Store shortcut. Install Python from python.org (tick "Add python.exe to PATH") or turn off the python.exe App execution alias in Windows Settings' }
    throw 'Python 3 not found: install it from python.org and tick "Add python.exe to PATH" (a new terminal or launcher start is needed afterwards)'
}
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
$profileJson = & $python -I (Join-Path $root 'tools\pipeline\profile.py') $Game
if ($LASTEXITCODE -ne 0) { throw "no game profile '$Game' (games\$Game\game.toml)" }
$prof = $profileJson | Out-String | ConvertFrom-Json
if ($prof.status -eq 'planned') { throw "$($prof.title) is not supported yet (games\$Game\README.md)" }
$runtimeToml = Get-Content (Join-Path $root 'engine\runtime.toml') -Raw
$runtimeRepo = [regex]::Match($runtimeToml, '(?m)^repository\s*=\s*"([^"]+)"').Groups[1].Value
$runtimeCommit = [regex]::Match($runtimeToml, '(?m)^commit\s*=\s*"([^"]+)"').Groups[1].Value
$rt = Join-Path $root 'engine\runtime'
$rec = Join-Path $rt 'PS2Recomp'
$data = Join-Path $root "data\$Game"
$logs = Join-Path $data 'logs'
$gen = Join-Path $data 'recomp'
$vu1 = Join-Path $data 'vu1_capture'
$iopMods = Join-Path $data 'iop_modules'
# Build folder of this copy, remembered in data\build-root.txt (the launcher reads it too). C:\gow-build unless another
# copy (a development checkout, a second installation) already configured it: CMake refuses a cache made from another
# source folder, so this copy then takes C:\gow-build-<hash of its folder>.
$buildRootFile = Join-Path $root 'data\build-root.txt'
if (-not $BuildRoot -and (Test-Path $buildRootFile)) { $BuildRoot = (Get-Content $buildRootFile -Raw).Trim() }
if (-not $BuildRoot) {
    $BuildRoot = 'C:\gow-build'
    $cache = Join-Path $BuildRoot 'CMakeCache.txt'
    if (Test-Path $cache) {
        $home_ = [regex]::Match((Get-Content $cache -Raw), '(?m)^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$').Groups[1].Value.Trim()
        if (-not $home_.StartsWith((Barra $rt), [StringComparison]::OrdinalIgnoreCase)) {
            $md5 = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))
            $BuildRoot = 'C:\gow-build-' + (($md5[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
        }
    }
    New-Item -ItemType Directory -Force (Split-Path $buildRootFile) | Out-Null
    [IO.File]::WriteAllText($buildRootFile, $BuildRoot)
}
# the compiler: -Toolchain, else the one this copy used last (data\toolchain.txt), else msvc
$toolchainFile = Join-Path $root 'data\toolchain.txt'
if (-not $Toolchain -and (Test-Path $toolchainFile)) { $Toolchain = (Get-Content $toolchainFile -Raw).Trim() }
if ($Toolchain -notin @('msvc', 'clang')) { $Toolchain = 'msvc' }
[IO.File]::WriteAllText($toolchainFile, $Toolchain)
$bld = if ($Config -eq 'Release') { $BuildRoot } else { "$BuildRoot-dev" }   # Ninja is single-config: one folder each
if ($Toolchain -eq 'clang') { $bld += '-clang' }   # CMake cannot change the compiler of a configured folder
$pgoDir = Join-Path $root "data\$Game\pgo"
$pgoProfile = Join-Path $pgoDir 'gow.profdata'
$runnerExe = Join-Path $bld 'ps2xRuntime\ps2EntryRunner.exe'
New-Item -ItemType Directory -Force $data, $logs | Out-Null
# git settings for this process only (the user's git config is not changed): long paths (the dependencies'
# checkouts), and engine\runtime trusted as ours — on drives without file owners (exFAT/FAT32 USB disks, some network
# shares) git otherwise stops with "detected dubious ownership in repository"
$env:GIT_CONFIG_COUNT = '2'
$env:GIT_CONFIG_KEY_0 = 'core.longpaths'; $env:GIT_CONFIG_VALUE_0 = 'true'
$env:GIT_CONFIG_KEY_1 = 'safe.directory'; $env:GIT_CONFIG_VALUE_1 = (Barra $rt)
# parallel compilers: two logical cores stay free for Windows (a build on every core froze the machine), at most one
# compiler per 1.6 GB above 4 GB (a cl.exe on generated code takes 1.3-1.6 GB; paging made the build and the test crawl)
$ramGb = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
$jobs = [int][math]::Max(1, [math]::Min([Environment]::ProcessorCount - 2, [math]::Floor(($ramGb - 4) / 1.6)))
# the whole pipeline (cl.exe, ninja, python) runs below normal priority so the desktop stays usable; the recorded test
# game goes back to normal priority in the optimize stage
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

function Use-Msvc {
    if ($env:VCINSTALLDIR) { return }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw 'Visual Studio Build Tools not found: install them with "Desktop development with C++"' }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'the Build Tools have no C++ compiler: add "Desktop development with C++"' }
    cmd /c "`"$vs\VC\Auxiliary\Build\vcvars64.bat`" >nul && set" | ForEach-Object { if ($_ -match '^([^=]+)=(.*)$') { Set-Item "env:$($Matches[1])" $Matches[2] } }
    foreach ($c in @('cl', 'cmake', 'ninja')) { if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "$c not found after vcvars64.bat" } }
}
# llvm-mingw (clang for Windows with its own headers and libraries; Visual Studio is not used) downloaded once, plus
# CMake and Ninja: from PATH or the Build Tools when present, otherwise from pip
$llvmVersion = 'llvm-mingw-20261020-ucrt-x86_64'
$llvmSha256 = 'fd5462b7f5d93b2ff981fcd3f9c7e427e47f3203c64ea91c27bcc444eebd74cd'
function Use-Clang {
    if ($script:clangReady) { return }
    $tools = Join-Path $root 'data\_tools'
    $llvm = Join-Path $tools $llvmVersion
    if (-not (Test-Path (Join-Path $llvm 'bin\clang++.exe'))) {
        $zip = Join-Path $tools "$llvmVersion.zip"
        New-Item -ItemType Directory -Force $tools | Out-Null
        if (-not (Test-Path $zip) -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $llvmSha256) {
            Write-Host "downloading $llvmVersion (about 170 MB, once)"
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing "https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/$llvmVersion.zip" -OutFile $zip
            if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $llvmSha256) { Remove-Item $zip; throw "$llvmVersion.zip: unexpected SHA-256" }
        }
        Write-Host "unpacking $llvmVersion"
        Expand-Archive -Path $zip -DestinationPath $tools -Force
    }
    $paths = @(Join-Path $llvm 'bin')
    foreach ($c in 'cmake', 'ninja') {
        if (Get-Command $c -ErrorAction SilentlyContinue) { continue }
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $vs = if (Test-Path $vswhere) { & $vswhere -latest -products * -property installationPath } else { $null }
        $ext = if ($vs) { Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake' } else { '' }
        $cand = if ($c -eq 'cmake') { Join-Path $ext 'CMake\bin\cmake.exe' } else { Join-Path $ext 'Ninja\ninja.exe' }
        if ($vs -and (Test-Path $cand)) { $paths += Split-Path $cand }
        else {
            Native $python @('-m', 'pip', 'install', '--user', '--quiet', $c) "pip install $c"
            $paths += "$(& $python -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))")".Trim()
        }
    }
    # the MSVC environment (INCLUDE, LIB) must not leak into the mingw target
    foreach ($v in 'INCLUDE', 'LIB', 'LIBPATH', 'VCINSTALLDIR') { Remove-Item "env:$v" -ErrorAction SilentlyContinue }
    $env:PATH = ($paths -join ';') + ';' + $env:PATH
    $script:llvmBin = Join-Path $llvm 'bin'
    $script:clangReady = $true
}
function Use-Toolchain { if ($Toolchain -eq 'clang') { Use-Clang } else { Use-Msvc } }
function Languages {
    $f = Join-Path $data 'languages.json'
    if (-not (Test-Path $f)) { throw 'no prepared disc: run the "discs" stage with your ISO' }
    return Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
}

# --- fetch: the runtime -------------------------------------------------------------------------------------------
if ($Stages -contains 'fetch') {
    Step 'runtime (PS2Recomp + Tobiichi)'
    if (-not $git) { throw 'git not found: install Git for Windows' }
    if (-not (Test-Path (Join-Path $rec 'CMakeLists.txt'))) {
        Write-Host "cloning $runtimeRepo -> engine\runtime"
        Native $git @('clone', '--quiet', $runtimeRepo, $rt) 'git clone of the runtime'
    }
    $ErrorActionPreference = 'Continue'
    $head = & $git -C $rt rev-parse HEAD 2>$null
    $ErrorActionPreference = 'Stop'
    if ("$head".Trim() -ne $runtimeCommit) {
        $dirty = & $git -C $rt status --porcelain --untracked-files=no
        if ($dirty) { throw "engine\runtime has local changes and is not at ${runtimeCommit}: delete engine\runtime and run fetch again" }
        Native $git @('-C', $rt, 'fetch', '--quiet', 'origin') 'git fetch'
        Native $git @('-C', $rt, 'checkout', '--quiet', $runtimeCommit) 'git checkout'
    }
    # Which patches are in? Patches can touch the same file (01 and 07: ReleaseMode.cmake), so a per-patch reverse check
    # fails once a later one is in. Instead, in a temporary index (the files are not touched): the tree after 0..N
    # patches on the pinned commit, and the tree of the files as they are; the matching prefix tells what is left.
    $patches = @(Get-ChildItem (Join-Path $root 'engine\patches\*.patch') | Sort-Object Name)
    $index = Join-Path $env:TEMP "gow-patch-index-$PID"
    $oldIndex = $env:GIT_INDEX_FILE
    $ErrorActionPreference = 'Continue'
    try {
        $env:GIT_INDEX_FILE = $index
        & $git -C $rt read-tree HEAD
        $trees = @("$(& $git -C $rt write-tree)".Trim())
        foreach ($patch in $patches) {
            & $git -C $rt apply --cached $patch.FullName 2>$null
            if ($LASTEXITCODE -ne 0) { throw "patch $($patch.Name) does not apply to runtime commit $runtimeCommit" }
            $trees += "$(& $git -C $rt write-tree)".Trim()
        }
        $touched = @(& $git -C $rt diff --name-only HEAD $trees[-1])
        & $git -C $rt read-tree HEAD
        & $git -C $rt add -u 2>$null
        if ($touched.Count) { & $git -C $rt add -A -- $touched 2>$null }
        $current = "$(& $git -C $rt write-tree)".Trim()
    }
    finally {
        $env:GIT_INDEX_FILE = $oldIndex
        Remove-Item $index -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = 'Stop'
    }
    $done = [array]::IndexOf($trees, $current)
    if ($done -lt 0) { throw 'engine\runtime has changes that are not engine\patches: delete the engine\runtime folder and run again' }
    for ($i = 0; $i -lt $patches.Count; $i++) {
        if ($i -lt $done) { Write-Host "patch $($patches[$i].Name): applied"; continue }
        Native $git @('-C', $rt, 'apply', $patches[$i].FullName) "patch $($patches[$i].Name)"
        Write-Host "patch $($patches[$i].Name): applied now"
    }
}

# --- discs ----------------------------------------------------------------------------------------------------------
if ($Stages -contains 'discs') {
    Step 'discs'
    $list = @($Discs -split '\|' | Where-Object { $_ })
    if (-not $list) { throw 'no disc given (-Discs "<iso>|<iso>")' }
    Native $python (@('-I', (Join-Path $root 'tools\disc\prepare.py'), '--game', $Game, '--data', (Join-Path $root 'data')) + $list) 'disc preparation'
}

# --- configure ------------------------------------------------------------------------------------------------------
function Configure([string]$dir = $bld, [string]$pgo = 'auto') {
    Use-Toolchain
    Need (Join-Path $rec 'CMakeLists.txt') 'runtime (run the fetch stage)'
    $ltcgValue = if ($Ltcg) { 'ON' } else { 'OFF' }
    $pdbValue = if ($Pdb) { 'ON' } else { 'OFF' }
    $extra = @()
    if (Get-ChildItem -Path $vu1 -Filter *.bin -ErrorAction SilentlyContinue | Select-Object -First 1) {
        # the runtime's CMake reads the extra VU1 block heads from vu1n_heads.txt next to the capture folder: the profile's
        # list plus the entries the game met without native code while recording (vu1n_heads_seen.txt, see
        # VU1NativeAccess::recordMissHead); written only when the set changes (a change regenerates the native VU1 code)
        $headList = @()
        if ($prof.runtime.vu1_native_heads) { $headList += Join-Path $rt $prof.runtime.vu1_native_heads }
        $headList += Join-Path $vu1 'vu1n_heads_seen.txt'
        $headSet = @($headList | Where-Object { Test-Path $_ } | ForEach-Object { Get-Content $_ } |
            ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -match '^[0-9a-f]+$' } | Sort-Object -Unique)
        $headsDst = Join-Path $data 'vu1n_heads.txt'
        $headsText = ($headSet -join "`n") + "`n"
        if ($headSet -and -not ((Test-Path $headsDst) -and ((Get-Content $headsDst -Raw) -eq $headsText))) {
            [IO.File]::WriteAllText($headsDst, $headsText)
            Write-Host "VU1 block heads: $($headSet.Count)"
        }
        $extra += "-DPS2X_VU1_MICROCODE_DIR=$(Barra $vu1)"
        $extra += "-DPS2X_VU1_GENERATOR_SOURCE=$(Barra (Join-Path $rt $prof.runtime.vu1_generator))"
        $extra += "-DPS2X_VU1N_GEN_OVERRIDE=$(Barra (Join-Path $rt $prof.runtime.vu1_native_generator))"
    }
    if ($Toolchain -eq 'clang') {
        # -fno-strict-aliasing -fwrapv: the generated code and the runtime rely on MSVC's lenient aliasing and wrapping;
        # -static: no libc++ / libunwind DLLs next to the exe
        $flags = '-fno-strict-aliasing -fwrapv'
        $link = '-static'
        if ($pgo -eq 'generate') { $flags += ' -fprofile-instr-generate'; $link += ' -fprofile-instr-generate' }
        elseif ($pgo -eq 'auto' -and (Test-Path $pgoProfile)) {
            Write-Host "profile-guided: $pgoProfile"
            $flags += " -fprofile-instr-use=$(Barra $pgoProfile) -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date"
        }
        $extra += @('-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++', '-DCMAKE_RC_COMPILER=llvm-rc',
            "-DCMAKE_C_FLAGS=$flags", "-DCMAKE_CXX_FLAGS=$flags", "-DCMAKE_EXE_LINKER_FLAGS=$link")
    }
    Native 'cmake' (@('-S', $rec, '-B', $dir, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$Config", "-DPS2X_RELEASE_LTCG=$ltcgValue", "-DPS2X_RELEASE_PDB=$pdbValue",
        '-DPS2X_ENABLE_RUNTIME_LOGS=OFF', '-DPS2X_ENABLE_AGRESSIVE_LOGS=OFF', '-DPS2X_ENABLE_IOP_RPC_TRACE=OFF',
        '-DPS2X_BUILD_STUDIO=OFF', '-DPS2X_BUILD_ANALYZER=OFF', '-DPS2X_BUILD_TEST=OFF', '-DPS2X_SHOW_WINDOWS_CONSOLE=OFF',
        '-DPS2X_RUNNER_UNITY_BUILD_BATCH_SIZE=8') + $extra) 'cmake configure'
}
if ($Stages -contains 'configure') { Step "configure ($Config, $bld)"; Configure }

# --- recompile ------------------------------------------------------------------------------------------------------
if ($Stages -contains 'recomp') {
    Step 'recompile the executable'
    Use-Toolchain
    Need (Join-Path $bld 'CMakeCache.txt') 'configured build folder (run the configure stage)'
    Native 'ninja' @('-C', $bld, "-j$jobs", 'ps2_recomp') 'ps2_recomp build'
    $elf = (Languages).recompile_elf
    Need $elf 'executable to recompile'
    $out = Join-Path $gen 'out'
    New-Item -ItemType Directory -Force $out | Out-Null
    Get-ChildItem $out -File | Remove-Item
    Copy-Item $elf (Join-Path $gen $prof.executable.name) -Force
    Copy-Item (Join-Path $rt $prof.runtime.function_map) (Join-Path $gen 'funcmap.csv') -Force
    (Get-Content -Raw (Join-Path $rt $prof.runtime.recompiler_template)) `
        -replace '@ELF@', (Barra (Join-Path $gen $prof.executable.name)) `
        -replace '@MAP@', (Barra (Join-Path $gen 'funcmap.csv')) `
        -replace '@OUT@', ((Barra $out) + '/') | Set-Content (Join-Path $gen 'recomp.toml') -Encoding ASCII
    $ErrorActionPreference = 'Continue'   # ~2000 control-flow warnings on stderr are expected
    if ($Codegen -eq 'locals') { $env:PS2X_CODEGEN = 'locals'; Write-Host 'code generation: register locals' }
    & (Join-Path $bld 'ps2xRecomp\ps2_recomp.exe') (Join-Path $gen 'recomp.toml') *>&1 | ForEach-Object { "$_" } |
        Out-File -Encoding utf8 (Join-Path $logs 'recomp.log')
    $rc = $LASTEXITCODE
    Remove-Item env:PS2X_CODEGEN -ErrorAction SilentlyContinue
    $ErrorActionPreference = 'Stop'
    if ($rc -ne 0) { throw 'ps2_recomp failed (data\<game>\logs\recomp.log)' }
    Write-Host ("generated: {0} files" -f (Get-ChildItem $out -File).Count)
}

# --- sync -----------------------------------------------------------------------------------------------------------
if ($Stages -contains 'sync') {
    Step 'generated code into the runner'
    $out = Join-Path $gen 'out'
    Need $out 'recompiler output (run the recomp stage)'
    $runner = Join-Path $rec 'ps2xRuntime\src\runner'
    $incl = Join-Path $rec 'ps2xRuntime\include'
    New-Item -ItemType Directory -Force $runner | Out-Null
    function Copy-IfChanged($src, $dst) {
        if (Test-Path $dst) {
            $a = Get-Item $src; $b = Get-Item $dst
            if ($a.Length -eq $b.Length -and [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($a.FullName), [IO.File]::ReadAllBytes($b.FullName))) { return 0 }
        }
        Copy-Item -Force $src $dst; return 1
    }
    $changed = 0
    foreach ($f in Get-ChildItem (Join-Path $out '*.cpp')) { $changed += Copy-IfChanged $f.FullName (Join-Path $runner $f.Name) }
    foreach ($f in Get-ChildItem (Join-Path $out '*.h')) { $changed += Copy-IfChanged $f.FullName (Join-Path $incl $f.Name) }
    foreach ($o in $prof.runtime.overrides) { $changed += Copy-IfChanged (Join-Path $rt $o) (Join-Path $runner (Split-Path -Leaf $o)) }
    Write-Host "runner: $changed files updated"
}

# --- build ----------------------------------------------------------------------------------------------------------
function Build-Game([string]$dir = $bld) {
    Use-Toolchain
    Need (Join-Path $dir 'CMakeCache.txt') 'configured build folder (run the configure stage)'
    $log = Join-Path $logs 'build.log'
    Write-Host "$jobs compilers in parallel"
    $ErrorActionPreference = 'Continue'
    $writer = New-Object IO.StreamWriter($log, $false, (New-Object Text.UTF8Encoding($false)))
    $writer.AutoFlush = $true
    $lastPct = -1; $errors = 0
    & ninja -C $dir "-j$jobs" ps2EntryRunner 2>&1 | ForEach-Object {
        $s = "$_"
        if ($s -eq 'System.Management.Automation.RemoteException') { return }
        $writer.WriteLine($s)
        if ($s -match '^\[(\d+)/(\d+)\]') {
            $pct = [int](100 * [int]$Matches[1] / [int]$Matches[2])
            if ($pct -ne $lastPct) { $lastPct = $pct; Write-Host "@@progress $($Matches[1]) $($Matches[2])" }
            if ($s -match 'Linking CXX executable') { Write-Host '@@status linking the executable' }
        } elseif ($s -match 'error C\d|error LNK|fatal error|FAILED:|error:') { if (++$errors -le 20) { Write-Host $s -ForegroundColor Red } }
    }
    $rc = $LASTEXITCODE
    $writer.Close()
    $ErrorActionPreference = 'Stop'
    if ($rc -ne 0) { throw "build failed (rc=$rc), data\$Game\logs\build.log" }
    Write-Host "OK: $(Join-Path $dir 'ps2xRuntime\ps2EntryRunner.exe')"
}
if ($Stages -contains 'build') { Step "build the game ($Config, $Toolchain)"; Build-Game }

# --- pgo: profile-guided optimisation (clang) -----------------------------------------------------------------------
# An instrumented copy of the game (its own build folder) plays the [optimize] pad script with the hardware renderer and
# sound, like a player; closing its window writes the profile (engine/patches/12), which is merged into gow.profdata and
# used by every later clang build. A new recompile leaves it partly stale (those functions are just not profiled).
if ($Stages -contains 'pgo') {
    if ($Toolchain -ne 'clang') { throw 'the pgo stage needs -Toolchain clang' }
    $genBld = "$bld-pgogen"
    Step 'profile-guided optimisation: instrumented build'
    Configure $genBld 'generate'
    Build-Game $genBld
    $secs = if ($Seconds -gt 0) { $Seconds } else { [int]$prof.optimize.seconds }
    Step "profile-guided optimisation: the game plays itself for $secs s (do not touch the keyboard or the game window)"
    $elf = (Languages).recompile_elf
    New-Item -ItemType Directory -Force $pgoDir | Out-Null
    Get-ChildItem $pgoDir -Filter '*.profraw' -ErrorAction SilentlyContinue | Remove-Item
    $vars = @{ LLVM_PROFILE_FILE = (Join-Path $pgoDir 'run-%p.profraw'); GOW_SKIP_FMV = '1'; GOW_PAD_TEST = '1'; GOW_PAD_TEST_NO_CAPTURE = '1'
               PS2X_GS_WORKER = '1'; GOW_GS_FINISH_ASINCRONO = '1'; PS2X_GS_HW = '1'; GOW_AUDIO_DEVICE = 'default'
               GOW_PAD_GUION = $prof.optimize.pad_script }
    if (Get-ChildItem -Path $vu1 -Filter *.bin -ErrorAction SilentlyContinue | Select-Object -First 1) { $vars.GOW_VU1_CAPTURA = $vu1 }
    foreach ($k in $vars.Keys) { Set-Item "env:$k" $vars[$k] }
    $p = Start-Process -FilePath (Join-Path $genBld 'ps2xRuntime\ps2EntryRunner.exe') -ArgumentList "`"$elf`"" -WorkingDirectory $logs -PassThru
    try { $p.PriorityClass = 'Normal' } catch { }
    for ($t = 0; $t -lt $secs -and -not $p.HasExited; $t += 5) { Start-Sleep 5; Write-Host "@@progress $([math]::Min($t + 5, $secs)) $secs" }
    if (-not $p.HasExited) { $null = $p.CloseMainWindow(); $null = $p.WaitForExit(60000) }   # the profile is written on close
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    foreach ($k in $vars.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    $raw = @(Get-ChildItem $pgoDir -Filter '*.profraw' | Where-Object Length -gt 0)
    if (-not $raw) { throw 'the instrumented game wrote no profile' }
    Native (Join-Path $script:llvmBin 'llvm-profdata.exe') (@('merge', '-o', $pgoProfile) + @($raw.FullName)) 'llvm-profdata merge'
    $raw | Remove-Item
    Write-Host ("profile: {0} ({1:N0} MB)" -f $pgoProfile, ((Get-Item $pgoProfile).Length / 1MB))
    Step "rebuild with the profile ($Config, clang)"
    Configure
    Build-Game
}

# --- optimize / native ----------------------------------------------------------------------------------------------
if ($Stages -contains 'optimize') {
    $secs = if ($Seconds -gt 0) { $Seconds } else { [int]$prof.optimize.seconds }
    Step "record: the game plays itself for $secs s (do not touch the keyboard or the game window)"
    Need $runnerExe 'built game (run the build stage)'
    $elf = (Languages).recompile_elf
    New-Item -ItemType Directory -Force $vu1, $iopMods | Out-Null
    $vars = @{ GOW_VU1_CAPTURA = $vu1; PS2X_IOP_DUMP_MODULES = $iopMods; GOW_SKIP_FMV = '1'; GOW_PAD_TEST = '1'; GOW_AUDIO = '0'
               GOW_PAD_TEST_NO_CAPTURE = '1'; PS2X_GS_WORKER = '1'; GOW_GS_FINISH_ASINCRONO = '1'; GOW_PAD_GUION = $prof.optimize.pad_script }
    foreach ($k in $vars.Keys) { Set-Item "env:$k" $vars[$k] }
    # nothing left from the build (mspdbsrv, vctip, a stray cl.exe) may compete with the game for the 4 minutes
    Get-Process -Name mspdbsrv, vctip, cl, link -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $runnerExe -ArgumentList "`"$elf`"" -WorkingDirectory $logs -PassThru
    try { $p.PriorityClass = 'Normal' } catch { }
    for ($t = 0; $t -lt $secs -and -not $p.HasExited; $t += 5) { Start-Sleep 5; Write-Host "@@progress $([math]::Min($t + 5, $secs)) $secs" }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    foreach ($k in $vars.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
}
if ($Stages -contains 'optimize' -or $Stages -contains 'native') {
    Step 'native VU1 and IOP code'
    $nVu1 = @(Get-ChildItem $vu1 -Filter *.bin -ErrorAction SilentlyContinue).Count
    $nIop = @(Get-ChildItem $iopMods -Filter *.bin -ErrorAction SilentlyContinue).Count
    Write-Host "recorded: $nVu1 VU1 micro-memories, $nIop IOP modules"
    if ($nIop -gt 0) { Native $python @('-I', (Join-Path $rt $prof.runtime.iop_native_generator), $iopMods, (Join-Path $rec 'ps2xIOP\src\native')) 'IOP native code' }
    Configure
    Step "rebuild ($Config)"
    Build-Game
    Set-Content -Path (Join-Path $data 'native.stamp') -Value "$nVu1" -Encoding ASCII
}

# --- launcher (development) -----------------------------------------------------------------------------------------
if ($Stages -contains 'launcher') {
    Step 'launcher (Qt 6)'
    Use-Msvc
    $qtVersion = '6.8.3'
    $qtDir = Join-Path $root 'data\_tools\qt'
    $qt = Get-ChildItem -Path 'C:\Qt', $qtDir -Directory -Filter '6.*' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem $_.FullName -Directory -Filter 'msvc*_64' } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $qt) {
        Write-Host "downloading Qt $qtVersion (aqtinstall, about 1 GB, once)"
        New-Item -ItemType Directory -Force $qtDir | Out-Null
        Native $python @('-m', 'pip', 'install', '--user', '--quiet', '--upgrade', 'aqtinstall') 'pip install aqtinstall'
        Push-Location $qtDir
        try { Native $python @('-m', 'aqt', 'install-qt', 'windows', 'desktop', $qtVersion, 'win64_msvc2022_64', '-O', $qtDir) 'Qt download' }
        finally { Pop-Location }
        $qt = Join-Path $qtDir "$qtVersion\msvc2022_64"
    }
    $lb = Join-Path $root 'launcher\build'
    Native 'cmake' @('-S', (Join-Path $root 'launcher'), '-B', $lb, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_PREFIX_PATH=$(Barra $qt)") 'launcher configure'
    Native 'ninja' @('-C', $lb, "-j$jobs") 'launcher build'
    $exe = Get-ChildItem $lb -Filter '*.exe' | Select-Object -First 1 -ExpandProperty FullName
    Native (Join-Path $qt 'bin\windeployqt.exe') @('--release', '--no-translations', '--qmldir', (Join-Path $root 'launcher\qml'), $exe) 'windeployqt'
    # shortcut in the repository root, so the built launcher is one double-click away
    $lnk = Join-Path $root 'God of War Launcher.lnk'
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $sc.TargetPath = $exe; $sc.WorkingDirectory = $lb; $sc.IconLocation = "$exe,0"; $sc.Description = 'God of War Native PC'
    $sc.Save()
    Write-Host "OK: $exe"
    Write-Host "shortcut: $lnk"
}
# --- package: the release zip (GitHub Releases) ---------------------------------------------------------------------
# launcher/bin = the built launcher + its Qt DLLs; the rest is this repository without generated data. Users unzip it
# anywhere and start launcher\bin\gow-launcher.exe (it finds the repository root by games\<id>\game.toml above it).
if ($Stages -contains 'package' -or ($Stages -contains 'installer' -and -not (Test-Path (Join-Path $root 'data\_package\gow-native-pc')))) {
    Step 'release package'
    $lb = Join-Path $root 'launcher\build'
    $exe = Join-Path $lb 'gow-launcher.exe'
    Need $exe 'built launcher (run the launcher stage)'
    $stage = Join-Path $root 'data\_package\gow-native-pc'
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Force (Join-Path $stage 'launcher\bin') | Out-Null
    # build outputs only: the QML module folder (Tobiichi/) is compiled into the exe, .exp/.lib/.cpp are link leftovers
    Get-ChildItem $lb | Where-Object { $_.Name -notmatch '^(CMakeFiles|\.ninja.*|\.qt|build\.ninja|CMakeCache\.txt|cmake_install\.cmake|.*_autogen|.*\.qmltypes|qmltypes|\.rcc|meta_types|Tobiichi|.*\.exp|.*\.lib|.*\.cpp|.*\.pdb|.*\.ilk)$' } |
        Copy-Item -Destination (Join-Path $stage 'launcher\bin') -Recurse -Force
    foreach ($item in @('README.md', 'README.pt-BR.md', 'CREDITS.md', 'LICENSE', 'AGENTS.md', 'CLAUDE.md', 'build.cmd', 'docs', 'games', 'tools')) {
        Copy-Item (Join-Path $root $item) $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Force (Join-Path $stage 'engine') | Out-Null
    Copy-Item (Join-Path $root 'engine\runtime.toml'), (Join-Path $root 'engine\README.md') (Join-Path $stage 'engine')
    Copy-Item (Join-Path $root 'engine\patches') (Join-Path $stage 'engine') -Recurse
    Get-ChildItem $stage -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
    $zip = Join-Path $root 'data\_package\gow-native-pc-windows.zip'
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path $stage -DestinationPath $zip
    Write-Host ("OK: {0} ({1:N0} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
}
# --- installer: one .exe for GitHub Releases ------------------------------------------------------------------------
# installer/setup.cpp (Win32, no Qt) packs the package folder into a copy of itself (LZMS); the result installs per user,
# makes Start menu / desktop shortcuts and an Apps entry, and removes itself (uninstall.exe).
if ($Stages -contains 'installer') {
    Step 'installer'
    Use-Msvc
    $stage = Join-Path $root 'data\_package\gow-native-pc'
    Need (Join-Path $stage 'launcher\bin\gow-launcher.exe') 'release package (run the package stage)'
    $ib = Join-Path $root 'data\_tools\installer-build'
    Native 'cmake' @('-S', (Join-Path $root 'installer'), '-B', $ib, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release') 'installer configure'
    Native 'ninja' @('-C', $ib) 'installer build'
    $setup = Join-Path $root 'data\_package\gow-native-pc-setup.exe'
    Write-Host "@@status packing (LZMS, about a minute)"
    Native (Join-Path $ib 'gow-setup.exe') @('--pack', $stage, $setup) 'installer pack'
    Write-Host ("OK: {0} ({1:N0} MB)" -f $setup, ((Get-Item $setup).Length / 1MB))
}
Write-Host "`nDone." -ForegroundColor Green
