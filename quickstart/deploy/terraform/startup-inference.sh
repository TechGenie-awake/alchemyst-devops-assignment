#!/bin/bash
# Inference-worker VM boot script. Output logged to /var/log/startup.log on the VM.
exec > /var/log/startup.log 2>&1
set -euxo pipefail

apt-get update
apt-get install -y docker.io git
systemctl enable --now docker

rm -rf /opt/app
git clone --branch ${repo_branch} ${repo_url} /opt/app

cd /opt/app/quickstart/workers/inference-worker
docker build -t inference-worker .
docker rm -f inference-worker 2>/dev/null || true
docker run -d --restart unless-stopped --name inference-worker \
  -e III_URL=ws://${engine_ip}:49134 \
  inference-worker

echo "inference-worker startup complete"
