module Hackage.MCP.Core (runApp) where

import MCP.Server
import Data.Text (Text)
import Hackage.MCP.Tool (toolHandlers)

customInstructions :: Text
customInstructions = undefined

runApp :: IO ()
runApp = do 
    putStrLn "Hello from MCP"
    let httpConfig = HttpConfig {
        httpPort = 7000
      , httpHost = "0.0.0.0"
      , httpEndpoint = "/mcp"
      , httpVerbose = True
    }
    let mcpServerInfo = McpServerInfo {
        serverName = "hackage-doc"
      , serverVersion = "0.1.0"
      , serverInstructions = customInstructions
    }
    let mcpServerHandlers = McpServerHandlers {
        prompts = Nothing
      , resources = Nothing
      , tools = Just toolHandlers
    }
    runMcpServerHttpWithConfig httpConfig mcpServerInfo mcpServerHandlers
