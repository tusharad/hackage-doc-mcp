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
import MCP.Server.Types

toolList :: IO [ToolDefinition]
toolList =
    return
        [ ToolDefinition
            { toolDefinitionName = "search_hoogle"
            , toolDefinitionDescription = "Search Hoogle for identifiers, types, or packages."
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
        ]

toolCall :: ToolName -> [(ArgumentName, ArgumentValue)] -> AppM (Either Error Content)
toolCall toolName args = case toolName of
    "search_hoogle" ->
        case lookup "query" args of
            Nothing -> pure $ Left $ MissingRequiredParams "Missing 'query' argument"
            Just query -> do
                AppEnv{..} <- ask
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
    _ -> pure $ Left $ UnknownTool toolName

toolHandlers :: AppEnv -> (ToolListHandler IO, ToolCallHandler IO)
toolHandlers appEnv = (toolList, toolCallIO)
  where
    toolCallIO toolName args = runAppM appEnv (toolCall toolName args)
