#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
BOLD='\033[1m'
ITALIC='\033[3m'
RESET='\033[0m'

if [ -z "$BASH_VERSION" ]; then
  echo -e "${RED}Este script deve ser executado em um ambiente Bash.${RESET}"
  exit 1
fi

echo ""
echo -e "${BOLD}${CYAN}Aeedo-Connect Setup${RESET}"

DEPENDENCIES=(git)
for dep in "${DEPENDENCIES[@]}"; do
  if ! command -v $dep &> /dev/null; then
    echo -e "${RED}Dependência '${dep}' não encontrada. Por favor, instale '${dep}' e tente novamente.${RESET}"
    exit 1
  fi
done

echo ""
echo -e "${YELLOW}Qual gerenciador de pacotes deseja usar para instalar as dependências?${RESET}"
echo -e "1) ${BLUE}npm${RESET}"
echo -e "2) ${BLUE}yarn${RESET}"
echo -e "3) ${BLUE}pnpm${RESET}"
echo ""
read -rp "Escolha sua opção (1, 2, 3): " packageManager

case $packageManager in
  1)
    packageCommand="npm install"
    ;;
  2)
    packageCommand="yarn"
    ;;
  3)
    packageCommand="pnpm install"
    ;;
  *)
    echo -e "${RED}Opção inválida. Encerrando o setup.${RESET}"
    exit 1
    ;;
esac

if ! command -v ${packageCommand%% *} &> /dev/null; then
  echo -e "${RED}Gerenciador de pacotes '${packageCommand%% *}' não encontrado. Por favor, instale-o antes de continuar.${RESET}"
  exit 1
fi

if [ -d "apps" ]; then
  echo -e "${YELLOW}A pasta 'apps' já existe. Deseja removê-la e começar do zero? (s/n)${RESET}"
  read -rp "Sua escolha: " removeApps

  if [[ $removeApps =~ ^[sS]$ ]]; then
    echo -e "${CYAN}Removendo a pasta 'apps'...${RESET}"
    rm -rf apps || { echo -e "${RED}Erro ao remover a pasta 'apps'. Encerrando.${RESET}"; exit 1; }
  else
    echo -e "${YELLOW}Continuando com a pasta 'apps' existente.${RESET}"
  fi
fi

mkdir -p apps || { echo -e "${RED}Erro ao criar a pasta 'apps'. Encerrando.${RESET}"; exit 1; }
cd apps || exit 1

repos=(
  "https://github.com/segabrielcarvalho/aeedo-connect-api.git"
  "https://github.com/segabrielcarvalho/aeedo-connect-web.git"
  "https://github.com/segabrielcarvalho/aeedo-connect-doc.git"
  "https://github.com/segabrielcarvalho/aeedo-connect-admin.git"
)

echo -e "${CYAN}Clonando os repositórios...${RESET}"
for repo in "${repos[@]}"; do
  repo_name=$(basename "$repo" .git)
  if [ ! -d "$repo_name" ]; then
    echo -e "${YELLOW}Clonando ${repo}...${RESET}"
    git clone "$repo" || { echo -e "${RED}Erro ao clonar ${repo}. Verifique sua conexão ou permissões do Git.${RESET}"; exit 1; }
  else
    echo -e "${GREEN}Repositório ${repo_name} já existe. Pulando clonagem.${RESET}"
  fi
done

apps=(
  "aeedo-connect-api"
  "aeedo-connect-web"
  "aeedo-connect-doc"
  "aeedo-connect-admin"
)

envExamples=(
  "../../envs/.env.api.example"
  "../../envs/.env.web.example"
  "../../envs/.env.doc.example"
  "../../envs/.env.admin.example"
)


declare -a APP_PORTS

