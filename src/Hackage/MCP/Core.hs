module Hackage.MCP.Core (runApp, mcpServerInfo) where

import Control.Concurrent.STM (newTVarIO)
import Control.Exception (bracket)
import Data.IORef (newIORef, writeIORef)
import Data.Text (Text)
import Database.SQLite.Simple (close, open)
import Hackage.MCP.Cache (AppEnv (..), CacheConfig (..), initCache)
import Hackage.MCP.LocalHoogle (RegenState (..))
import Hackage.MCP.Tool (toolHandlers)
import Hoogle (defaultDatabaseLocation, withDatabase)
import MCP.Server
import Options.Applicative
import System.Directory (doesFileExist)

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
    cacheEnabledParser :: Parser Bool
    cacheEnabledParser =
        (\enableCacheFlag disableCacheFlag -> enableCacheFlag && not disableCacheFlag)
            <$> switch (long "enable-cache" <> short 'c' <> help "Enable SQLite-backed cache")
            <*> switch (long "disable-cache" <> help "Disable SQLite-backed cache")

customInstructions :: Text
customInstructions = "Use tools to search Hoogle, list package modules, and fetch concise Markdown docs for Haskell modules from Hackage. When passing module names to get_module_docs, convert them to hyphen-casing: for example, Data.List becomes Data-List. A local Hoogle database can be loaded for searching private/local dependencies. If searches miss local packages, call regenerate_local_hoogle with your project's ghcBinPath (find it with: nix-shell --run 'dirname $(which ghc-pkg)')."

cacheDatabasePath :: FilePath
cacheDatabasePath = "hackage-doc-cache.sqlite3"

mcpServerInfo :: McpServerInfo
mcpServerInfo =
    McpServerInfo
        { serverName = "hackage-doc"
        , serverVersion = "0.0.3.0"
        , serverInstructions = customInstructions
        }

runApp :: IO ()
runApp = do
    config <- execParser opts
    bracket (open cacheDatabasePath) close $ \baseConnection -> do
        initCache baseConnection
        localHoogleDbRef <- newIORef Nothing
        regenStateVar <- newTVarIO RegenIdle
        -- Try loading existing default Hoogle database if present
        defaultPath <- defaultDatabaseLocation
        defaultExists <- doesFileExist defaultPath
        let startServer :: IO ()
            startServer = do
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
                            , appLocalHoogleDb = localHoogleDbRef
                            , appLocalHoogleRegenState = regenStateVar
                            }
                    mcpServerHandlers =
                        McpServerHandlers
                            { prompts = Nothing
                            , resources = Nothing
                            , tools = Just (toolHandlers appEnv)
                            }
                runMcpServerStdio mcpServerInfo mcpServerHandlers
        if defaultExists
            then withDatabase defaultPath $ \database -> do
                writeIORef localHoogleDbRef (Just database)
                startServer
            else startServer
  where
    opts :: ParserInfo ConfigParams
    opts =
        info
            (configParams <**> helper)
            ( progDesc "MCP Server for Hackage"
                <> header "Hello from hackage-doc-mcp"
            )
