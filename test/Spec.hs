{-# LANGUAGE OverloadedStrings #-}

import Hackage.MCP.Tool (toolHandlers)
import Hackage.MCP.Hoogle (searchHoogle)
import Hackage.MCP.Fetch (fetchHackageHtmlPage)
import Hackage.MCP.Parse (scrapeHackageModuleList, scrapeHackageDocPage)
import MCP.Server.Types
import qualified Data.Aeson as JSON
import Data.Either (isRight)
import Data.Text (Text)
import qualified Data.Text as T

main :: IO ()
main = do
  putStrLn "MCP Tool Handler Integration Tests"
  putStrLn "===================================="
  
  let (toolList, toolCall) = toolHandlers
  
  -- Test 1: Verify all tools are listed
  putStrLn "\n[Test 1] Verifying tool list..."
  tools <- toolList
  let toolNames = map toolDefinitionName tools
  if length toolNames == 3
    then putStrLn $ "✓ Tool list contains " ++ show (length toolNames) ++ " tools"
    else putStrLn $ "✗ Expected 3 tools, got " ++ show (length toolNames)
  
  -- Test 2: Test search_hoogle happy path
  putStrLn "\n[Test 2] Testing search_hoogle (happy path)..."
  result1 <- toolCall "search_hoogle" [("query", "langchain")]
  case result1 of
    Left err -> putStrLn $ "✗ Failed with error: " ++ show err
    Right (ContentText _) -> putStrLn "✓ search_hoogle returned ContentText"
    Right _ -> putStrLn "✗ Unexpected response type"
  
  -- Test 3: Test search_hoogle error handling
  putStrLn "\n[Test 3] Testing search_hoogle error handling..."
  result2 <- toolCall "search_hoogle" []
  case result2 of
    Left (MissingRequiredParams _) -> putStrLn "✓ Correctly raised MissingRequiredParams"
    Left err -> putStrLn $ "✗ Wrong error type: " ++ show err
    Right _ -> putStrLn "✗ Should have returned error"
  
  -- Test 4: Test list_package_modules happy path
  putStrLn "\n[Test 4] Testing list_package_modules (happy path)..."
  result3 <- toolCall "list_package_modules" [("package_name", "text")]
  case result3 of
    Left err -> putStrLn $ "✗ Failed with error: " ++ show err
    Right (ContentText jsonText) -> do
      putStrLn $ "✓ list_package_modules returned " ++ show (T.length jsonText) ++ " chars"
    Right _ -> putStrLn "✗ Unexpected response type"
  
  -- Test 5: Test list_package_modules error handling
  putStrLn "\n[Test 5] Testing list_package_modules error handling..."
  result4 <- toolCall "list_package_modules" []
  case result4 of
    Left (MissingRequiredParams _) -> putStrLn "✓ Correctly raised MissingRequiredParams"
    Left err -> putStrLn $ "✗ Wrong error type: " ++ show err
    Right _ -> putStrLn "✗ Should have returned error"
  
  -- Test 6: Test get_module_docs happy path
  putStrLn "\n[Test 6] Testing get_module_docs (happy path)..."
  result5 <- toolCall "get_module_docs" [("package_name", "base"), ("module_name", "Data-List")]
  case result5 of
    Left err -> putStrLn $ "✗ Failed with error: " ++ show err
    Right (ContentText markdown) -> 
      putStrLn $ "✓ get_module_docs returned markdown (" ++ show (T.length markdown) ++ " chars)"
    Right _ -> putStrLn "✗ Unexpected response type"
  
  -- Test 7: Test get_module_docs missing package_name
  putStrLn "\n[Test 7] Testing get_module_docs error handling (missing package_name)..."
  result6 <- toolCall "get_module_docs" [("module_name", "Data.List")]
  case result6 of
    Left (MissingRequiredParams _) -> putStrLn "✓ Correctly raised MissingRequiredParams"
    Left err -> putStrLn $ "✗ Wrong error type: " ++ show err
    Right _ -> putStrLn "✗ Should have returned error"
  
  -- Test 8: Test get_module_docs missing module_name
  putStrLn "\n[Test 8] Testing get_module_docs error handling (missing module_name)..."
  result7 <- toolCall "get_module_docs" [("package_name", "base")]
  case result7 of
    Left (MissingRequiredParams _) -> putStrLn "✓ Correctly raised MissingRequiredParams"
    Left err -> putStrLn $ "✗ Wrong error type: " ++ show err
    Right _ -> putStrLn "✗ Should have returned error"
  
  -- Test 9: Test unknown tool
  putStrLn "\n[Test 9] Testing unknown tool error handling..."
  result8 <- toolCall "nonexistent_tool" []
  case result8 of
    Left (UnknownTool _) -> putStrLn "✓ Correctly raised UnknownTool"
    Left err -> putStrLn $ "✗ Wrong error type: " ++ show err
    Right _ -> putStrLn "✗ Should have returned error"
  
  putStrLn "\n===================================="
  putStrLn "All tests completed!"
