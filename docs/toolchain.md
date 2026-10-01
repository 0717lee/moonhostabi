# Project-local MoonBit toolchain

For a project-local Windows toolchain, install the pinned snapshot once from
the repository root (the installer checksum is also pinned in CI):

```powershell
$env:MOON_HOME = Join-Path (Get-Location) '.tools/moonbit-0.10.14'
$env:MOON_TOOLCHAIN_ROOT = $env:MOON_HOME
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"
$env:MOONBIT_INSTALL_VERSION = '0.10.14+7d59c7ec9'
New-Item -ItemType Directory -Force $env:MOON_HOME | Out-Null
$installer = Join-Path $env:MOON_HOME 'install.ps1'
Invoke-WebRequest https://cli.moonbitlang.com/install/powershell.ps1 -OutFile $installer
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLowerInvariant() -cne
    'a5101e91ffa9905fb25cd009b9a4aa942971a294bd055c89836e3af89b710c64') {
  throw 'MoonBit installer checksum mismatch.'
}
pwsh -NoProfile -File $installer
if ($LASTEXITCODE -ne 0) { throw 'MoonBit installation failed.' }
moon version --all
```

In a new PowerShell session, repeat the first three environment assignments
before running the gates. Confirm that `moonc` reports `v0.10.14+7d59c7ec9`;
the `moon` build-tool version and the package version are separate identities.
