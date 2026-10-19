param([switch]$Build)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
function Load-EnvFile([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
                $value = $Matches[2].Trim().Trim('"').Trim("'")
                [Environment]::SetEnvironmentVariable($Matches[1], $value, 'Process')
            }
        }
    }
}
Load-EnvFile (Join-Path $PSScriptRoot '.env.local')
$jar = Join-Path $PSScriptRoot 'target\hostelcc-server-2.0.0.jar'
if ($Build -or -not (Test-Path -LiteralPath $jar)) { & .\mvnw.cmd -q clean package; if ($LASTEXITCODE -ne 0) { throw 'Maven build failed' } }
& java -jar $jar --spring.profiles.active=dev --debug=false
exit $LASTEXITCODE
