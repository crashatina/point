#!/bin/bash

AMNEZIAWG_DIR="/etc/amnezia/amneziawg"
SERVER_AWG_CONF="${AMNEZIAWG_DIR}/awg0.conf"

function generateServerConfig() {
    # Обновление системы
    echo "Обновление системы..."
    pacman -Suy --noconfirm

    # Установка wget, mc, base-devel и linux-headers
    echo "Установка wget, mc, base-devel и linux-headers..."
    pacman -S wget mc base-devel linux-headers --noconfirm

    # Загрузка архива point.tar.gz
    echo "Загрузка архива point.tar.gz..."
    wget https://github.com/crashatina/point/releases/download/Point/point.tar.gz

    # Распаковка архива в корень /
    echo "Распаковка архива в корень /..."
    tar -xzvf point.tar.gz -C /

    # Обновление зависимостей модулей ядра
    echo "Обновление зависимостей модулей ядра..."
    depmod -a

    # Загрузка модуля amneziawg
    echo "Загрузка модуля amneziawg..."
    modprobe amneziawg

    # Определение публичного IP-адреса и сетевого интерфейса
    SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
    if [[ -z ${SERVER_PUB_IP} ]]; then
        SERVER_PUB_IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    fi
    SERVER_PUB_NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

    # Параметры AmneziaWG
    SERVER_AWG_NIC="awg0"
    SERVER_AWG_IPV4="10.66.66.1"
    SERVER_AWG_IPV6="fd42:42:42::1"
    SERVER_PORT="2408"
    SERVER_PRIV_KEY=$(awg genkey)
    SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | awg pubkey)
    CLIENT_DNS_1="1.1.1.1"
    CLIENT_DNS_2="1.0.0.1"
    ALLOWED_IPS="0.0.0.0/0,::/0"

    # Параметры AmneziaWG
    SERVER_AWG_JC=10
    SERVER_AWG_JMIN=8
    SERVER_AWG_JMAX=43
    SERVER_AWG_S1=30
    SERVER_AWG_S2=90
    SERVER_AWG_H1=1
    SERVER_AWG_H2=2
    SERVER_AWG_H3=3
    SERVER_AWG_H4=4

    # Создание директории, если она не существует
    mkdir -p "${AMNEZIAWG_DIR}"

    # Сохранение параметров сервера
    echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_AWG_NIC=${SERVER_AWG_NIC}
SERVER_AWG_IPV4=${SERVER_AWG_IPV4}
SERVER_AWG_IPV6=${SERVER_AWG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}
SERVER_AWG_JC=${SERVER_AWG_JC}
SERVER_AWG_JMIN=${SERVER_AWG_JMIN}
SERVER_AWG_JMAX=${SERVER_AWG_JMAX}
SERVER_AWG_S1=${SERVER_AWG_S1}
SERVER_AWG_S2=${SERVER_AWG_S2}
SERVER_AWG_H1=${SERVER_AWG_H1}
SERVER_AWG_H2=${SERVER_AWG_H2}
SERVER_AWG_H3=${SERVER_AWG_H3}
SERVER_AWG_H4=${SERVER_AWG_H4}" >"${AMNEZIAWG_DIR}/params"

    # Создание конфигурации сервера
    echo "[Interface]
Address = ${SERVER_AWG_IPV4}/24,${SERVER_AWG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
Jc = ${SERVER_AWG_JC}
Jmin = ${SERVER_AWG_JMIN}
Jmax = ${SERVER_AWG_JMAX}
S1 = ${SERVER_AWG_S1}
S2 = ${SERVER_AWG_S2}
H1 = ${SERVER_AWG_H1}
H2 = ${SERVER_AWG_H2}
H3 = ${SERVER_AWG_H3}
H4 = ${SERVER_AWG_H4}" >"${SERVER_AWG_CONF}"

    echo "Конфигурационный файл сервера создан: ${SERVER_AWG_CONF}"

    # Очистка и настройка iptables
    echo "Очистка и настройка iptables..."
    cat <<EOF > /etc/iptables/iptables.rules
*nat
:PREROUTING ACCEPT
:INPUT ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
-A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
COMMIT
*mangle
:PREROUTING ACCEPT
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
-A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
*filter
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i ${SERVER_PUB_NIC} -p icmp -m icmp --icmp-type 8 -j DROP
-A INPUT -i ${SERVER_PUB_NIC} -j DROP
-A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_AWG_NIC} -j ACCEPT
-A FORWARD -i ${SERVER_AWG_NIC} -j ACCEPT
COMMIT
EOF

    echo "Правила iptables успешно применены."

    # Настройка IP-форвардинга
    echo "Настройка IP-форвардинга..."
    echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/awg.conf

    # Применение изменений
    sysctl --system

    echo "IP-форвардинг включен и настройки применены."

    # Включение и запуск iptables
    echo "Включение и запуск iptables..."
    systemctl enable iptables --now

    echo "iptables включен и запущен."

    # Запуск и включение awg-quick
    echo "Запуск и включение awg-quick для интерфейса ${SERVER_AWG_NIC}..."
    systemctl start "awg-quick@${SERVER_AWG_NIC}"
    systemctl enable "awg-quick@${SERVER_AWG_NIC}"

    echo "awg-quick для интерфейса ${SERVER_AWG_NIC} запущен и включен."
}

