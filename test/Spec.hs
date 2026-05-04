import Hackage.MCP.Hoogle (searchHoogle)
import Data.Either (isRight)

main :: IO ()
main = do
  result <- searchHoogle "langchain"
  if isRight result
    then putStrLn "searchHoogle happy path test passed"
    else putStrLn $ "searchHoogle failed: " ++ show result
