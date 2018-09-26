#!/bin/sh

set -e

mix local.hex --force
mix local.rebar --force

if [ "$1" = test ] ; then
  export MIX_ENV=test
  mix deps.get
  mix format --check-formatted
  mix credo --strict
  mix test
fi
