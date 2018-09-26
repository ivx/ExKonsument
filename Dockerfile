FROM elixir:1.7.3-slim

ENV DOCKERIZE_VERSION v0.6.1
ADD https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz /dockerize.tar.gz
RUN tar -C /usr/local/bin -xzvf dockerize.tar.gz

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
