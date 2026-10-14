#!/usr/bin/env bash
# Deploys the site to the server behind macwand.dev and checks it's live.
set -euo pipefail

HOST="${HOST:-root@137.184.52.244}"
DIR="$(cd "$(dirname "$0")" && pwd)"

rsync -az --delete --exclude '_*.html' --exclude .DS_Store "$DIR/" "$HOST:/opt/macwand-site/"
ssh "$HOST" 'cd /opt/macwand-site && docker compose up -d --build'
curl -fsS https://macwand.dev/ | grep -q '<h1 id="hero-title">MacWand</h1>' && echo "macwand.dev is live"
