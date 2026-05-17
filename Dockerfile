FROM debian:trixie-slim 

RUN apt update && apt install libffi8 \
    libgmp10 ca-certificates -y \
     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY ./release/hackage-doc-mcp-exe .
RUN chmod +x ./hackage-doc-mcp-exe

CMD ["./hackage-doc-mcp-exe", "-c"]
