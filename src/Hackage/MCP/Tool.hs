module Hackage.MCP.Tool (toolHandlers) where

import Control.Monad.Reader (ask, liftIO)
import Hackage.MCP.Cache (
    AppEnv (..),
    AppM,
    CacheConfig (..),
    fetchModuleDocs,
    fetchPackageModules,
    lookupOrFetchHoogle,
    lookupOrFetchModuleDocs,
    lookupOrFetchPackageModules,
    runAppM,
    searchHoogle,
 )
import Hackage.MCP.LocalHoogle (
    localHoogleStatus,
    regenerateLocalHoogle,
    reloadLocalHoogle,
    searchLocalHoogle,
 )
import MCP.Server.Types

toolList :: IO [ToolDefinition]
toolList =
    return
        [ ToolDefinition
            { toolDefinitionName = "search_hoogle"
            , toolDefinitionDescription = "Search Hoogle for identifiers, types, or packages. Prefers local Hoogle database when available, falls back to web API."
            , toolDefinitionInputSchema =
                InputSchemaDefinitionObject
                    { properties =
                        [
                            ( "query"
                            , InputSchemaDefinitionProperty
                                { propertyType = "string"
                                , propertyDescription = "Hoogle search query"
                                }
                            )
                        ]
                    , required = ["query"]
                    }
            , toolDefinitionTitle = Just "Search Hoogle"
            }
        , ToolDefinition
            { toolDefinitionName = "list_package_modules"
            , toolDefinitionDescription = "List exposed modules in a Hackage package."
            , toolDefinitionInputSchema =
                InputSchemaDefinitionObject
                    { properties =
                        [
                            ( "package_name"
                            , InputSchemaDefinitionProperty
                                { propertyType = "string"
                                , propertyDescription = "Exact Hackage package name"
                                }
                            )
                        ]
                    , required = ["package_name"]
                    }
            , toolDefinitionTitle = Just "List Package Modules"
            }
        , ToolDefinition
            { toolDefinitionName = "get_module_docs"
            , toolDefinitionDescription = "Fetch LLM-friendly Markdown docs for a module in a package."
            , toolDefinitionInputSchema =
                InputSchemaDefinitionObject
                    { properties =
                        [
                            ( "package_name"
                            , InputSchemaDefinitionProperty
                                { propertyType = "string"
                                , propertyDescription = "Exact Hackage package name"
                                }
                            )
                        ,
                            ( "module_name"
                            , InputSchemaDefinitionProperty
                                { propertyType = "string"
                                , propertyDescription = "Fully-qualified module name in hyphen-casing form e.g Data-List (not Data.List)"
                                }
                            )
                        ]
                    , required = ["package_name", "module_name"]
                    }
            , toolDefinitionTitle = Just "Get Module Docs"
            }
        , ToolDefinition
            { toolDefinitionName = "regenerate_local_hoogle"
            , toolDefinitionDescription = "Regenerate the local Hoogle database asynchronously from the GHC package DB. Returns immediately -- use local_hoogle_status to poll progress. Requires ghcBinPath so ghc-pkg can be found."
            , toolDefinitionInputSchema =
                InputSchemaDefinitionObject
                    { properties =
                        [
                            ( "ghcBinPath"
                            , InputSchemaDefinitionProperty
                                { propertyType = "string"
                                , propertyDescription = "Path to GHC's bin directory containing ghc-pkg. Find with: nix-shell --run 'dirname $(which ghc-pkg)'"
                                }
                            )
                        ]
                    , required = ["ghcBinPath"]
                    }
            , toolDefinitionTitle = Just "Regenerate Local Hoogle"
            }
        , ToolDefinition
            { toolDefinitionName = "reload_local_hoogle"
            , toolDefinitionDescription = "Reload the local Hoogle database from disk without regenerating. Use after running hoogle generate externally."
            , toolDefinitionInputSchema =
                InputSchemaDefinitionObject
                    { properties =
                        [
                            ( "reloadPath"
                            , InputSchemaDefinitionProperty
                                { propertyType = "string"
                                , propertyDescription = "Path to the .hoo database file to reload. Use empty string for default location."
                                }
                            )
                        ]
                    , required = ["reloadPath"]
                    }
            , toolDefinitionTitle = Just "Reload Local Hoogle"
            }
        , ToolDefinition
            { toolDefinitionName = "local_hoogle_status"
            , toolDefinitionDescription = "Check the status of an asynchronous local Hoogle database regeneration."
            , toolDefinitionInputSchema =
                InputSchemaDefinitionObject
                    { properties = []
                    , required = []
                    }
            , toolDefinitionTitle = Just "Local Hoogle Status"
            }
        ]

