module Hackage.MCP.Tool (toolHandlers) where

import qualified Data.Aeson as JSON
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Hackage.MCP.Fetch (fetchHackageHtmlPage)
import Hackage.MCP.Hoogle (searchHoogle)
import Hackage.MCP.Parse (scrapeHackageDocPage, scrapeHackageModuleList)
import MCP.Server.Types

-- Normalize module name by converting dots to hyphens (e.g., Data.List -> Data-List)
normalizeModuleName :: T.Text -> T.Text
normalizeModuleName = T.replace "." "-"

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

toolCall :: ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error Content)
toolCall toolName args = case toolName of
    "search_hoogle" -> do
        case lookup "query" args of
            Nothing -> return $ Left $ MissingRequiredParams "Missing 'query' argument"
            Just query -> do
                result <- searchHoogle query
                case result of
                    Left err -> return $ Left $ InternalError err
                    Right jsonText -> return $ Right (ContentText jsonText)
    "list_package_modules" -> do
        case lookup "package_name" args of
            Nothing -> return $ Left $ MissingRequiredParams "Missing 'package_name' argument"
            Just packageName -> do
                let url = T.concat ["https://hackage.haskell.org/package/", packageName]
                htmlResult <- fetchHackageHtmlPage url
                case htmlResult of
                    Left err -> return $ Left $ InternalError err
                    Right html -> do
                        parseResult <- scrapeHackageModuleList html
                        case parseResult of
                            Left err -> return $ Left $ InternalError err
                            Right modules -> do
                                let moduleNames = map fst modules
                                let jsonOutput = TL.toStrict $ TLE.decodeUtf8 $ JSON.encode moduleNames
                                return $ Right (ContentText jsonOutput)
    "get_module_docs" -> do
        case (lookup "package_name" args, lookup "module_name" args) of
            (Nothing, _) -> return $ Left $ MissingRequiredParams "Missing 'package_name' argument"
            (_, Nothing) -> return $ Left $ MissingRequiredParams "Missing 'module_name' argument"
            (Just packageName, Just moduleName) -> do
                let normalizedModuleName = normalizeModuleName moduleName
                let url = T.concat ["https://hackage.haskell.org/package/", packageName, "/docs/", normalizedModuleName, ".html"]
                htmlResult <- fetchHackageHtmlPage url
                case htmlResult of
                    Left err -> return $ Left $ InternalError err
                    Right html -> do
                        parseResult <- scrapeHackageDocPage html
                        case parseResult of
                            Left err -> return $ Left $ InternalError err
                            Right markdown -> return $ Right (ContentText markdown)
    _ -> return $ Left $ UnknownTool toolName

toolHandlers :: (ToolListHandler IO, ToolCallHandler IO)
toolHandlers = (toolList, toolCall)
