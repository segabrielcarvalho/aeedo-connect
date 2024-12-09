#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "\n${BOLD}${CYAN}Iniciando o Setup do Projeto${RESET}\n"

echo -e "${YELLOW}Em qual plataforma você deseja rodar o projeto?${RESET}"
echo -e "1) ${BLUE}Linux${RESET}"
echo -e "2) ${BLUE}macOS${RESET}"
read -rp "Escolha sua opção (1, 2): " platformChoice

case $platformChoice in
  1)
    echo -e "\n${GREEN}Executando o setup para Linux...${RESET}"
    bash "$BASE_DIR/scripts/setup-linux.sh"
    ;;
  2)
    echo -e "\n${GREEN}Executando o setup para macOS...${RESET}"
    bash "$BASE_DIR/scripts/setup-linux.sh"
    ;;
  *)
    echo -e "\n${RED}Opção inválida. Encerrando o setup.${RESET}"
    exit 1
    ;;
esac
