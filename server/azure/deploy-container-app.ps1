[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$ResourceGroup = "hostelcc-rg",
    [string]$Location = "centralindia",
    [string]$ContainerAppEnvName = "hostelcc-env",
    [string]$ContainerAppName = "hostelcc-api",

    [string]$AcrName = "",
    [string]$ImageName = "hostelcc-api",
    [string]$ImageTag = "v1",

    [string]$PostgresServerName = "",
    [string]$PostgresAdminUser = "hosteladmin",
    [Parameter(Mandatory = $true)]
    [string]$PostgresAdminPassword,
    [string]$DatabaseName = "hostel_db",

    [string]$RedisName = "",

    [Parameter(Mandatory = $true)]
    [string]$DjangoSecretKey,

    [string]$CorsAllowedOrigins = "",
    [string]$EmailHostUser = "",
    [string]$EmailHostPassword = "",
    [string]$DefaultFromEmail = "",

    [switch]$SkipMigrations
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-LowerAlphaNum {
    param([string]$InputValue)
    return (($InputValue -replace "[^a-zA-Z0-9]", "").ToLowerInvariant())
}

function Ensure-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install Azure CLI first."
    }
}

function Invoke-Az {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & az @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Args -join ' ')"
    }
}

function Try-AzTsv {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    try {
        $result = (& az @Args 2>$null)
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return ($result | Out-String).Trim()
    }
    catch {
        return $null
    }
}

function Ensure-ProviderRegistered {
    param([string]$Namespace)

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            & az provider register --namespace $Namespace --output none 2>$null
            $state = Try-AzTsv provider show --namespace $Namespace --query registrationState --output tsv
            if ($state -eq "Registered") {
                return
            }
        }
        catch {
        }

        Write-Warning "Provider '$Namespace' registration attempt $attempt not ready; retrying in 10 seconds ..."
        Start-Sleep -Seconds 10
    }

    $finalState = Try-AzTsv provider show --namespace $Namespace --query registrationState --output tsv
    if ($finalState -ne "Registered") {
        throw "Azure resource provider '$Namespace' is not registered. Current state: '$finalState'."
    }
}

Ensure-Command "az"

if (-not $AcrName) {
    $AcrName = "hostelccacr$(Get-Random -Minimum 10000 -Maximum 99999)"
}
if (-not $PostgresServerName) {
    $PostgresServerName = "hostelccpg$(Get-Random -Minimum 10000 -Maximum 99999)"
}
if (-not $RedisName) {
    $RedisName = "hostelccredis$(Get-Random -Minimum 10000 -Maximum 99999)"
}

$AcrName = Get-LowerAlphaNum -InputValue $AcrName
$PostgresServerName = Get-LowerAlphaNum -InputValue $PostgresServerName
$RedisName = Get-LowerAlphaNum -InputValue $RedisName

if ($AcrName.Length -lt 5 -or $AcrName.Length -gt 50) {
    throw "AcrName must be 5-50 alphanumeric characters."
}
if ($PostgresServerName.Length -lt 3 -or $PostgresServerName.Length -gt 63) {
    throw "PostgresServerName must be 3-63 alphanumeric characters."
}
if ($RedisName.Length -lt 1 -or $RedisName.Length -gt 63) {
    throw "RedisName must be 1-63 alphanumeric characters."
}

$currentSubscription = Try-AzTsv account show --query id --output tsv
if (-not $currentSubscription) {
    throw "Azure CLI is not logged in. Run 'az login' and then rerun this script."
}

Write-Host "Setting Azure subscription to $SubscriptionId ..."
Invoke-Az account set --subscription $SubscriptionId

Write-Host "Installing containerapp extension and registering providers ..."
Invoke-Az extension add --name containerapp --upgrade --yes
Ensure-ProviderRegistered -Namespace "Microsoft.App"
Ensure-ProviderRegistered -Namespace "Microsoft.OperationalInsights"
Ensure-ProviderRegistered -Namespace "Microsoft.DBforPostgreSQL"
Ensure-ProviderRegistered -Namespace "Microsoft.Cache"
Ensure-ProviderRegistered -Namespace "Microsoft.ContainerRegistry"

Write-Host "Creating resource group $ResourceGroup in $Location ..."
Invoke-Az group create --name $ResourceGroup --location $Location --output none

$logWorkspaceName = ("{0}-logs" -f $ContainerAppEnvName).ToLowerInvariant()
if ($logWorkspaceName.Length -gt 63) {
    $logWorkspaceName = $logWorkspaceName.Substring(0, 63)
}

$existingWorkspace = Try-AzTsv monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $logWorkspaceName --query name --output tsv
if (-not $existingWorkspace) {
    Write-Host "Creating Log Analytics workspace $logWorkspaceName ..."
    Invoke-Az monitor log-analytics workspace create --resource-group $ResourceGroup --workspace-name $logWorkspaceName --location $Location --output none
}

