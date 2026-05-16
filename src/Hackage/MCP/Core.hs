module Hackage.MCP.Core (runApp, mcpServerInfo) where

import Control.Exception (bracket)
import Data.Text (Text)
import Database.SQLite.Simple (close, open)
import Hackage.MCP.Cache (AppEnv (..), CacheConfig (..), initCache)
import Hackage.MCP.Tool (toolHandlers)
import MCP.Server
import Options.Applicative

data ConfigParams = ConfigParams
    { enableCache :: Bool
    , configCacheExpiryHours :: Int
    }
    deriving (Eq, Show)

configParams :: Parser ConfigParams
configParams =
    ConfigParams
        <$> cacheEnabledParser
        <*> option auto (showDefault <> value 168 <> long "cache-expiry-hours" <> short 'e' <> help "Cache TTL in hours")
  where
    cacheEnabledParser =
        (\enableCacheFlag disableCacheFlag -> enableCacheFlag && not disableCacheFlag)
            <$> switch (long "enable-cache" <> short 'c' <> help "Enable SQLite-backed cache")
            <*> switch (long "disable-cache" <> help "Disable SQLite-backed cache")

customInstructions :: Text
customInstructions = "Use tools to search Hoogle, list package modules, and fetch concise Markdown docs for Haskell modules from Hackage. When passing module names to get_module_docs, convert them to hyphen-casing: for example, Data.List becomes Data-List."

cacheDatabasePath :: FilePath
cacheDatabasePath = "hackage-doc-cache.sqlite3"

runApp :: IO ()
runApp = do
    config <- execParser opts
    bracket (open cacheDatabasePath) close $ \baseConnection -> do
        initCache baseConnection
        let appEnv =
                AppEnv
                    { appCacheConfig =
                        if enableCache config
                            then
                                Just $
                                    CacheConfig
                                        { cacheExpiryHours = configCacheExpiryHours config
                                        , dbConnection = baseConnection
                                        }
                            else Nothing
                    }
            mcpServerInfo =
                McpServerInfo
                    { serverName = "hackage-doc"
                    , serverVersion = "0.0.2.0"
                    , serverInstructions = customInstructions
                    }
            mcpServerHandlers =
                McpServerHandlers
                    { prompts = Nothing
                    , resources = Nothing
                    , tools = Just (toolHandlers appEnv)
                    }
        runMcpServerStdio mcpServerInfo mcpServerHandlers
  where
    opts =
        info
            (configParams <**> helper)
            ( progDesc "MCP Server for Hackage"
                <> header "Hello from hackage-doc-mcp"
            )
