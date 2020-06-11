#!/bin/bash

DOWNLOADER=
GITHUB_URL=https://github.com/AdrienPoupa/laradose
VERSION=1.0.0

install() {
  if [ -d ./docker ]; then
    fatal "Laradose is already installed"
  fi

	echo "Installing Laradose to the current directory..."

  copy_files

  generate_ssl_certificate

  configure

	echo "Laradose was installed successfully!"

	exit 0
}

copy_files() {
  verify_download curl || verify_download wget || fatal 'curl or wget are required for downloading files'
  verify_command unzip || fatal 'unzip is required for the installation script'

  echo "Downloading..."
	download laradose.zip ${GITHUB_URL}/archive/master.zip

  echo "Unzipping..."
	unzip -q laradose.zip -d laradose

  echo "Copying files..."
	cp -r ./laradose/laradose-master/docker ./docker
	cp ./laradose/laradose-master/docker-compose.yml ./
	cp ./laradose/laradose-master/laradose.sh ./laradose.sh

	cat ./laradose/laradose-master/.env >> ./.env
	cat ./laradose/laradose-master/.env >> ./.env.example

	rm -rf ./laradose
	rm ./laradose.zip
}

generate_ssl_certificate() {
  echo "Generating SSL certificate..."

  # Create private and public key
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ./docker/nginx/keys/server.key -out ./docker/nginx/keys/server.crt -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=localhost"

  # Create csr file
  openssl req -new -key ./docker/nginx/keys/server.key -out ./docker/nginx/keys/server.csr -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=localhost"
}

update() {
	echo "Be aware that this command will overwrite any modifications you made to Laradose configuration or Docker images."
	echo "Please make sure that your folder is versioned so you can revert to the previous state if needed."
	read -r -p "Press any key to continue..."
	echo "Updating Laradose..."
	copy_files
	exit 0
}

# Menu inspired by https://serverfault.com/a/298312
additional_containers_menu() {
    echo "Select the additional containers you want to enable:"
    for i in "${!options[@]}"; do
        printf "%d%s. %s\n" $((i+1)) "${choices[i]:-}" "${options[i]}"
    done
    if [[ "$msg" ]]; then echo "$msg"; fi
}

configure() {
  echo "Laradose configuration"

  options=("Redis" "Laravel Horizon" "Laravel Echo Server" "phpMyAdmin")
  folders=("redis" "horizon" "echo" "phpmyadmin")

  prompt="Type the container number (again to uncheck, ENTER when done): "
  while additional_containers_menu && read -rp "$prompt" num && [[ "$num" ]]; do
      [[ "$num" != *[![:digit:]]* ]] &&
      (( num > 0 && num <= ${#options[@]} )) ||
      { msg="Invalid option: $num"; continue; }
      ((num--)); msg="${options[num]} was ${choices[num]:+un}enabled"
      [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
  done

  compose_file_input="docker-compose.yml:"
  for i in "${!options[@]}"; do
      [[ "${choices[i]}" ]] && compose_file_input=$compose_file_input"/docker/${folders[i]}/docker-compose.override.yml":
  done

  # Remove last :
  compose_file_input=${compose_file_input%?}

  # Export the vars in .env into your shell:
  export "$(grep -E -v '^#' .env | xargs)"

  sed -i "s#COMPOSE_FILE=.*#COMPOSE_FILE=${compose_file_input}#" ./.env

  env_input "NGINX_HTTPS_PORT" "Nginx HTTPS port"

  env_input "NGINX_HTTP_PORT" "Nginx HTTP port"

  env_input "DB_PORT" "MySQL port"

  if [[ $compose_file_input == *"redis"* ]]; then
    env_input "REDIS_PORT" "Redis port"
  fi

  if [[ $compose_file_input == *"phpmyadmin"* ]]; then
      env_input "PHPMYADMIN_PORT" "phpMyAdmin port"
  fi

  env_input "PHP_VERSION" "PHP Version (7.2, 7.3, 7.4)"

  env_input "USER_ID" "Linux User ID for file permissions (current user: $(id -u))"

  env_input "GROUP_ID" "Linux Group ID for file permissions (current group: $(id -g))"

  env_input "MIX_MODE" "Mix mode can be one of: watch, hot, dev, prod"

  env_input "MIX_BROWSERSYNC" "Enable Browsersync (enabled or disabled)"

  echo "Configuration complete!"

  exit 0
}

env_input() {
    key=$1
    description=$2

    read -r -p "$description: [${!key}] " new_value

    if [ -n "$new_value" ]; then
        sed -i "s/${key}=.*/${key}=${new_value}/" ./.env
    fi
}

uninstall() {
	echo "Uninstalling Laradose..."

	rm -rf ./docker
	rm ./docker-compose.yml
	rm ./.env.laradose

	echo "Laradose was uninstalled successfully!"
	echo "You can now remove additional entries from your .env and .env.example files"

	exit 0
}

show_menus() {
	clear
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "             L A R A D O S E"
	echo
	echo "Author: Adrien Poupa"
	echo "Version: "${VERSION}
	echo "URL: "${GITHUB_URL}
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "1. Install"
	echo "2. Update"
	echo "3. Configure"
	echo "4. Uninstall"
	echo "0. Exit"
}

read_options() {
	local choice
	read -r -p "Enter choice [1 - 4] " choice
	case $choice in
		1) install ;;
		2) update ;;
		3) configure ;;
		4) uninstall ;;
		*) exit 0;;
	esac
}

# Credits https://raw.githubusercontent.com/rancher/k3s/master/install.sh
verify_download() {
    verify_command

    # Set verified executable as our downloader program and return success
    DOWNLOADER=$1
    return 0
}

# --- verify existence of a command executable ---
verify_command() {
    # Return failure if it doesn't exist or is no executable
    [ -x "$(command -v "$1")" ] || return 1

    return 0
}

download() {
    [ $# -eq 2 ] || fatal 'download needs exactly 2 arguments'

    case $DOWNLOADER in
        curl)
            curl -o "$1" -sfL "$2"
            ;;
        wget)
            wget -qO "$1" "$2"
            ;;
        *)
            fatal "Incorrect executable '$DOWNLOADER'"
            ;;
    esac

    # Abort if download command failed
    [ $? -eq 0 ] || fatal 'Download failed'
}

fatal() {
    echo '[ERROR]' "$@" >&2
    exit 1
}

while true
do
  verify_command docker || fatal 'Docker is required for Laradose'
  verify_command docker-compose || fatal 'docker-compose is required for Laradose'
  if ! [ -f ./.env ]; then
    fatal 'You must have a .env file'
  fi
	show_menus
	read_options
done