#!/bin/bash
# The agent's explicit restart verb for ChannelForge's operator frontend (apps/web). It's a
# static Vite build served by nginx, not its own long-running process — "restart" means
# rebuilding dist/ and asking nginx to reload so it picks up the new static assets.
set -euo pipefail
cd /web
npm run build
supervisorctl -c /etc/supervisor/supervisord.conf restart nginx
