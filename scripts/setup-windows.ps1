<#
.SYNOPSIS
    为 CxKitty 准备 Windows 运行环境。

.DESCRIPTION
    自动完成以下工作:
      1. 从 python.org 探测 3.13 系列中最新的、且提供 Windows 嵌入式发行版的补丁版本
      2. 下载并解压该嵌入式解释器到仓库根目录的 runtime\
      3. 修改 pythonXYZ._pth, 启用 site 并把 app\ 加入模块搜索路径
      4. 通过 get-pip.py 装上 pip, 再按 app\requirements.txt 安装全部依赖

    Windows 上只使用这份便携 (嵌入式) 解释器, 不会去找、也不会改动系统里已装的
    Python —— 装在 runtime\ 下, 删掉整个目录即可彻底卸载。

    脚本可重复执行: 运行时已就绪就直接跳过; 解释器在但依赖不全 (上次装到一半、
    手工删过包) 只补装依赖, 不重下解释器; 需要整个重装时加 -Force。

.PARAMETER PythonSeries
    要安装的 Python 主版本系列, 默认 3.13。

.PARAMETER IndexUrl
    pip 使用的镜像源。默认留空, 即使用 requirements.txt 里自带的 --index-url。

.PARAMETER Force
    即使 runtime\ 已存在也重新下载并覆盖安装。

.EXAMPLE
    .\scripts\setup-windows.ps1
    .\scripts\setup-windows.ps1 -IndexUrl https://pypi.org/simple
    .\scripts\setup-windows.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$PythonSeries = "3.13",
    [string]$IndexUrl = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # 关掉进度条, 否则 PS5.1 下载会非常慢

# 老版本 PowerShell 默认不启用 TLS1.2, python.org 会直接拒绝
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$RuntimeDir = Join-Path $RepoRoot "runtime"
$AppDir     = Join-Path $RepoRoot "app"
$FtpBase    = "https://www.python.org/ftp/python"

function Write-Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Note($msg)  { Write-Host "    $msg" -ForegroundColor DarkGray }
function Write-Ok($msg)    { Write-Host "==> $msg" -ForegroundColor Green }

# 嵌入式发行版只有 win32 / amd64 / arm64 三种, 且依赖 (numpy onnxruntime opencv)
# 目前只在 amd64 上提供 wheel, 所以统一使用 amd64 (ARM 版 Windows 可以模拟运行)
$Arch = "amd64"
if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    Write-Note "检测到 ARM64 系统, 仍使用 amd64 版本 (依赖库没有 ARM64 wheel), 将以模拟方式运行"
}

function Get-LatestEmbeddableVersion {
    <#
      python.org 上的补丁版本目录里不一定有嵌入式压缩包 —— 一个系列进入
      "security-only" 阶段后就只发布源码了。所以这里从高到低逐个探测,
      返回第一个真正提供 embed zip 的版本。
    #>
    param([string]$Series)

    Write-Step "正在探测 Python $Series 的最新可用嵌入式版本..."
    try {
        $index = Invoke-WebRequest -Uri "$FtpBase/" -UseBasicParsing -TimeoutSec 60
    } catch {
        throw "无法访问 $FtpBase/ : $($_.Exception.Message)"
    }

    $escaped = [regex]::Escape($Series)
    $patches = [regex]::Matches($index.Content, "href=""$escaped\.(\d+)/""") |
               ForEach-Object { [int]$_.Groups[1].Value } |
               Sort-Object -Unique -Descending

    if (-not $patches) { throw "在 python.org 上没有找到任何 $Series.x 版本" }
    Write-Note "已发布补丁版: $Series.$($patches -join ", $Series.")"

    foreach ($patch in $patches) {
        $version = "$Series.$patch"
        $url = "$FtpBase/$version/python-$version-embed-$Arch.zip"
        try {
            Invoke-WebRequest -Uri $url -UseBasicParsing -Method Head -TimeoutSec 30 | Out-Null
            Write-Note "$version 提供嵌入式发行版, 选定该版本"
            return [pscustomobject]@{ Version = $version; Url = $url }
        } catch {
            Write-Note "$version 无嵌入式发行版 (仅源码发布), 继续向前查找"
        }
    }
    throw "$Series 系列没有任何版本提供 Windows 嵌入式发行版"
}

function Install-Runtime {
    param([string]$Version, [string]$Url)

    $tmp = Join-Path ([IO.Path]::GetTempPath()) "cxkitty-python-$Version-$Arch.zip"

    Write-Step "下载 Python $Version 嵌入式发行版..."
    Write-Note $Url
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 600

    # 简单校验: 能被当作 zip 打开, 且包含 python.exe
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($tmp)
    try {
        if (-not ($zip.Entries.Name -contains "python.exe")) {
            throw "下载的压缩包里没有 python.exe, 文件可能已损坏"
        }
    } finally { $zip.Dispose() }

    Write-Step "解压到 $RuntimeDir ..."
    if (Test-Path $RuntimeDir) { Remove-Item -Recurse -Force $RuntimeDir }
    Expand-Archive -Path $tmp -DestinationPath $RuntimeDir -Force
    Remove-Item -Force $tmp
}

