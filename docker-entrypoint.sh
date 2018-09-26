#!/bin/bash

set -e

RABBITMQ_TCP="tcp://${RABBITMQ_URL#amqp:*@}"
dockerize -wait "$RABBITMQ_TCP" -timeout 20s

if [ "$1" = test ] ; then
  mix format --check-formatted
  mix credo --strict
  mix test
fi
