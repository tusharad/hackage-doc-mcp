FROM debian:trixie-slim AS build

RUN apt update && apt install build-essential curl libffi-dev libffi8 libgmp-dev libpq-dev \
    libgmp10 libncurses-dev libncurses6 libtinfo6 pkg-config zlib1g-dev -y \
     && rm -rf /var/lib/apt/lists/*

ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1
RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ENV PATH=${PATH}:/root/.ghcup/bin:/root/.local/bin

RUN ghcup install stack recommended --set

WORKDIR /app
COPY . .

RUN stack build --copy-bins --local-bin-path ./release --ghc-options="-O2"

FROM debian:trixie-slim AS runtime

RUN apt update && apt install libffi8 \
    libgmp10 ca-certificates -y \
     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/release/hackage-doc-mcp-exe .
RUN chmod +x ./hackage-doc-mcp-exe
CMD ["./hackage-doc-mcp-exe"]