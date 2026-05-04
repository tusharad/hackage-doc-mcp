# hackage-doc-mcp

hackage-doc is MCP server written entirely in Haskell to support AI agents access the latest haddock documentation of Haskell packages.

Features include:

1. hoogle search 
2. read documentation page of a particular module of packges.
3. list all modules of a package.

supports only http transport.

## Screencaptures

## Quickstart

You need docker installed.

## Pull the latest docker image

docker pull _

## Run docker

```
docker run -p 7000:7000 tusharKnight8/hackage-doc-mcp
```

## VS Code configuration

Add this in your `mcp.json`

```json
{
  "mcpServers": {
    "hackage-doc": {
      "type": "http",
      "url": "http://localhost:7000/mcp",
      "headers": {
        "MCP-Protocol-Version": "2025-11-25"
      }
    }
  }
}
```

## MCP Server tools

Tool name:
1. search_hoogle: takes a query and returns the hoogle result
2. list_package_modules: takes a package name and returns list of modules
3. get_module_docs: takes a package name and module name and returns module documentation

## Roadmap

1. Clean module documentation markdown structure.
2. In memory cache

## Special thanks

- [mcp-server](https://github.com/drshade/haskell-mcp-server)