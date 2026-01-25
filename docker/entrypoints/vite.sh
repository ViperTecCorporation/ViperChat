#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

if [ ! -d /app/node_modules ]; then
  pnpm install
fi

echo "Ready to run Vite development server."

exec "$@"