$workspaceId = Try-AzTsv monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $logWorkspaceName --query customerId --output tsv
$workspaceKey = $null
for ($attempt = 1; $attempt -le 5; $attempt++) {
    $workspaceKey = Try-AzTsv monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $logWorkspaceName --query primarySharedKey --output tsv
    if ($workspaceKey) {
        break
    }
    Write-Warning "Log Analytics key fetch attempt $attempt failed; retrying in 10 seconds ..."
    Start-Sleep -Seconds 10
}

$existingEnv = Try-AzTsv containerapp env show --name $ContainerAppEnvName --resource-group $ResourceGroup --query name --output tsv
if (-not $existingEnv) {
    Write-Host "Creating Container Apps environment $ContainerAppEnvName ..."
    if ($workspaceId -and $workspaceKey) {
        Invoke-Az containerapp env create --name $ContainerAppEnvName --resource-group $ResourceGroup --location $Location --logs-workspace-id $workspaceId --logs-workspace-key $workspaceKey --output none
    }
    else {
        Write-Warning "Could not resolve Log Analytics workspace credentials. Creating environment with auto-generated logging workspace."
        Invoke-Az containerapp env create --name $ContainerAppEnvName --resource-group $ResourceGroup --location $Location --output none
    }
}

$existingAcr = Try-AzTsv acr show --name $AcrName --resource-group $ResourceGroup --query name --output tsv
if (-not $existingAcr) {
    Write-Host "Creating Azure Container Registry $AcrName ..."
    Invoke-Az acr create --name $AcrName --resource-group $ResourceGroup --sku Basic --admin-enabled true --output none
} else {
    Invoke-Az acr update --name $AcrName --admin-enabled true --output none
}

$serverDir = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $serverDir
try {
    Write-Host "Building and pushing image to ACR ..."
    $remoteBuildSucceeded = $true
    try {
        Invoke-Az acr build --registry $AcrName --image "$ImageName`:$ImageTag" . --output none
    }
    catch {
        $remoteBuildSucceeded = $false
        Write-Warning "ACR remote build failed. Falling back to local Docker build and push."
    }

    if (-not $remoteBuildSucceeded) {
        Ensure-Command "docker"

        $acrLoginServerForPush = (& az acr show --name $AcrName --resource-group $ResourceGroup --query loginServer --output tsv)
        if (-not $acrLoginServerForPush) {
            throw "Could not resolve ACR login server for '$AcrName'."
        }

        Invoke-Az acr login --name $AcrName --output none

        & docker build -t "$ImageName`:$ImageTag" .
        if ($LASTEXITCODE -ne 0) {
            throw "Local Docker build failed."
        }

        & docker tag "$ImageName`:$ImageTag" "$acrLoginServerForPush/$ImageName`:$ImageTag"
        if ($LASTEXITCODE -ne 0) {
            throw "Docker tag failed."
        }

        & docker push "$acrLoginServerForPush/$ImageName`:$ImageTag"
        if ($LASTEXITCODE -ne 0) {
            throw "Docker push failed."
        }
    }
}
finally {
    Pop-Location
}

$existingPostgres = Try-AzTsv postgres flexible-server show --name $PostgresServerName --resource-group $ResourceGroup --query name --output tsv
if (-not $existingPostgres) {
    Write-Host "Creating PostgreSQL flexible server $PostgresServerName ..."
    Invoke-Az postgres flexible-server create --resource-group $ResourceGroup --name $PostgresServerName --location $Location --admin-user $PostgresAdminUser --admin-password $PostgresAdminPassword --sku-name Standard_B1ms --tier Burstable --storage-size 32 --version 16 --public-access 0.0.0.0 --yes --output none
}

$existingDb = Try-AzTsv postgres flexible-server db show --resource-group $ResourceGroup --server-name $PostgresServerName --database-name $DatabaseName --query name --output tsv
if (-not $existingDb) {
    Write-Host "Creating PostgreSQL database $DatabaseName ..."
    Invoke-Az postgres flexible-server db create --resource-group $ResourceGroup --server-name $PostgresServerName --database-name $DatabaseName --output none
}

$existingRedis = Try-AzTsv redis show --name $RedisName --resource-group $ResourceGroup --query name --output tsv
if (-not $existingRedis) {
    Write-Host "Creating Azure Cache for Redis $RedisName ..."
    Invoke-Az redis create --name $RedisName --resource-group $ResourceGroup --location $Location --sku Basic --vm-size C0 --minimum-tls-version 1.2 --output none
}

$acrLoginServer = (& az acr show --name $AcrName --resource-group $ResourceGroup --query loginServer --output tsv)
$acrUsername = Try-AzTsv acr credential show --name $AcrName --query username --output tsv
$acrPassword = Try-AzTsv acr credential show --name $AcrName --query passwords[0].value --output tsv

$redisPrimaryKey = $null
for ($attempt = 1; $attempt -le 5; $attempt++) {
    $redisPrimaryKey = Try-AzTsv redis list-keys --name $RedisName --resource-group $ResourceGroup --query primaryKey --output tsv
    if ($redisPrimaryKey) {
        break
    }
    Write-Warning "Redis key fetch attempt $attempt failed; retrying in 15 seconds ..."
    Start-Sleep -Seconds 15
}
if (-not $redisPrimaryKey) {
    throw "Could not retrieve Redis primary key for '$RedisName'."
}
$redisUrl = "rediss://:$redisPrimaryKey@$RedisName.redis.cache.windows.net:6380/1"

