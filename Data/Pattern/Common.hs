-----------------------------------------------------------------------------
-- |
-- Module:      Data.Pattern.Common
-- License:     BSD3
-- Maintainer:  Brent Yorgey <byorgey@cis.upenn.edu>
-- Stability:   experimental
-- Portability: non-portable (see .cabal)
--
-- Common pattern combinators.
-----------------------------------------------------------------------------


module Data.Pattern.Common (
  -- * Basic patterns
  var, __, failp, (/\), (\/), view, tryView,
  -- * Non-binding patterns
  is, cst,
  -- * Anonymous matching
  elim,
  -- * Monadic matching
  mmatch,
  -- * Smart constructors for patterns
  -- | Build patterns from a selector function.
  mk0, mk1, mk2, mk3, mk4, mk5,
  -- * Tuple patterns
  tup0, tup1, tup2, tup3, tup4, tup5,
  -- * @Maybe@ patterns
  nothing, just,
  -- * @Either@ patterns
  left, right,
  -- * List patterns
  nil, cons, filterp
 ) where

import Data.Pattern.Base

import Control.Applicative
import Control.Monad
import qualified Data.Foldable as F
import qualified Data.Traversable as T

import Data.Maybe

-- XXX todo: add examples of each combinator!

-- | Variable pattern: always succeeds, and binds the value to a variable.
var :: Pattern (a :*: Nil) a
var = Pattern (Just . oneT)

-- | Wildcard pattern: always succeeds. (This is written as two underscores.)
__ :: Pat0 a
__ = is (const True)

-- | Failure pattern: never succeeds.
failp :: Pat0 a
failp = is (const False)

-- | Conjunctive (and) pattern: matches a value against two patterns,
--   and succeeds only if both succeed, binding variables from both.
--
-- @(/\\) = 'mk2' (\\a -> Just (a,a))@
(/\) :: Pat2 a a a
(/\) = mk2 (\a -> Just (a,a))

-- | Disjunctive (or) pattern: matches a value against the first
--   pattern, or against the second pattern if the first one fails.
(\/) :: Pattern as a -> Pattern as a -> Pattern as a
(Pattern l) \/ (Pattern r) = Pattern (\a -> l a `mplus` r a)

-- | View pattern: do some computation, then pattern match on the
--   result.
view :: (a -> b) -> Pat1 b a
view f = mk1 (Just . f)

-- | Partial view pattern: do some (possibly failing) computation,
--   then pattern match on the result if the computation is successful.
--   Note that 'tryView' is a synonym for 'mk1'.
tryView :: (a -> Maybe b) -> Pat1 b a
tryView = mk1

-- | @elim = flip 'match'@
--
-- Useful for anonymous matching (or for building \"eliminators\",
-- like 'maybe' and 'either'). For example:
--
-- > either withLeft withRight = elim $
-- >              left  var ->> withLeft
-- >          <|> right var ->> withRight
elim :: Clause a r -> a -> r
elim = flip match

-- | @mmatch m p = m >>= 'elim' p@
--
-- Useful for applicative-looking monadic pattern matching, as in
--
-- > ex7 :: IO ()
-- > ex7 = mmatch getLine $
-- >       cst "" ->> return ()
-- >   <|> var    ->> putStrLn . ("You said " ++)
mmatch :: (Monad m) => m a -> Clause a (m b) -> m b
mmatch m p = m >>= elim p

