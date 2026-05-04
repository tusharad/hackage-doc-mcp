module Hackage.MCP.Tool (toolHandlers) where

import MCP.Server.Types
import Hackage.MCP.Hoogle (searchHoogle)

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
                                , propertyDescription = "Fully-qualified module name"
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
  "list_package_modules" -> return $ Left $ InternalError "Not yet implemented"
  "get_module_docs" -> return $ Left $ InternalError "Not yet implemented"
  _ -> return $ Left $ UnknownTool toolName

toolHandlers :: (ToolListHandler IO, ToolCallHandler IO)
toolHandlers = (toolList, toolCall)
