FROM elixir:1.8.1-alpine
WORKDIR /code
ADD . .
ENTRYPOINT ["./docker-entrypoint.sh"]
