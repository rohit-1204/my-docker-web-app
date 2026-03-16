#!/usr/bin/env bash
set -euo pipefail

############################################
# Config - change these as per your needs
############################################

# Git repo URL (HTTPS or SSH)
REPO_URL="${REPO_URL:-https://github.com/<username>/<repo>.git}"

# Local folder name for repo
APP_DIR="${APP_DIR:-my-docker-web-app}"

# Docker image name & tag
IMAGE_NAME="${IMAGE_NAME:-my-html-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Container name
CONTAINER_NAME="${CONTAINER_NAME:-htmlapp}"

# Host port to expose (Jenkins uses 8080, so default 8081)
HOST_PORT="${HOST_PORT:-8081}"

# Container port (nginx listens on 80 inside container)
CONTAINER_PORT="${CONTAINER_PORT:-80}"

############################################
# Helpers
############################################
info(){ echo -e "\n✅ $*"; }
warn(){ echo -e "\n⚠️  $*"; }
err(){ echo -e "\n❌ $*" >&2; }

############################################
# Pre-checks
############################################
command -v git >/dev/null 2>&1 || { err "git not installed. Install git first."; exit 1; }
command -v docker >/dev/null 2>&1 || { err "docker not installed. Install docker first."; exit 1; }

# Ensure docker daemon is running
if ! sudo systemctl is-active --quiet docker; then
  info "Starting Docker service..."
  sudo systemctl start docker
  sudo systemctl enable docker >/dev/null 2>&1 || true
fi

############################################
# Clone or pull repo
############################################
if [ -d "$APP_DIR/.git" ]; then
  info "Repo exists. Pulling latest code in: $APP_DIR"
  cd "$APP_DIR"
  git pull
else
  info "Cloning repo into: $APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

############################################
# Ensure Dockerfile exists (create if missing)
############################################
if [ ! -f Dockerfile ]; then
  warn "Dockerfile not found in repo. Creating a default Nginx Dockerfile..."
  cat > Dockerfile <<'DOCKER'
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
DOCKER
fi

############################################
# Build image
############################################
info "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

############################################
# Stop & remove old container if exists
############################################
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  warn "Removing existing container: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

############################################
# Port check (avoid bind address in use)
############################################
if sudo ss -ltnp 2>/dev/null | grep -q ":${HOST_PORT} "; then
  warn "Port ${HOST_PORT} already in use. Choose another port like 8090."
  warn "Example: HOST_PORT=8090 ./deploy_html_docker.sh"
  exit 1
fi

############################################
# Run container
############################################
info "Running container ${CONTAINER_NAME} on port ${HOST_PORT} -> ${CONTAINER_PORT}"
docker run -d --name "${CONTAINER_NAME}" -p "${HOST_PORT}:${CONTAINER_PORT}" "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null

############################################
# Show status
############################################
info "Container status:"
docker ps --filter "name=${CONTAINER_NAME}"

PUBLIC_IP="$(curl -s http://checkip.amazonaws.com || true)"
if [ -n "${PUBLIC_IP}" ]; then
  info "Open in browser: http://${PUBLIC_IP}:${HOST_PORT}"
else
  info "Open in browser: http://<EC2_PUBLIC_IP>:${HOST_PORT}"
fi

info "Done ✅"
