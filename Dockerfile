FROM elixir:1.7.3-slim

RUN adduser --disabled-password --gecos '' test
USER test

RUN mix local.hex --force
RUN mix local.rebar --force

COPY . /code
WORKDIR /code
USER root
RUN chown -R test:test /code

USER test

ENV MIX_ENV test
RUN mix deps.get

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["run"]
