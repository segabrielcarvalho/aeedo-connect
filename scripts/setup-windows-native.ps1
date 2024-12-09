Param()

function Write-Color {
    param(
        [Parameter(Mandatory=$true)] [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host -NoNewline $Message -ForegroundColor $Color
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Command-Exists {
    param([string]$CommandName)
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Is-Port-In-Use {
    param([int]$Port)
    $connections = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    foreach ($conn in $connections) {
        if ($conn.Port -eq $Port) {
            return $true
        }
    }
    return $false
}

function Get-EnvVariableFromFile {
    param(
        [string]$FilePath,
        [string]$VarName
    )
    if (Test-Path $FilePath) {
        $line = (Get-Content $FilePath | Where-Object {$_ -match "^$VarName="})
        if ($line) {
            return $line -replace "^$VarName=", ""
        }
    }
    return $null
}

Write-Host ""
Write-Color "Aeedo-Connect Setup" Cyan

$DEPENDENCIES = @("git")

foreach ($dep in $DEPENDENCIES) {
    if (!(Command-Exists $dep)) {
        Write-Color "Dependência '$dep' não encontrada. Por favor, instale '$dep' e tente novamente." Red
        exit 1
    }
}

Write-Host ""
Write-Color "Qual gerenciador de pacotes deseja usar para instalar as dependências?" Yellow
Write-Color "1) npm" Blue
Write-Color "2) yarn" Blue
Write-Color "3) pnpm" Blue
Write-Host ""
$packageManager = Read-Host "Escolha sua opção (1, 2, 3)"

switch ($packageManager) {
    "1" {
        $packageCommand = "npm install"
    }
    "2" {
        $packageCommand = "yarn"
    }
    "3" {
        $packageCommand = "pnpm install"
    }
    default {
        Write-Color "Opção inválida. Encerrando o setup." Red
        exit 1
    }
}

$pkgCmdExec = ($packageCommand -split " ")[0]
if (!(Command-Exists $pkgCmdExec)) {
    Write-Color "Gerenciador de pacotes '$pkgCmdExec' não encontrado. Por favor, instale-o antes de continuar." Red
    exit 1
}

if (Test-Path "apps") {
    Write-Color "A pasta 'apps' já existe. Deseja removê-la e começar do zero? (s/n)" Yellow
    $removeApps = Read-Host "Sua escolha"
    if ($removeApps -match "^[sS]$") {
        Write-Color "Removendo a pasta 'apps'..." Cyan
        Remove-Item -Recurse -Force "apps" -ErrorAction Stop
    } else {
        Write-Color "Continuando com a pasta 'apps' existente." Yellow
    }
}

if (!(Test-Path "apps")) {
    New-Item -ItemType Directory -Name "apps" -ErrorAction Stop | Out-Null
}

Set-Location "apps"

$repos = @(
    "https://github.com/segabrielcarvalho/aeedo-connect-api.git",
    "https://github.com/segabrielcarvalho/aeedo-connect-web.git",
    "https://github.com/segabrielcarvalho/aeedo-connect-doc.git",
    "https://github.com/segabrielcarvalho/aeedo-connect-admin.git"
)

Write-Color "Clonando os repositórios..." Cyan
foreach ($repo in $repos) {
    $repo_name = [System.IO.Path]::GetFileNameWithoutExtension($repo)
    if (!(Test-Path $repo_name)) {
        Write-Color "Clonando $repo..." Yellow
        git clone $repo
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao clonar $repo. Verifique sua conexão ou permissões do Git." Red
            exit 1
        }
    } else {
        Write-Color "Repositório $repo_name já existe. Pulando clonagem." Green
    }
}

$apps = @(
    "aeedo-connect-api",
    "aeedo-connect-web",
    "aeedo-connect-doc",
    "aeedo-connect-admin"
)

$envExamples = @(
    "..\..\envs\.env.api.example",
    "..\..\envs\.env.web.example",
    "..\..\envs\.env.doc.example",
    "..\..\envs\.env.admin.example"
)

$APP_PORTS = @()

for ($i = 0; $i -lt $apps.Count; $i++) {
    $app = $apps[$i]
    $envExample = $envExamples[$i]

    Write-Color "Configurando $app..." Yellow
    Set-Location $app

    if ($app -eq "aeedo-connect-api") {
        if (!(Command-Exists "docker")) {
            Write-Color "Docker não encontrado. Instale o Docker para continuar." Red
            exit 1
        }

        if (!(Test-Path ".env")) {
            Copy-Item $envExample ".env"
            if ($LASTEXITCODE -ne 0) {
                Write-Color "Erro ao copiar o arquivo .env para $app." Red
                exit 1
            }
            Write-Color ".env configurado para $app." Green
        } else {
            Write-Color "Arquivo .env já existe para $app. Deseja sobrescrevê-lo? (s/n)" Yellow
            $overwriteEnv = Read-Host "Sua escolha"
            if ($overwriteEnv -match "^[sS]$") {
                Copy-Item $envExample ".env" -Force
                if ($LASTEXITCODE -ne 0) {
                    Write-Color "Erro ao copiar o arquivo .env para $app." Red
                    exit 1
                }
                Write-Color ".env sobrescrito para $app." Green
            } else {
                Write-Color "Mantendo o arquivo .env existente para $app." Yellow
            }
        }

        if (!(Test-Path ".env")) {
            Write-Color "Erro: Arquivo .env não encontrado para $app." Red
            exit 1
        }

        $APP_PORT = Get-EnvVariableFromFile ".env" "APP_PORT"
        if ([string]::IsNullOrEmpty($APP_PORT)) {
            Write-Color "Erro: Variável APP_PORT não encontrada no arquivo .env de $app." Red
            exit 1
        }

        Write-Color "Atualizando docker-compose.yml para mapear a porta $APP_PORT..." Cyan
        if (!(Test-Path "docker-compose.yml")) {
            Write-Color "Erro: docker-compose.yml não encontrado." Red
            exit 1
        }

        $dockerComposeContent = Get-Content "docker-compose.yml"
        $newContent = $dockerComposeContent -replace "80:80", "$APP_PORT:80"
        $newContent | Set-Content "docker-compose.yml"

        Write-Color "Instalando dependências do Composer via Docker..." Cyan
        docker run --rm -v "$($PWD.Path):/var/www/html" -w /var/www/html laravelsail/php84-composer:latest composer install --ignore-platform-reqs
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao instalar dependências do Composer." Red
            exit 1
        }

        Write-Color "Parando e removendo containers e volumes existentes..." Cyan
        docker-compose down -v
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao parar/remover containers." Red
            exit 1
        }

        Write-Color "Iniciando os containers com Docker Compose..." Cyan
        docker-compose up -d
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao iniciar os containers com o Docker Compose." Red
            exit 1
        }

        Write-Color "Aguardando o banco de dados estar pronto..." Cyan
        $MAX_RETRIES = 60
        $RETRIES = 0

        $DB_HOST = Get-EnvVariableFromFile ".env" "DB_HOST"
        $DB_USERNAME = Get-EnvVariableFromFile ".env" "DB_USERNAME"
        $DB_PASSWORD = Get-EnvVariableFromFile ".env" "DB_PASSWORD"

        while ($RETRIES -lt $MAX_RETRIES) {
            docker-compose exec mysql mysqladmin ping -h $DB_HOST -u $DB_USERNAME --password=$DB_PASSWORD --silent
            if ($LASTEXITCODE -eq 0) {
                break
            }
            $RETRIES++
            Write-Color "Banco de dados ainda não está pronto. Tentativa $RETRIES/$MAX_RETRIES..." Yellow
            Start-Sleep -Seconds 2
        }

        if ($RETRIES -ge $MAX_RETRIES) {
            Write-Color "Banco de dados não ficou pronto a tempo. Verifique a configuração e tente novamente." Red
            exit 1
        }

        Write-Color "Banco de dados está pronto! Continuando..." Green

        Write-Color "Limpando cache de configuração e aplicação..." Cyan
        docker-compose exec laravel.test php artisan config:clear
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao limpar cache de configuração." Red
            exit 1
        }
        docker-compose exec laravel.test php artisan cache:clear
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao limpar cache de aplicação." Red
            exit 1
        }

        Write-Color "Executando migrações..." Cyan
        docker-compose exec laravel.test php artisan migrate --force
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao executar migrações." Red
            exit 1
        }

        Write-Color "Executando seeders..." Cyan
        docker-compose exec laravel.test php artisan db:seed --force
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao executar seeders." Red
            exit 1
        }

        $APP_PORTS += "$app|$APP_PORT"

    } else {
        $envLocalPath = ".env.local"
        if (!(Test-Path $envLocalPath)) {
            Copy-Item $envExample $envLocalPath
            if ($LASTEXITCODE -ne 0) {
                Write-Color "Erro ao copiar o arquivo .env.local para $app." Red
                exit 1
            }
            Write-Color ".env.local configurado para $app." Green
        } else {
            Write-Color "Arquivo .env.local já existe para $app. Pulando cópia." Green
        }

        $APP_PORT = Get-EnvVariableFromFile $envLocalPath "PORT"
        if ([string]::IsNullOrEmpty($APP_PORT)) {
            Write-Color "Erro: Variável PORT não encontrada no arquivo .env.local de $app." Red
            exit 1
        }

        if (Is-Port-In-Use $APP_PORT) {
            Write-Color "A porta $APP_PORT já está em uso. Por favor, libere a porta ou altere a configuração." Red
            exit 1
        }

        Write-Color "Instalando dependências para $app..." Cyan
        & $pkgCmdExec install
        if ($LASTEXITCODE -ne 0) {
            Write-Color "Erro ao instalar dependências para $app. Verifique o gerenciador de pacotes." Red
            exit 1
        }

        $APP_PORTS += "$app|$APP_PORT"
    }

    Set-Location ..
}

Write-Host ""
Write-Color "Setup local concluído com sucesso! 🚀" Green