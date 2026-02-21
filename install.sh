#!/bin/bash

# --- КОНФИГУРАЦИЯ ---
ALIAS_NAME="gotelegram"
BINARY_PATH="/usr/local/bin/gotelegram"

# --- ЦВЕТА (минимально) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
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
        echo "Установка Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
        echo "Установка qrencode..."
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
    PORT=$(docker inspect mtproto-proxy --format='{{(index (index .HostConfig.PortBindings (printf "%s/tcp" (index .Config.ExposedPorts 0))) 0).HostPort}}' 2>/dev/null)
    PORT=${PORT:-443}
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

    echo -e "\n${GREEN}=== ПОДКЛЮЧЕНИЕ К ПРОКСИ ===${NC}"
    echo -e "IP:     $IP"
    echo -e "Port:   $PORT"
    echo -e "Secret: $SECRET"
    echo -e "Link:   ${BLUE}$LINK${NC}"
    echo -e "\n${GREEN}=== QR-код для подключения ===${NC}"
    qrencode -t ANSIUTF8 "$LINK"
}

# --- УСТАНОВКА ПРОКСИ ---
install_proxy() {
    clear
    echo -e "${GREEN}--- Установка MTProto прокси ---${NC}"
    
    # Выбор домена
    echo -e "\nВыберите домен для маскировки (Fake TLS):"
    domains=(
        "google.com" "cloudflare.com" "github.com" "microsoft.com"
        "amazon.com" "apple.com" "telegram.org" "vk.com"
    )
    
    for i in "${!domains[@]}"; do
        echo "$((i+1))) ${domains[$i]}"
    done
    echo "$((${#domains[@]}+1))) Свой вариант"
    
    read -p "Выберите домен [1-${#domains[@]}]: " d_idx
    
    if [ "$d_idx" -eq "$((${#domains[@]}+1))" ]; then
        read -p "Введите домен: " DOMAIN
    else
        DOMAIN=${domains[$((d_idx-1))]}
    fi
    DOMAIN=${DOMAIN:-google.com}

    # Выбор порта
    echo -e "\nВыберите порт:"
    echo "1) 443 (рекомендуется)"
    echo "2) 8443"
    echo "3) Свой порт"
    read -p "Выбор: " p_choice
    
    case $p_choice in
        2) PORT=8443 ;;
        3) read -p "Введите порт: " PORT ;;
        *) PORT=443 ;;
    esac

    # Установка
    echo -e "\n${GREEN}Настройка прокси...${NC}"
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
        echo -e "${GREEN}Прокси успешно установлен!${NC}"
        show_config
    else
        echo -e "${RED}Ошибка при установке прокси${NC}"
    fi
    
    read -p "Нажмите Enter для продолжения..."
}

# --- УДАЛЕНИЕ ПРОКСИ ---
remove_proxy() {
    echo -e "${RED}Удаление прокси...${NC}"
    docker stop mtproto-proxy &>/dev/null
    docker rm mtproto-proxy &>/dev/null
    echo -e "${GREEN}Прокси удален${NC}"
    read -p "Нажмите Enter..."
}

# --- ОСНОВНОЕ МЕНЮ ---
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}=== MTProto Proxy Manager ===${NC}"
        echo "1) Установить прокси"
        echo "2) Показать данные подключения"
        echo "3) Перезапустить прокси"
        echo "4) Удалить прокси"
        echo "0) Выход"
        echo ""
        read -p "Выберите действие: " choice
        
        case $choice in
            1) install_proxy ;;
            2) 
                clear
                show_config
                read -p "Нажмите Enter..."
                ;;
            3)
                echo "Перезапуск прокси..."
                docker restart mtproto-proxy &>/dev/null
                echo -e "${GREEN}Готово${NC}"
                read -p "Нажмите Enter..."
                ;;
            4) remove_proxy ;;
            0) 
                echo "Выход"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Неверный выбор${NC}"
                read -p "Нажмите Enter..."
                ;;
        esac
    done
}

# --- ЗАПУСК ---
check_root
install_deps
main_menu
