#!/bin/bash

set -e

echo -e " \e[32mUpdating system\e[0m"
sleep 2
apt update -y
apt upgrade -y
apt install -y net-tools software-properties-common curl unzip

VERSION="5.6.8"
TIME_ZONE="Europe/Amsterdam"
MYSQL_ROOT_PASSWORD="test123456"
REPOSITORY="https://bob-tv-previous-customize.trycloudflare.com/stalker"

# SET LOCALE TO UTF-8
function setLocale {
    echo -e " \e[32mSetting locales\e[0m"
    locale-gen en_US.UTF-8  >> /dev/null 2>&1
    export LANG="en_US.UTF-8"
    echo -e " \e[32mDone.\e[0m"
}

# TWEAK SYSTEM VALUES
function tweakSystem {
    echo -ne "\e[32mTweaking system"
    cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
fs.file-max = 327680
kernel.core_uses_pid = 1
kernel.core_pattern = /var/crash/core-%e-%s-%u-%g-%p-%t
fs.suid_dumpable = 2
EOF
    sysctl -p >> /dev/null 2>&1
    echo -e " \e[32mDone.\e[0m"
}

setLocale;
tweakSystem;

sleep 3

add-apt-repository ppa:ondrej/php -y
apt update -y

echo -e " \e[32mInstalling required packages\e[0m"
sleep 3
apt install -y nginx apache2 php8.2 php8.2-cli php8.2-common php8.2-xml php8.2-mbstring php8.2-curl php8.2-zip php8.2-mysql php8.2-soap php8.2-intl php8.2-bcmath memcached php8.2-memcached nodejs npm unzip composer

systemctl stop nginx apache2

# Ensure nodejs is accessible as node
ln -sf /usr/bin/nodejs /usr/bin/node

# Set PHP alternative
update-alternatives --set php /usr/bin/php8.2

# Set Timezone
echo -e " \e[32mSetting the Server Timezone to $TIME_ZONE\e[0m"
timedatectl set-timezone $TIME_ZONE
dpkg-reconfigure -f noninteractive tzdata

# Install MySQL
echo -e " \e[32mInstalling MySQL Server\e[0m"
export DEBIAN_FRONTEND="noninteractive"
echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
apt install -y mysql-server

# Configure MySQL
sed -i 's/127\.0\.0\.1/0\.0\.0\.0/g' /etc/mysql/mysql.conf.d/mysqld.cnf
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE stalker_db;"
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE USER 'stalker'@'%' IDENTIFIED BY '1';"
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'stalker'@'%' WITH GRANT OPTION;"
echo "sql_mode=''" >> /etc/mysql/mysql.conf.d/mysqld.cnf
echo "default_authentication_plugin=mysql_native_password" >> /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

# Install Ministra Portal
echo -e " \e[32mInstalling Ministra Portal $VERSION \e[0m"
sleep 3
cd /var/www/html/
wget $REPOSITORY/ministra-$VERSION.zip
unzip ministra-$VERSION.zip
rm -rf ministra-$VERSION.zip

# Configure Apache & Nginx
cd /etc/apache2/sites-enabled/
rm -rf *
wget $REPOSITORY/000-default.conf
cd /etc/apache2/
rm -rf ports.conf
wget $REPOSITORY/ports.conf
cd /etc/nginx/sites-available/
rm -rf default
wget $REPOSITORY/default
systemctl restart apache2 nginx

# Fix Smart Launcher Applications
mkdir -p /var/www/.npm
chmod 777 /var/www/.npm

cd /var/www/html/stalker_portal/server
wget -O custom.ini $REPOSITORY/custom.ini

# Ensure composer dependencies for deploy
cd /var/www/html/stalker_portal/deploy/composer
php composer.deploy.phar install --no-dev --no-suggest --no-interaction

# Install Phing
composer global require phing/phing
export PATH="$HOME/.config/composer/vendor/bin:$PATH"
echo 'export PATH="$HOME/.config/composer/vendor/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Build Ministra Portal
cd /var/www/html/stalker_portal/deploy
sed -i 's/php5enmod/phpenmod/g' build.xml
sed -i 's/php5dismod/phpdismod/g' build.xml
sed -i 's/command=/executable=/g' build.xml  # Fix Phing execTask error
~/.config/composer/vendor/bin/phing

# Output Completion Info
echo -e " \e[32mInstallation Complete!\e[0m"
echo -e " \e[0mDefault username: \e[32madmin\e[0m"
echo -e " \e[0mDefault password: \e[32m1\e[0m"
echo -e " \e[0mPortal WAN: \e[32mhttp://$(curl -s http://ipecho.net/plain)/stalker_portal\e[0m"
echo -e " \e[0mPortal LAN: \e[32mhttp://$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')/stalker_portal\e[0m"
echo -e " \e[0mMySQL User: \e[32mroot\e[0m"
echo -e " \e[0mMySQL Pass: \e[32m$MYSQL_ROOT_PASSWORD\e[0m"
echo -e " \e[0mTo change admin password, run the following in MySQL:\e[0m"
echo -e " \e[32mmysql -u root -p\e[0m"
echo -e " \e[32mUSE stalker_db;\e[0m"
echo -e " \e[32mUPDATE administrators SET pass=MD5('new_password_here') WHERE login='admin';\e[0m"
echo -e " \e[32mQUIT;\e[0m"
echo -e " \e[32m--------------------------------------------------------------------\e[0m"
