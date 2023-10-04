# EZ-Deploy

This is a script for deploying Dockerized web applications. It automates the process of installing necessary dependencies, cloning the repository, building and running the Docker image, and setting up Nginx and SSL if needed. The script can be run any time you need to deploy a new version of your application from the git repository.

## Quick Start

1. Clone this repository: `git clone https://github.com/user/ez-deploy.git`
2. Navigate to the cloned directory: `cd ez-deploy`
3. Run the script with your GitHub repository and domain name: `./deploy.sh https://github.com/yourusername/yourrepo.git yourdomain.com`

## Usage

```bash
# To deploy a web application with Nginx and SSL setup:
./deploy.sh <github_repo> [domain_name]

# To deploy a web application without Nginx and SSL setup:
./deploy.sh --no-webserver <github_repo>
```

Replace `<github_repo>` with your GitHub repository URL and `[domain_name]` with your domain name. The `--no-webserver` option can be used if you do not want to set up Nginx and SSL.

Example:
```bash
# With Nginx and SSL:
./deploy.sh https://github.com/user/repo.git example.com

# Without Nginx and SSL:
./deploy.sh --no-webserver https://github.com/user/repo.git
```

## Features

- Automatic installation of dependencies (Docker, Docker Compose, Nginx, Certbot)
- Cloning of your GitHub repository
- Building and running of your Docker image
- Optional setup of Nginx and SSL
