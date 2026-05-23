{-# LANGUAGE OverloadedStrings #-}

import Control.Concurrent.STM (newTVarIO)
import Control.Exception (bracket)
import Data.IORef (newIORef)
import qualified Data.Text as T
import Data.Version (showVersion)
import Database.SQLite.Simple (close, open)
import Hackage.MCP.Cache (AppEnv (..), CacheConfig (..), initCache)
import Hackage.MCP.Core (mcpServerInfo)
import Hackage.MCP.LocalHoogle (RegenState (..), formatTargets, stripHtmlTags)
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
        , testStripHtmlTags
        , testFormatTargetsEmpty
        , testLocalHoogleStatusIdle
        , testToolListIncludesNewTools
        , testRegenerateLocalHoogleMissingParam
        , testReloadLocalHoogleMissingParam
        ]

testServerVersionHandling :: TestTree
testServerVersionHandling = do
    testCase "Server version and Package version shall be same" $ do
        assertBool
            "Server version and package version are not equal"
            (serverVersion mcpServerInfo == T.pack (showVersion version))

-- Test 1: Verify all tools are listed
testToolListVerification :: TestTree
testToolListVerification = testCase "Tool list contains all six tools" $ withTestEnv $ \env -> do
    tools <- fst (toolHandlers env)
    let toolNames = map toolDefinitionName tools
    length toolNames @?= 6
    assertBool "Missing search_hoogle" ("search_hoogle" `elem` toolNames)
    assertBool "Missing list_package_modules" ("list_package_modules" `elem` toolNames)
    assertBool "Missing get_module_docs" ("get_module_docs" `elem` toolNames)

testSearchHoogleHappyPath :: TestTree
testSearchHoogleHappyPath = testCase "search_hoogle returns ContentText for valid query" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "search_hoogle" [("query", "langchain")]
    case result of
        Left err -> assertFailure $ "search_hoogle failed with error: " ++ show err
        Right (ContentText _) -> return ()
        Right _ -> assertFailure "search_hoogle returned unexpected response type"

testSearchHoogleErrorHandling :: TestTree
testSearchHoogleErrorHandling = testCase "search_hoogle raises MissingRequiredParams for missing query" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "search_hoogle" []
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testListPackageModulesHappyPath :: TestTree
testListPackageModulesHappyPath = testCase "list_package_modules returns ContentText for valid package" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "list_package_modules" [("package_name", "text")]
    case result of
        Left err -> assertFailure $ "list_package_modules failed with error: " ++ show err
        Right (ContentText jsonText) ->
            assertBool "Response should not be empty" (not $ T.null jsonText)
        Right _ -> assertFailure "list_package_modules returned unexpected response type"

testListPackageModulesErrorHandling :: TestTree
testListPackageModulesErrorHandling = testCase "list_package_modules raises MissingRequiredParams for missing package_name" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "list_package_modules" []
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testGetModuleDocsHappyPath :: TestTree
testGetModuleDocsHappyPath = testCase "get_module_docs returns markdown for valid package and module" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "get_module_docs" [("package_name", "base"), ("module_name", "Data-List")]
    case result of
        Left err -> assertFailure $ "get_module_docs failed with error: " ++ show err
        Right (ContentText markdown) ->
            assertBool "Response should not be empty" (not $ T.null markdown)
        Right _ -> assertFailure "get_module_docs returned unexpected response type"

testGetModuleDocsMissingPackageName :: TestTree
testGetModuleDocsMissingPackageName = testCase "get_module_docs raises MissingRequiredParams for missing package_name" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "get_module_docs" [("module_name", "Data.List")]
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testGetModuleDocsMissingModuleName :: TestTree
testGetModuleDocsMissingModuleName = testCase "get_module_docs raises MissingRequiredParams for missing module_name" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "get_module_docs" [("package_name", "base")]
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testUnknownToolErrorHandling :: TestTree
testUnknownToolErrorHandling = testCase "Unknown tool raises UnknownTool error" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "nonexistent_tool" []
    case result of
        Left (UnknownTool _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for unknown tool"

-- New tests for local Hoogle functionality

testStripHtmlTags :: TestTree
testStripHtmlTags = testCase "stripHtmlTags removes HTML tags" $ do
    stripHtmlTags "<b>hello</b>" @?= "hello"
    stripHtmlTags "plain text" @?= "plain text"
    stripHtmlTags "<s0>map</s0> :: (a -> b) -> [a] -> [b]" @?= "map :: (a -> b) -> [a] -> [b]"
    stripHtmlTags "" @?= ""

testFormatTargetsEmpty :: TestTree
testFormatTargetsEmpty = testCase "formatTargets returns message for empty list" $ do
    formatTargets [] @?= "No results found."

testLocalHoogleStatusIdle :: TestTree
testLocalHoogleStatusIdle = testCase "local_hoogle_status returns status text when idle" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "local_hoogle_status" []
    case result of
        Left err -> assertFailure $ "local_hoogle_status failed: " ++ show err
        Right (ContentText statusText) ->
            assertBool "Status text should contain 'No'" (T.isInfixOf "No" statusText)
        Right _ -> assertFailure "local_hoogle_status returned unexpected response type"

testToolListIncludesNewTools :: TestTree
testToolListIncludesNewTools = testCase "Tool list includes local Hoogle tools" $ withTestEnv $ \env -> do
    tools <- fst (toolHandlers env)
    let toolNames = map toolDefinitionName tools
    assertBool "Missing regenerate_local_hoogle" ("regenerate_local_hoogle" `elem` toolNames)
    assertBool "Missing reload_local_hoogle" ("reload_local_hoogle" `elem` toolNames)
    assertBool "Missing local_hoogle_status" ("local_hoogle_status" `elem` toolNames)

testRegenerateLocalHoogleMissingParam :: TestTree
testRegenerateLocalHoogleMissingParam = testCase "regenerate_local_hoogle raises MissingRequiredParams for missing ghcBinPath" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "regenerate_local_hoogle" []
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

testReloadLocalHoogleMissingParam :: TestTree
testReloadLocalHoogleMissingParam = testCase "reload_local_hoogle raises MissingRequiredParams for missing reloadPath" $ withTestEnv $ \env -> do
    let toolCallHandler = snd (toolHandlers env)
    result <- toolCallHandler "reload_local_hoogle" []
    case result of
        Left (MissingRequiredParams _) -> return ()
        Left err -> assertFailure $ "Wrong error type: " ++ show err
        Right _ -> assertFailure "Should have returned error for missing parameter"

withTestEnv :: (AppEnv -> IO a) -> IO a
withTestEnv = bracket setup teardown
  where
    setup :: IO AppEnv
    setup = do
        conn <- open ":memory:"
        initCache conn
        localHoogleDbRef <- newIORef Nothing
        regenStateVar <- newTVarIO RegenIdle
        pure
            AppEnv
                { appCacheConfig =
                    Just
                        CacheConfig
                            { cacheExpiryHours = 168
                            , dbConnection = conn
                            }
                , appLocalHoogleDb = localHoogleDbRef
                , appLocalHoogleRegenState = regenStateVar
                }
    teardown :: AppEnv -> IO ()
    teardown env = do
        case appCacheConfig env of
            Just appConf -> close $ dbConnection appConf
            Nothing -> pure ()
