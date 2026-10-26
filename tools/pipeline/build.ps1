# The build pipeline: from disc images to a native PC game, driven by a game profile (games/<id>/game.toml).
# The launcher's Install tab runs it; build.cmd runs it from a terminal. Stages (run in this order, any subset):
#   tools      the build tools into data/_tools (portable Git, Python, CMake, Ninja and the clang compiler, each
#              downloaded once and checked against its SHA-256); every other stage also fetches what it needs
#   fetch      engine/runtime: clone engine/runtime.toml's repository at its commit, apply engine/patches/*.patch
#   discs      -Discs "<iso>|<iso>": tools/disc/prepare.py -> data/<game>/discs/*, languages.json, one memory card
#   vu1disc    experimental: the VU1 microcode of every level read from the prepared disc (tools/disc/vu1_from_disc.py)
#              into data/<game>/vu1_capture, so the next configure + build compiles it without playing (run "native")
#   configure  CMake + Ninja in -BuildRoot (a short path: the runtime's dependencies exceed MAX_PATH in long folders),
#              with the recorded VU1 microcode (data/<game>/vu1_capture) when there is some
#   recomp     ps2_recomp: the profile's executable (languages.json: recompile_elf) -> C++ (data/<game>/recomp)
#   sync       generated C++ + the profile's overrides into the runtime's runner (only changed files)
#   build      ps2EntryRunner (log: data/<game>/logs/build.log)
#   pgo        clang only: an instrumented build plays the [optimize] pad script, its profile goes to
#              data/<game>/pgo/gow.profdata, and the game is rebuilt with it (profile-guided optimisation)
#   optimize   the game plays itself (profile [optimize]: pad script, seconds), hidden and muted (engine/patches/15), recording
#              the VU1 microcode and IOP modules it uses, then "native" (only the VU1 / IOP code is rebuilt: patch 16)
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
# -Toolchain clang|msvc: the C++ compiler. clang (the default) = llvm-mingw (downloaded once into data\_tools, no
#        Visual Studio needed, ~15 min for a full build, static exe; needs engine/patches/12); msvc = Visual Studio Build
#        Tools (cl.exe, 45-60 min). clang builds go to <build root>-clang, so switching keeps both. The choice is
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
# Portable copies in data\_tools, used instead of whatever the machine has installed (no installer, no admin rights, no
# PATH changes; an old system Python without tomllib or a Microsoft Store stub cannot get in the way). Each is downloaded
# once from its official release and checked against the SHA-256 published there.
$toolsDir = Join-Path $root 'data\_tools'
$portable = @{
    git    = @{ url = 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/MinGit-2.56.0.2-64-bit.zip'
                sha = 'da35e72aa21c005a5a0d298cfbae110bc1609a815730ea0dde84b01a1b3cd3be'; dir = 'mingit'; exe = 'cmd\git.exe'; mb = 40 }
    python = @{ url = 'https://www.python.org/ftp/python/3.13.16/python-3.13.16-embed-amd64.zip'
                sha = '97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297'; dir = 'python'; exe = 'python.exe'; mb = 11 }
    cmake  = @{ url = 'https://github.com/Kitware/CMake/releases/download/v3.31.12/cmake-3.31.12-windows-x86_64.zip'
                sha = '0c4baa40f28b3f8225eb3fdf6946c987b4fe901403b4eaf2fbbd9378100aaa0c'; dir = 'cmake'; exe = 'cmake-3.31.12-windows-x86_64\bin\cmake.exe'; mb = 52
                skip = @('*/doc/*', '*/man/*') }
    ninja  = @{ url = 'https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-win.zip'
                sha = '07fc8261b42b20e71d1720b39068c2e14ffcee6396b76fb7a795fb460b78dc65'; dir = 'ninja'; exe = 'ninja.exe'; mb = 1 }
}
# Unpacks a zip with Windows' own tar.exe (bsdtar, Windows 10 1803+): a few seconds where Expand-Archive took minutes on
# archives of thousands of small files. skip: path patterns left out (documentation, unused targets).
function Expand-Zip([string]$zip, [string]$dest, [string[]]$skip = @()) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        $a = @('-xf', $zip, '-C', $dest)
        foreach ($x in $skip) { $a += @('--exclude', $x) }
        & $tar @a
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "tar failed (rc=$LASTEXITCODE), unpacking with Expand-Archive"
    }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
}
function Get-PortableTool([string]$name) {
    $t = $portable[$name]
    $dest = Join-Path $toolsDir $t.dir
    $exe = Join-Path $dest $t.exe
    if (Test-Path $exe) { return $exe }
    New-Item -ItemType Directory -Force $toolsDir | Out-Null
    $zip = Join-Path $toolsDir ([IO.Path]::GetFileName($t.url))
    if (-not (Test-Path $zip) -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $t.sha) {
        Write-Host "@@status downloading $name (about $($t.mb) MB, once)"
        Write-Host "downloading $name : $($t.url)"
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing $t.url -OutFile $zip
        if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $t.sha) { Remove-Item $zip; throw "$name download: unexpected SHA-256 (try again)" }
    }
    Write-Host "@@status unpacking $name"
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Expand-Zip $zip $dest $(if ($t.skip) { $t.skip } else { @() })
    Remove-Item $zip
    # the embeddable Python's ._pth file would keep each script's own folder off sys.path
    if ($name -eq 'python') { Get-ChildItem $dest -Filter '*._pth' | Remove-Item }
    if (-not (Test-Path $exe)) { throw "$name : $exe missing after unpacking" }
    return $exe
}
$python = Get-PortableTool 'python'
$git = Get-PortableTool 'git'
$cmakeExe = Get-PortableTool 'cmake'
$ninjaExe = Get-PortableTool 'ninja'
# Git for CMake's dependency downloads (FetchContent), CMake and Ninja for every build
$env:PATH = (@((Split-Path $git), (Split-Path $cmakeExe), (Split-Path $ninjaExe)) -join ';') + ';' + $env:PATH
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
$md5 = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))
$ownRoot = 'C:\gow-build-' + (($md5[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
# a build folder configured from another copy's runtime (CMake refuses its cache)
function Test-ForeignCache([string]$folder) {
    $cache = Join-Path $folder 'CMakeCache.txt'
    if (-not (Test-Path $cache)) { return $false }
    $home_ = [regex]::Match((Get-Content $cache -Raw), '(?m)^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$').Groups[1].Value.Trim()
    return -not $home_.StartsWith((Barra $rt), [StringComparison]::OrdinalIgnoreCase)
}
if (-not $BuildRoot -and (Test-Path $buildRootFile)) { $BuildRoot = (Get-Content $buildRootFile -Raw).Trim() }
if (-not $BuildRoot) {
    $BuildRoot = 'C:\gow-build'
    # every folder of the root (MSVC, clang, dev configuration) must be this copy's or unused
    foreach ($folder in @($BuildRoot, "$BuildRoot-clang", "$BuildRoot-dev", "$BuildRoot-clang-pgogen")) {
        if (Test-ForeignCache $folder) { $BuildRoot = $ownRoot; break }
    }
    New-Item -ItemType Directory -Force (Split-Path $buildRootFile) | Out-Null
    [IO.File]::WriteAllText($buildRootFile, $BuildRoot)
}
# the compiler: -Toolchain, else the one this copy used last (data\toolchain.txt), else clang
$toolchainFile = Join-Path $root 'data\toolchain.txt'
if (-not $Toolchain -and (Test-Path $toolchainFile)) { $Toolchain = (Get-Content $toolchainFile -Raw).Trim() }
if ($Toolchain -notin @('msvc', 'clang')) { $Toolchain = 'clang' }
[IO.File]::WriteAllText($toolchainFile, $Toolchain)
$bld = if ($Config -eq 'Release') { $BuildRoot } else { "$BuildRoot-dev" }   # Ninja is single-config: one folder each
if ($Toolchain -eq 'clang') { $bld += '-clang' }   # CMake cannot change the compiler of a configured folder
# The recorded root can since have been taken by another copy (a test checkout configured C:\gow-build-clang): this copy
# moves to its own root, where the next build starts from scratch (a full build)
if ((Test-ForeignCache $bld) -or (Test-ForeignCache "$bld-pgogen")) {
    if ($BuildRoot -eq $ownRoot) { throw "$bld was configured from another copy of the project: delete that folder and run again" }
    Write-Host "build folder $bld belongs to another copy of the project: this copy now uses $ownRoot (the next build is a full one)"
    $bld = $bld.Replace($BuildRoot, $ownRoot)
    $BuildRoot = $ownRoot
    [IO.File]::WriteAllText($buildRootFile, $BuildRoot)
}
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
# llvm-mingw (clang for Windows with its own headers and libraries; Visual Studio is not used) downloaded once (CMake and
# Ninja: the portable tools above)
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
            Write-Host "@@status downloading the clang compiler (about 170 MB, once)"
        Write-Host "downloading $llvmVersion (about 170 MB, once)"
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing "https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/$llvmVersion.zip" -OutFile $zip
            if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $llvmSha256) { Remove-Item $zip; throw "$llvmVersion.zip: unexpected SHA-256" }
        }
        Write-Host "@@status unpacking the clang compiler"
        Write-Host "unpacking $llvmVersion"
        # only the x86-64 Windows target is used: the i686 / ARM sysroots and the debugger's Python stay out
        Expand-Zip $zip $tools @('*/aarch64-w64-mingw32/*', '*/armv7-w64-mingw32/*', '*/i686-w64-mingw32/*', '*/python/*')
        Remove-Item $zip
    }
    $paths = @(Join-Path $llvm 'bin')
    # the MSVC environment (INCLUDE, LIB) must not leak into the mingw target
    foreach ($v in 'INCLUDE', 'LIB', 'LIBPATH', 'VCINSTALLDIR') { Remove-Item "env:$v" -ErrorAction SilentlyContinue }
    $env:PATH = ($paths -join ';') + ';' + $env:PATH
    $script:llvmBin = Join-Path $llvm 'bin'
    $script:clangReady = $true
}
function Use-Toolchain { if ($Toolchain -eq 'clang') { Use-Clang } else { Use-Msvc } }
# Asks the game to close the way its window's close button does (WM_CLOSE to its GLFW window), which also works while the
# window is hidden (GOW_WINDOW_HIDDEN, engine/patches/15): Process.CloseMainWindow only finds visible windows. Returns the
# number of windows asked.
function Close-GameWindow([int]$procId) {
    if (-not ('GowWindows' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GowWindows {
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder name, int size);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    public static int Close(uint pid) {
        int asked = 0;
        EnumWindows(delegate (IntPtr hwnd, IntPtr lParam) {
            uint owner;
            GetWindowThreadProcessId(hwnd, out owner);
            var name = new StringBuilder(64);
            GetClassName(hwnd, name, name.Capacity);
            // GLFW30 = the game window (GLFW's helper window has another class)
            if (owner == pid && name.ToString() == "GLFW30") { PostMessage(hwnd, 0x0010 /* WM_CLOSE */, IntPtr.Zero, IntPtr.Zero); asked++; }
            return true;
        }, IntPtr.Zero);
        return asked;
    }
}
'@
    }
    return [GowWindows]::Close([uint32]$procId)
}
function Languages {
    $f = Join-Path $data 'languages.json'
    if (-not (Test-Path $f)) { throw 'no prepared disc: run the "discs" stage with your ISO' }
    return Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
}

