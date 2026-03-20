#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

# Install any missing gems before starting the dev server.
bundle install

BUNDLE="bundle check"

until $BUNDLE
do
  sleep 2
done

if [ ! -d /app/node_modules ]; then
  pnpm install
fi

echo "Ready to run Vite development server."

exec "$@"
