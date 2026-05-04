module Hackage.MCP.Parse
  ( ModuleName
  , scrapeHackageModuleList
  , scrapeHackageDocPage
  )
where

import Data.Text (Text)
import qualified Data.Text as T
import Text.HTML.Scalpel
import Data.List (intersperse)

type ModuleName = (Text, Maybe Text)

-- | Scrape the Hackage package HTML and return a list of module names
-- and optional links. Expects the HTML for a package page (contains
-- a `div` with id `module-list`).
scrapeHackageModuleList :: Text -> IO (Either Text [ModuleName])
scrapeHackageModuleList rawHtml = do
  let html_ = T.unpack rawHtml
      scraper = chroots ("div" @: ["id" @= "module-list"]) $ chroots "a" $ do
        name <- text anySelector
        href <- attr "href" anySelector
        return (name, href)
  case scrapeStringLike html_ scraper of
    Nothing -> pure $ Left "Failed to find module list in HTML"
    Just lists ->
      let pairs = concat lists
          converted = map (\(n, h) -> (T.strip (T.pack n), Just (T.strip (T.pack h)))) pairs
       in pure $ Right converted

-- | Convert a Haddock HTML page into a minimal Markdown document that keeps
-- the most useful information for an LLM: title, package summary,
-- metadata, description, synopsis, and interface sections.
-- Removes HTML formatting and provides clean, structured text.
scrapeHackageDocPage :: Text -> IO (Either Text Text)
scrapeHackageDocPage htmlContent = do
    let mbRes = extractModuleName htmlContent
    case mbRes of
        Nothing -> pure $ Left "something went wrong"
        Just r -> pure $ Right r
    
extractModuleName :: Text -> Maybe Text
extractModuleName htmlContent = scrapeStringLike htmlContent $ do 
    modName <- moduleScraper
    desc <- descriptionScraper
    topText <- topDivScraper 
    return $ "Module name: " <> modName <> "\n" 
         <> "Description: " <> desc <> "\n" 
         <> mconcat (intersperse " \n " topText)

moduleScraper :: Scraper Text Text
moduleScraper = text $ 
    "div" @: ["id" @= "module-header"] // "p" @: [hasClass "caption"]

descriptionScraper :: Scraper Text Text
descriptionScraper = text $ 
    "div" @: ["id" @= "description"] // "div" @: [hasClass "doc"] // "p"

topDivScraper :: Scraper Text [Text]
topDivScraper = texts $ 
    "div" @: [hasClass "top"] // anySelector