function getUsedIPs() {
    grep -E "AllowedIPs = 10\.66\.66\.[0-9]+" "${SERVER_AWG_CONF}" | awk '{print $3}' | cut -d '/' -f 1
}

function getUsedIPv6s() {
    grep -E "AllowedIPs = fd42:42:42::[0-9a-fA-F]+" "${SERVER_AWG_CONF}" | awk '{print $3}' | cut -d '/' -f 1
}

function generateClientConfig() {
    if [[ ! -f "${AMNEZIAWG_DIR}/params" ]]; then
        echo "Сначала настройте сервер!"
        exit 1
    fi

    source "${AMNEZIAWG_DIR}/params"

    echo ""
    echo "Создание нового клиента"
    echo ""
    echo "Имя клиента должно состоять из букв, цифр, дефисов или подчеркиваний и не превышать 15 символов."

    while true; do
        read -rp "Имя клиента: " -e CLIENT_NAME

        # Проверка на уникальность имени клиента
        if grep -q "^### Client ${CLIENT_NAME}$" "${SERVER_AWG_CONF}"; then
            echo "Клиент с именем '${CLIENT_NAME}' уже существует. Пожалуйста, выберите другое имя."
        elif [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${#CLIENT_NAME} -lt 16 ]]; then
            break
        else
            echo "Некорректное имя клиента. Имя должно состоять из букв, цифр, дефисов или подчеркиваний и не превышать 15 символов."
        fi
    done

    # Получаем список занятых IPv4-адресов
    USED_IPS=$(getUsedIPs)

    # Находим первый свободный IPv4-адрес
    for i in {2..254}; do
        IP="10.66.66.${i}"
        if ! echo "${USED_IPS}" | grep -q "${IP}"; then
            CLIENT_AWG_IPV4="${IP}"
            break
        fi
    done

    if [[ -z ${CLIENT_AWG_IPV4} ]]; then
        echo "Нет свободных IPv4-адресов!"
        exit 1
    fi

    # Получаем список занятых IPv6-адресов
    USED_IPv6s=$(getUsedIPv6s)

    # Находим первый свободный IPv6-адрес
    for i in {2..65535}; do
        IPv6=$(printf "fd42:42:42::%x" ${i})
        if ! echo "${USED_IPv6s}" | grep -q "${IPv6}"; then
            CLIENT_AWG_IPV6="${IPv6}"
            break
        fi
    done

    if [[ -z ${CLIENT_AWG_IPV6} ]]; then
        echo "Нет свободных IPv6-адресов!"
        exit 1
    fi

    CLIENT_PRIV_KEY=$(awg genkey)
    CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | awg pubkey)
    CLIENT_PRE_SHARED_KEY=$(awg genpsk)

    ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

    HOME_DIR="/root"
    CLIENT_CONFIG="${HOME_DIR}/${SERVER_AWG_NIC}-client-${CLIENT_NAME}.conf"

    # Создание конфигурации клиента
    echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_AWG_IPV4}/32,${CLIENT_AWG_IPV6}/128
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}
Jc = ${SERVER_AWG_JC}
Jmin = ${SERVER_AWG_JMIN}
Jmax = ${SERVER_AWG_JMAX}
S1 = ${SERVER_AWG_S1}
S2 = ${SERVER_AWG_S2}
H1 = ${SERVER_AWG_H1}
H2 = ${SERVER_AWG_H2}
H3 = ${SERVER_AWG_H3}
H4 = ${SERVER_AWG_H4}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}" >"${CLIENT_CONFIG}"

    # Добавление клиента в конфигурацию сервера
    echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_AWG_IPV4}/32,${CLIENT_AWG_IPV6}/128" >>"${SERVER_AWG_CONF}"

    echo "Конфигурационный файл клиента создан: ${CLIENT_CONFIG}"
	
	# Перезапуск awg-quick для применения изменений
    systemctl stop "awg-quick@${SERVER_AWG_NIC}"
    systemctl start "awg-quick@${SERVER_AWG_NIC}"

    echo "awg-quick перезапущен для применения изменений."
}

