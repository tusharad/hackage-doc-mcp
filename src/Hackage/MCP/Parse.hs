{-# LANGUAGE OverloadedStrings #-}

module Hackage.MCP.Parse
  ( ModuleName
  , scrapeHackageModuleList
  )
where

import Data.Text (Text)
import qualified Data.Text as T
import Text.HTML.Scalpel

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
