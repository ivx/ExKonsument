FROM elixir:1.7.3-slim

RUN adduser --disabled-password --gecos '' test
USER test

RUN mix local.hex --force
RUN mix local.rebar --force

COPY --chown=test:test . /code
WORKDIR /code

ENV MIX_ENV test
RUN mix deps.get
RUN mix compile

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["run"]
