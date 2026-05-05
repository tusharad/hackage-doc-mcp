module Hackage.MCP.Fetch (fetchHackageHtmlPage) where

import Control.Exception (SomeException, catch)
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Simple
import Network.HTTP.Types.Status (statusCode)

fetchHackageHtmlPage :: Text -> IO (Either Text Text)
fetchHackageHtmlPage urlText
    | T.null (T.strip urlText) = pure $ Left "URL cannot be empty"
    | otherwise = do
        let url = T.unpack urlText
        eReq <- catch (Right <$> parseRequest url) handleParseError
        case eReq of
            Left err -> pure $ Left err
            Right req -> do
                eitherResp <- catch (Right <$> httpLbs req) handleHttpError
                case eitherResp of
                    Left err -> pure $ Left err
                    Right resp -> do
                        let code = statusCode (getResponseStatus resp)
                        if code >= 200 && code < 300
                            then case TE.decodeUtf8' (BL.toStrict (getResponseBody resp)) of
                                Left decodeErr -> pure $ Left $ "Failed to decode response body: " <> T.pack (show decodeErr)
                                Right html -> pure $ Right html
                            else pure $ Left $ "Unexpected HTTP status: " <> T.pack (show code)
  where
    handleParseError :: SomeException -> IO (Either Text a)
    handleParseError err = pure $ Left $ "Failed to parse request: " <> T.pack (show err)

    handleHttpError :: SomeException -> IO (Either Text a)
    handleHttpError err = pure $ Left $ "HTTP request failed: " <> T.pack (show err)
