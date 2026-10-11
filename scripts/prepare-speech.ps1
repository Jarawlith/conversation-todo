param([string]$Destination=(Join-Path $PSScriptRoot '../src/node_modules'))
$ErrorActionPreference='Stop'
$packages=@(
    @{name='sherpa-onnx-node';sha512='MsDMBdhLFTZ1GwvcGSSQhnS7g/EA8OMH6IYysCVUOM7j8Icty9KRc0E6YT1A5fWBsZwRfKOeh88QC95aRvS8ag=='},
    @{name='sherpa-onnx-win-x64';sha512='oZF1c9VPOKtMwn83Bboc5XSWL+76BRoyB3eUuVnCknBKxwSULZU2Foia9VHWzU+n4I12rPsP6z6H9Rp1hD9o8g=='}
)
foreach($package in $packages){
    $folder=Join-Path $Destination $package.name
    if(Test-Path -LiteralPath (Join-Path $folder 'package.json')){
        $installed=Get-Content -LiteralPath (Join-Path $folder 'package.json') -Raw|ConvertFrom-Json
        if($installed.version -eq '1.13.8'){continue}
    }
    [void][IO.Directory]::CreateDirectory($folder)
    $temporary=Join-Path $env:TEMP ($package.name+'-'+[guid]::NewGuid().ToString('N')+'.tgz')
    try{
        $url='https://registry.npmjs.org/'+$package.name+'/-/'+$package.name+'-1.13.8.tgz'
        & curl.exe --fail --location --silent --show-error --max-time 180 $url --output $temporary
        if($LASTEXITCODE -ne 0){throw 'Speech runtime download failed'}
        $hash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($temporary)))
        if($hash -ne $package.sha512){throw 'Speech runtime checksum mismatch'}
        & tar.exe -xf $temporary -C $folder --strip-components=1
        if($LASTEXITCODE -ne 0){throw 'Speech runtime extraction failed'}
    }finally{Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}
