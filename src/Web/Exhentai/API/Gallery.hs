{-# LANGUAGE StrictData #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Gallery API.
module Web.Exhentai.API.Gallery
  ( Gallery (..),
    GalleryInfo (..),
    Visibility (..),
    GalleryCategory (..),
    TagCategory (..),
    allGalleryCats,
    fetchGalleryInfo,

    -- ** Internal API
    parseGalleryLink,
    parseGallery,
  )
where

import Control.Effect
import Control.Effect.Bracket
import Control.Effect.Error
import Control.Effect.Exh
import Control.Monad
import Data.Maybe
import Data.Set (Set, fromList)
import Data.Text (Text, pack, strip)
import Data.Time
import Data.Void
import Network.HTTP.Client hiding (Cookie)
import Optics.Core
import Optics.TH
import Text.Megaparsec hiding (token)
import Text.Megaparsec.Char.Lexer
import Text.XML
import Text.XML.Optics
import Web.Exhentai.Errors
import qualified Web.Exhentai.Parsing.Gallery as G
import Web.Exhentai.Utils
import Prelude hiding (length)
import qualified Prelude as P

data Gallery = Gallery
  { galleryId :: {-# UNPACK #-} !Int,
    token :: {-# UNPACK #-} !Text
  }
  deriving (Show, Eq)

toGalleryLink :: Gallery -> Text
toGalleryLink Gallery {..} = "https://exhentai.org/g/" <> pack (show galleryId) <> "/" <> token <> "/"

parseGalleryLink :: Text -> Maybe Gallery
parseGalleryLink = parseMaybe galleryLink
  where
    galleryLink :: Parser Gallery
    galleryLink = do
      _ <- chunk "https://exhentai.org/g/"
      galleryId <- decimal
      _ <- single '/'
      token <- takeWhile1P Nothing (/= '/')
      _ <- optional $ single '/'
      pure Gallery {..}

data TagCategory
  = Language
  | Parody
  | Character
  | Group
  | Artist
  | Male
  | Female
  | Misc'
  | Reclass
  deriving (Show, Eq, Enum)

readTagCat :: Text -> Maybe TagCategory
readTagCat "language:" = Just Language
readTagCat "parody:" = Just Parody
readTagCat "character:" = Just Character
readTagCat "group:" = Just Group
readTagCat "artist:" = Just Artist
readTagCat "male:" = Just Male
readTagCat "female:" = Just Female
readTagCat "misc:" = Just Misc'
readTagCat "reclass:" = Just Reclass
readTagCat _ = Nothing

data GalleryCategory
  = Misc
  | Doujinshi
  | Manga
  | ArtistCG
  | GameCG
  | ImageSet
  | Cosplay
  | AsianPorn
  | NonH
  | Western
  | Private
  deriving (Show, Eq, Ord, Enum, Bounded)

allGalleryCats :: Set GalleryCategory
allGalleryCats = fromList [Misc .. Private]

readCat :: Text -> Maybe GalleryCategory
readCat "Doujinshi" = Just Doujinshi
readCat "Manga" = Just Manga
readCat "Artist CG" = Just ArtistCG
readCat "Game CG" = Just GameCG
readCat "Non-H" = Just NonH
readCat "Image Set" = Just ImageSet
readCat "Western" = Just Western
readCat "Cosplay" = Just Cosplay
readCat "Misc" = Just Misc
readCat "Private" = Just Private
readCat "Asian Porn" = Just AsianPorn
readCat _ = Nothing

-- | Information about a gallery
data GalleryInfo = GalleryInfo
  { title :: {-# UNPACK #-} Text,
    previewLink :: {-# UNPACK #-} Text,
    category :: GalleryCategory,
    jaTitle :: Maybe Text,
    uploader :: {-# UNPACK #-} Text,
    rating :: {-# UNPACK #-} Double,
    ratingCount :: {-# UNPACK #-} Int,
    favoriteCount :: {-# UNPACK #-} Int,
    tags :: [(TagCategory, [Text])],
    uploadTime :: {-# UNPACK #-} UTCTime,
    newer :: Maybe Gallery,
    parent :: Maybe Gallery,
    visibility :: Visibility,
    language :: {-# UNPACK #-} Text,
    length :: {-# UNPACK #-} Int,
    archiverLink :: {-# UNPACK #-} Text,
    torrentLink :: {-# UNPACK #-} Text
  }
  deriving (Show, Eq)

data Visibility
  = Visible
  | Replaced
  | Expunged
  | Unknown {-# UNPACK #-} Text
  deriving (Show, Eq)

readVisibility :: Text -> Visibility
readVisibility "Yes" = Visible
readVisibility "No (Replaced)" = Replaced
readVisibility "No (Expunged)" = Expunged
readVisibility v = Unknown v

-- | Extract all gallery informations from a document
parseGallery :: Document -> Either Text GalleryInfo
parseGallery d = do
  title <- annotate "title" $ d ^?: G.enTitle
  previewLink <- annotate "preview link" $ d ^?: G.previewStr >>= parsePreviewLink
  let jaTitle = d ^?: G.jaTitle
  category <- annotate "category" $ d ^?: G.category >>= readCat
  uploader <- annotate "uploader" $ d ^?: G.uploader
  rating <- annotate "average rating" $ d ^?: G.averageRating >>= parseAverageRating
  ratingCount <- annotate "rating count" $ d ^?: G.ratingCount
  archiverLink <- annotate "archiver link" $ d ^?: G.popupLink >>= parsePopUpLink
  torrentLink <- annotate "torrent link" $ case d ^..: G.popupLink of (_ : tl : _) -> Just tl; _ -> Nothing
  let newer = d ^?: G.newer >>= parseGalleryLink
  case d ^..: G.metaValues of
    (time : parn : vis : lang : _ : len : fav : _) -> do
      uploadTime <- annotate "upload time" $ time ^? pre lower % _Content >>= parseUploadTime
      let parent = parn ^? pre lower % _Element % attr "href" >>= parseGalleryLink
      (readVisibility -> visibility) <- annotate "visibility" $ vis ^? pre lower % _Content
      (strip -> language) <- annotate "language" $ lang ^? pre lower % _Content
      length <- annotate "length" $ len ^? pre lower % _Content >>= parseGalleryLength
      let cats = mapMaybe readTagCat (d ^..: G.tagCategory)
      let tags' = map (^.. G.tags) $ d ^..: G.tagsByCategory
      unless (P.length cats == P.length tags') $ Left "length of categories and tags does not match"
      let tags = zip cats tags'
      favoriteCount <- annotate "favorite count" $ fav ^? pre lower % _Content >>= parseFavoriteCount
      pure GalleryInfo {..}
    _ -> Left "extracting metadata"

-- | Fetch a gallery's 'GalleryInfo'
fetchGalleryInfo ::
  Effs '[Http, Error HttpException, Cookie, ConduitIO, Bracket, Throw ExhentaiError] m =>
  Gallery ->
  m GalleryInfo
fetchGalleryInfo g = do
  let url = toGalleryLink g
  d <- htmlRequest' url
  case parseGallery d of
    Left err -> throw $ XMLParseFailure err url
    Right info -> pure info
{-# INLINEABLE fetchGalleryInfo #-}

--------------------------------------------------
--

type Parser = Parsec Void Text

parsePopUpLink :: Text -> Maybe Text
parsePopUpLink = parseMaybe archiverLink
  where
    archiverLink :: Parser Text
    archiverLink = do
      _ <- chunk "return popUp('"
      url <- takeWhile1P Nothing (/= '\'')
      _ <- takeRest
      pure url

parseAverageRating :: Text -> Maybe Double
parseAverageRating = parseMaybe averageRating
  where
    averageRating :: Parser Double
    averageRating =
      ( do
          _ <- chunk "Average: "
          float
      )
        <|> (chunk "Not Yet Rated" >> pure 0)

parseGalleryLength :: Text -> Maybe Int
parseGalleryLength = parseMaybe galleryLength
  where
    galleryLength :: Parser Int
    galleryLength = do
      d <- decimal
      _ <- chunk " pages"
      pure d

parseFavoriteCount :: Text -> Maybe Int
parseFavoriteCount = parseMaybe favoriteCount
  where
    once = do
      _ <- chunk "Once"
      pure 1
    never = do
      _ <- chunk "Never"
      pure 0
    favoriteCount :: Parser Int
    favoriteCount =
      ( do
          d <- decimal
          _ <- chunk " times"
          pure d
      )
        <|> once
        <|> never

parsePreviewLink :: Text -> Maybe Text
parsePreviewLink = parseMaybe previewLink
  where
    previewLink :: Parser Text
    previewLink = do
      _ <- many $ do
        notFollowedBy urlOpening
        anySingle
      _ <- urlOpening
      url <- takeWhile1P Nothing (/= ')')
      _ <- takeRest
      pure url
    urlOpening :: Parser Text
    urlOpening = chunk "url("

makeFieldLabelsWith noPrefixFieldLabels ''GalleryInfo
makePrismLabels ''TagCategory
makePrismLabels ''GalleryCategory
makePrismLabels ''Visibility
