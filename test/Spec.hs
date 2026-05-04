{-# LANGUAGE OverloadedStrings #-}

import Test.Tasty
import Test.Tasty.HUnit
import Hackage.MCP.Tool (toolHandlers)
import MCP.Server.Types
import qualified Data.Text as T

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "MCP Tool Handler Integration Tests"
  [ testToolListVerification
  , testSearchHoogleHappyPath
  , testSearchHoogleErrorHandling
  , testListPackageModulesHappyPath
  , testListPackageModulesErrorHandling
  , testGetModuleDocsHappyPath
  , testGetModuleDocsMissingPackageName
  , testGetModuleDocsMissingModuleName
  , testUnknownToolErrorHandling
  ]

-- Test 1: Verify all tools are listed
testToolListVerification :: TestTree
testToolListVerification = withResource toolListSetup teardown $ \toolListIO ->
  testCase "Tool list contains all three tools" $ do
    tools <- toolListIO
    let toolNames = map toolDefinitionName tools
    length toolNames @?= 3
    assertBool "Missing search_hoogle" ("search_hoogle" `elem` toolNames)
    assertBool "Missing list_package_modules" ("list_package_modules" `elem` toolNames)
    assertBool "Missing get_module_docs" ("get_module_docs" `elem` toolNames)
  where
    toolListSetup = fst toolHandlers
    teardown _ = return ()

-- Test 2: Test search_hoogle happy path
testSearchHoogleHappyPath :: TestTree
testSearchHoogleHappyPath = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "search_hoogle returns ContentText for valid query" $ do
    toolCall <- toolCallIO
    result <- toolCall "search_hoogle" [("query", "langchain")]
    case result of
      Left err -> assertFailure $ "search_hoogle failed with error: " ++ show err
      Right (ContentText _) -> return ()
      Right _ -> assertFailure "search_hoogle returned unexpected response type"
  where
    teardown _ = return ()

-- Test 3: Test search_hoogle error handling
testSearchHoogleErrorHandling :: TestTree
testSearchHoogleErrorHandling = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "search_hoogle raises MissingRequiredParams for missing query" $ do
    toolCall <- toolCallIO
    result <- toolCall "search_hoogle" []
    case result of
      Left (MissingRequiredParams _) -> return ()
      Left err -> assertFailure $ "Wrong error type: " ++ show err
      Right _ -> assertFailure "Should have returned error for missing parameter"
  where
    teardown _ = return ()

-- Test 4: Test list_package_modules happy path
testListPackageModulesHappyPath :: TestTree
testListPackageModulesHappyPath = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "list_package_modules returns ContentText for valid package" $ do
    toolCall <- toolCallIO
    result <- toolCall "list_package_modules" [("package_name", "text")]
    case result of
      Left err -> assertFailure $ "list_package_modules failed with error: " ++ show err
      Right (ContentText jsonText) -> 
        assertBool "Response should not be empty" (not $ T.null jsonText)
      Right _ -> assertFailure "list_package_modules returned unexpected response type"
  where
    teardown _ = return ()

-- Test 5: Test list_package_modules error handling
testListPackageModulesErrorHandling :: TestTree
testListPackageModulesErrorHandling = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "list_package_modules raises MissingRequiredParams for missing package_name" $ do
    toolCall <- toolCallIO
    result <- toolCall "list_package_modules" []
    case result of
      Left (MissingRequiredParams _) -> return ()
      Left err -> assertFailure $ "Wrong error type: " ++ show err
      Right _ -> assertFailure "Should have returned error for missing parameter"
  where
    teardown _ = return ()

-- Test 6: Test get_module_docs happy path
testGetModuleDocsHappyPath :: TestTree
testGetModuleDocsHappyPath = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "get_module_docs returns markdown for valid package and module" $ do
    toolCall <- toolCallIO
    result <- toolCall "get_module_docs" [("package_name", "base"), ("module_name", "Data-List")]
    case result of
      Left err -> assertFailure $ "get_module_docs failed with error: " ++ show err
      Right (ContentText markdown) -> 
        assertBool "Response should not be empty" (not $ T.null markdown)
      Right _ -> assertFailure "get_module_docs returned unexpected response type"
  where
    teardown _ = return ()

-- Test 7: Test get_module_docs missing package_name
testGetModuleDocsMissingPackageName :: TestTree
testGetModuleDocsMissingPackageName = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "get_module_docs raises MissingRequiredParams for missing package_name" $ do
    toolCall <- toolCallIO
    result <- toolCall "get_module_docs" [("module_name", "Data.List")]
    case result of
      Left (MissingRequiredParams _) -> return ()
      Left err -> assertFailure $ "Wrong error type: " ++ show err
      Right _ -> assertFailure "Should have returned error for missing parameter"
  where
    teardown _ = return ()

-- Test 8: Test get_module_docs missing module_name
testGetModuleDocsMissingModuleName :: TestTree
testGetModuleDocsMissingModuleName = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "get_module_docs raises MissingRequiredParams for missing module_name" $ do
    toolCall <- toolCallIO
    result <- toolCall "get_module_docs" [("package_name", "base")]
    case result of
      Left (MissingRequiredParams _) -> return ()
      Left err -> assertFailure $ "Wrong error type: " ++ show err
      Right _ -> assertFailure "Should have returned error for missing parameter"
  where
    teardown _ = return ()

-- Test 9: Test unknown tool error handling
testUnknownToolErrorHandling :: TestTree
testUnknownToolErrorHandling = withResource (pure (snd toolHandlers)) teardown $ \toolCallIO ->
  testCase "Unknown tool raises UnknownTool error" $ do
    toolCall <- toolCallIO
    result <- toolCall "nonexistent_tool" []
    case result of
      Left (UnknownTool _) -> return ()
      Left err -> assertFailure $ "Wrong error type: " ++ show err
      Right _ -> assertFailure "Should have returned error for unknown tool"
  where
    teardown _ = return ()
