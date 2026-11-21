[CmdletBinding()]
param(
    [ipaddress[]]$PcAddress = @("192.168.0.12","192.168.56.1","127.0.0.1"),
    [string]$Jdk = $env:JAVA_HOME,
    [string]$PlatformJar = "$env:ANDROID_HOME\platforms\android-35\android.jar",
    [string]$BuildTools = "$env:ANDROID_HOME\build-tools\35.0.0",
    [string]$OutputFile = "$PSScriptRoot\build\NEXUS.apk"
)
$ErrorActionPreference = 'Stop'
$addresses = @($PcAddress | ForEach-Object { $_.ToString() } | Select-Object -Unique)
if (!$addresses.Count) { throw 'Supply at least one PC address.' }
foreach ($address in $PcAddress) {
$ip = $address.GetAddressBytes()
if ($ip.Length -ne 4 -or -not ($address.ToString() -eq '127.0.0.1' -or $ip[0] -eq 10 -or ($ip[0] -eq 172 -and $ip[1] -ge 16 -and $ip[1] -le 31) -or ($ip[0] -eq 192 -and $ip[1] -eq 168))) {
    throw 'Choose the private LAN IPv4 address printed by the Windows server.'
}
}
function Run([string]$tool, [string[]]$arguments) {
    & $tool @arguments
    if ($LASTEXITCODE -ne 0) { throw "$tool failed with exit code $LASTEXITCODE" }
}
$Jdk = (Resolve-Path -LiteralPath $Jdk).Path
$PlatformJar = (Resolve-Path -LiteralPath $PlatformJar).Path
$BuildTools = (Resolve-Path -LiteralPath $BuildTools).Path
$OutputFile = [IO.Path]::GetFullPath($OutputFile)
$env:JAVA_HOME = $Jdk
$env:PATH = "$Jdk\bin;$env:PATH"
$stage = Join-Path $env:TEMP ("NexusBuild-" + [Guid]::NewGuid())
$identity = Join-Path $env:LOCALAPPDATA 'NEXUS\AndroidSigning'
$keystore = Join-Path $identity 'personal.p12'
$secret = Join-Path $identity 'password.dpapi'
foreach ($dir in @("$stage\generated","$stage\classes","$stage\dex","$stage\res\xml","$stage\res\values",$identity,(Split-Path -Parent $OutputFile))) {
    [IO.Directory]::CreateDirectory($dir) | Out-Null
}
Copy-Item -LiteralPath "$PSScriptRoot\res\drawable" -Destination "$stage\res" -Recurse
$domains = ($addresses | ForEach-Object { "<domain includeSubdomains='false'>$_</domain>" }) -join ''
$items = ($addresses | ForEach-Object { "<item>$_</item>" }) -join ''
$xml = "<network-security-config><base-config cleartextTrafficPermitted='false'/><domain-config cleartextTrafficPermitted='true'>$domains</domain-config></network-security-config>"
[IO.File]::WriteAllText("$stage\res\xml\network_security_config.xml",$xml)
[IO.File]::WriteAllText("$stage\res\values\strings.xml","<resources><string-array name='pc_addresses'>$items</string-array></resources>")
try {
    Run "$BuildTools\aapt2.exe" @('compile','--dir',"$stage\res",'-o',"$stage\res.zip")
    Run "$BuildTools\aapt2.exe" @('link','--manifest',"$PSScriptRoot\AndroidManifest.xml",'-I',$PlatformJar,'--java',"$stage\generated",'-o',"$stage\base.apk","$stage\res.zip")
    $sources = @(Get-ChildItem -Recurse -Filter '*.java' -Path "$PSScriptRoot\src","$stage\generated" | ForEach-Object FullName)
    Run "$Jdk\bin\javac.exe" (@('-encoding','UTF-8','-source','8','-target','8','-bootclasspath',"$BuildTools\core-lambda-stubs.jar;$PlatformJar",'-d',"$stage\classes") + $sources)
    Run "$Jdk\bin\jar.exe" @('cf',"$stage\classes.jar",'-C',"$stage\classes",'.')
    Run "$Jdk\bin\java.exe" @('-cp',"$BuildTools\lib\d8.jar",'com.android.tools.r8.D8','--release','--min-api','26','--lib',$PlatformJar,'--output',"$stage\dex","$stage\classes.jar")
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open("$stage\base.apk",'Update')
    try { [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,"$stage\dex\classes.dex",'classes.dex') | Out-Null }
    finally { $zip.Dispose() }
    Run "$BuildTools\zipalign.exe" @('-p','4',"$stage\base.apk","$stage\aligned.apk")
    if (!(Test-Path $secret)) {
        if (Test-Path $keystore) {throw "Existing signing key needs its original protected password file: $secret"}
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}
        $protectedPass = ConvertTo-SecureString ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
        $protectedPass | ConvertFrom-SecureString | Set-Content -LiteralPath $secret
    }
    $secure = (Get-Content -Raw -LiteralPath $secret).Trim() | ConvertTo-SecureString
    $env:NEXUS_BUILD_KEY = [Net.NetworkCredential]::new('signer',$secure).Password
    if (!(Test-Path $keystore)) {
        Run "$Jdk\bin\keytool.exe" @('-genkeypair','-keystore',$keystore,'-storetype','PKCS12','-alias','nexus','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=NEXUS Personal Build','-storepass:env','NEXUS_BUILD_KEY')
    }
    $signerArgs=@('-jar',"$BuildTools\lib\apksigner.jar")
    Run "$Jdk\bin\java.exe" ($signerArgs + @('sign','--ks',$keystore,'--ks-pass','env:NEXUS_BUILD_KEY','--v4-signing-enabled','false','--out',"$stage\signed.apk","$stage\aligned.apk"))
    Run "$Jdk\bin\java.exe" ($signerArgs + @('verify','--verbose',"$stage\signed.apk"))
    Copy-Item -LiteralPath "$stage\signed.apk" -Destination $OutputFile -Force
    Write-Host "Verified APK: $OutputFile"
} finally {
    Remove-Item Env:NEXUS_BUILD_KEY -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($stage)
    if ((Split-Path -Parent $resolved) -eq [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') -and (Split-Path -Leaf $resolved) -match '^NexusBuild-[0-9a-f-]{36}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