function Set-PthFile {
    <#
      嵌入式发行版带 ._pth 文件时会进入 isolated 模式: 不读环境变量,
      也不会把脚本所在目录加进 sys.path。所以必须自己把 app\ 写进去,
      并放开 "import site" —— 否则 pip / site-packages 都用不了。
    #>
    $pth = Get-ChildItem -Path $RuntimeDir -Filter "python*._pth" | Select-Object -First 1
    if (-not $pth) { throw "在 $RuntimeDir 下没有找到 ._pth 文件" }

    Write-Step "配置 $($pth.Name) ..."
    # python313._pth -> python313, 对应的标准库压缩包即 python313.zip
    $stdlibZip = [IO.Path]::GetFileNameWithoutExtension($pth.Name)
    $lines = @(
        "${stdlibZip}.zip"
        "."
        "Lib\site-packages"
        "..\app"
        ""
        "import site"
    )
    Set-Content -Path $pth.FullName -Value $lines -Encoding ASCII
    Write-Note ($lines -join " | ")
}

function Install-Pip {
    Write-Step "安装 pip ..."
    $python = Join-Path $RuntimeDir "python.exe"
    $getPip = Join-Path ([IO.Path]::GetTempPath()) "get-pip.py"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip -UseBasicParsing -TimeoutSec 300

    $pipArgs = @($getPip, "--no-warn-script-location")
    if ($IndexUrl) { $pipArgs += @("--index-url", $IndexUrl) }
    & $python @pipArgs
    if ($LASTEXITCODE -ne 0) { throw "pip 安装失败 (exit $LASTEXITCODE)" }
    Remove-Item -Force $getPip
}

function Install-Requirements {
    Write-Step "安装项目依赖 ..."
    $python = Join-Path $RuntimeDir "python.exe"
    $req = Join-Path $AppDir "requirements.txt"
    if (-not (Test-Path $req)) { throw "找不到 $req" }

    # 不带 -IndexUrl 时, pip 会直接用 requirements.txt 里写的 --index-url (清华源)
    $tmpReq = $null
    if ($IndexUrl) {
        # requirements.txt 内的 --index-url 优先级高于命令行参数,
        # 想覆盖就必须先把那一行去掉, 否则 -IndexUrl 不会生效
        $tmpReq = Join-Path ([IO.Path]::GetTempPath()) "cxkitty-requirements.txt"
        Get-Content $req | Where-Object { $_ -notmatch '^\s*--index-url' } | Set-Content -Path $tmpReq -Encoding UTF8
        $req = $tmpReq
        Write-Note "使用镜像源 $IndexUrl"
    }

    $pipArgs = @("-m", "pip", "install", "-r", $req, "--no-warn-script-location")
    if ($IndexUrl) { $pipArgs += @("--index-url", $IndexUrl) }
    try {
        & $python @pipArgs
        if ($LASTEXITCODE -ne 0) { throw "依赖安装失败 (exit $LASTEXITCODE)" }
    } finally {
        if ($tmpReq -and (Test-Path $tmpReq)) { Remove-Item -Force $tmpReq }
    }
}

function Test-Dependencies {
    <#
      依赖是否齐全, 判断逻辑统一放在 scripts\check_env.py 里 (退出码 0 = 可用),
      启动.bat 用的是同一个脚本, 免得两边对"环境完整"的定义走偏。
    #>
    $python = Join-Path $RuntimeDir "python.exe"
    if (-not (Test-Path $python)) { return $false }
    & $python (Join-Path $PSScriptRoot "check_env.py")
    return ($LASTEXITCODE -eq 0)
}

function Test-Pip {
    $python = Join-Path $RuntimeDir "python.exe"
    & $python -m pip --version | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------- main

if ((Test-Path (Join-Path $RuntimeDir "python.exe")) -and -not $Force) {
    & (Join-Path $RuntimeDir "python.exe") -V
    if (Test-Dependencies) {
        Write-Ok "runtime\ 已就绪, 跳过安装 (需要重装请加 -Force)"
        exit 0
    }
    # 解释器在、依赖不全: 补装依赖就够了, 没必要重新下载解释器
    Write-Step "运行时已存在但依赖不完整, 补装依赖 ..."
    if (-not (Test-Pip)) { Install-Pip }
    Install-Requirements
    # pip 只看 dist-info 元数据, 包目录被手工删掉时它会认为"已安装"而不补装, 故这里兜一层
    if (-not (Test-Dependencies)) {
        throw "补装依赖后环境仍不完整, 请加 -Force 重装 (.\scripts\setup-windows.ps1 -Force)"
    }
    Write-Ok "依赖已补齐"
    exit 0
}

$target = Get-LatestEmbeddableVersion -Series $PythonSeries
Install-Runtime -Version $target.Version -Url $target.Url
Set-PthFile
Install-Pip
Install-Requirements

if (-not (Test-Dependencies)) {
    throw "依赖安装完成但环境自检未通过, 请检查上面的 pip 输出"
}

Write-Ok "环境准备完成, Python $($target.Version) 已安装到 runtime\"
Write-Host ""
Write-Host "运行方式: 双击仓库根目录的 启动.bat" -ForegroundColor Yellow
Write-Host "改配置:   启动.bat 菜单里选 [2] (可视化编辑 app\config.yml)" -ForegroundColor Yellow
