#!/bin/bash

# --- КОНФИГУРАЦИЯ ---
ALIAS_NAME="gotelegram"
BINARY_PATH="/usr/local/bin/gotelegram"
CONTAINER_NAME="MTGProto"

# --- ТВОИ ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[38;2;22;255;0m'      # #16ff00
BLUE='\033[38;2;15;139;253m'     # #0f8bfd
YELLOW='\033[38;2;249;241;165m'  # #f9f1a5
NC='\033[0m'

# --- СИСТЕМНЫЕ ПРОВЕРКИ ---
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Ошибка: запустите через sudo!${NC}"
        exit 1
    fi
}

install_deps() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Установка Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}Установка qrencode...${NC}"
        apt-get update && apt-get install -y qrencode 2>/dev/null || yum install -y qrencode 2>/dev/null
    fi
    cp "$0" "$BINARY_PATH" && chmod +x "$BINARY_PATH"
}

get_ip() {
    local ip
    ip=$(curl -s -4 --max-time 5 https://api.ipify.org || curl -s -4 --max-time 5 https://icanhazip.com || echo "0.0.0.0")
    echo "$ip" | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1
}

# --- ПОКАЗАТЬ КОНФИГУРАЦИЮ ---
show_config() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then 
        echo -e "${RED}Прокси не запущен${NC}"
        return 1
    fi
    
    SECRET=$(docker inspect "$CONTAINER_NAME" --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
    IP=$(get_ip)
    PORT=$(docker inspect "$CONTAINER_NAME" --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
    PORT=${PORT:-443}
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

    echo -e "\n${GREEN}=== ПОДКЛЮЧЕНИЕ К ПРОКСИ ===${NC}"
    echo -e "${YELLOW}IP:${NC}     $IP"
    echo -e "${YELLOW}Port:${NC}   $PORT"
    echo -e "${YELLOW}Secret:${NC} $SECRET"
    echo -e "${YELLOW}Link:${NC}   ${BLUE}$LINK${NC}"
    echo -e "\n${GREEN}=== QR-код для подключения ===${NC}"
    qrencode -t ANSIUTF8 "$LINK"
}

# --- УСТАНОВКА ПРОКСИ ---
menu_install() {
    clear
    echo -e "${GREEN}--- Установка MTProto прокси ---${NC}"
    
    # Выбор домена
    echo -e "\n${YELLOW}Выберите домен для маскировки (Fake TLS):${NC}"
    domains=(
        "google.com" "wikipedia.org" "habr.com" "github.com" 
        "coursera.org" "udemy.com" "medium.com" "stackoverflow.com"
        "bbc.com" "cnn.com" "reuters.com" "nytimes.com"
        "lenta.ru" "rbc.ru" "ria.ru" "kommersant.ru"
        "stepik.org" "duolingo.com" "khanacademy.org" "ted.com"
    )
    
    for i in "${!domains[@]}"; do
        printf "${YELLOW}%2d)${NC} %-20s " "$((i+1))" "${domains[$i]}"
        [[ $(( (i+1) % 2 )) -eq 0 ]] && echo ""
    done
    echo ""
    
    read -p "$(echo -e ${YELLOW}Ваш выбор [1-20]: ${NC})" d_idx
    DOMAIN=${domains[$((d_idx-1))]}
    DOMAIN=${DOMAIN:-google.com}

    # Выбор порта
    echo -e "\n${YELLOW}Выберите порт:${NC}"
    echo -e "1) 443 (рекомендуется)"
    echo -e "2) 8443"
    echo -e "3) Свой порт"
    read -p "$(echo -e ${YELLOW}Выбор: ${NC})" p_choice
    
    case $p_choice in
        2) PORT=8443 ;;
        3) read -p "$(echo -e ${YELLOW}Введите порт: ${NC})" PORT ;;
        *) PORT=443 ;;
    esac

    # Проверка порта
    if ss -tuln | grep -q ":$PORT "; then
        echo -e "${RED}Внимание! Порт $PORT уже занят!${NC}"
        read -p "$(echo -e ${YELLOW}Продолжить всё равно? (y/n): ${NC})" force
        if [ "$force" != "y" ]; then
            echo -e "${YELLOW}Отмена установки${NC}"
            read -p "$(echo -e ${YELLOW}Нажмите Enter...${NC})"
            return
        fi
    fi

    # Установка
    echo -e "\n${GREEN}Настройка прокси...${NC}"
    SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN")
    
    # Остановка старого контейнера если есть
    docker stop "$CONTAINER_NAME" &>/dev/null && docker rm "$CONTAINER_NAME" &>/dev/null
    
    # Запуск нового
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart always \
        -p "$PORT":"$PORT" \
        nineseconds/mtg:2 simple-run \
        -n 1.1.1.1 \
        -i prefer-ipv4 \
        0.0.0.0:"$PORT" \
        "$SECRET" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Прокси успешно установлен!${NC}"
        show_config
    else
        echo -e "${RED}Ошибка при установке прокси${NC}"
    fi
    
    read -p "$(echo -e ${YELLOW}Нажмите Enter для продолжения...${NC})"
}

# --- УДАЛЕНИЕ ПРОКСИ ---
remove_proxy() {
    echo -e "${RED}Удаление прокси...${NC}"
    docker stop "$CONTAINER_NAME" &>/dev/null && docker rm "$CONTAINER_NAME" &>/dev/null
    echo -e "${GREEN}Прокси удален${NC}"
    read -p "$(echo -e ${YELLOW}Нажмите Enter...${NC})"
}

# --- ПЕРЕЗАПУСК ПРОКСИ ---
restart_proxy() {
    echo -e "${YELLOW}Перезапуск прокси...${NC}"
    docker restart "$CONTAINER_NAME" &>/dev/null
    echo -e "${GREEN}Готово${NC}"
    read -p "$(echo -e ${YELLOW}Нажмите Enter...${NC})"
}

# --- ОСНОВНОЕ МЕНЮ ---
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔════════════════════════════════╗${NC}"
        echo -e "${GREEN}║       MTGProto Manager         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}1)${NC} Установить прокси"
        echo -e "${YELLOW}2)${NC} Показать данные подключения"
        echo -e "${YELLOW}3)${NC} Перезапустить прокси"
        echo -e "${YELLOW}4)${NC} Удалить прокси"
        echo -e "${YELLOW}0)${NC} Выход"
        echo ""
        read -p "$(echo -e ${YELLOW}Выберите действие: ${NC})" choice
        
        case $choice in
            1) menu_install ;;
            2) 
                clear
                show_config
                read -p "$(echo -e ${YELLOW}Нажмите Enter...${NC})"
                ;;
            3) restart_proxy ;;
            4) remove_proxy ;;
            0) 
                echo -e "${YELLOW}Выход${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Неверный выбор${NC}"
                read -p "$(echo -e ${YELLOW}Нажмите Enter...${NC})"
                ;;
        esac
    done
}

# --- ЗАПУСК ---
check_root
install_deps
main_menu
