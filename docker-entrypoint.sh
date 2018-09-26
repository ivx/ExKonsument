#!/bin/sh

set -e

if [ "$1" = test ] ; then
  mix format --check-formatted
  mix credo --strict
  mix test
fi
