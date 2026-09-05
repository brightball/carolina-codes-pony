FROM ghcr.io/ponylang/ponyc:release AS build
USER root
# ponyc:release is Alpine; musl binary must stay on Alpine at runtime.
RUN apk add --no-cache openssl-dev libpq-dev git ca-certificates
WORKDIR /src
COPY corral.json lock.json ./
COPY carolina ./carolina
COPY main.pony ./
RUN corral fetch \
 && mkdir -p /out \
 && corral run -- ponyc --path=. -Dopenssl_3.0.x --bin-name pony -o /out .

FROM alpine:3.24
RUN apk add --no-cache libssl3 libpq libatomic ca-certificates
COPY --from=build /out/pony /usr/local/bin/carolina-codes-pony
ENV PORT=8080
EXPOSE 8080
CMD ["/usr/local/bin/carolina-codes-pony"]
