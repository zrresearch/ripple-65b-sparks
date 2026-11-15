#!/usr/bin/env bash
docker logs ripple-nvfp4 > $HOME/ripple-nvfp4/logs/serve-$(date +%Y%m%d-%H%M%S).log 2>&1 || true
docker rm -f ripple-nvfp4 >/dev/null 2>&1 || true
