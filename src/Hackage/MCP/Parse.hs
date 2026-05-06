module Hackage.MCP.Parse (
    ModuleName,
    scrapeHackageModuleList,
    scrapeHackageDocPage,
    runTest,
)
where

import Control.Applicative
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Text.HTML.Scalpel

type ModuleName = (Text, Maybe Text)

data TopBlock = TopBlock
    { topName :: Text
    , topKeyword :: Maybe Text
    , topSignature :: Maybe Text
    , topArgDocs :: [Text]
    , topDocs :: [Text]
    , topConstructors :: [ConstructorBlock]
    , topFields :: [FieldBlock]
    }

data ConstructorBlock = ConstructorBlock
    { constructorName :: Text
    , constructorSignature :: Maybe Text
    , constructorDocs :: [Text]
    }

data FieldBlock = FieldBlock
    { fieldName :: Text
    , fieldSignature :: Maybe Text
    , fieldDocs :: [Text]
    }

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

scrapeHackageDocPage :: Text -> IO (Either Text Text)
scrapeHackageDocPage rawHtml = do
    let html_ = T.unpack rawHtml
        packageName = extractPackageName html_
    case packageName of
        Nothing -> pure $ Left "Failed to parse package name from haddock page"
        Just pkg -> do
            let infoPairs = extractModuleInfo html_
                moduleName = extractModuleName html_
                descriptionParts = extractDescription html_
                interfaceHeadings = extractInterfaceHeadings html_
                topBlocks = extractTopBlocks html_
                markdown = renderMarkdown pkg infoPairs moduleName descriptionParts interfaceHeadings topBlocks
            pure $ Right markdown

