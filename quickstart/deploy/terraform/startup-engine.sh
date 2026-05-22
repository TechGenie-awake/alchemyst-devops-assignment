#!/bin/bash
# Engine VM boot script. Output logged to /var/log/startup.log on the VM.
exec > /var/log/startup.log 2>&1
set -euxo pipefail

apt-get update
apt-get install -y docker.io git
systemctl enable --now docker

rm -rf /opt/app
git clone --branch ${repo_branch} ${repo_url} /opt/app

cd /opt/app/quickstart/deploy/engine
docker build -t iii-engine .
docker rm -f engine 2>/dev/null || true
docker run -d --restart unless-stopped --name engine \
  -p 3111:3111 -p 49134:49134 \
  iii-engine

echo "engine startup complete"
