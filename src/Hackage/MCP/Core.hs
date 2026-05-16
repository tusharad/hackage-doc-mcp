module Hackage.MCP.Core (runApp) where

import Data.Text (Text)
import Hackage.MCP.Tool (toolHandlers)
import MCP.Server
import Options.Applicative

data ConfigParams = ConfigParams
    { enableCache :: Bool
    , cacheExpiry :: Int
    }
    deriving (Eq, Show)

configParams :: Parser ConfigParams
configParams =
    ConfigParams
        <$> flag False True (long "enable_cache" <> short 'c' <> showDefault)
        <*> option auto (showDefault <> value 168 <> long "cache_expirey" <> short 'e')

customInstructions :: Text
customInstructions = "Use tools to search Hoogle, list package modules, and fetch concise Markdown docs for Haskell modules from Hackage. When passing module names to get_module_docs, convert them to hyphen-casing: for example, Data.List becomes Data-List."

runApp :: IO ()
runApp = do
    config <- execParser opts
    print config
    let mcpServerInfo =
            McpServerInfo
                { serverName = "hackage-doc"
                , serverVersion = "0.1.0"
                , serverInstructions = customInstructions
                }
    let mcpServerHandlers =
            McpServerHandlers
                { prompts = Nothing
                , resources = Nothing
                , tools = Just toolHandlers
                }
    runMcpServerStdio mcpServerInfo mcpServerHandlers
  where
    opts =
        info
            (configParams <**> helper)
            ( progDesc "MCP Server for Hackage"
                <> header "Hello from hackage-doc-mcp"
            )
