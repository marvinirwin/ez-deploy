#!/bin/bash
# This script deploys a Dockerized web application.
# It installs necessary dependencies, clones the repository, builds and runs the Docker image,
# and sets up Nginx and SSL if needed.
#
# Usage:
# ./deploy.sh <github_repo> [domain_name]
# Example:
# ./deploy.sh https://github.com/user/repo.git example.com
#
# If you don't want to set up Nginx and SSL, use the --no-webserver option:
# ./deploy.sh --no-webserver https://github.com/user/repo.git

set -e

copy_to_clipboard() {
  echo -n "$1"
}

print_and_copy() {
  echo "$1"
  copy_to_clipboard "$1"
}

# Function to find an open port
find_open_port() {
  while :; do
    PORT="$(shuf -i 2000-65000 -n 1)"
    ss -lpn | grep -q ":$PORT "
    if [[ $? -eq 1 ]]; then
      break
    fi
  done
  echo $PORT
}

NO_WEBSERVER=0
if [[ $1 == "--no-webserver" ]]; then
  NO_WEBSERVER=1
  shift
fi

if [[ "$EUID" -ne 0 ]]; then
  print_and_copy "Please run as root"
  exit 1
fi

if [[ $NO_WEBSERVER -eq 1 && "$#" -ne 1 ]] || [[ $NO_WEBSERVER -eq 0 && "$#" -ne 2 ]]; then
  print_and_copy "Usage: $0 [--no-webserver] <github_repo> [domain_name]"
  exit 1
fi

