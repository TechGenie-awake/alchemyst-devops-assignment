#!/bin/bash
# Caller-worker VM boot script. Output logged to /var/log/startup.log on the VM.
exec > /var/log/startup.log 2>&1
set -euxo pipefail

# Wait for NAT egress to actually work before touching apt. apt-get update
# exits 0 even when every source fails (just prints W:), so probing apt
# directly isn't reliable. Probe a known-good HTTP endpoint instead.
for i in $(seq 1 60); do
  curl -fsS --max-time 5 http://archive.ubuntu.com/ubuntu/ > /dev/null && break
  sleep 5
done
apt-get update
apt-get install -y docker.io git
systemctl enable --now docker

rm -rf /opt/app
git clone --branch ${repo_branch} ${repo_url} /opt/app

cd /opt/app/quickstart/workers/caller-worker
docker build -t caller-worker .
docker rm -f caller-worker 2>/dev/null || true
docker run -d --restart unless-stopped --name caller-worker \
  -e III_URL=ws://${engine_ip}:49134 \
  caller-worker

echo "caller-worker startup complete"
