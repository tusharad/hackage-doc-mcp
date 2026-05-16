{-# LANGUAGE OverloadedStrings #-}

import Control.Exception (bracket)
import qualified Data.Text as T
import Database.SQLite.Simple (close, open)
import Hackage.MCP.Cache (AppEnv (..), CacheConfig (..), initCache)
import Data.Version (showVersion)
import Hackage.MCP.Core (mcpServerInfo)
import Hackage.MCP.Tool (toolHandlers)
import MCP.Server.Types
import Paths_hackage_doc_mcp (version)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
    testGroup
        "MCP Tool Handler Integration Tests"
        [ testToolListVerification
        , testSearchHoogleHappyPath
        , testSearchHoogleErrorHandling
        , testListPackageModulesHappyPath
        , testListPackageModulesErrorHandling
        , testGetModuleDocsHappyPath
        , testGetModuleDocsMissingPackageName
        , testGetModuleDocsMissingModuleName
        , testUnknownToolErrorHandling
        , testServerVersionHandling
        ]

testServerVersionHandling :: TestTree
testServerVersionHandling = do
    testCase "Server version and Package version shall be same" $ do
        assertBool
            "Server version and package version are not equal"
            (serverVersion mcpServerInfo == T.pack (showVersion version))

-- Test 1: Verify all tools are listed
testToolListVerification :: TestTree
testToolListVerification = testCase "Tool list contains all three tools" $ withTestEnv $ \env -> do
    tools <- fst (toolHandlers env)
    let toolNames = map toolDefinitionName tools
    length toolNames @?= 3
    assertBool "Missing search_hoogle" ("search_hoogle" `elem` toolNames)
    assertBool "Missing list_package_modules" ("list_package_modules" `elem` toolNames)
    assertBool "Missing get_module_docs" ("get_module_docs" `elem` toolNames)

testSearchHoogleHappyPath :: TestTree
testSearchHoogleHappyPath = testCase "search_hoogle returns ContentText for valid query" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "search_hoogle" [("query", "langchain")]
    case result of
        Left err -> assertFailure $ "search_hoogle failed with error: " ++ show err
        Right (ContentText _) -> return ()
        Right _ -> assertFailure "search_hoogle returned unexpected response type"

testSearchHoogleErrorHandling :: TestTree
testSearchHoogleErrorHandling = testCase "search_hoogle raises MissingRequiredParams for missing query" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "search_hoogle" []
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testListPackageModulesHappyPath :: TestTree
testListPackageModulesHappyPath = testCase "list_package_modules returns ContentText for valid package" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "list_package_modules" [("package_name", "text")]
    case result of
        Left err -> assertFailure $ "list_package_modules failed with error: " ++ show err
        Right (ContentText jsonText) ->
            assertBool "Response should not be empty" (not $ T.null jsonText)
        Right _ -> assertFailure "list_package_modules returned unexpected response type"

testListPackageModulesErrorHandling :: TestTree
testListPackageModulesErrorHandling = testCase "list_package_modules raises MissingRequiredParams for missing package_name" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "list_package_modules" []
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testGetModuleDocsHappyPath :: TestTree
testGetModuleDocsHappyPath = testCase "get_module_docs returns markdown for valid package and module" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "get_module_docs" [("package_name", "base"), ("module_name", "Data-List")]
    case result of
        Left err -> assertFailure $ "get_module_docs failed with error: " ++ show err
        Right (ContentText markdown) ->
            assertBool "Response should not be empty" (not $ T.null markdown)
        Right _ -> assertFailure "get_module_docs returned unexpected response type"

testGetModuleDocsMissingPackageName :: TestTree
testGetModuleDocsMissingPackageName = testCase "get_module_docs raises MissingRequiredParams for missing package_name" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "get_module_docs" [("module_name", "Data.List")]
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testGetModuleDocsMissingModuleName :: TestTree
testGetModuleDocsMissingModuleName = testCase "get_module_docs raises MissingRequiredParams for missing module_name" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "get_module_docs" [("package_name", "base")]
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testUnknownToolErrorHandling :: TestTree
testUnknownToolErrorHandling = testCase "Unknown tool raises UnknownTool error" $ withTestEnv $ \env -> do
    let toolCall = snd (toolHandlers env)
    result <- toolCall "nonexistent_tool" []
    case result of
        Left (UnknownTool _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for unknown tool"

withTestEnv :: (AppEnv -> IO a) -> IO a
withTestEnv = bracket setup teardown
  where
    setup = do
        conn <- open ":memory:"
        initCache conn
        pure
            AppEnv
                { appCacheConfig =
                    Just
                        CacheConfig
                            { cacheExpiryHours = 168
                            , dbConnection = conn
                            }
                }
    teardown env = do
        case appCacheConfig env of
            Just appConf -> close $ dbConnection appConf
            Nothing -> pure ()
