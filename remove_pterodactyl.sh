#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

echo "--------------------------------------------------------"
echo "WARNING: This will COMPLETEY REMOVE Pterodactyl Panel and Wings."
echo "This includes ALL server files, databases, and configurations."
echo "--------------------------------------------------------"
read -p "Are you sure you want to proceed? (y/N): " confirm

if [[ $confirm != [yY] ]]; then
    echo "Uninstallation cancelled."
    exit 1
fi

echo "Starting removal process..."

# --- Step 1: Stop and Remove Wings Daemon ---
echo "Removing Wings..."
systemctl stop wings
systemctl disable wings
rm -f /etc/systemd/system/wings.service
rm -f /usr/local/bin/wings
rm -rf /etc/pterodactyl
rm -rf /var/lib/pterodactyl # Deletes game data
systemctl daemon-reload

# --- Step 2: Remove the Pterodactyl Panel ---
echo "Removing Panel web files and Nginx config..."
rm -rf /var/www/pterodactyl
rm -f /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-available/pterodactyl.conf
systemctl reload nginx

# --- Step 3: Remove the Database ---
# Note: This assumes you are using the default 'panel' database name.
echo "Removing Database and Database User..."
read -sp "Enter MariaDB/MySQL Root Password: " DB_PASS
echo

mysql -u root -p"$DB_PASS" <<EOF
DROP DATABASE IF EXISTS panel;
DROP USER IF EXISTS 'pterodactyl'@'localhost';
DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

echo "--------------------------------------------------------"
echo "Success! Pterodactyl has been completely removed."
echo "--------------------------------------------------------"