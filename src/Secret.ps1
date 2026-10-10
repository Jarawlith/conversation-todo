param([Parameter(Mandatory=$true)][string]$File)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
Add-Type -AssemblyName Microsoft.PowerShell.Security
Import-Module -Assembly ([Microsoft.PowerShell.Commands.ConvertToSecureStringCommand].Assembly) -Global -Force -ErrorAction Stop
$secure = Get-Content -LiteralPath $File -Raw | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { [Console]::Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