GITHUB_REPO=$1
FOLDER_NAME=$(basename "$GITHUB_REPO" .git)
FOLDER_NAME=${FOLDER_NAME//\//_}
if [[ $NO_WEBSERVER -eq 0 ]]; then
  DOMAIN_NAME=$2
  FOLDER_NAME=$2
  FOLDER_NAME=${FOLDER_NAME//\//_}
  # Check if the domain name is a subdomain of marvinirwin.com
  IS_SUBDOMAIN=0
  if [[ $DOMAIN_NAME == *".marvinirwin.com" ]]; then
    IS_SUBDOMAIN=1
    SUBDOMAIN_NAME=$(echo $DOMAIN_NAME | cut -d'.' -f1)
    DOMAIN_NAME="marvinirwin.com"
    FOLDER_NAME=$SUBDOMAIN_NAME
  fi
  NGINX_REDIRECT_SOURCE=$DOMAIN_NAME
  if [[ $IS_SUBDOMAIN -eq 1 ]]; then
    NGINX_REDIRECT_SOURCE=$SUBDOMAIN_NAME.$DOMAIN_NAME
  fi
  # Check if the DOMAIN_OWNER_EMAIL environment variable is set
  if [[ -z "${DOMAIN_OWNER_EMAIL}" ]]; then
    print_and_copy "Please set the DOMAIN_OWNER_EMAIL environment variable"
    exit 1
  fi
  EMAIL=$DOMAIN_OWNER_EMAIL
else
  EMAIL='marvin@marvinirwin.com' # replace with your email address
fi

print_and_copy "$NGINX_REDIRECT_SOURCE"

print_and_copy "Updating apt-get"
apt-get update || {
  print_and_copy "Failed to update apt-get"
  exit 1
}
print_and_copy "apt-get updated successfully"

# Install Docker
if ! command -v docker &>/dev/null; then
  print_and_copy "Installing Docker"
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common || {
    print_and_copy "Failed to install Docker dependencies"
    exit 1
  }
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - || {
    print_and_copy "Failed to add Docker gpg key"
    exit 1
  }
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || {
    print_and_copy "Failed to add Docker repository"
    exit 1
  }
  apt-get update || {
    print_and_copy "Failed to update apt-get"
    exit 1
  }
  apt-get install -y docker-ce || {
    print_and_copy "Failed to install Docker"
    exit 1
  }
  print_and_copy "Docker installed successfully"
fi

# Install Docker Compose
if ! command -v docker-compose &>/dev/null; then
  print_and_copy "Installing Docker Compose"
  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || {
    print_and_copy "Failed to download Docker Compose"
    exit 1
  }
  chmod +x /usr/local/bin/docker-compose || {
    print_and_copy "Failed to make Docker Compose executable"
    exit 1
  }
  print_and_copy "Docker Compose installed successfully"
fi

# Install Nginx
if ! command -v nginx &>/dev/null; then
  print_and_copy "Installing Nginx"
  apt-get install -y nginx || {
    print_and_copy "Failed to install Nginx"
    exit 1
  }
  print_and_copy "Nginx installed successfully"
fi

# Install Certbot
if ! command -v certbot &>/dev/null; then
  print_and_copy "Installing Certbot"
  apt-get install -y certbot python3-certbot-nginx || {
    print_and_copy "Failed to install Certbot"
    exit 1
  }
  print_and_copy "Certbot installed successfully"
fi

# Clone the repository or pull the latest changes
if [ -d "/opt/$FOLDER_NAME" ]; then
  print_and_copy "Pulling the latest changes from the repository"
  cd /opt/$FOLDER_NAME
  OLD_COMMIT=$(git rev-parse HEAD)
  git pull || {
    print_and_copy "Failed to pull the latest changes from the repository"
    exit 1
  }
  NEW_COMMIT=$(git rev-parse HEAD)
  print_and_copy "Pulled the latest changes from the repository successfully"
else
  print_and_copy "Cloning the repository"
  git clone "$GITHUB_REPO" /opt/$FOLDER_NAME || {
    print_and_copy "Failed to clone the repository"
    exit 1
  }
  cd /opt/$FOLDER_NAME
  OLD_COMMIT=""
  NEW_COMMIT=$(git rev-parse HEAD)
  print_and_copy "Cloned the repository successfully"
fi

if [ ! -f ".env" ]; then
  print_and_copy "No .env file found in the directory. Opening vim to create one."
  vim .env
fi
# Find an open port
OPEN_PORT=$(find_open_port)
print_and_copy "Found open port: $OPEN_PORT"

# Build and run the Docker image if there are new commits
print_and_copy "Building and running the Docker image"
docker build -t "$FOLDER_NAME-image" . || {
  print_and_copy "Failed to build the Docker image"
  exit 1
}

# Stop and remove the Docker container if it's already running
docker stop "$FOLDER_NAME-container" || true
docker rm "$FOLDER_NAME-container" || true

# Start the Docker container with a health check
if [[ $NO_WEBSERVER -eq 0 ]]; then
  # With health check
  docker run --network=clone-connection -d --env-file .env --name "$FOLDER_NAME-container" -p "$OPEN_PORT:80" -e PORT=80 --health-cmd='curl -f http://localhost:80 || exit 1' "$FOLDER_NAME-image" || {
    print_and_copy "Failed to run the Docker container"
    exit 1
  }
else
  # Without health check
  docker run --network=clone-connection -d --env-file .env --name "$FOLDER_NAME-container" -p "$OPEN_PORT:80" -e PORT=80 "$FOLDER_NAME-image" || {
    print_and_copy "Failed to run the Docker container"
    exit 1
  }
fi
print_and_copy "Docker image built and running successfully"

# Wait for the health check to pass while printing the Docker logs
print_and_copy "Waiting for the health check to pass while printing the Docker logs"

if [[ $NO_WEBSERVER -eq 0 ]]; then
  docker logs -f "$FOLDER_NAME-container" &
  while [ "$(docker inspect -f {{.State.Health.Status}} $FOLDER_NAME-container)" != "healthy" ]; do
    sleep 1
  done
  kill %1
  sleep 5
else
  docker logs -f "$FOLDER_NAME-container" &
    sleep 5
  kill %1
fi

if [[ $NO_WEBSERVER -eq 0 ]]; then
  # Nginx configuration
  print_and_copy "Configuring Nginx"
  cat <<EOF >/etc/nginx/conf.d/$NGINX_REDIRECT_SOURCE.conf
server {
    listen 80;
    server_name $NGINX_REDIRECT_SOURCE;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $NGINX_REDIRECT_SOURCE;

    ssl_certificate /etc/letsencrypt/live/$NGINX_REDIRECT_SOURCE/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$NGINX_REDIRECT_SOURCE/privkey.pem;

    location / {
        proxy_pass http://localhost:$OPEN_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  print_and_copy "Nginx configured successfully"

# Get the SSL certificate
print_and_copy "Getting the SSL certificate"
if ! [ -d "/etc/letsencrypt/live/$NGINX_REDIRECT_SOURCE" ]; then
  certbot --nginx -d "$NGINX_REDIRECT_SOURCE" --non-interactive --agree-tos --email "$EMAIL" || {
    print_and_copy "Failed to get the SSL certificate"
    exit 1
  }
fi
print_and_copy "SSL certificate obtained successfully"



  # Reload Nginx
  print_and_copy "Reloading Nginx"
  systemctl reload nginx || {
    print_and_copy "Failed to reload Nginx"
    exit 1
  }
  print_and_copy "Nginx reloaded successfully"
fi

