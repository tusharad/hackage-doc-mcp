FROM debian:trixie-slim AS build
ARG USE_PREBUILT=false
ARG TARGETPLATFORM

RUN apt update && apt install build-essential curl libffi-dev libffi8 libgmp-dev libpq-dev \
        libgmp10 libncurses-dev libncurses6 libtinfo6 pkg-config zlib1g-dev -y \
         && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# If a prebuilt binary is provided and the build is triggered with
# --build-arg USE_PREBUILT=true, look for a platform-specific binary
# named `release/hackage-doc-mcp-exe-<linux_arch>` (e.g. linux_amd64).
# If found, move it into place; otherwise fall back to building.
RUN if [ "$USE_PREBUILT" = "true" ]; then \
            arch="${TARGETPLATFORM//\//_}"; \
            if [ -f ./release/hackage-doc-mcp-exe-$arch ]; then \
                echo "Using prebuilt binary for $TARGETPLATFORM" && \
                mv ./release/hackage-doc-mcp-exe-$arch ./release/hackage-doc-mcp-exe; \
            else \
                echo "Prebuilt binary not found for $TARGETPLATFORM, compiling..." && \
                export BOOTSTRAP_HASKELL_NONINTERACTIVE=1 && \
                curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh && \
                export PATH=${PATH}:/root/.ghcup/bin:/root/.local/bin && \
                ghcup install stack recommended --set && \
                stack build --copy-bins --local-bin-path ./release --ghc-options=\"-O2\" ; \
            fi ; \
        else \
            export BOOTSTRAP_HASKELL_NONINTERACTIVE=1 && \
            curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh && \
            export PATH=${PATH}:/root/.ghcup/bin:/root/.local/bin && \
            ghcup install stack recommended --set && \
            stack build --copy-bins --local-bin-path ./release --ghc-options=\"-O2\" ; \
        fi

FROM debian:trixie-slim AS runtime

RUN apt update && apt install libffi8 \
    libgmp10 ca-certificates -y \
     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/release/hackage-doc-mcp-exe .
RUN chmod +x ./hackage-doc-mcp-exe
CMD ["./hackage-doc-mcp-exe", "-c"]
