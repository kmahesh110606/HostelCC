param([string]$AdminEmail='admin@hostelcc.local')
$ErrorActionPreference='Stop'
$workspace=Split-Path $PSScriptRoot -Parent
$destination=Join-Path $workspace '.env.local'
if(Test-Path -LiteralPath $destination) { Write-Output '.env.local already exists; edit it to change local settings.'; exit 0 }
if($AdminEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Provide a valid admin email' }
function New-Secret {
    $bytes=New-Object byte[] 48
    $generator=[Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes); return [Convert]::ToBase64String($bytes) } finally { $generator.Dispose() }
}
@"
ADMIN_EMAIL=$AdminEmail
HOSTELCC_DB_PASSWORD=$(New-Secret)
JWT_SECRET=$(New-Secret)
SITE_PORT=8080
SMTP_HOST=
SMTP_PORT=587
SMTP_AUTH=true
SMTP_STARTTLS=true
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM=
"@ | Set-Content -LiteralPath $destination -Encoding ascii
Write-Output 'Created .env.local with fresh local-only secrets. Set ADMIN_EMAIL and SMTP settings before signing in. No credentials were printed.'
