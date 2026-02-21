#!/bin/bash

# --- КОНФИГУРАЦИЯ ---
ALIAS_NAME="gotelegram"
BINARY_PATH="/usr/local/bin/gotelegram"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'


YELLOW_CUSTOM='\033[38;2;249;241;165m'  # #f9f1a5
BLUE_CUSTOM='\033[38;2;15;139;253m'     # #0f8bfd
GREEN_CUSTOM='\033[38;2;22;255;0m'      # #16ff00

# --- СИСТЕМНЫЕ ПРОВЕРКИ ---
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Ошибка: запустите через sudo!${NC}"
        exit 1
    fi
}

install_deps() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW_CUSTOM}Установка Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW_CUSTOM}Установка qrencode...${NC}"
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
    if ! docker ps | grep -q "mtproto-proxy"; then 
        echo -e "${RED}Прокси не запущен${NC}"
        return 1
    fi
    
    SECRET=$(docker inspect mtproto-proxy --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
    IP=$(get_ip)
    
    # Правильное получение порта
    PORT=$(docker port mtproto-proxy 2>/dev/null | head -1 | grep -o '[0-9]*$')
    if [ -z "$PORT" ]; then
        # Fallback метод через inspect
        PORT=$(docker inspect mtproto-proxy --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
    fi
    PORT=${PORT:-443}
    
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

    echo -e "\n${GREEN_CUSTOM}=== ПОДКЛЮЧЕНИЕ К ПРОКСИ ===${NC}"
    echo -e "${YELLOW_CUSTOM}IP:     ${NC}$IP"
    echo -e "${YELLOW_CUSTOM}Port:   ${NC}$PORT"
    echo -e "${YELLOW_CUSTOM}Secret: ${NC}$SECRET"
    echo -e "${YELLOW_CUSTOM}Link:   ${BLUE_CUSTOM}$LINK${NC}"
    echo -e "\n${GREEN_CUSTOM}=== QR-код для подключения ===${NC}"
    qrencode -t ANSIUTF8 "$LINK"
}

# --- УСТАНОВКА ПРОКСИ ---
install_proxy() {
    clear
    echo -e "${GREEN_CUSTOM}--- Установка MTProto прокси ---${NC}"
    
    # Выбор домена
    echo -e "\n${YELLOW_CUSTOM}Выберите домен для маскировки (Fake TLS):${NC}"
    domains=(
        "google.com" "cloudflare.com" "github.com" "microsoft.com"
        "amazon.com" "apple.com" "telegram.org" "vk.com"
        "yandex.ru" "yahoo.com" "bing.com" "duckduckgo.com"
    )
    
    for i in "${!domains[@]}"; do
        echo "$((i+1))) ${domains[$i]}"
    done
    echo "$((${#domains[@]}+1))) Свой вариант"
    
    read -p "$(echo -e ${YELLOW_CUSTOM}Выберите домен [1-${#domains[@]}]: ${NC})" d_idx
    
    if [ "$d_idx" -eq "$((${#domains[@]}+1))" ]; then
        read -p "$(echo -e ${YELLOW_CUSTOM}Введите домен: ${NC})" DOMAIN
    else
        DOMAIN=${domains[$((d_idx-1))]}
    fi
    DOMAIN=${DOMAIN:-google.com}

    # Выбор порта
    echo -e "\n${YELLOW_CUSTOM}Выберите порт:${NC}"
    echo "1) 443 (рекомендуется)"
    echo "2) 8443"
    echo "3) Свой порт"
    read -p "$(echo -e ${YELLOW_CUSTOM}Выбор: ${NC})" p_choice
    
    case $p_choice in
        2) PORT=8443 ;;
        3) read -p "$(echo -e ${YELLOW_CUSTOM}Введите порт: ${NC})" PORT ;;
        *) PORT=443 ;;
    esac

    # Проверка, не занят ли порт
    if ss -tuln | grep -q ":$PORT "; then
        echo -e "${RED}Внимание! Порт $PORT уже занят!${NC}"
        read -p "$(echo -e ${YELLOW_CUSTOM}Продолжить всё равно? (y/n): ${NC})" force
        if [ "$force" != "y" ]; then
            echo -e "${YELLOW_CUSTOM}Отмена установки${NC}"
            read -p "$(echo -e ${YELLOW_CUSTOM}Нажмите Enter...${NC})"
            return
        fi
    fi

    # Установка
    echo -e "\n${GREEN_CUSTOM}Настройка прокси...${NC}"
    SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN")
    
    # Остановка старого контейнера если есть
    docker stop mtproto-proxy &>/dev/null && docker rm mtproto-proxy &>/dev/null
    
    # Запуск нового
    docker run -d \
        --name mtproto-proxy \
        --restart always \
        -p "$PORT":"$PORT" \
        nineseconds/mtg:2 run \
        -b 0.0.0.0:"$PORT" \
        "$SECRET" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN_CUSTOM}Прокси успешно установлен!${NC}"
        show_config
    else
        echo -e "${RED}Ошибка при установке прокси${NC}"
    fi
    
    read -p "$(echo -e ${YELLOW_CUSTOM}Нажмите Enter для продолжения...${NC})"
}

# --- УДАЛЕНИЕ ПРОКСИ ---
remove_proxy() {
    echo -e "${RED}Удаление прокси...${NC}"
    docker stop mtproto-proxy &>/dev/null
    docker rm mtproto-proxy &>/dev/null
    echo -e "${GREEN_CUSTOM}Прокси удален${NC}"
    read -p "$(echo -e ${YELLOW_CUSTOM}Нажмите Enter...${NC})"
}

# --- ОСНОВНОЕ МЕНЮ ---
main_menu() {
    while true; do
        clear
        echo -e "${GREEN_CUSTOM}╔════════════════════════════════╗${NC}"
        echo -e "${GREEN_CUSTOM}║    MTProto Proxy Manager      ║${NC}"
        echo -e "${GREEN_CUSTOM}╚════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW_CUSTOM}1)${NC} Установить прокси (с обфускацией)"
        echo -e "${YELLOW_CUSTOM}2)${NC} Показать данные подключения"
        echo -e "${YELLOW_CUSTOM}3)${NC} Перезапустить прокси"
        echo -e "${YELLOW_CUSTOM}4)${NC} Удалить прокси"
        echo -e "${YELLOW_CUSTOM}0)${NC} Выход"
        echo ""
        read -p "$(echo -e ${YELLOW_CUSTOM}Выберите действие: ${NC})" choice
        
        case $choice in
            1) install_proxy ;;
            2) 
                clear
                show_config
                read -p "$(echo -e ${YELLOW_CUSTOM}Нажмите Enter...${NC})"
                ;;
            3)
                echo -e "${YELLOW_CUSTOM}Перезапуск прокси...${NC}"
                docker restart mtproto-proxy &>/dev/null
                echo -e "${GREEN_CUSTOM}Готово${NC}"
                read -p "$(echo -e ${YELLOW_CUSTOM}Нажмите Enter...${NC})"
                ;;
            4) remove_proxy ;;
            0) 
                echo -e "${YELLOW_CUSTOM}Выход${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Неверный выбор${NC}"
                read -p "$(echo -e ${YELLOW_CUSTOM}Нажмите Enter...${NC})"
                ;;
        esac
    done
}

# --- ЗАПУСК ---
check_root
install_deps
main_menu
