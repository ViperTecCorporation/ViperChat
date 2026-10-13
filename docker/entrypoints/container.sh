#!/bin/sh

set -e

# Rails checks its PID before loading config/puma.rb. A crashed container may
# leave PID 1 behind; at this point PID 1 belongs to this entrypoint, not Puma.
# Do not remove a web PID when starting a worker or a maintenance command.
case "$*" in
  "bundle exec rails s"|"bundle exec rails s "*|\
  "bundle exec rails server"|"bundle exec rails server "*|\
  "rails s"|"rails s "*|"rails server"|"rails server "*|\
  "bin/rails s"|"bin/rails s "*|"bin/rails server"|"bin/rails server "*|\
  "bundle exec puma"|"bundle exec puma "*|"puma"|"puma "*)
    rm -f -- /app/tmp/pids/server.pid /tmp/chatwoot-server.pid
    ;;
esac

# Keep the server as PID 1 so Docker signals reach it directly.
exec "$@"
