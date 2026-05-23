{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Hackage.MCP.Cache (
    CacheConfig (..),
    AppEnv (..),
    AppM,
    runAppM,
    initCache,
    fetchPackageModules,
    searchHoogle,
    lookupOrFetchHoogle,
    lookupOrFetchPackageModules,
    lookupOrFetchModuleDocs,
    fetchModuleDocs,
)
where

import Control.Concurrent.STM (TVar)
import Control.Monad.Reader (ReaderT, liftIO, runReaderT)
import qualified Data.Aeson as JSON
import Data.IORef (IORef)
import Data.Int (Int64)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Data.Time.Clock.POSIX (getPOSIXTime)
import Database.SQLite.Simple (Connection, Only (..), Query, execute, execute_, query)
import Hackage.MCP.Fetch (fetchHackageHtmlPage)
import Hackage.MCP.Hoogle (searchHoogle)
import Hackage.MCP.LocalHoogle (RegenState)
import Hackage.MCP.Parse (scrapeHackageDocPage, scrapeHackageModuleList)
import Hoogle (Database)

data CacheConfig = CacheConfig
    { cacheExpiryHours :: Int
    , dbConnection :: Connection
    }

data AppEnv = AppEnv
    { appCacheConfig :: Maybe CacheConfig
    , appLocalHoogleDb :: IORef (Maybe Database)
    , appLocalHoogleRegenState :: TVar RegenState
    }

type AppM = ReaderT AppEnv IO

runAppM :: AppEnv -> AppM a -> IO a
runAppM env action = runReaderT action env

initCache :: Connection -> IO ()
initCache conn = mapM_ (execute_ conn) createTableStatements
  where
    createTableStatements :: [Query]
    createTableStatements =
        [ "CREATE TABLE IF NOT EXISTS hoogle_cache (query TEXT PRIMARY KEY, response TEXT NOT NULL, created_at INTEGER NOT NULL)"
        , "CREATE TABLE IF NOT EXISTS package_modules_cache (package_name TEXT PRIMARY KEY, response TEXT NOT NULL, created_at INTEGER NOT NULL)"
        , "CREATE TABLE IF NOT EXISTS module_docs_cache (package_name TEXT NOT NULL, module_name TEXT NOT NULL, response TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (package_name, module_name))"
        ]

lookupOrFetchHoogle :: Connection -> CacheConfig -> Text -> AppM (Either Text Text)
lookupOrFetchHoogle conn cacheConfig cacheQuery = do
    cached <- liftIO $ lookupHoogleCache conn cacheConfig cacheQuery
    case cached of
        Just response -> pure $ Right response
        Nothing -> do
            fetched <- liftIO $ searchHoogle cacheQuery
            liftIO $ storeHoogleCache conn cacheQuery fetched
            pure fetched

lookupOrFetchPackageModules :: Connection -> CacheConfig -> Text -> AppM (Either Text Text)
lookupOrFetchPackageModules conn cacheConfig packageName = do
    cached <- liftIO $ lookupPackageModulesCache conn cacheConfig packageName
    case cached of
        Just response -> pure $ Right response
        Nothing -> do
            fetched <- liftIO $ fetchPackageModules packageName
            liftIO $ storePackageModulesCache conn packageName fetched
            pure fetched

lookupOrFetchModuleDocs :: Connection -> CacheConfig -> Text -> Text -> AppM (Either Text Text)
lookupOrFetchModuleDocs conn cacheConfig packageName moduleName = do
    cached <- liftIO $ lookupModuleDocsCache conn cacheConfig packageName moduleName
    case cached of
        Just response -> pure $ Right response
        Nothing -> do
            fetched <- liftIO $ fetchModuleDocs packageName moduleName
            liftIO $ storeModuleDocsCache conn packageName moduleName fetched
            pure fetched

fetchPackageModules :: Text -> IO (Either Text Text)
fetchPackageModules packageName = do
    let url = T.concat ["https://hackage.haskell.org/package/", packageName]
    htmlResult <- fetchHackageHtmlPage url
    case htmlResult of
        Left err -> pure $ Left err
        Right html -> do
            parseResult <- scrapeHackageModuleList html
            case parseResult of
                Left err -> pure $ Left err
                Right modules -> do
                    let moduleNames = map fst modules
                    pure $ Right $ TL.toStrict $ TLE.decodeUtf8 $ JSON.encode moduleNames

fetchModuleDocs :: Text -> Text -> IO (Either Text Text)
fetchModuleDocs packageName moduleName = do
    let normalizedModuleName = T.replace "." "-" moduleName
        url = T.concat ["https://hackage.haskell.org/package/", packageName, "/docs/", normalizedModuleName, ".html"]
    htmlResult <- fetchHackageHtmlPage url
    case htmlResult of
        Left err -> pure $ Left err
        Right html -> scrapeHackageDocPage html

lookupHoogleCache :: Connection -> CacheConfig -> Text -> IO (Maybe Text)
lookupHoogleCache conn CacheConfig{..} cacheQuery = do
    cleanupHoogleCache conn cacheExpiryHours
    rows <- query conn "SELECT response FROM hoogle_cache WHERE query = ?" (Only cacheQuery) :: IO [Only Text]
    pure $ responseFromSingleRow rows

lookupPackageModulesCache :: Connection -> CacheConfig -> Text -> IO (Maybe Text)
lookupPackageModulesCache conn CacheConfig{..} packageName = do
    cleanupPackageModulesCache conn cacheExpiryHours
    rows <- query conn "SELECT response FROM package_modules_cache WHERE package_name = ?" (Only packageName) :: IO [Only Text]
    pure $ responseFromSingleRow rows

lookupModuleDocsCache :: Connection -> CacheConfig -> Text -> Text -> IO (Maybe Text)
lookupModuleDocsCache conn CacheConfig{..} packageName moduleName = do
    cleanupModuleDocsCache conn cacheExpiryHours
    rows <- query conn "SELECT response FROM module_docs_cache WHERE package_name = ? AND module_name = ?" (packageName, moduleName) :: IO [Only Text]
    pure $ responseFromSingleRow rows

storeHoogleCache :: Connection -> Text -> Either Text Text -> IO ()
storeHoogleCache _ _ (Left _) = pure ()
storeHoogleCache conn cacheQuery (Right response) = do
    now <- currentUnixTime
    execute conn "INSERT OR REPLACE INTO hoogle_cache (query, response, created_at) VALUES (?, ?, ?)" (cacheQuery, response, now)

storePackageModulesCache :: Connection -> Text -> Either Text Text -> IO ()
storePackageModulesCache _ _ (Left _) = pure ()
storePackageModulesCache conn packageName (Right response) = do
    now <- currentUnixTime
    execute conn "INSERT OR REPLACE INTO package_modules_cache (package_name, response, created_at) VALUES (?, ?, ?)" (packageName, response, now)

storeModuleDocsCache :: Connection -> Text -> Text -> Either Text Text -> IO ()
storeModuleDocsCache _ _ _ (Left _) = pure ()
storeModuleDocsCache conn packageName moduleName (Right response) = do
    now <- currentUnixTime
    execute conn "INSERT OR REPLACE INTO module_docs_cache (package_name, module_name, response, created_at) VALUES (?, ?, ?, ?)" (packageName, moduleName, response, now)

cleanupHoogleCache :: Connection -> Int -> IO ()
cleanupHoogleCache conn cacheExpiryHours = do
    cutoff <- cacheCutoff cacheExpiryHours
    execute conn "DELETE FROM hoogle_cache WHERE created_at < ?" (Only cutoff)

cleanupPackageModulesCache :: Connection -> Int -> IO ()
cleanupPackageModulesCache conn cacheExpiryHours = do
    cutoff <- cacheCutoff cacheExpiryHours
    execute conn "DELETE FROM package_modules_cache WHERE created_at < ?" (Only cutoff)

cleanupModuleDocsCache :: Connection -> Int -> IO ()
cleanupModuleDocsCache conn cacheExpiryHours = do
    cutoff <- cacheCutoff cacheExpiryHours
    execute conn "DELETE FROM module_docs_cache WHERE created_at < ?" (Only cutoff)

cacheCutoff :: Int -> IO Int64
cacheCutoff cacheExpiryHours = do
    now <- currentUnixTime
    pure $ now - fromIntegral (cacheExpiryHours * 3600)

currentUnixTime :: IO Int64
currentUnixTime = floor <$> getPOSIXTime

responseFromSingleRow :: [Only Text] -> Maybe Text
responseFromSingleRow rows = case listToMaybe rows of
    Nothing -> Nothing
    Just (Only response) -> Just response
