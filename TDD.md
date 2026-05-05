# Technical Design Document: Hackage-MCP

## 1. Overview
The Hackage-MCP server acts as a bridge between AI Agents (via the Model Context Protocol) and the Haskell ecosystem. 
It provides tools to search Hoogle, list package modules, and read detailed, LLM-optimized documentation scraped 
directly from Hackage.

## 2. Architecture & Technology Stack
*   **Language:** Haskell
*   **Build System:** Stack
*   **License:** MIT
*   **Core Libraries:**
    *   `mcp-server`: Foundation for the MCP protocol and tool registration.
    *   `http-conduit`: Lightweight HTTP fetching with built-in TLS handling.
    *   `scalpel`: DOM traversal and HTML scraping.
    *   `aeson`: JSON parsing for the Hoogle API and MCP responses.
*   **Deployment:** Docker 

## 3. Module Design
The project will be structured into distinct modules to separate network I/O, parsing logic, and the MCP interface.

*   **`Hackage.MCP.Core`**: The entry point. 
        Initializes the `mcp-server`, defines tool schemas, and 
        routes incoming MCP requests to the underlying functional handlers.
*   **`Hackage.MCP.Tool`**:
    * Implementation of ToolListHandler and ToolCallHandler.
*   **`Hackage.MCP.Hoogle`**: 
    *   Handles network requests to the Hoogle JSON API.
    *   Parses the JSON response into internal Haskell data types.
*   **`Hackage.MCP.Fetch`**:
    *   Responsible for network I/O to `hackage.haskell.org`.
    *   Fetches package index pages and specific module documentation pages.
*   **`Hackage.MCP.Parse`**:
    *   Contains `scalpel` scrapers.
    *   Extracts the module list from a package front page.
    *   Extracts signatures, types, and documentation blocks from Haddock-generated HTML.
    *   Transforms DOM nodes into clean, LLM-readable Markdown.

## 4. Exposed MCP Tools
The server will expose three primary tools to the AI Agent:

### Tool 1: `search_hoogle`
*   **Input:** `query` (String) - The type signature, module, or package name to search.
*   **Output:** A JSON array containing objects with `docs`, `name`, `url`, `package`, and `module`.
*   **Description:** Queries the external Hoogle API and returns structured search results.

### Tool 2: `list_package_modules`
*   **Input:** `package_name` (String) - The exact name of the Hackage package.
*   **Output:** A JSON array of strings representing available modules (e.g., `["Data.Text", "Data.Text.IO"]`).
*   **Description:** Scrapes the Hackage package front page to retrieve all exposed modules. Yields a clear error if the package is invalid or not found.

### Tool 3: `get_module_docs`
*   **Input:** `package_name` (String), `module_name` (String).
*   **Output:** Markdown-formatted string containing function signatures, types, and associated documentation.
*   **Description:** Scrapes the specific Haddock page for the given module, filtering out HTML boilerplate and returning high-density information.

## 5. Acceptance Criteria & Test Plan

### Unit & Integration Tests
*   **Hoogle API Integration:**
    *   *Input:* `query = "langchain"`
    *   *Expected:* Response includes package `langchain-hs`.
*   **Package Module Listing:**
    *   *Input:* `package_name = "langchain-hs"`
    *   *Expected:* Returns list containing `Langchain.Agent.Core`, `Langchain.Agent.Executor`, `Langchain.Agent.Middleware`, `Langchain.Agent.ReAct`.
    *   *Failure State:* Input `invalid-package-123` correctly returns an actionable error string, not a generic HTTP 404 crash.
*   **Module Documentation Scraping:**
    *   *Input:* `package_name = "langchain-hs"`, `module_name = "Langchain.Agent.Core"`
    *   *Expected:* Successfully parses and returns function signatures and documentation text without raw HTML tags.