extractPackageName :: String -> Maybe Text
extractPackageName html_ =
    T.strip . T.pack
        <$> scrapeStringLike html_ (text ("div" @: ["id" @= "package-header"] // "span" @: ["class" @= "caption"]))

extractModuleInfo :: String -> [(Text, Text)]
extractModuleInfo html_ =
    fromMaybe [] $ do
        rows <- scrapeStringLike html_ scraper
        pure $ mapMaybe toPair rows
  where
    scraper =
        chroots
            ( "div" @: ["id" @= "content"]
                // "div" @: ["id" @= "module-header"]
                // "table" @: ["class" @= "info"]
                // "tr"
            )
            $ do
                key <- text "th"
                val <- text "td"
                pure (T.pack key, T.pack val)
    toPair (k, v) =
        let key = normalizeText k
            val = normalizeText v
         in if T.null key || T.null val then Nothing else Just (key, val)

extractModuleName :: String -> Maybe Text
extractModuleName html_ =
    normalizeText . T.pack
        <$> scrapeStringLike
            html_
            ( text
                ( "div" @: ["id" @= "content"]
                    // "div" @: ["id" @= "module-header"]
                    // "p" @: ["class" @= "caption"]
                )
            )

extractDescription :: String -> [Text]
extractDescription html_ =
    case scrapeStringLike html_ scraper of
        Nothing -> []
        Just parts -> filter (not . T.null) $ map normalizeText parts
  where
    scraper = scrapeRichText ("div" @: ["id" @= "description"] // "div" @: ["class" @= "doc"])

extractInterfaceHeadings :: String -> [Text]
extractInterfaceHeadings html_ =
    filter (not . T.null) $
        maybe
            []
            (map (normalizeText . T.pack))
            (scrapeStringLike html_ (texts ("div" @: ["id" @= "interface"] // "h1")))

extractTopBlocks :: String -> [TopBlock]
extractTopBlocks html_ = fromMaybe [] $ scrapeStringLike html_ topScraper
  where
    topScraper =
        chroots ("div" @: ["id" @= "interface"] // "div" @: ["class" @= "top"]) $ do
            srcLine <- text ("p" @: ["class" @= "src"])
            defName <- text ("p" @: ["class" @= "src"] // "a" @: ["class" @= "def"])
            argTypes <- texts ("div" @: ["class" @= "subs arguments"] // "td" @: ["class" @= "src"])
            argDocs <- texts ("div" @: ["class" @= "subs arguments"] // "td" @: ["class" @= "doc"])
            docs <- scrapeRichText ("div" @: ["class" @= "doc"])
            constructors <-
                chroots ("div" @: ["class" @= "subs constructors"] // "tr") $ do
                    nameLine <- text ("td" @: ["class" @= "src"])
                    constructorDef <- text ("td" @: ["class" @= "src"] // "a" @: ["class" @= "def"])
                    constructorDocs <- scrapeRichText ("td" @: ["class" @= "doc"])
                    let (constructorName', constructorSignature') = parseSrcLine (normalizeText (T.pack nameLine))
                        constructorNameFinal = if T.null (normalizeText (T.pack constructorDef)) then constructorName' else normalizeText (T.pack constructorDef)
                        cleanedConstructorDocs = filter (not . T.null) $ map normalizeText constructorDocs
                    pure
                        ConstructorBlock
                            { constructorName = constructorNameFinal
                            , constructorSignature = constructorSignature'
                            , constructorDocs = cleanedConstructorDocs
                            }
            fields <-
                chroots ("div" @: ["class" @= "subs fields"] // "li") $ do
                    fieldDef <- text ("dfn" @: ["class" @= "src"] // "a" @: ["class" @= "def"])
                    fieldSrc <- text ("dfn" @: ["class" @= "src"])
                    fieldDocs <- scrapeRichText ("div" @: ["class" @= "doc"])
                    let (_, fieldSignature') = parseSrcLine (normalizeText (T.pack fieldSrc))
                        cleanedFieldDocs = filter (not . T.null) $ map normalizeText fieldDocs
                    pure
                        FieldBlock
                            { fieldName = normalizeText (T.pack fieldDef)
                            , fieldSignature = fieldSignature'
                            , fieldDocs = cleanedFieldDocs
                            }
            let (name, sigFromSrc) = parseSrcLine (normalizeText (T.pack srcLine))
                actualName = if T.null (normalizeText (T.pack defName)) then name else normalizeText (T.pack defName)
                sigFromArgs = buildSignatureFromArgs name (map (normalizeText . T.pack) argTypes)
                finalSig = sigFromSrc <|> sigFromArgs
                cleanedArgDocs = filter (not . T.null) $ map (normalizeText . T.pack) argDocs
                cleanedDocs = filter (not . T.null) $ map normalizeText docs
            pure
                TopBlock
                    { topName = actualName
                    , topKeyword = parseTopKeyword (normalizeText (T.pack srcLine))
                    , topSignature = finalSig
                    , topArgDocs = cleanedArgDocs
                    , topDocs = cleanedDocs
                    , topConstructors = constructors
                    , topFields = fields
                    }

scrapeRichText :: Selector -> Scraper String [Text]
scrapeRichText selector = do
    blocks <- chroots selector $ do
        ps <- texts "p"
        pres <- texts "pre"
        pure $ ps ++ pres
    pure . map (normalizeText . T.pack) $ concat blocks

parseTopKeyword :: Text -> Maybe Text
parseTopKeyword src =
    case T.words src of
        (keyword : _)
            | keyword `elem` ["newtype", "data", "type", "class"] -> Just keyword
        _ -> Nothing

parseSrcLine :: Text -> (Text, Maybe Text)
parseSrcLine src =
    let filteredTokens = filter (`notElem` ["Source", "#"]) (T.words src)
        cleaned = T.unwords filteredTokens
        name = fromMaybe "" (listToMaybe filteredTokens)
     in case T.breakOn "::" cleaned of
            (_, "") -> (name, Nothing)
            (_, suffix) -> (name, Just (normalizeText (name <> " " <> suffix)))

buildSignatureFromArgs :: Text -> [Text] -> Maybe Text
buildSignatureFromArgs name argTypes =
    let parts = filter (not . T.null) argTypes
     in if T.null name || null parts
            then Nothing
            else Just (normalizeText (name <> " " <> T.unwords parts))

renderMarkdown :: Text -> [(Text, Text)] -> Maybe Text -> [Text] -> [Text] -> [TopBlock] -> Text
renderMarkdown packageName infoPairs moduleName descriptionParts interfaceHeadings topBlocks =
    T.intercalate
        "\n"
        ( ["# " <> packageName, "", "## info", ""]
            ++ renderInfo infoPairs
            ++ renderModuleName moduleName
            ++ renderDescription descriptionParts
            ++ renderInterfaceHeadings interfaceHeadings
            ++ renderInterface topBlocks
        )
  where
    renderInfo [] = ["No module metadata found.", ""]
    renderInfo pairs = map (\(k, v) -> T.toLower k <> ": " <> v) pairs ++ [""]

    renderModuleName Nothing = []
    renderModuleName (Just name)
        | T.null name = []
        | otherwise = ["## " <> name, ""]

    renderDescription [] = []
    renderDescription parts = ["## Description", ""] ++ parts ++ [""]

    renderInterfaceHeadings [] = []
    renderInterfaceHeadings headings = "## Interface" : "" : concatMap (\heading -> ["### " <> heading, ""]) headings

    renderInterface [] = []
    renderInterface blocks = concatMap renderTop blocks

    renderTop TopBlock{..} =
        let sigLine = case topKeyword of
                Just keyword -> keyword <> " " <> topName
                Nothing -> topName
            renderedSig = fromMaybe sigLine topSignature
            argDocLines = map ("-- " <>) topArgDocs
         in [renderedSig]
                ++ argDocLines
                ++ [""]
                ++ topDocs
                ++ renderConstructors topConstructors
                ++ renderFields topFields
                ++ [""]

    renderConstructors [] = []
    renderConstructors constructors =
        "## Constructors"
            : ""
            : concatMap renderConstructor constructors

    renderConstructor ConstructorBlock{..} =
        let sigLine = fromMaybe constructorName constructorSignature
         in [sigLine] ++ map ("-- " <>) constructorDocs ++ [""]

    renderFields [] = []
    renderFields fields =
        "## Fields"
            : ""
            : concatMap renderField fields

    renderField FieldBlock{..} =
        let sigLine = fromMaybe fieldName fieldSignature
         in [sigLine] ++ map ("-- " <>) fieldDocs ++ [""]

normalizeText :: Text -> Text
normalizeText = collapseWs . T.strip . T.replace "\160" " "

collapseWs :: Text -> Text
collapseWs = T.unwords . T.words

runTest :: IO ()
runTest = do
    readFile "./sample.html" >>= scrapeHackageDocPage . T.pack >>= either T.putStrLn T.putStrLn
