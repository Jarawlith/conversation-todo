param([Parameter(Mandatory=$true)][string]$NodeExe,[Parameter(Mandatory=$true)][string]$ISCC)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $root '.build/payload'
$node = (Resolve-Path -LiteralPath $NodeExe).Path
$compiler = (Resolve-Path -LiteralPath $ISCC).Path
if ((& $node --version) -ne 'v24.19.0') { throw 'Build requires Node.js v24.19.0 Windows x64.' }
[void][IO.Directory]::CreateDirectory($stage)
[void][IO.Directory]::CreateDirectory((Join-Path $stage 'runtime'))
Get-ChildItem -LiteralPath (Join-Path $root 'src') -File | Where-Object { $_.Name -notin @('server.js','Launcher.cs','NativeHost.cs') } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stage -Force }
Copy-Item -LiteralPath (Join-Path $root 'src/ChromeExtension') -Destination $stage -Recurse -Force
& (Join-Path $PSScriptRoot 'prepare-speech.ps1')
Copy-Item -LiteralPath (Join-Path $root 'src/node_modules') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'third-party') -Destination (Join-Path $stage 'licenses') -Recurse -Force
Copy-Item -LiteralPath $node -Destination (Join-Path $stage 'runtime/node.exe') -Force
Copy-Item -LiteralPath (Join-Path $root 'third-party/Node-LICENSE.txt') -Destination (Join-Path $stage 'runtime/LICENSE.txt') -Force
$csc = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:winexe (('/out:') + (Join-Path $stage 'CodexTodo.exe')) (Join-Path $root 'src/Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed.' }
& $csc /nologo /target:exe (('/out:') + (Join-Path $stage 'NativeHost.exe')) (Join-Path $root 'src/NativeHost.cs')
if ($LASTEXITCODE -ne 0) { throw 'Native host build failed.' }
& $compiler /Q (Join-Path $root 'installer/ConversationTodo.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
Write-Output (Join-Path $root 'dist/ConversationTodo-Mainland-Setup-0.9.0.exe')
