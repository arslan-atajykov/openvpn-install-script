#!/bin/bash

set -e

# Обновление и установка OpenVPN и easy-rsa
apt-get update
apt-get install -y openvpn easy-rsa iptables

# Настройка easy-rsa
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Создание vars с настройками easy-rsa (можно добавить сюда свои значения)
cat > vars <<EOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "SanFrancisco"
set_var EASYRSA_REQ_ORG        "MyOrg"
set_var EASYRSA_REQ_EMAIL      "email@example.com"
set_var EASYRSA_REQ_OU         "MyOU"
EOF

# Инициализация PKI и создание CA
./easyrsa init-pki
./easyrsa build-ca nopass

# Генерация ключей сервера и клиента, dh, tls-crypt
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
openvpn --genkey --secret ta.key

# Копирование ключей и сертификатов в /etc/openvpn/server
mkdir -p /etc/openvpn/server
cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/server/

# Создание базового server.conf с нужными настройками
cat > /etc/openvpn/server/server.conf <<EOF
port 1194
proto udp
dev tun
user nobody
group nogroup
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

# Криптография
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt ta.key
auth SHA256
cipher AES-128-GCM
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256
remote-cert-tls client
explicit-exit-notify 1
verb 3

# ВАЖНО: прокидываем маршруты и DNS клиенту
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
EOF

# Включаем IP forwarding
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

# Настройка iptables для NAT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

# Сохраняем правила iptables, чтобы остались после перезагрузки (для Debian/Ubuntu)
apt-get install -y iptables-persistent
netfilter-persistent save

# Включаем и запускаем OpenVPN сервер
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

echo "OpenVPN сервер установлен и настроен с прокидыванием маршрутов и DNS."
