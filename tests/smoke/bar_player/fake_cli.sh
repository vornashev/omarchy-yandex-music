#!/bin/sh
if [ "$1" = status ]; then
  printf '%s\n' '{"title":"Sample track","artist":"Sample artist","volume":25,"playing":false,"preferences":{}}'
else
  printf '%s\n' '{}'
fi