-- | \"Predicate pattern\". 'mk0' but with 'Bool' instead of @'Maybe' ()@.
-- Succeeds if function yields 'True', fails otherwise.
--
-- Can be used with @('/\')@ for some uses similar to pattern guards:
--
-- @match a $
--      left (var /\\ is even) ->> id
--  ||| left __               ->> const 0
--  ||| right __              ->> const 1@
is :: (a -> Bool) -> Pat0 a
is g = mk0 (\a -> if g a then Just () else Nothing)

-- | \"Constant patterns\": tests for equality to the given constant.
-- @cst x = is (==x)@
cst :: (Eq a) => a -> Pat0 a
cst x = is (==x)

-- | Matches the 'Left' of an 'Either'.
left :: Pat1 a (Either a b)
left = mk1 (either Just (const Nothing))

-- | Matches the 'Right' of an 'Either'.
right :: Pat1 b (Either a b)
right = mk1 (either (const Nothing) Just)

-- | Matches @Nothing@.
nothing :: Pat0 (Maybe a)
nothing = is isNothing

-- | Matches @Just@.
just :: Pat1 a (Maybe a)
just = mk1 id

-- | Matches the empty list.
nil :: Pat0 [a]
nil = is null

-- | Matches a cons.
cons :: Pat2 a [a] [a]
cons = mk2 (\l -> case l of { (x:xs) -> Just (x,xs); _ -> Nothing })


-- XXX use (Tup vs :*: Nil) or something like that instead of (Map [] vs)?

-- | @pfilter p@ matches every element of a 'F.Foldable' data structure
--   against the pattern @p@, discarding elements that do not match.
--   From the matching elements, binds a list of values corresponding
--   to each pattern variable.
--
--   For example, XXX
--
pfilter :: (Distribute vs, F.Foldable t) => Pattern vs a -> Pattern (Map [] vs) (t a)
pfilter (Pattern p) = Pattern $ Just . distribute . catMaybes . map p . F.toList

-- | @pmap p@ matches every element of a 'T.Traversable' data
--   structure against the pattern @p@.  The entire match fails if any
--   of the elements fail to match @p@.  If all the elements match,
--   binds a @t@-structure full of bound values corresponding to each
--   variable bound in @p@.
--
--   For example, XXX
pmap :: (Distribute vs, T.Traversable t) => Pattern vs a -> Pattern (Map t vs) (t a)
pmap (Pattern p) = Pattern $ fmap distribute . T.traverse p

-- | @pfoldr p f b@ matches every element of a 'F.Foldable' data
--   structure against the pattern @p@, discarding elements that do
--   not match.  Folds over the bindings produced by the matching
--   elements to produce a summary value.
--
--   For example,
--
--   The same functionality could be achieved by matching with
--   @pfilter p@ and then appropriately combining and folding the
--   resulting lists of bound values.  In particular, if @p@ binds
--   only one value we have
--
-- > match t (pfoldr p f b ->> id) === match t (pfilter p ->> foldr f b)
--
--   However, when @p@ binds more than one value, it can be convenient
--   to be able to process the bindings from each match together,
--   rather than having to deal with them once they are separated out
--   into separate lists.
pfoldr :: (F.Foldable t, Functor t) => Pattern vs a -> (Fun vs (b -> b)) -> b -> Pattern (b :*: Nil) (t a)
pfoldr (Pattern p) f b = Pattern $ Just . oneT . foldr (flip runTuple f) b . catMaybes . F.toList . fmap p

-- | \"0-tuple pattern\". A strict match on the @()@.
tup0 :: Pat0 ()
tup0 = mk0 (\() -> Just ())

-- | \"1-tuple pattern\". Rather useless.
tup1 :: Pat1 a a
tup1 = mk1 Just

-- | \"2-tuple pattern\"
tup2 :: Pat2 a b (a,b)
tup2 (Pattern pa) (Pattern pb) = Pattern (\(a,b) -> (<>) <$> pa a <*> pb b)

-- | \"3-tuple pattern\"
tup3 :: Pat3 a b c (a,b,c)
tup3 (Pattern pa) (Pattern pb) (Pattern pc) =
   Pattern (\(a,b,c) -> (<>) <$> pa a <*> ((<>) <$> pb b <*> pc c))

-- | \"4-tuple pattern\"
tup4 :: Pat4 a b c d (a,b,c,d)
tup4 (Pattern pa) (Pattern pb) (Pattern pc) (Pattern pd) =
   Pattern (\(a,b,c,d) -> (<>) <$> pa a <*> ((<>) <$> pb b <*> ((<>) <$> pc c <*> pd d)))

-- | \"5-tuple pattern\"
tup5 :: Pat5 a b c d e (a,b,c,d,e)
tup5 (Pattern pa) (Pattern pb) (Pattern pc) (Pattern pd) (Pattern pe) =
   Pattern (\(a,b,c,d,e) -> (<>) <$> pa a <*> ((<>) <$> pb b <*> ((<>) <$> pc c <*> ((<>) <$> pd d <*> pe e))))


mk0 :: (a -> Maybe ()) -> Pat0 a
mk0 g = Pattern (fmap (const zeroT) . g)

mk1 :: (a -> Maybe b) -> Pat1 b a
mk1 g (Pattern p) = Pattern (\a -> g a >>= p)

mk2 :: (a -> Maybe (b,c)) -> Pat2 b c a
mk2 g b c = mk1 g (tup2 b c)

mk3 :: (a -> Maybe (b,c,d)) -> Pat3 b c d a
mk3 g b c d = mk1 g (tup3 b c d)

mk4 :: (a -> Maybe (b,c,d,e)) -> Pat4 b c d e a
mk4 g b c d e = mk1 g (tup4 b c d e)

mk5 :: (a -> Maybe (b,c,d,e,f)) -> Pat5 b c d e f a
mk5 g b c d e f = mk1 g (tup5 b c d e f)
