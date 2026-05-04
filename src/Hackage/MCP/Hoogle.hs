{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Hackage.MCP.Hoogle (searchHoogle, HoogleResult) where

import Control.Exception (SomeException, catch)
import Data.Aeson (FromJSON (..), ToJSON, withObject, (.:))
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Network.HTTP.Conduit (httpLbs, newManager, parseRequest, tlsManagerSettings, responseBody)
import Network.HTTP.Types.URI (urlEncode)
import qualified Data.ByteString.Char8 as BS

-- | Hoogle search result item
data HoogleResult = HoogleResult
  { docs :: Text,
    item :: Text,
    module_ :: ModuleInfo,
    package :: PackageInfo,
    type_ :: Text,
    url :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON HoogleResult

instance FromJSON HoogleResult where
  parseJSON = withObject "HoogleResult" $ \v ->
    HoogleResult
      <$> v .: "docs"
      <*> v .: "item"
      <*> v .: "module"
      <*> v .: "package"
      <*> v .: "type"
      <*> v .: "url"

-- | Module information from Hoogle result
data ModuleInfo = ModuleInfo
  { moduleName :: Text,
    moduleUrl :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON ModuleInfo

instance FromJSON ModuleInfo where
  parseJSON = withObject "ModuleInfo" $ \v ->
    ModuleInfo
      <$> v .: "name"
      <*> v .: "url"

-- | Package information from Hoogle result
data PackageInfo = PackageInfo
  { packageName :: Text,
    packageUrl :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON PackageInfo

instance FromJSON PackageInfo where
  parseJSON = withObject "PackageInfo" $ \v ->
    PackageInfo
      <$> v .: "name"
      <*> v .: "url"

-- | Search Hoogle with a query and return JSON results as Text
searchHoogle :: Text -> IO (Either Text Text)
searchHoogle query = do
  let encodedQuery = urlEncode False (BS.pack $ T.unpack query)
  let url = "https://hoogle.haskell.org/?hoogle=" <> BS.unpack encodedQuery <> "&mode=json"
  result <- tryRequest url
  case result of
    Left err -> return $ Left err
    Right body -> return $ Right (TE.decodeUtf8 $ BL.toStrict body)
  where
    tryRequest :: String -> IO (Either Text BL.ByteString)
    tryRequest urlStr = do
      eitherReq <- catch (Right <$> parseRequest urlStr) handleParseError
      case eitherReq of
        Left err -> return $ Left err
        Right req -> do
          manager <- newManager tlsManagerSettings
          eitherResp <- catch (Right <$> httpLbs req manager) handleHttpError
          case eitherResp of
            Left err -> return $ Left err
            Right resp -> return $ Right (responseBody resp)

    handleParseError :: SomeException -> IO (Either Text a)
    handleParseError err = return $ Left $ "Failed to parse request: " <> T.pack (show err)

    handleHttpError :: SomeException -> IO (Either Text a)
    handleHttpError err = return $ Left $ "HTTP request failed: " <> T.pack (show err)

