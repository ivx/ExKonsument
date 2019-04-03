FROM elixir:1.8.0-alpine
WORKDIR /code
ADD . .
ENTRYPOINT ["./docker-entrypoint.sh"]