# --- tools: everything above already ran; the stage also fetches the compiler ----------------------------------------
if ($Stages -contains 'tools') {
    Step 'build tools'
    if ($Toolchain -eq 'clang') { Use-Clang }
    Write-Host "OK: Git, Python, CMake, Ninja$(if ($Toolchain -eq 'clang') { ', clang' }) in $toolsDir"
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

# --- vu1disc: VU1 microcode from the disc (experimental) -------------------------------------------------------------
if ($Stages -contains 'vu1disc') {
    Step 'VU1 microcode from the disc'
    $genPy = Join-Path $rt $prof.runtime.vu1_native_generator
    Need $genPy 'runtime (run the fetch stage)'
    $discDir = Split-Path (Languages).recompile_elf
    New-Item -ItemType Directory -Force $vu1 | Out-Null
    Native $python @('-I', (Join-Path $root 'tools\disc\vu1_from_disc.py'), '--game', $Game, '--gen', $genPy, $discDir, $vu1) 'VU1 microcode from the disc'
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
        $extra += @('-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++', '-DCMAKE_RC_COMPILER=llvm-rc', "-DCMAKE_MAKE_PROGRAM=$(Barra $ninjaExe)",
            "-DCMAKE_C_FLAGS=$flags", "-DCMAKE_CXX_FLAGS=$flags", "-DCMAKE_EXE_LINKER_FLAGS=$link")
    }
    $extra += "-DPython3_EXECUTABLE=$(Barra $python)"
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
    # the background VU1 compiler (launcher: "Compile new areas while playing") builds modules with this compiler and the
    # build's flags; clang only (an MSVC game has another C++ library layout than llvm-mingw modules)
    if ($Toolchain -eq 'clang' -and $dir -eq $bld) {
        $jit = [ordered]@{ cxx = (Join-Path $script:llvmBin 'clang++.exe'); python = $python
                           generator = (Join-Path $rt $prof.runtime.vu1_native_generator)
                           flags = "-O3 -DNDEBUG -std=gnu++20 -march=native -ffp-contract=off -fno-strict-aliasing -fwrapv -I`"$(Barra (Join-Path $rec 'ps2xRuntime\include'))`"" }
        [IO.File]::WriteAllText((Join-Path $data 'vu1_jit.json'), ($jit | ConvertTo-Json))
    }
}
if ($Stages -contains 'build') {
    Step "build the game ($Config, $Toolchain)"
    Build-Game
    # a launcher update that changed the runtime patches asked for this rebuild (tools/pipeline/update.ps1)
    Remove-Item (Join-Path $root 'data\needs-rebuild.txt') -ErrorAction SilentlyContinue
}

# --- pgo: profile-guided optimisation (clang) -----------------------------------------------------------------------
# An instrumented copy of the game (its own build folder) plays the [optimize] pad script with the hardware renderer and
# the sound path running, like a player, but hidden and silent (GOW_WINDOW_HIDDEN, engine/patches/15; GOW_AUDIO=0 with
# GOW_AUDIO_PCM=NUL keeps the audio stream paced at volume 0); closing its window writes the profile (engine/patches/12),
# which is merged into gow.profdata and used by every later clang build. A new recompile leaves it partly stale (those
# functions are just not profiled).
if ($Stages -contains 'pgo') {
    if ($Toolchain -ne 'clang') { throw 'the pgo stage needs -Toolchain clang' }
    $genBld = "$bld-pgogen"
    Step 'profile-guided optimisation: instrumented build'
    Configure $genBld 'generate'
    Build-Game $genBld
    $secs = if ($Seconds -gt 0) { $Seconds } else { [int]$prof.optimize.seconds }
    Step "profile-guided optimisation: the game plays itself for $secs s (hidden, in the background)"
    $elf = (Languages).recompile_elf
    New-Item -ItemType Directory -Force $pgoDir | Out-Null
    Get-ChildItem $pgoDir -Filter '*.profraw' -ErrorAction SilentlyContinue | Remove-Item
    $vars = @{ LLVM_PROFILE_FILE = (Join-Path $pgoDir 'run-%p.profraw'); GOW_SKIP_FMV = '1'; GOW_PAD_TEST = '1'; GOW_PAD_TEST_NO_CAPTURE = '1'
               PS2X_GS_WORKER = '1'; GOW_GS_FINISH_ASINCRONO = '1'; PS2X_GS_HW = '1'; GOW_WINDOW_HIDDEN = '1'
               GOW_AUDIO = '0'; GOW_AUDIO_PCM = 'NUL'; GOW_PAD_GUION = $prof.optimize.pad_script }
    if (Get-ChildItem -Path $vu1 -Filter *.bin -ErrorAction SilentlyContinue | Select-Object -First 1) { $vars.GOW_VU1_CAPTURA = $vu1 }
    foreach ($k in $vars.Keys) { Set-Item "env:$k" $vars[$k] }
    $p = Start-Process -FilePath (Join-Path $genBld 'ps2xRuntime\ps2EntryRunner.exe') -ArgumentList "`"$elf`"" -WorkingDirectory $logs -PassThru
    try { $p.PriorityClass = 'Normal' } catch { }
    for ($t = 0; $t -lt $secs -and -not $p.HasExited; $t += 5) { Start-Sleep 5; Write-Host "@@progress $([math]::Min($t + 5, $secs)) $secs" }
    if (-not $p.HasExited) { $null = Close-GameWindow $p.Id; $null = $p.WaitForExit(60000) }   # the profile is written on close
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
    Step "record: the game plays itself for $secs s (hidden, in the background)"
    Need $runnerExe 'built game (run the build stage)'
    $elf = (Languages).recompile_elf
    New-Item -ItemType Directory -Force $vu1, $iopMods | Out-Null
    # the hardware renderer as the player has it: with PS2X_GS_SHADER_CACHE_DIR (the launcher passes its own) the shaders
    # compiled here are already in the cache at the first play. The window stays hidden (engine/patches/15): the GPU
    # draws as usual, nothing shows on the desktop and no key can reach the game
    $vars = @{ GOW_VU1_CAPTURA = $vu1; PS2X_IOP_DUMP_MODULES = $iopMods; GOW_SKIP_FMV = '1'; GOW_PAD_TEST = '1'; GOW_AUDIO = '0'
               GOW_PAD_TEST_NO_CAPTURE = '1'; PS2X_GS_WORKER = '1'; GOW_GS_FINISH_ASINCRONO = '1'; PS2X_GS_HW = '1'
               GOW_WINDOW_HIDDEN = '1'; GOW_PAD_GUION = $prof.optimize.pad_script }
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
        # developers only: the portable Python has no pip, aqtinstall needs a full Python (python.org)
        $sysPython = (Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1).Source
        if (-not $sysPython) { throw 'building the launcher needs Qt 6: install Python from python.org (for aqtinstall) or Qt in C:\Qt' }
        New-Item -ItemType Directory -Force $qtDir | Out-Null
        Native $sysPython @('-m', 'pip', 'install', '--user', '--quiet', '--upgrade', 'aqtinstall') 'pip install aqtinstall'
        Push-Location $qtDir
        try { Native $sysPython @('-m', 'aqt', 'install-qt', 'windows', 'desktop', $qtVersion, 'win64_msvc2022_64', '-O', $qtDir) 'Qt download' }
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