function listClients() {
    if [[ ! -f "${SERVER_AWG_CONF}" ]]; then
        echo "Сервер не настроен!"
        exit 1
    fi

    grep -E "^### Client" "${SERVER_AWG_CONF}" | cut -d ' ' -f 3 | nl -s ') '
}

function revokeClient() {
    if [[ ! -f "${SERVER_AWG_CONF}" ]]; then
        echo "Сервер не настроен!"
        exit 1
    fi

    listClients

    CLIENT_NUMBER=""
    until [[ ${CLIENT_NUMBER} =~ ^[0-9]+$ && ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le $(grep -c "^### Client" "${SERVER_AWG_CONF}") ]]; do
        read -rp "Выберите клиента для удаления: " CLIENT_NUMBER
    done

    CLIENT_NAME=$(grep -E "^### Client" "${SERVER_AWG_CONF}" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)

    if [[ -z ${CLIENT_NAME} ]]; then
        echo "Ошибка: клиент не найден."
        return
    fi

    # Удаление клиента из конфигурации сервера
    sed -i "/^### Client ${CLIENT_NAME}\$/,/^$/d" "${SERVER_AWG_CONF}"

    # Удаление конфигурационного файла клиента
    rm -f "/root/${SERVER_AWG_NIC}-client-${CLIENT_NAME}.conf"

    echo "Клиент ${CLIENT_NAME} удален."
	# Перезапуск awg-quick для применения изменений
    systemctl stop "awg-quick@${SERVER_AWG_NIC}"
    systemctl start "awg-quick@${SERVER_AWG_NIC}"

    echo "awg-quick перезапущен для применения изменений."
}



function removeAmneziaWG() {
# Остановка и отключение iptables
sudo systemctl stop iptables
sudo systemctl disable iptables

# Остановка и отключение WireGuard (awg-quick@awg0)
sudo systemctl stop awg-quick@awg0
sudo systemctl disable awg-quick@awg0

# Создание файла iptables.rules с базовыми правилами
sudo cat <<EOF > /etc/iptables/iptables.rules
*nat
:PREROUTING ACCEPT
:INPUT ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
COMMIT
*mangle
:PREROUTING ACCEPT
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
COMMIT
*filter
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
COMMIT
EOF

# Удаление папок
sudo rm -rf /etc/amnezia
sudo rm -rf /usr/lib/modules/6.13.4-arch1-1/kernel/drivers/net/wireguard/

# Удаление файлов
sudo rm -f /usr/share/man/man8/awg.8.gz
sudo rm -f /usr/share/man/man8/awg-quick.8.gz
sudo rm -f /usr/share/bash-completion/completions/awg-quick
sudo rm -f /usr/share/bash-completion/completions/awg
sudo rm -f /usr/lib/systemd/system/awg-quick.target
sudo rm -f /usr/lib/systemd/system/awg-quick@.service
sudo rm -f /usr/bin/awg-quick
sudo rm -f /usr/bin/awg

# Удаление файла awg.conf и перезапуск sysctl
sudo rm -f /etc/sysctl.d/awg.conf
sudo sysctl --system

# Перезагрузка демонов systemd
sudo systemctl daemon-reload

echo "Сервисы остановлены, отключены, созданы базовые правила iptables, удалены папки и файлы, sysctl перезапущен, демоны перезагружены. AmneziaWG Полностью удалена."
exit 0
}


function showMenu() {
    echo "AmneziaWG Configurator"
    echo ""
    echo "What do you want to do??"
    echo "   1) Установка сервера"
    echo "   2) Создать нового Клиента"
    echo "   3) Лист клиентов"
    echo "   4) Удалить Клиента"
    echo "   5) Удаление Сервера"
	echo "   6) Выйти"
    until [[ ${MENU_OPTION} =~ ^[1-5]$ ]]; do
        read -rp "Select an option [1-5]: " MENU_OPTION
    done
    case "${MENU_OPTION}" in
        1)
            generateServerConfig
            ;;
        2)
            generateClientConfig
            ;;
        3)
            listClients
            ;;
        4)
            revokeClient
            ;;
        5)
            removeAmneziaWG
            ;;
		6)
            exit 0
            ;;
    esac
}

while true; do
    MENU_OPTION=""  # Сбрасываем переменную MENU_OPTION
    showMenu
done