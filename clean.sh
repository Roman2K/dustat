#!/usr/bin/env bash
set -eo pipefail

# docker rm `docker ps -f 'status=exited' -q`
# docker volume prune -f
# docker image prune -f

docker run -v services2_ytdump-meta:/meta bash -c 'find /meta/* -type f -not -name "*.skip" -delete'

cd $HOME/code/services2/docker-compose
./run config --volume \
  | xargs -L1 -I{} docker run --rm -v "docker-compose_{}:/vol" bash -c '
      find /vol -name "*.log" -print0 \
        | xargs -0 -I{} bash -c "
            echo -n truncating \"{}\" && truncate -s0 \"{}\" && echo \" OK\"
          "
    '
