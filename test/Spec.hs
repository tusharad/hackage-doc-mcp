import Hackage.MCP.Hoogle (searchHoogle)
import Hackage.MCP.Fetch (fetchHackageHtmlPage)
import Hackage.MCP.Parse (scrapeHackageModuleList, scrapeHackageDocPage)
import Data.Either (isRight)

main :: IO ()
main = do
  result <- searchHoogle "langchain"
  if isRight result
    then putStrLn "searchHoogle happy path test passed"
    else putStrLn $ "searchHoogle failed: " ++ show result

  res2 <- fetchHackageHtmlPage "https://hackage.haskell.org/package/langchain-hs-0.0.3.0"
  case res2 of
    Left err -> putStrLn $ "fetchHackageHtmlPage failed: " ++ show err
    Right html -> do
      emods <- scrapeHackageModuleList html
      case emods of
        Left perr -> putStrLn $ "scrapeHackageModuleList failed: " ++ show perr
        Right mods -> if null mods
          then putStrLn "scrapeHackageModuleList returned no modules"
          else do
            putStrLn "scrapeHackageModuleList happy path test passed"
            let (moduleName, _) = head mods
            eRes3 <- fetchHackageHtmlPage "https://hackage-content.haskell.org/package/base-4.22.0.0/docs/Data-List.html"
            case eRes3 of
                Left err3 -> print err3
                Right r -> do
                    res4 <- scrapeHackageDocPage r