toolCall :: ToolName -> [(ArgumentName, ArgumentValue)] -> AppM (Either Error Content)
toolCall toolName args = case toolName of
    "search_hoogle" ->
        case lookup "query" args of
            Nothing -> pure $ Left $ MissingRequiredParams "Missing 'query' argument"
            Just query -> do
                AppEnv{..} <- ask
                localResult <- liftIO $ searchLocalHoogle appLocalHoogleDb query
                case localResult of
                    Just localText -> pure $ Right $ ContentText localText
                    Nothing -> do
                        result <- case appCacheConfig of
                            Nothing -> liftIO $ searchHoogle query
                            Just conf@CacheConfig{..} -> lookupOrFetchHoogle dbConnection conf query
                        pure $ either (Left . InternalError) (Right . ContentText) result
    "list_package_modules" ->
        case lookup "package_name" args of
            Nothing -> pure $ Left $ MissingRequiredParams "Missing 'package_name' argument"
            Just packageName -> do
                AppEnv{..} <- ask
                result <- case appCacheConfig of
                    Nothing -> liftIO $ fetchPackageModules packageName
                    Just conf@CacheConfig{..} -> lookupOrFetchPackageModules dbConnection conf packageName
                pure $ either (Left . InternalError) (Right . ContentText) result
    "get_module_docs" ->
        case (lookup "package_name" args, lookup "module_name" args) of
            (Nothing, _) -> pure $ Left $ MissingRequiredParams "Missing 'package_name' argument"
            (_, Nothing) -> pure $ Left $ MissingRequiredParams "Missing 'module_name' argument"
            (Just packageName, Just moduleName) -> do
                AppEnv{..} <- ask
                result <- case appCacheConfig of
                    Nothing -> liftIO $ fetchModuleDocs packageName moduleName
                    Just conf@CacheConfig{..} -> lookupOrFetchModuleDocs dbConnection conf packageName moduleName
                pure $ either (Left . InternalError) (Right . ContentText) result
    "regenerate_local_hoogle" ->
        case lookup "ghcBinPath" args of
            Nothing -> pure $ Left $ MissingRequiredParams "Missing 'ghcBinPath' argument"
            Just ghcBinPath -> do
                AppEnv{..} <- ask
                result <- liftIO $ regenerateLocalHoogle appLocalHoogleDb appLocalHoogleRegenState ghcBinPath
                pure $ Right $ ContentText result
    "reload_local_hoogle" ->
        case lookup "reloadPath" args of
            Nothing -> pure $ Left $ MissingRequiredParams "Missing 'reloadPath' argument"
            Just reloadPath -> do
                AppEnv{..} <- ask
                result <- liftIO $ reloadLocalHoogle appLocalHoogleDb reloadPath
                pure $ Right $ ContentText result
    "local_hoogle_status" -> do
        AppEnv{..} <- ask
        result <- liftIO $ localHoogleStatus appLocalHoogleRegenState
        pure $ Right $ ContentText result
    _ -> pure $ Left $ UnknownTool toolName

toolHandlers :: AppEnv -> (ToolListHandler IO, ToolCallHandler IO)
toolHandlers appEnv = (toolList, toolCallIO)
  where
    toolCallIO :: ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error Content)
    toolCallIO toolName toolArgs = runAppM appEnv (toolCall toolName toolArgs)
