#!/bin/bash
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для цветного вывода
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функция для проверки установки команд
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 не установлен. Установите и попробуйте снова."
        exit 1
    fi
}

# Проверяем необходимые команды
check_command terraform
check_command docker
check_command jq  # Для парсинга JSON

deploy() {
    log_info "🚀 Начало развертывания инфраструктуры..."
    
    # Шаг 1: Создание ВМ в Yandex Cloud
    log_info "📦 Этап 1: Создание ВМ в Yandex Cloud..."
    cd ./terraform_yc
    
    terraform init
    terraform apply -auto-approve
    
    # Получаем outputs
    VM_IP=$(terraform output -raw vm_ip 2>/dev/null || terraform output -json | jq -r '.vm_ip.value // .vm_ip_address.value')
    VM_USER=$(terraform output -raw vm_user 2>/dev/null || terraform output -json | jq -r '.vm_user.value // "ubuntu"')
    SSH_PORT=$(terraform output -raw ssh_port 2>/dev/null || terraform output -json | jq -r '.ssh_port.value // "22"')
    
    if [ -z "$VM_IP" ] || [ "$VM_IP" = "null" ]; then
        log_error "Не удалось получить IP адрес ВМ. Проверьте outputs в terraform_yc"
        exit 1
    fi
    
    log_info "✅ ВМ создана: $VM_USER@$VM_IP:$SSH_PORT"
    
    # Ждем, пока ВМ станет доступна по SSH
    log_info "⏳ Ожидание доступности ВМ по SSH..."
    until nc -z $VM_IP $SSH_PORT 2>/dev/null; do
        sleep 5
        echo -n "."
    done
    echo ""
    
    # Даем время на полную загрузку ВМ
    sleep 40
    
    # Шаг 2: Создание Docker Context
    log_info "🐳 Этап 2: Создание Docker Context..."
    
    # Проверяем, существует ли контекст
    if docker context ls | grep -q "yc-vm"; then
        log_warn "Docker Context 'yc-vm' уже существует. Обновляю..."
        docker context rm yc-vm -f
    fi
    
    # Создаем новый контекст
    docker context create yc-vm --docker "host=ssh://${VM_USER}@${VM_IP}:${SSH_PORT}"
    docker context use yc-vm
    ssh-keyscan ${VM_IP} >> ~/.ssh/known_hosts

    # Проверяем подключение
    log_info "🔍 Проверка подключения к удаленному Docker..."
    if docker version > /dev/null 2>&1; then
        log_info "✅ Docker Context успешно создан и активирован"
    else
        log_error "Не удалось подключиться к Docker на ВМ. Проверьте установку Docker на ВМ."
        exit 1
    fi

    # Шаг 3: Развертывание Docker контейнеров
    log_info "📦 Этап 3: Развертывание Docker контейнеров..."
    cd ../terraform_docker

    terraform init
    terraform apply -auto-approve

log_info "✅ Развертывание завершено!"
    
    # Выводим информацию для подключения
    log_info "🌐 Информация для подключения:"
    echo "----------------------------------------"
    echo "ВМ: $VM_USER@$VM_IP"
    echo "Docker Context: yc-vm"
    echo ""
    echo "Для работы с удаленным Docker используйте:"
    echo "  docker context use yc-vm"
    echo ""
    echo "Для проверки контейнеров:"
    echo "  docker context use yc-vm"
    echo "  docker ps"
    echo ""
    echo "Для возврата к локальному Docker:"
    echo "  docker context use default"
    echo "----------------------------------------"
}

# Функция удаления инфраструктуры
destroy() {
    log_info "🗑️  Удаление инфраструктуры..."
    
    # Шаг 1: Удаление Docker контейнеров
    log_info "🐳 Этап 1: Удаление Docker контейнеров..."
    cd ./terraform_docker 2>/dev/null || log_warn "Директория terraform_docker не найдена, пропускаю..."
    
    if [ -d "./terraform_docker" ]; then
        cd ./terraform_docker
        terraform destroy -auto-approve || log_warn "Не удалось удалить Docker ресурсы"
        cd ..
    fi
    
    # Удаляем Docker Context
    log_info "🗑️  Удаление Docker Context..."
    if docker context ls | grep -q "yc-vm"; then
        docker context rm yc-vm -f
        log_info "✅ Docker Context 'yc-vm' удален"
    fi
    
    # Возвращаемся к локальному контексту
    docker context use default > /dev/null 2>&1
    
    # Шаг 2: Удаление ВМ
    log_info "📦 Этап 2: Удаление ВМ в Yandex Cloud..."
    cd ../terraform_yc 2>/dev/null || {
        log_error "Директория terraform_yc не найдена"
        exit 1
    }
    
    terraform destroy -auto-approve
    
    log_info "✅ Инфраструктура полностью удалена"
}

# Функция показа помощи
show_help() {
    echo "Использование: $0 [OPTION]"
    echo ""
    echo "Опции:"
    echo "  -d, --destroy    Удалить всю инфраструктуру"
    echo "  -h, --help       Показать это сообщение"
    echo "  (без опций)      Создать инфраструктуру"
    echo ""
    echo "Примеры:"
    echo "  $0               # Создать инфраструктуру"
    echo "  $0 --destroy     # Удалить инфраструктуру"
}

# Парсинг аргументов
case "$1" in
    -d|--destroy)
        destroy
        ;;
    -h|--help)
        show_help
        ;;
    "")
        deploy
        ;;
    *)
        log_error "Неизвестная опция: $1"
        show_help
        exit 1
        ;;
esac
