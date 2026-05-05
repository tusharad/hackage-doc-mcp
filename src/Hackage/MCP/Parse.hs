module Hackage.MCP.Parse (
    ModuleName,
    scrapeHackageModuleList,
    scrapeHackageDocPage,
)
where

import Control.Applicative
import Data.List (intercalate)
import Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T
import Text.HTML.Scalpel
import Text.HTML.TagSoup

type ModuleName = (Text, Maybe Text)

{- | Scrape the Hackage package HTML and return a list of module names
and optional links. Expects the HTML for a package page (contains
a `div` with id `module-list`).
-}
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

extractPureText :: String -> String
extractPureText rawHtml =
    unwords [txt | TagText txt <- parseTags rawHtml]

targetedScraper :: Scraper String String
targetedScraper = do
    mDesc <- optional $ innerHTML ("div" @: ["id" @= "description"])
    mSyn <- optional $ innerHTML ("div" @: ["id" @= "synopsis"])
    mInt <- optional $ innerHTML ("div" @: ["id" @= "interface"])

    let foundSectionsHtml = catMaybes [mDesc, mSyn, mInt]
    let cleanTextSections = map extractPureText foundSectionsHtml
    return $ intercalate "\n\n" cleanTextSections

extractTargetedDocs :: String -> Maybe String
extractTargetedDocs htmlContent = scrapeStringLike htmlContent targetedScraper

scrapeHackageDocPage :: Text -> IO (Either Text Text)
scrapeHackageDocPage htmlContent = do
    pure $ Right $ T.pack $ fromMaybe "" (extractTargetedDocs (T.unpack htmlContent))