$imageRef = "$acrLoginServer/$ImageName`:$ImageTag"
$dbHost = "$PostgresServerName.postgres.database.azure.com"

$secrets = @(
    "django-secret-key=$DjangoSecretKey"
    "db-password=$PostgresAdminPassword"
    "redis-url=$redisUrl"
)
if ($EmailHostPassword) {
    $secrets += "email-host-password=$EmailHostPassword"
}

$envVars = @(
    "DJANGO_DEBUG=False"
    "PORT=8000"
    "WEB_CONCURRENCY=3"
    "GUNICORN_TIMEOUT=120"
    "DJANGO_SECRET_KEY=secretref:django-secret-key"
    "DJANGO_ALLOWED_HOSTS=*"
    "DB_NAME=$DatabaseName"
    "DB_USER=$PostgresAdminUser"
    "DB_PASSWORD=secretref:db-password"
    "DB_HOST=$dbHost"
    "DB_PORT=5432"
    "DB_SSLMODE=require"
    "DB_CONN_MAX_AGE=60"
    "REDIS_URL=secretref:redis-url"
    "CORS_ALLOWED_ORIGINS=$CorsAllowedOrigins"
)
if ($EmailHostUser) {
    $envVars += "EMAIL_HOST_USER=$EmailHostUser"
}
if ($DefaultFromEmail) {
    $envVars += "DEFAULT_FROM_EMAIL=$DefaultFromEmail"
}
if ($EmailHostPassword) {
    $envVars += "EMAIL_HOST_PASSWORD=secretref:email-host-password"
}

$existingContainerApp = Try-AzTsv containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query name --output tsv
if (-not $existingContainerApp) {
    Write-Host "Creating Azure Container App $ContainerAppName ..."
    if ($acrUsername -and $acrPassword) {
        Invoke-Az containerapp create --name $ContainerAppName --resource-group $ResourceGroup --environment $ContainerAppEnvName --image $imageRef --ingress external --target-port 8000 --registry-server $acrLoginServer --registry-username $acrUsername --registry-password $acrPassword --cpu 1.0 --memory 2Gi --min-replicas 2 --max-replicas 10 --secrets $secrets --env-vars $envVars --output none
    }
    else {
        Write-Warning "ACR admin credentials unavailable. Using system-assigned identity for image pull."
        Invoke-Az containerapp create --name $ContainerAppName --resource-group $ResourceGroup --environment $ContainerAppEnvName --image $imageRef --ingress external --target-port 8000 --registry-server $acrLoginServer --registry-identity system --system-assigned --cpu 1.0 --memory 2Gi --min-replicas 2 --max-replicas 10 --secrets $secrets --env-vars $envVars --output none

        $principalId = Try-AzTsv containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query identity.principalId --output tsv
        $acrId = Try-AzTsv acr show --name $AcrName --resource-group $ResourceGroup --query id --output tsv
        if (-not $principalId -or -not $acrId) {
            throw "Could not resolve managed identity or ACR ID for AcrPull role assignment."
        }

        Write-Host "Assigning AcrPull role to Container App managed identity ..."
        & az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role AcrPull --scope $acrId --output none 2>$null
    }
} else {
    Write-Host "Updating Azure Container App $ContainerAppName ..."
    Invoke-Az containerapp secret set --name $ContainerAppName --resource-group $ResourceGroup --secrets $secrets --output none
    if ($acrUsername -and $acrPassword) {
        Invoke-Az containerapp update --name $ContainerAppName --resource-group $ResourceGroup --image $imageRef --set-env-vars $envVars --registry-server $acrLoginServer --registry-username $acrUsername --registry-password $acrPassword --output none
    }
    else {
        Invoke-Az containerapp update --name $ContainerAppName --resource-group $ResourceGroup --image $imageRef --set-env-vars $envVars --registry-server $acrLoginServer --registry-identity system --output none
    }
}

$fqdn = (& az containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query properties.configuration.ingress.fqdn --output tsv)
if ($fqdn) {
    $csrfOrigin = "https://$fqdn"
    Invoke-Az containerapp update --name $ContainerAppName --resource-group $ResourceGroup --set-env-vars "DJANGO_ALLOWED_HOSTS=$fqdn" "DJANGO_CSRF_TRUSTED_ORIGINS=$csrfOrigin" --output none
}

if (-not $SkipMigrations) {
    Write-Host "Running Django migrations and collectstatic in the container app ..."
    & az containerapp exec --name $ContainerAppName --resource-group $ResourceGroup --command "sh -c 'python manage.py migrate && python manage.py collectstatic --noinput'"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not run migrations automatically. Run this manually:"
        Write-Host "az containerapp exec --name $ContainerAppName --resource-group $ResourceGroup --command \"sh -c 'python manage.py migrate && python manage.py collectstatic --noinput'\""
    }
}

Write-Host "Deployment completed."
if ($fqdn) {
    Write-Host "Backend URL: https://$fqdn"
    Write-Host "Health URL: https://$fqdn/healthz/"
}
