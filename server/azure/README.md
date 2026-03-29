# Azure Deployment (Container Apps)

This folder contains automation to deploy the Django backend to Azure using:
- Azure Container Apps (web API)
- Azure Database for PostgreSQL Flexible Server
- Azure Cache for Redis
- Azure Container Registry

## Prerequisites

1. Azure subscription.
2. Azure CLI installed.
3. Logged in with Azure CLI.
4. Dockerfile already present in `server/` (this repo already has it).

Install Azure CLI on Windows (PowerShell):

```powershell
winget install --exact --id Microsoft.AzureCLI
```

Login:

```powershell
az login
```

## Deploy

From repository root:

```powershell
Set-Location .\server

$subscriptionId = "<your-subscription-id>"
$postgresPassword = "<strong-postgres-password>"
$djangoSecret = -join ((33..126) | Get-Random -Count 64 | ForEach-Object { [char]$_ })

.\azure\deploy-container-app.ps1 \
  -SubscriptionId $subscriptionId \
  -PostgresAdminPassword $postgresPassword \
  -DjangoSecretKey $djangoSecret \
  -CorsAllowedOrigins "https://your-frontend-domain.com" \
  -EmailHostUser "your-email@outlook.com" \
  -EmailHostPassword "your-email-app-password" \
  -DefaultFromEmail "your-email@outlook.com"
```

The script prints the deployed HTTPS URL and health endpoint.

## What The Script Does

1. Creates/updates resource group and required Azure providers.
2. Creates Azure Container Registry and pushes backend image.
3. Creates PostgreSQL server and application database.
4. Creates Redis cache.
5. Creates or updates Azure Container App with autoscaling.
6. Sets environment variables and secrets.
7. Attempts to run migrations + collectstatic in the running container.

## Optional Parameters

- `-ResourceGroup` (default: `hostelcc-rg`)
- `-Location` (default: `centralindia`)
- `-ContainerAppName` (default: `hostelcc-api`)
- `-ContainerAppEnvName` (default: `hostelcc-env`)
- `-AcrName` (auto-generated if omitted)
- `-PostgresServerName` (auto-generated if omitted)
- `-RedisName` (auto-generated if omitted)
- `-SkipMigrations` (skip migration/collectstatic step)

## Post-Deployment Checklist

1. Add your custom domain to Container Apps and bind TLS cert.
2. Set `DJANGO_ALLOWED_HOSTS` and `DJANGO_CSRF_TRUSTED_ORIGINS` for custom domain.
3. Move media files to Azure Blob Storage for multi-replica deployments.
4. Enable Azure Monitor alerts for CPU, memory, error rate, and DB health.
5. Load test and tune:
   - container replicas
   - gunicorn workers
   - PostgreSQL tier
   - Redis tier
