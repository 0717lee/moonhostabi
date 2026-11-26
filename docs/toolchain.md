# Project-local MoonBit toolchain

For a project-local Windows toolchain, install the pinned snapshot once from
the repository root (the installer checksum is also pinned in CI):

```powershell
$env:MOON_HOME = Join-Path (Get-Location) '.tools/moonbit-1.0.0-rc1'
$env:MOON_TOOLCHAIN_ROOT = $env:MOON_HOME
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"
$env:MOONBIT_INSTALL_VERSION = '1.0.0-rc1+3c0520448'
New-Item -ItemType Directory -Force $env:MOON_HOME | Out-Null
$installer = Join-Path $env:MOON_HOME 'install.ps1'
Invoke-WebRequest https://cli.moonbitlang.com/install/powershell.ps1 -OutFile $installer
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLowerInvariant() -cne
    '1b36c041bb5089a579a4ced44f0b8f1d8c21caddcb5a980bc31027955f9b720a') {
  throw 'MoonBit installer checksum mismatch.'
}
pwsh -NoProfile -File $installer
if ($LASTEXITCODE -ne 0) { throw 'MoonBit installation failed.' }
moon version --all
```

In a new PowerShell session, repeat the first three environment assignments
before running the gates. Confirm that `moonc` reports `v1.0.0-rc1+3c0520448`;
the `moon` build-tool version and the package version are separate identities.
