module Main where

import Data.Maybe
import Test.Hspec
import Text.HTML.DOM
import qualified Web.Exhentai.Parsing.Gallery as G
import Web.Exhentai.Parsing.Image
import qualified Web.Exhentai.Parsing.Search as S
import Web.Exhentai.Utils
import Prelude hiding (readFile)

main :: IO ()
main = do
  image <- readFile "test/Image.html"
  galleryMpv <- readFile "test/Gallery-MPV.html"
  galleryNonMpv <- readFile "test/Gallery-NonMPV.html"
  search <- readFile "test/Search-Compat.html"
  searchLong <- readFile "test/Search-Long.html"
  hspec $ do
    describe "Image.imageSrc" $ do
      it "should return the image source link" $ do
        (image ^?: imageSrc) `shouldSatisfy` isJust

    describe "Image.nextPage" $ do
      it "should return the link to the next page" $ do
        (image ^?: nextPage) `shouldSatisfy` isJust

    describe "Gallery.enTitle" $ do
      it "should return the title of the gallery" $ do
        (galleryMpv ^?: G.enTitle) `shouldSatisfy` isJust
        (galleryNonMpv ^?: G.enTitle) `shouldSatisfy` isJust

    describe "Gallery.jaTitle" $ do
      it "should return the original title of the gallery" $ do
        (galleryMpv ^?: G.jaTitle) `shouldSatisfy` isJust
        (galleryNonMpv ^?: G.jaTitle) `shouldSatisfy` isJust

    describe "Gallery.category" $ do
      it "should return the category of the gallery" $ do
        (galleryMpv ^?: G.category) `shouldSatisfy` isJust
        (galleryNonMpv ^?: G.category) `shouldSatisfy` isJust

    describe "Gallery.uploader" $ do
      it "should return the uploader of the gallery" $ do
        (galleryMpv ^?: G.uploader) `shouldSatisfy` isJust
        (galleryNonMpv ^?: G.uploader) `shouldSatisfy` isJust

    describe "Gallery.ratingCount" $ do
      it "should return the total rating count of the gallery" $ do
        (galleryMpv ^?: G.ratingCount) `shouldSatisfy` isJust
        (galleryNonMpv ^?: G.ratingCount) `shouldSatisfy` isJust

    describe "Gallery.averageRating" $ do
      it "should return the average rating of the gallery" $ do
        (galleryMpv ^?: G.averageRating) `shouldSatisfy` isJust
        (galleryNonMpv ^?: G.averageRating) `shouldSatisfy` isJust

    describe "Search.pages" $ do
      it "should return available page range" $ do
        (search ^?: S.pages) `shouldSatisfy` isJust
        (searchLong ^?: S.pages) `shouldSatisfy` isJust
