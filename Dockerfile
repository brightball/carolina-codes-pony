FROM ghcr.io/ponylang/ponyc:release AS build
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends libssl-dev libpq-dev git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY corral.json lock.json ./
COPY carolina ./carolina
COPY main.pony ./
RUN corral fetch \
 && mkdir -p /out \
 && corral run -- ponyc --path=. -Dopenssl_3.0.x -o /out .

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libssl3 libpq5 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/pony /usr/local/bin/carolina-codes-pony
ENV PORT=8080
EXPOSE 8080
CMD ["/usr/local/bin/carolina-codes-pony"]
