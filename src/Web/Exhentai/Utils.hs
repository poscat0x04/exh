{-# LANGUAGE RankNTypes #-}

module Web.Exhentai.Utils where

import Control.Lens
import Data.Maybe (isNothing)
import Data.Text (Text)
import Text.XML
import Text.XML.Lens

attributeSatisfies' :: Name -> (Maybe Text -> Bool) -> Traversal' Element Element
attributeSatisfies' n p = filtered (p . preview (attrs . ix n))

withoutAttribute :: Name -> Traversal' Element Element
withoutAttribute = flip attributeSatisfies' isNothing

lower :: Traversal' Element Node
lower = nodes . traverse

deepen :: Traversal' Element Element
deepen = lower . _Element

body :: Traversal' Document Element
body = root . named "html" . deepen . named "body"

div :: Traversal' Element Element
div = named "div"

h1 :: Traversal' Element Element
h1 = named "h1"

a :: Traversal' Element Element
a = named "a"

table :: Traversal' Element Element
table = named "table"

tr :: Traversal' Element Element
tr = named "tr"

td :: Traversal' Element Element
td = named "td"

cl :: Text -> Traversal' Element Element
cl = attributeIs "class"

id :: Text -> Traversal' Element Element
id = attributeIs "id"