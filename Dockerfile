FROM elixir:1.7.3-alpine

RUN mix local.hex --force
RUN mix local.rebar --force

COPY . /code
WORKDIR /code

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["run"]
