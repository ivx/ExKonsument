FROM elixir:1.8.2-alpine
WORKDIR /code
ADD . .
ENTRYPOINT ["./docker-entrypoint.sh"]
