-- | Local Hoogle database operations.
--
-- Provides search, regeneration, reload, and status functions for a
-- local Hoogle database built from the GHC package DB. This covers
-- private/local dependencies that the public Hoogle API cannot see.
--
-- Format functions render Hoogle 'Target' results into readable text,
-- stripping HTML tags that Hoogle embeds in its output.
module Hackage.MCP.LocalHoogle
    ( RegenState (..)
    , searchLocalHoogle
    , regenerateLocalHoogle
    , reloadLocalHoogle
    , localHoogleStatus
    , formatTarget
    , formatTargets
    , stripHtmlTags
    ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (TVar, atomically, readTVarIO, writeTVar)
import Control.Exception (SomeException, bracket, try)
import Data.IORef (IORef, readIORef, writeIORef)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import Hoogle (Database, Target (..), defaultDatabaseLocation, hoogle, searchDatabase, withDatabase)
import System.Environment (lookupEnv, setEnv)
import System.IO (hFlush, stderr, stdout)

-- | Tracks the state of an asynchronous database regeneration.
data RegenState
    = RegenIdle
    | RegenRunning UTCTime
    | RegenDone UTCTime Text
    | RegenFailed UTCTime Text

-- | Search the local Hoogle database.
--
-- Returns 'Nothing' when no database is loaded or when results are empty,
-- signalling the caller to fall back to the web API. Returns @Just text@
-- with formatted results when local results are found.
searchLocalHoogle :: IORef (Maybe Database) -> Text -> IO (Maybe Text)
searchLocalHoogle databaseRef searchQuery = do
    mDatabase <- readIORef databaseRef
    case mDatabase of
        Nothing -> pure Nothing
        Just database -> do
            let results = take 20 (searchDatabase database (Text.unpack searchQuery))
            case results of
                [] -> pure Nothing
                _nonEmpty -> pure (Just (formatTargets results))

-- | Start asynchronous regeneration of the local Hoogle database.
--
-- Guards against concurrent regeneration by checking 'RegenRunning'.
-- Spawns a background thread that calls @hoogle generate --local@,
-- redirecting stdout to stderr to avoid corrupting the MCP JSON-RPC stream.
-- On success, loads the new database into the 'IORef'.
regenerateLocalHoogle :: IORef (Maybe Database) -> TVar RegenState -> Text -> IO Text
regenerateLocalHoogle databaseRef regenStateVar ghcBinPath = do
    currentState <- readTVarIO regenStateVar
    case currentState of
        RegenRunning _ -> pure "Database regeneration already in progress. Use local_hoogle_status to check progress."
        RegenIdle -> startRegeneration
        RegenDone _ _ -> startRegeneration
        RegenFailed _ _ -> startRegeneration
  where
    startRegeneration :: IO Text
    startRegeneration = do
        startTime <- getCurrentTime
        atomically (writeTVar regenStateVar (RegenRunning startTime))
        databasePath <- defaultDatabaseLocation
        let ghcBinStr = Text.unpack ghcBinPath
        _ <- forkIO $ do
            result <- try $ do
                withPrependedPath ghcBinStr $
                    withSilencedStdout $
                        hoogle ["generate", "--local", "--database=" <> databasePath]
                withDatabase databasePath $ \newDatabase ->
                    writeIORef databaseRef (Just newDatabase)
            finishTime <- getCurrentTime
            case result of
                Right () ->
                    atomically (writeTVar regenStateVar (RegenDone finishTime (Text.pack databasePath)))
                Left someException ->
                    atomically (writeTVar regenStateVar (RegenFailed finishTime (Text.pack (show (someException :: SomeException)))))
        pure "Database regeneration started. Use local_hoogle_status to check progress."

-- | Reload the local Hoogle database from disk without regenerating.
--
-- If the path is empty, uses the default Hoogle database location.
reloadLocalHoogle :: IORef (Maybe Database) -> Text -> IO Text
reloadLocalHoogle databaseRef path = do
    databasePath <- if Text.null path
        then defaultDatabaseLocation
        else pure (Text.unpack path)
    withDatabase databasePath $ \newDatabase -> do
        writeIORef databaseRef (Just newDatabase)
        pure (Text.pack ("Database reloaded from: " <> databasePath))

-- | Check the status of an asynchronous database regeneration.
localHoogleStatus :: TVar RegenState -> IO Text
localHoogleStatus regenStateVar = do
    currentState <- readTVarIO regenStateVar
    now <- getCurrentTime
    case currentState of
        RegenIdle -> pure "No regeneration in progress or completed."
        RegenRunning startTime ->
            let elapsed = floor (diffUTCTime now startTime) :: Int
            in pure (Text.pack ("Regeneration in progress (started " <> show elapsed <> "s ago)."))
        RegenDone finishTime databasePathText ->
            let ago = floor (diffUTCTime now finishTime) :: Int
            in pure (Text.pack ("Regeneration completed " <> show ago <> "s ago. Database loaded from: " <> Text.unpack databasePathText))
        RegenFailed finishTime errorText ->
            let ago = floor (diffUTCTime now finishTime) :: Int
            in pure (Text.pack ("Regeneration failed " <> show ago <> "s ago: " <> Text.unpack errorText))

-- | Format a single Hoogle 'Target' into a readable markdown block.
formatTarget :: Target -> Text
formatTarget target = Text.unlines
    [ "## " <> stripHtmlTags (Text.pack (targetItem target))
    , case targetPackage target of
        Just (packageName, _url) -> "Package: " <> Text.pack packageName
        Nothing -> ""
    , case targetModule target of
        Just (targetModuleName, _url) -> "Module: " <> Text.pack targetModuleName
        Nothing -> ""
    , if null (targetDocs target)
        then ""
        else "\n" <> stripHtmlTags (Text.pack (targetDocs target))
    , "URL: " <> Text.pack (targetURL target)
    ]

-- | Format a list of targets separated by horizontal rules.
-- Returns a "No results found." message for an empty list.
formatTargets :: [Target] -> Text
formatTargets [] = "No results found."
formatTargets targets =
    Text.intercalate "\n---\n\n" (map formatTarget targets)

-- | Strip HTML tags from text, keeping only the text content.
--
-- Hoogle wraps function names in @\<s0\>...\<\/s0\>@ spans. This does
-- a single-pass removal of all angle-bracketed sequences.
stripHtmlTags :: Text -> Text
stripHtmlTags = go False
  where
    go :: Bool -> Text -> Text
    go inTag input = case Text.uncons input of
        Nothing -> Text.empty
        Just ('<', rest) -> go True rest
        Just (char, rest)
            | inTag -> case char of
                '>' -> go False rest
                _anyOther -> go True rest
            | otherwise -> Text.cons char (go False rest)

-- | Temporarily prepend a directory to PATH, run an action, then restore.
withPrependedPath :: FilePath -> IO a -> IO a
withPrependedPath dir action = do
    oldPath <- lookupEnv "PATH"
    let newPath = case oldPath of
            Nothing -> dir
            Just existingPath -> dir <> ":" <> existingPath
    bracket
        (setEnv "PATH" newPath)
        (\_ -> maybe (setEnv "PATH" "") (setEnv "PATH") oldPath)
        (\_ -> action)

-- | Redirect stdout to stderr during an action.
--
-- Hoogle's library API writes progress text to stdout which would corrupt
-- the MCP JSON-RPC stream. We redirect stdout to stderr (so it's still
-- visible for debugging) and restore it after.
withSilencedStdout :: IO a -> IO a
withSilencedStdout action = do
    hFlush stdout
    savedStdout <- hDuplicate stdout
    hDuplicateTo stderr stdout
    result <- action
    hFlush stdout
    hDuplicateTo savedStdout stdout
    pure result
