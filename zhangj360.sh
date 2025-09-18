#!/bin/bash

# 提示用户输入用户名和密码
USERNAME = zhangj360
PASSWORD = socks

# 定义端口
HTTP_PORT=56666

# 获取 VPS 的外部 IP 地址
VPS_IP=$(hostname -I | awk '{print $1}')

# 检查是否能够获取到IP
if [ -z "$VPS_IP" ]; then
    echo "无法获取到IP地址，程序退出。"
    exit 1
fi

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "请以root用户运行此脚本"
    exit 1
fi

# 更新系统并安装必要工具
echo "更新系统并安装基础工具..."
yum update -y
yum install -y epel-release wget net-tools httpd-tools firewalld

# 配置防火墙
configure_firewall() {
    echo "配置防火墙..."
    # 安装并启动firewalld
    systemctl start firewalld
    systemctl enable firewalld

    # 设置默认区域为public
    firewall-cmd --set-default-zone=public

    # 删除所有现有规则，确保干净状态
    firewall-cmd --permanent --zone=public --remove-service=ssh
    firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client
    firewall-cmd --permanent --remove-port=1-59393/tcp
    firewall-cmd --permanent --remove-port=59396-65535/tcp

    # 只开放必要的端口
    firewall-cmd --permanent --zone=public --add-port=$HTTP_PORT/tcp

    # 可选：如果需要SSH管理，保留22端口
    firewall-cmd --permanent --zone=public --add-port=22/tcp

    # 应用规则
    firewall-cmd --reload

    echo "防火墙已配置，只开放端口：22（SSH，可选）、$HTTP_PORT（HTTP）"
}

# 安装并配置Squid（HTTP代理，带认证）
install_http() {
    echo "安装Squid HTTP代理..."
    yum install -y squid
    if [ $? -ne 0 ]; then
        echo "Squid安装失败，请检查网络或yum源"
        exit 1
    fi

    # 生成Squid密码文件
    htpasswd -bc /etc/squid/passwd zhangj360 socks

    # 写入Squid配置文件
    cat <<EOF >/etc/squid/squid.conf
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours

acl auth_users proxy_auth REQUIRED
acl manager proto cache_object
acl localhost src 127.0.0.1/32 ::1
acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1
acl localnet src 0.0.0.0/0

acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

http_access allow manager localhost
http_access deny manager
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow auth_users
http_access deny all

http_port $HTTP_PORT
via off
forwarded_for delete

hierarchy_stoplist cgi-bin ?
coredump_dir /var/spool/squid

refresh_pattern ^ftp:       1440    20% 10080
refresh_pattern ^gopher:    1440    0%  1440
refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
refresh_pattern .           0       20% 4320
EOF

    # 启动Squid服务
    systemctl restart squid
    systemctl enable squid
    if systemctl is-active squid >/dev/null 2>&1; then
        echo "Squid已成功启动，监听端口：$HTTP_PORT，用户：zhangj360，密码：socks
    else
        echo "Squid启动失败，请检查日志：/var/log/squid/"
        exit 1
    fi
}

# 检查端口是否被占用
check_ports() {
    if netstat -tuln | grep -q ":$HTTP_PORT "; then
        echo "端口 $HTTP_PORT 已被占用，请更换端口或释放该端口"
        exit 1
    fi
}

# 主函数
main() {
    echo "开始部署HTTP代理服务..."
    check_ports
    configure_firewall
    install_http
    echo "部署完成！"
    echo "HTTP代理：$VPS_IP:$HTTP_PORT (用户：zhangj360 密码：socks)"
    echo "防火墙已启用，只开放端口：22（SSH，可选）、$HTTP_PORT"
    echo "请确保DMIT安全组已开放端口 $HTTP_PORT"
}

main
