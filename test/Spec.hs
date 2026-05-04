import Hackage.MCP.Hoogle (searchHoogle)
import Hackage.MCP.Fetch (fetchHackageHtmlPage)
import Hackage.MCP.Parse (scrapeHackageModuleList)
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
            print mods
            putStrLn "scrapeHackageModuleList happy path test passed"