for i in "${!apps[@]}"; do
  app="${apps[i]}"
  env="${envExamples[i]}"

  echo -e "${YELLOW}Configurando ${app}...${RESET}"

  cd "$app" || exit 1

  if [ "$app" = "aeedo-connect-api" ]; then
    if ! command -v docker &> /dev/null; then
      echo -e "${RED}Docker não encontrado. Instale o Docker para continuar.${RESET}"
      exit 1
    fi

    if [ ! -f .env ]; then
      cp "$env" .env || { echo -e "${RED}Erro ao copiar o arquivo .env para ${app}.${RESET}"; exit 1; }
      echo -e "${GREEN}.env configurado para ${app}.${RESET}"
    else
      echo -e "${YELLOW}Arquivo .env já existe para ${app}. Deseja sobrescrevê-lo? (s/n)${RESET}"
      read -rp "Sua escolha: " overwriteEnv
      if [[ $overwriteEnv =~ ^[sS]$ ]]; then
        cp "$env" .env || { echo -e "${RED}Erro ao copiar o arquivo .env para ${app}.${RESET}"; exit 1; }
        echo -e "${GREEN}.env sobrescrito para ${app}.${RESET}"
      else
        echo -e "${YELLOW}Mantendo o arquivo .env existente para ${app}.${RESET}"
      fi
    fi

    if [ ! -f .env ]; then
      echo -e "${RED}Erro: Arquivo .env não encontrado para ${app}.${RESET}"
      exit 1
    fi

    APP_PORT=$(grep -E "^APP_PORT=" .env | cut -d '=' -f2-)

    if [ -z "$APP_PORT" ]; then
      echo -e "${RED}Erro: Variável APP_PORT não encontrada no arquivo .env de ${app}.${RESET}"
      exit 1
    fi

    echo -e "${CYAN}Atualizando docker-compose.yml para mapear a porta ${APP_PORT}...${RESET}"
    sed -i.bak "s/80:80/${APP_PORT}:80/g" docker-compose.yml || { echo -e "${RED}Erro ao atualizar docker-compose.yml.${RESET}"; exit 1; }

    echo -e "${CYAN}Instalando dependências do Composer via Docker...${RESET}"
    docker run --rm \
      -u "$(id -u):$(id -g)" \
      -v "$(pwd):/var/www/html" \
      -w /var/www/html \
      laravelsail/php84-composer:latest \
      composer install --ignore-platform-reqs || { echo -e "${RED}Erro ao instalar dependências do Composer.${RESET}"; exit 1; }

    chmod +x vendor/bin/sail

    echo -e "${CYAN}Parando e removendo containers e volumes existentes...${RESET}"
    ./vendor/bin/sail down -v

    echo -e "${CYAN}Iniciando os containers com o Sail...${RESET}"
    ./vendor/bin/sail up -d || { echo -e "${RED}Erro ao iniciar os containers com o Sail.${RESET}"; exit 1; }

    echo -e "${CYAN}Aguardando o banco de dados estar pronto...${RESET}"
    MAX_RETRIES=60
    RETRIES=0

    DB_HOST=$(grep -E "^DB_HOST=" .env | cut -d '=' -f2-)
    DB_USERNAME=$(grep -E "^DB_USERNAME=" .env | cut -d '=' -f2-)
    DB_PASSWORD=$(grep -E "^DB_PASSWORD=" .env | cut -d '=' -f2-)

    while ! ./vendor/bin/sail exec mysql mysqladmin ping -h "${DB_HOST}" -u "${DB_USERNAME}" --password="${DB_PASSWORD}" --silent; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo -e "${RED}Banco de dados não ficou pronto a tempo. Verifique a configuração e tente novamente.${RESET}"
        exit 1
      fi
      echo -e "${YELLOW}Banco de dados ainda não está pronto. Tentativa $RETRIES/${MAX_RETRIES}...${RESET}"
      sleep 2
    done

    echo -e "${GREEN}Banco de dados está pronto! Continuando...${RESET}"
    echo -e "${CYAN}Limpando cache de configuração e aplicação...${RESET}"
    ./vendor/bin/sail artisan config:clear || { echo -e "${RED}Erro ao limpar cache de configuração.${RESET}"; exit 1; }
    ./vendor/bin/sail artisan cache:clear || { echo -e "${RED}Erro ao limpar cache de aplicação.${RESET}"; exit 1; }

    echo -e "${CYAN}Executando migrações...${RESET}"
    ./vendor/bin/sail artisan migrate --force || { echo -e "${RED}Erro ao executar migrações.${RESET}"; exit 1; }

    echo -e "${CYAN}Executando seeders...${RESET}"
    ./vendor/bin/sail artisan db:seed --force || { echo -e "${RED}Erro ao executar seeders.${RESET}"; exit 1; }

    APP_PORTS+=("$app|$APP_PORT")

  else
    if [ ! -f .env.local ]; then
      cp "$env" .env.local || { echo -e "${RED}Erro ao copiar o arquivo .env.local para ${app}.${RESET}"; exit 1; }
      echo -e "${GREEN}.env.local configurado para ${app}.${RESET}"
    else
      echo -e "${GREEN}Arquivo .env.local já existe para ${app}. Pulando cópia.${RESET}"
    fi

    APP_PORT=$(grep -E "^PORT=" .env.local | cut -d '=' -f2-)

    if [ -z "$APP_PORT" ]; then
      echo -e "${RED}Erro: Variável PORT não encontrada no arquivo .env.local de ${app}.${RESET}"
      exit 1
    fi

    if is_port_in_use "$APP_PORT"; then
      echo -e "${RED}A porta ${APP_PORT} já está em uso. Por favor, libere a porta ou altere a configuração.${RESET}"
      exit 1
    fi

    echo -e "${CYAN}Instalando dependências para ${app}...${RESET}"
    $packageCommand || { echo -e "${RED}Erro ao instalar dependências para ${app}. Verifique o gerenciador de pacotes.${RESET}"; exit 1; }

    APP_PORTS+=("$app|$APP_PORT")
  fi

  cd ..
done

echo ""
echo -e "${BOLD}${GREEN}Setup local concluído com sucesso! 🚀${RESET}"