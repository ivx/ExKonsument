#!/bin/sh

set -e

if [ "$1" = test ] ; then
  export MIX_ENV=test
  mix deps.get
  mix format --check-formatted
  mix credo --strict
  mix test
fi
