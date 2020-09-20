{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP          #-}
{-# LANGUAGE GADTs        #-}
{-# LANGUAGE RankNTypes   #-}

-- This library emulates Data.ByteString.Lazy but includes a monadic element
-- and thus at certain points uses a `Stream`/`FreeT` type in place of lists.

-- |
-- Module      : Data.ByteString.Streaming
-- Copyright   : (c) Don Stewart 2006
--               (c) Duncan Coutts 2006-2011
--               (c) Michael Thompson 2015
-- License     : BSD-style
--
-- Maintainer  : what_is_it_to_do_anything@yahoo.com
-- Stability   : experimental
-- Portability : portable
--
-- See the simple examples of use <https://gist.github.com/michaelt/6c6843e6dd8030e95d58 here>
-- and the @ghci@ examples especially in "Data.ByteString.Streaming.Char8".
-- We begin with a slight modification of the documentation to "Data.ByteString.Lazy":
--
-- A time and space-efficient implementation of effectful byte streams using a
-- stream of packed 'Word8' arrays, suitable for high performance use, both in
-- terms of large data quantities, or high speed requirements. Streaming
-- ByteStrings are encoded as streams of strict chunks of bytes.
--
-- A key feature of streaming ByteStrings is the means to manipulate large or
-- unbounded streams of data without requiring the entire sequence to be
-- resident in memory. To take advantage of this you have to write your
-- functions in a streaming style, e.g. classic pipeline composition. The
-- default I\/O chunk size is 32k, which should be good in most circumstances.
--
-- Some operations, such as 'concat', 'append', 'reverse' and 'cons', have
-- better complexity than their "Data.ByteString" equivalents, due to
-- optimisations resulting from the list spine structure. For other operations
-- streaming, like lazy, ByteStrings are usually within a few percent of strict
-- ones.
--
-- This module is intended to be imported @qualified@, to avoid name clashes
-- with "Prelude" functions. eg.
--
-- > import qualified Data.ByteString.Streaming as Q
--
-- Original GHC implementation by Bryan O\'Sullivan. Rewritten to use
-- 'Data.Array.Unboxed.UArray' by Simon Marlow. Rewritten to support slices and
-- use 'Foreign.ForeignPtr.ForeignPtr' by David Roundy. Rewritten again and
-- extended by Don Stewart and Duncan Coutts. Lazy variant by Duncan Coutts and
-- Don Stewart. Streaming variant by Michael Thompson, following the ideas of
-- Gabriel Gonzales' pipes-bytestring.
module Data.ByteString.Streaming (
    -- * The @ByteString@ type
    ByteString

    -- * Introducing and eliminating 'ByteString's
    , empty            -- empty :: ByteString m ()
    , singleton        -- singleton :: Monad m => Word8 -> ByteString m ()
    , pack             -- pack :: Monad m => Stream (Of Word8) m r -> ByteString m r
    , unpack           -- unpack :: Monad m => ByteString m r -> Stream (Of Word8) m r
    , fromLazy         -- fromLazy :: Monad m => ByteString -> ByteString m ()
    , toLazy           -- toLazy :: Monad m => ByteString m () -> m ByteString
    , toLazy_          -- toLazy' :: Monad m => ByteString m () -> m (Of ByteString r)
    , fromChunks       -- fromChunks :: Monad m => Stream (Of ByteString) m r -> ByteString m r
    , toChunks         -- toChunks :: Monad m => ByteString m r -> Stream (Of ByteString) m r
    , fromStrict       -- fromStrict :: ByteString -> ByteString m ()
    , toStrict         -- toStrict :: Monad m => ByteString m () -> m ByteString
    , toStrict_        -- toStrict_ :: Monad m => ByteString m r -> m (Of ByteString r)
    , effects
    , copy
    , drained
    , mwrap
    , distribute       -- distribute :: ByteString (t m) a -> t (ByteString m) a


    -- * Transforming ByteStrings
    , map              -- map :: Monad m => (Word8 -> Word8) -> ByteString m r -> ByteString m r
    , intercalate      -- intercalate :: Monad m => ByteString m () -> Stream (ByteString m) m r -> ByteString m r
    , intersperse      -- intersperse :: Monad m => Word8 -> ByteString m r -> ByteString m r

    -- * Basic interface
    , cons             -- cons :: Monad m => Word8 -> ByteString m r -> ByteString m r
    , cons'            -- cons' :: Word8 -> ByteString m r -> ByteString m r
    , snoc
    , append           -- append :: Monad m => ByteString m r -> ByteString m s -> ByteString m s
    , filter           -- filter :: (Word8 -> Bool) -> ByteString m r -> ByteString m r
    , uncons           -- uncons :: Monad m => ByteString m r -> m (Either r (Word8, ByteString m r))
    , nextByte -- nextByte :: Monad m => ByteString m r -> m (Either r (Word8, ByteString m r))
    , denull

    -- * Substrings

    -- ** Breaking strings
    , break            -- break :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r)
    , drop             -- drop :: Monad m => GHC.Int.Int64 -> ByteString m r -> ByteString m r
    , dropWhile
    , group            -- group :: Monad m => ByteString m r -> Stream (ByteString m) m r
    , groupBy
    , span             -- span :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r)
    , splitAt          -- splitAt :: Monad m => GHC.Int.Int64 -> ByteString m r -> ByteString m (ByteString m r)
    , splitWith        -- splitWith :: Monad m => (Word8 -> Bool) -> ByteString m r -> Stream (ByteString m) m r
    , take             -- take :: Monad m => GHC.Int.Int64 -> ByteString m r -> ByteString m ()
    , takeWhile        -- takeWhile :: (Word8 -> Bool) -> ByteString m r -> ByteString m ()

    -- ** Breaking into many substrings
    , split            -- split :: Monad m => Word8 -> ByteString m r -> Stream (ByteString m) m r

    -- ** Special folds

    , concat          -- concat :: Monad m => Stream (ByteString m) m r -> ByteString m r

    -- * Builders

    , toStreamingByteStringWith
    , toStreamingByteString
    , toBuilder
    , concatBuilders

    -- * Building ByteStrings

    -- ** Infinite ByteStrings
    , repeat           -- repeat :: Word8 -> ByteString m r
    , iterate          -- iterate :: (Word8 -> Word8) -> Word8 -> ByteString m r
    , cycle            -- cycle :: Monad m => ByteString m r -> ByteString m s

    -- ** Unfolding ByteStrings
    , unfoldM          -- unfoldr :: (a -> m (Maybe (Word8, a))) -> m a -> ByteString m ()
    , unfoldr          -- unfold  :: (a -> Either r (Word8, a)) -> a -> ByteString m r
    , reread

    -- *  Folds, including support for `Control.Foldl`
    , foldr            -- foldr :: Monad m => (Word8 -> a -> a) -> a -> ByteString m () -> m a
    , fold             -- fold :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m () -> m b
    , fold_            -- fold' :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m r -> m (b, r)

    , head
    , head_
    , last
    , last_
    , length
    , length_
    , null
    , null_
    , nulls
    , testNull
    , count
    , count_
    -- * I\/O with 'ByteString's

    -- ** Standard input and output
    , getContents      -- getContents :: ByteString IO ()
    , stdin            -- stdin :: ByteString IO ()
    , stdout           -- stdout :: ByteString IO r -> IO r
    , interact         -- interact :: (ByteString IO () -> ByteString IO r) -> IO r

    -- ** Files
    , readFile         -- readFile :: FilePath -> ByteString IO ()
    , writeFile        -- writeFile :: FilePath -> ByteString IO r -> IO r
    , appendFile       -- appendFile :: FilePath -> ByteString IO r -> IO r

    -- ** I\/O with Handles
    , fromHandle       -- fromHandle :: Handle -> ByteString IO ()
    , toHandle         -- toHandle :: Handle -> ByteString IO r -> IO r
    , hGet             -- hGet :: Handle -> Int -> ByteString IO ()
    , hGetContents     -- hGetContents :: Handle -> ByteString IO ()
    , hGetContentsN    -- hGetContentsN :: Int -> Handle -> ByteString IO ()
    , hGetN            -- hGetN :: Int -> Handle -> Int -> ByteString IO ()
    , hGetNonBlocking  -- hGetNonBlocking :: Handle -> Int -> ByteString IO ()
    , hGetNonBlockingN -- hGetNonBlockingN :: Int -> Handle -> Int -> ByteString IO ()
    , hPut             -- hPut :: Handle -> ByteString IO r -> IO r
--    , hPutNonBlocking  -- hPutNonBlocking :: Handle -> ByteString IO r -> ByteString IO r
    -- * Etc.
    , zipWithStream    -- zipWithStream :: Monad m => (forall x. a -> ByteString m x -> ByteString m x) -> [a] -> Stream (ByteString m) m r -> Stream (ByteString m) m r

    -- * Simple chunkwise operations
    , unconsChunk
    , nextChunk
    , chunk
    , foldrChunks
    , foldlChunks
    , chunkFold
    , chunkFoldM
    , chunkMap
    , chunkMapM
    , chunkMapM_
  ) where

import           Prelude hiding
    (all, any, appendFile, break, concat, concatMap, cycle, drop, dropWhile,
    elem, filter, foldl, foldl1, foldr, foldr1, getContents, getLine, head,
    init, interact, iterate, last, length, lines, map, maximum, minimum,
    notElem, null, putStr, putStrLn, readFile, repeat, replicate, reverse,
    scanl, scanl1, scanr, scanr1, span, splitAt, tail, take, takeWhile,
    unlines, unzip, writeFile, zip, zipWith)

import qualified Data.ByteString as P (ByteString)
import qualified Data.ByteString as B
import           Data.ByteString.Builder.Internal hiding
    (append, defaultChunkSize, empty, hPut)
import qualified Data.ByteString.Internal as B
import qualified Data.ByteString.Lazy.Internal as BI
import qualified Data.ByteString.Unsafe as B

import           Data.ByteString.Streaming.Internal
import           Streaming hiding (concats, distribute, unfold)
import           Streaming.Internal (Stream(..))
import qualified Streaming.Prelude as SP

import           Control.Monad (forever)
import           Control.Monad.Trans.Resource
import           Data.Int (Int64)
import qualified Data.List as L
import           Data.Word (Word8)
import           Foreign.ForeignPtr (withForeignPtr)
import           Foreign.Ptr
import           Foreign.Storable
import           System.IO (Handle, IOMode(..), hClose, openBinaryFile)
import qualified System.IO as IO (stdin, stdout)
import           System.IO.Error (illegalOperationErrorType, mkIOError)

-- | /O(n)/ Concatenate a stream of byte streams.
concat :: Monad m => Stream (ByteString m) m r -> ByteString m r
concat x = destroy x join Go Empty
{-# INLINE concat #-}

-- | Given a byte stream on a transformed monad, make it possible to \'run\'
-- transformer.
distribute
  :: (Monad m, MonadTrans t, MFunctor t, Monad (t m), Monad (t (ByteString m)))
  => ByteString (t m) a -> t (ByteString m) a
distribute ls = dematerialize ls
             return
             (\bs x -> join $ lift $ Chunk bs (Empty x) )
             (join . hoist (Go . fmap Empty))
{-# INLINE distribute #-}

-- | Perform the effects contained in an effectful bytestring, ignoring the bytes.
effects :: Monad m => ByteString m r -> m r
effects bs = case bs of
  Empty r      -> return r
  Go m         -> m >>= effects
  Chunk _ rest -> effects rest
{-# INLINABLE effects #-}

-- | Perform the effects contained in the second in an effectful pair of
-- bytestrings, ignoring the bytes. It would typically be used at the type
--
-- > ByteString m (ByteString m r) -> ByteString m r
drained :: (Monad m, MonadTrans t, Monad (t m)) => t m (ByteString m r) -> t m r
drained t = t >>= lift . effects

-- -----------------------------------------------------------------------------
-- Introducing and eliminating 'ByteString's

-- | /O(1)/ The empty 'ByteString' -- i.e. @return ()@ Note that @ByteString m w@ is
-- generally a monoid for monoidal values of @w@, like @()@.
empty :: ByteString m ()
empty = Empty ()
{-# INLINE empty #-}

-- | /O(1)/ Yield a 'Word8' as a minimal 'ByteString'.
singleton :: Monad m => Word8 -> ByteString m ()
singleton w = Chunk (B.singleton w)  (Empty ())
{-# INLINE singleton #-}

-- | /O(n)/ Convert a monadic stream of individual 'Word8's into a packed byte stream.
pack :: Monad m => Stream (Of Word8) m r -> ByteString m r
pack = packBytes
{-# INLINE pack #-}

-- | /O(n)/ Converts a packed byte stream into a stream of individual bytes.
unpack ::  Monad m => ByteString m r -> Stream (Of Word8) m r
unpack = unpackBytes

-- | /O(c)/ Convert a monadic stream of individual strict 'ByteString' chunks
-- into a byte stream.
fromChunks :: Monad m => Stream (Of P.ByteString) m r -> ByteString m r
fromChunks cs = destroy cs (\(bs :> rest) -> Chunk bs rest) Go return
{-# INLINE fromChunks #-}

-- | /O(c)/ Convert a byte stream into a stream of individual strict
-- bytestrings. This of course exposes the internal chunk structure.
toChunks :: Monad m => ByteString m r -> Stream (Of P.ByteString) m r
toChunks bs = dematerialize bs return (\b mx -> Step (b:> mx)) Effect
{-# INLINE toChunks #-}

-- | /O(1)/ Yield a strict 'ByteString' chunk.
fromStrict :: P.ByteString -> ByteString m ()
fromStrict bs | B.null bs = Empty ()
              | otherwise = Chunk bs (Empty ())
{-# INLINE fromStrict #-}

-- | /O(n)/ Convert a byte stream into a single strict 'ByteString'.
--
-- Note that this is an /expensive/ operation that forces the whole monadic
-- ByteString into memory and then copies all the data. If possible, try to
-- avoid converting back and forth between streaming and strict bytestrings.
toStrict_ :: Monad m => ByteString m () -> m B.ByteString
toStrict_ = fmap B.concat . SP.toList_ . toChunks
{-# INLINE toStrict_ #-}

-- | /O(n)/ Convert a monadic byte stream into a single strict 'ByteString',
-- retaining the return value of the original pair. This operation is for use
-- with 'mapped'.
--
-- > mapped R.toStrict :: Monad m => Stream (ByteString m) m r -> Stream (Of ByteString) m r
--
-- It is subject to all the objections one makes to Data.ByteString.Lazy
-- 'toStrict'; all of these are devastating.
toStrict :: Monad m => ByteString m r -> m (Of B.ByteString r)
toStrict bs = do
  (bss :> r) <- SP.toList (toChunks bs)
  return (B.concat bss :> r)
{-# INLINE toStrict #-}

-- |/O(c)/ Transmute a pseudo-pure lazy bytestring to its representation as a
-- monadic stream of chunks.
--
-- >>> Q.putStrLn $ Q.fromLazy "hi"
-- hi
-- >>>  Q.fromLazy "hi"
-- Chunk "hi" (Empty (()))  -- note: a 'show' instance works in the identity monad
-- >>>  Q.fromLazy $ BL.fromChunks ["here", "are", "some", "chunks"]
-- Chunk "here" (Chunk "are" (Chunk "some" (Chunk "chunks" (Empty (())))))
fromLazy :: Monad m => BI.ByteString -> ByteString m ()
fromLazy = BI.foldrChunks Chunk (Empty ())
{-# INLINE fromLazy #-}

-- | /O(n)/ Convert an effectful byte stream into a single lazy 'ByteString'
-- with the same internal chunk structure. See `toLazy` which preserve
-- connectedness by keeping the return value of the effectful bytestring.
toLazy_ :: Monad m => ByteString m r -> m BI.ByteString
toLazy_ bs = dematerialize bs (\_ -> return BI.Empty) (fmap . BI.Chunk) join
{-# INLINE toLazy_ #-}

-- | /O(n)/ Convert an effectful byte stream into a single lazy 'ByteString'
-- with the same internal chunk structure, retaining the original return value.
--
-- This is the canonical way of breaking streaming (`toStrict` and the like are
-- far more demonic). Essentially one is dividing the interleaved layers of
-- effects and bytes into one immense layer of effects, followed by the memory
-- of the succession of bytes.
--
-- Because one preserves the return value, `toLazy` is a suitable argument for
-- 'Streaming.mapped':
--
-- > S.mapped Q.toLazy :: Stream (ByteString m) m r -> Stream (Of L.ByteString) m r
--
-- >>> Q.toLazy "hello"
-- "hello" :> ()
-- >>> S.toListM $ traverses Q.toLazy $ Q.lines "one\ntwo\nthree\nfour\nfive\n"
-- ["one","two","three","four","five",""]  -- [L.ByteString]
toLazy :: Monad m => ByteString m r -> m (Of BI.ByteString r)
toLazy bs0 = dematerialize bs0
                (\r -> return (BI.Empty :> r))
                (\b mx -> do
                      (bs :> x) <- mx
                      return $ BI.Chunk b bs :> x
                      )
                join
{-# INLINE toLazy #-}

-- ---------------------------------------------------------------------
-- Basic interface
--

-- | Test whether a `ByteString` is empty, collecting its return value; to reach
-- the return value, this operation must check the whole length of the string.
--
-- >>> Q.null "one\ntwo\three\nfour\nfive\n"
-- False :> ()
-- >>> Q.null ""
-- True :> ()
-- >>> S.print $ mapped R.null $ Q.lines "yours,\nMeredith"
-- False
-- False
null :: Monad m => ByteString m r -> m (Of Bool r)
null (Empty r)  = return (True :> r)
null (Go m)     = m >>= null
null (Chunk bs rest) = if B.null bs
   then null rest
   else do
     r <- SP.effects (toChunks rest)
     return (False :> r)
{-# INLINABLE null #-}

-- | /O(1)/ Test whether a `ByteString` is empty. The value is of course in the
-- monad of the effects.
--
-- >>>  Q.null "one\ntwo\three\nfour\nfive\n"
-- False
-- >>> Q.null $ Q.take 0 Q.stdin
-- True
-- >>> :t Q.null $ Q.take 0 Q.stdin
-- Q.null $ Q.take 0 Q.stdin :: MonadIO m => m Bool
null_ :: Monad m => ByteString m r -> m Bool
null_ (Empty _)      = return True
null_ (Go m)         = m >>= null_
null_ (Chunk bs rest) = if B.null bs
  then null_ rest
  else return False
{-# INLINABLE null_ #-}

-- | Similar to `null`, but yields the remainder of the `ByteString` stream when
-- an answer has been determined.
testNull :: Monad m => ByteString m r -> m (Of Bool (ByteString m r))
testNull (Empty r)  = return (True :> Empty r)
testNull (Go m)     = m >>= testNull
testNull p@(Chunk bs rest) = if B.null bs
   then testNull rest
   else return (False :> p)
{-# INLINABLE testNull #-}

-- | Remove empty ByteStrings from a stream of bytestrings.
denull :: Monad m => Stream (ByteString m) m r -> Stream (ByteString m) m r
denull = hoist (run . maps effects) . separate . mapped nulls
{-# INLINE denull #-}

{-| /O1/ Distinguish empty from non-empty lines, while maintaining streaming;
    the empty ByteStrings are on the right

>>> nulls  ::  ByteString m r -> m (Sum (ByteString m) (ByteString m) r)

    There are many ways to remove null bytestrings from a
    @Stream (ByteString m) m r@ (besides using @denull@). If we pass next to

>>> mapped nulls bs :: Stream (Sum (ByteString m) (ByteString m)) m r

    then can then apply @Streaming.separate@ to get

>>> separate (mapped nulls bs) :: Stream (ByteString m) (Stream (ByteString m) m) r

    The inner monad is now made of the empty bytestrings; we act on this
    with @hoist@ , considering that

>>> :t Q.effects . Q.concat
Q.effects . Q.concat
  :: Monad m => Stream (Q.ByteString m) m r -> m r

    we have

>>> hoist (Q.effects . Q.concat) . separate . mapped Q.nulls
  :: Monad n =>  Stream (Q.ByteString n) n b -> Stream (Q.ByteString n) n b
-}
nulls :: Monad m => ByteString m r -> m (Sum (ByteString m) (ByteString m) r)
nulls (Empty r)  = return (InR (return r))
nulls (Go m)     = m >>= nulls
nulls (Chunk bs rest) = if B.null bs
   then nulls rest
   else return (InL (Chunk bs rest))
{-# INLINABLE nulls #-}

-- | Like `length`, report the length in bytes of the `ByteString` by running
-- through its contents. Since the return value is in the effect @m@, this is
-- one way to "get out" of the stream.
length_ :: Monad m => ByteString m r -> m Int
length_ = fmap (\(n:> _) -> n) . foldlChunks (\n c -> n + fromIntegral (B.length c)) 0
{-# INLINE length_ #-}

-- | /O(n\/c)/ 'length' returns the length of a byte stream as an 'Int' together
-- with the return value. This makes various maps possible.
--
-- >>> Q.length "one\ntwo\three\nfour\nfive\n"
-- 23 :> ()
-- >>> S.print $ S.take 3 $ mapped Q.length $ Q.lines "one\ntwo\three\nfour\nfive\n"
-- 3
-- 8
-- 4
length :: Monad m => ByteString m r -> m (Of Int r)
length = foldlChunks (\n c -> n + fromIntegral (B.length c)) 0
{-# INLINE length #-}

-- | /O(1)/ 'cons' is analogous to '(:)' for lists.
cons :: Monad m => Word8 -> ByteString m r -> ByteString m r
cons c cs = Chunk (B.singleton c) cs
{-# INLINE cons #-}

-- | /O(1)/ Unlike 'cons', 'cons\'' is strict in the ByteString that we are
-- consing onto. More precisely, it forces the head and the first chunk. It does
-- this because, for space efficiency, it may coalesce the new byte onto the
-- first \'chunk\' rather than starting a new \'chunk\'.
--
-- So that means you can't use a lazy recursive contruction like this:
--
-- > let xs = cons\' c xs in xs
--
-- You can however use 'cons', as well as 'repeat' and 'cycle', to build
-- infinite byte streams.
cons' :: Word8 -> ByteString m r -> ByteString m r
cons' w (Chunk c cs) | B.length c < 16 = Chunk (B.cons w c) cs
cons' w cs           = Chunk (B.singleton w) cs
{-# INLINE cons' #-}

-- | /O(n\/c)/ Append a byte to the end of a 'ByteString'.
snoc :: Monad m => ByteString m r -> Word8 -> ByteString m r
snoc cs w = do    -- cs <* singleton w
  r <- cs
  singleton w
  return r
{-# INLINE snoc #-}

-- | /O(1)/ Extract the first element of a 'ByteString', which must be non-empty.
head_ :: Monad m => ByteString m r -> m Word8
head_ (Empty _)   = error "head"
head_ (Chunk c bs) = if B.null c
                        then head_ bs
                        else return $ B.unsafeHead c
head_ (Go m)      = m >>= head_
{-# INLINABLE head_ #-}

-- | /O(c)/ Extract the first element of a 'ByteString', if there is one.
head :: Monad m => ByteString m r -> m (Of (Maybe Word8) r)
head (Empty r)  = return (Nothing :> r)
head (Chunk c rest) = case B.uncons c of
  Nothing -> head rest
  Just (w,_) -> do
    r <- SP.effects $ toChunks rest
    return $! Just w :> r
head (Go m)      = m >>= head
{-# INLINABLE head #-}

-- | /O(1)/ Extract the head and tail of a 'ByteString', or 'Nothing' if it is
-- empty.
uncons :: Monad m => ByteString m r -> m (Maybe (Word8, ByteString m r))
uncons (Empty _) = return Nothing
uncons (Chunk c cs)
    = return $ Just (B.unsafeHead c
                     , if B.length c == 1
                         then cs
                         else Chunk (B.unsafeTail c) cs )
uncons (Go m) = m >>= uncons
{-# INLINABLE uncons #-}

-- | /O(1)/ Extract the head and tail of a 'ByteString', or its return value if
-- it is empty. This is the \'natural\' uncons for an effectful byte stream.
nextByte :: Monad m => ByteString m r -> m (Either r (Word8, ByteString m r))
nextByte (Empty r) = return (Left r)
nextByte (Chunk c cs)
    = if B.null c
        then nextByte cs
        else return $ Right (B.unsafeHead c
                     , if B.length c == 1
                         then cs
                         else Chunk (B.unsafeTail c) cs )
nextByte (Go m) = m >>= nextByte
{-# INLINABLE nextByte #-}

-- | Like `uncons`, but yields the entire first `B.ByteString` chunk that the
-- stream is holding onto. If there wasn't one, it tries to fetch it.
unconsChunk :: Monad m => ByteString m r -> m (Maybe (B.ByteString, ByteString m r))
unconsChunk (Empty _)    = return Nothing
unconsChunk (Chunk c cs) = return (Just (c,cs))
unconsChunk (Go m)       = m >>= unconsChunk
{-# INLINABLE unconsChunk #-}

-- | Similar to `unconsChunk`, but yields the final @r@ return value when there
-- is no subsequent chunk.
nextChunk :: Monad m => ByteString m r -> m (Either r (B.ByteString, ByteString m r))
nextChunk (Empty r) = return (Left r)
nextChunk (Go m) = m >>= nextChunk
nextChunk (Chunk c cs)
  | B.null c = nextChunk cs
  | otherwise = return (Right (c,cs))
{-# INLINABLE nextChunk #-}

-- | /O(n\/c)/ Extract the last element of a 'ByteString', which must be finite
-- and non-empty.
last_ :: Monad m => ByteString m r -> m Word8
last_ (Empty _)      = error "Data.ByteString.Streaming.last: empty string"
last_ (Go m)         = m >>= last_
last_ (Chunk c0 cs0) = go c0 cs0
 where
   go c (Empty _)    = if B.null c
       then error "Data.ByteString.Streaming.last: empty string"
       else return $ unsafeLast c
   go _ (Chunk c cs) = go c cs
   go x (Go m)       = m >>= go x
{-# INLINABLE last_ #-}

-- | Like `last_`, but suitable as an argument for `Streaming.mapped`.
last :: Monad m => ByteString m r -> m (Of (Maybe Word8) r)
last (Empty r)      = return (Nothing :> r)
last (Go m)         = m >>= last
last (Chunk c0 cs0) = go c0 cs0
  where
    go c (Empty r)    = return (Just (unsafeLast c) :> r)
    go _ (Chunk c cs) = go c cs
    go x (Go m)       = m >>= go x
{-# INLINABLE last #-}


-- isPrefixOf :: Monad m => B.ByteString -> ByteString m r -> m (Sum (ByteString m) (ByteString m) r)
-- isPrefixOf bytes bs = do
--   let len = B.length bytes
--   (bytes' :> rest) <- toStrict $ splitAt (fromIntegral len) bs
--   if bytes' == bytes
--     then return $ InR $ chunk bytes' >> rest
--     else return $ InL $ chunk bytes' >> rest
-- -- | /O(n\/c)/ Return all the elements of a 'ByteString' except the last one.
-- init :: ByteString -> ByteString
-- init Empty          = errorEmptyStream "init"
-- init (Chunk c0 cs0) = go c0 cs0
--   where go c Empty | B.length c == 1 = Empty
--                    | otherwise       = Chunk (B.unsafeInit c) Empty
--         go c (Chunk c' cs)           = Chunk c (go c' cs)
--
-- -- | /O(n\/c)/ Extract the 'init' and 'last' of a ByteString, returning Nothing
-- -- if it is empty.
-- --
-- -- * It is no faster than using 'init' and 'last'
-- unsnoc :: ByteString -> Maybe (ByteString, Word8)
-- unsnoc Empty        = Nothing
-- unsnoc (Chunk c cs) = Just (init (Chunk c cs), last (Chunk c cs))

-- | /O(n\/c)/ Append two `ByteString`s together.
append :: Monad m => ByteString m r -> ByteString m s -> ByteString m s
append xs ys = dematerialize xs (const ys) Chunk Go
{-# INLINE append #-}

-- ---------------------------------------------------------------------
-- Transformations

-- | /O(n)/ 'map' @f xs@ is the ByteString obtained by applying @f@ to each
-- element of @xs@.
map :: Monad m => (Word8 -> Word8) -> ByteString m r -> ByteString m r
map f z = dematerialize z Empty (Chunk . B.map f) Go
{-# INLINE map #-}

-- -- | /O(n)/ 'reverse' @xs@ returns the elements of @xs@ in reverse order.
-- reverse :: ByteString -> ByteString
-- reverse cs0 = rev Empty cs0
--   where rev a Empty        = a
--         rev a (Chunk c cs) = rev (Chunk (B.reverse c) a) cs
-- {-# INLINE reverse #-}

-- | The 'intersperse' function takes a 'Word8' and a 'ByteString' and
-- \`intersperses\' that byte between the elements of the 'ByteString'. It is
-- analogous to the intersperse function on Streams.
intersperse :: Monad m => Word8 -> ByteString m r -> ByteString m r
intersperse _ (Empty r)    = Empty r
intersperse w (Go m)       = Go (fmap (intersperse w) m)
intersperse w (Chunk c cs) = Chunk (B.intersperse w c)
                                   (dematerialize cs Empty (Chunk . intersperse') Go)
  where intersperse' :: P.ByteString -> P.ByteString
        intersperse' (B.PS fp o l) =
          B.unsafeCreate (2*l) $ \p' -> withForeignPtr fp $ \p -> do
            poke p' w
            B.c_intersperse (p' `plusPtr` 1) (p `plusPtr` o) (fromIntegral l) w

{-# INLINABLE intersperse #-}

-- | 'foldr', applied to a binary operator, a starting value (typically the
-- right-identity of the operator), and a ByteString, reduces the ByteString
-- using the binary operator, from right to left.
--
-- > foldr cons = id
--
foldr :: Monad m => (Word8 -> a -> a) -> a -> ByteString m () -> m a
foldr k = foldrChunks (flip (B.foldr k))
{-# INLINE foldr #-}

-- | 'fold', applied to a binary operator, a starting value (typically the
-- left-identity of the operator), and a ByteString, reduces the ByteString
-- using the binary operator, from left to right. We use the style of the foldl
-- libarary for left folds
fold :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m () -> m b
fold step0 begin finish p0 = loop p0 begin
  where
    loop p !x = case p of
        Chunk bs bss -> loop bss $! B.foldl' step0 x bs
        Go    m      -> m >>= \p' -> loop p' x
        Empty _      -> return (finish x)
{-# INLINABLE fold #-}

-- | 'fold_' keeps the return value of the left-folded bytestring. Useful for
-- simultaneous folds over a segmented bytestream.
fold_ :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m r -> m (Of b r)
fold_ step0 begin finish p0 = loop p0 begin
  where
    loop p !x = case p of
        Chunk bs bss -> loop bss $! B.foldl' step0 x bs
        Go    m      -> m >>= \p' -> loop p' x
        Empty r      -> return (finish x :> r)
{-# INLINABLE fold_ #-}

-- ---------------------------------------------------------------------
-- Special folds

-- /O(n)/ Concatenate a list of ByteStrings.
-- concat :: (Monad m) => [ByteString m ()] -> ByteString m ()
-- concat css0 = to css0
--   where
--     go css (Empty m')   = to css
--     go css (Chunk c cs) = Chunk c (go css cs)
--     go css (Go m)       = Go (fmap (go css) m)
--     to []               = Empty ()
--     to (cs:css)         = go css cs

-- ---------------------------------------------------------------------
-- Unfolds and replicates

{-| @'iterate' f x@ returns an infinite ByteString of repeated applications
-- of @f@ to @x@:

> iterate f x == [x, f x, f (f x), ...]

>>> R.stdout $ R.take 50 $ R.iterate succ 39
()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXY
>>> Q.putStrLn $ Q.take 50 $ Q.iterate succ '\''
()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXY
-}
iterate :: (Word8 -> Word8) -> Word8 -> ByteString m r
iterate f = unfoldr (\x -> case f x of !x' -> Right (x', x'))
{-# INLINABLE iterate #-}

{- | @'repeat' x@ is an infinite ByteString, with @x@ the value of every
     element.

>>> R.stdout $ R.take 50 $ R.repeat 60
<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
>>> Q.putStrLn $ Q.take 50 $ Q.repeat 'z'
zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
-}
repeat :: Word8 -> ByteString m r
repeat w = cs where cs = Chunk (B.replicate BI.smallChunkSize w) cs
{-# INLINABLE repeat #-}

{- | 'cycle' ties a finite ByteString into a circular one, or equivalently,
     the infinite repetition of the original ByteString. For an empty bytestring
     (like @return 17@) it of course makes an unproductive loop

>>> Q.putStrLn $ Q.take 7 $ Q.cycle  "y\n"
y
y
y
y
-}
cycle :: Monad m => ByteString m r -> ByteString m s
cycle = forever
{-# INLINE cycle #-}

-- | /O(n)/ The 'unfoldr' function is analogous to the Stream @unfoldr@.
-- 'unfoldr' builds a ByteString from a seed value. The function takes the
-- element and returns 'Nothing' if it is done producing the ByteString or
-- returns @'Just' (a,b)@, in which case, @a@ is a prepending to the ByteString
-- and @b@ is used as the next element in a recursive call.
unfoldM :: Monad m => (a -> Maybe (Word8, a)) -> a -> ByteString m ()
unfoldM f s0 = unfoldChunk 32 s0
  where unfoldChunk n s =
          case B.unfoldrN n f s of
            (c, Nothing)
              | B.null c  -> Empty ()
              | otherwise -> Chunk c (Empty ())
            (c, Just s')  -> Chunk c (unfoldChunk (n*2) s')
{-# INLINABLE unfoldM #-}

-- | 'unfold' is like 'unfoldr' but stops when the co-algebra returns 'Left';
-- the result is the return value of the @ByteString m r@ @unfoldr uncons = id@
unfoldr :: (a -> Either r (Word8, a)) -> a -> ByteString m r
unfoldr f s0 = unfoldChunk 32 s0
  where unfoldChunk n s =
          case unfoldrNE n f s of
            (c, Left r)
              | B.null c  -> Empty r
              | otherwise -> Chunk c (Empty r)
            (c, Right s') -> Chunk c (unfoldChunk (n*2) s')
{-# INLINABLE unfoldr #-}

-- ---------------------------------------------------------------------
-- Substrings

{-| /O(n\/c)/ 'take' @n@, applied to a ByteString @xs@, returns the prefix
    of @xs@ of length @n@, or @xs@ itself if @n > 'length' xs@.

    Note that in the streaming context this drops the final return value;
    'splitAt' preserves this information, and is sometimes to be preferred.

>>> Q.putStrLn $ Q.take 8 $ "Is there a God?" >> return True
Is there
>>> Q.putStrLn $ "Is there a God?" >> return True
Is there a God?
True
>>> rest <- Q.putStrLn $ Q.splitAt 8 $ "Is there a God?" >> return True
Is there
>>> Q.effects  rest
True
-}
take :: Monad m => Int64 -> ByteString m r -> ByteString m ()
take i _ | i <= 0 = Empty ()
take i cs0         = take' i cs0
  where take' 0 _            = Empty ()
        take' _ (Empty _)    = Empty ()
        take' n (Chunk c cs) =
          if n < fromIntegral (B.length c)
            then Chunk (B.take (fromIntegral n) c) (Empty ())
            else Chunk c (take' (n - fromIntegral (B.length c)) cs)
        take' n (Go m) = Go (fmap (take' n) m)
{-# INLINABLE take #-}

{-| /O(n\/c)/ 'drop' @n xs@ returns the suffix of @xs@ after the first @n@
    elements, or @[]@ if @n > 'length' xs@.

>>> Q.putStrLn $ Q.drop 6 "Wisconsin"
sin
>>> Q.putStrLn $ Q.drop 16 "Wisconsin"

>>>
-}
drop  :: Monad m => Int64 -> ByteString m r -> ByteString m r
drop i p | i <= 0 = p
drop i cs0 = drop' i cs0
  where drop' 0 cs           = cs
        drop' _ (Empty r)    = Empty r
        drop' n (Chunk c cs) =
          if n < fromIntegral (B.length c)
            then Chunk (B.drop (fromIntegral n) c) cs
            else drop' (n - fromIntegral (B.length c)) cs
        drop' n (Go m) = Go (fmap (drop' n) m)
{-# INLINABLE drop #-}

{-| /O(n\/c)/ 'splitAt' @n xs@ is equivalent to @('take' n xs, 'drop' n xs)@.

>>> rest <- Q.putStrLn $ Q.splitAt 3 "therapist is a danger to good hyphenation, as Knuth notes"
the
>>> Q.putStrLn $ Q.splitAt 19 rest
rapist is a danger
-}
splitAt :: Monad m => Int64 -> ByteString m r -> ByteString m (ByteString m r)
splitAt i cs0 | i <= 0 = Empty cs0
splitAt i cs0 = splitAt' i cs0
  where splitAt' 0 cs           = Empty cs
        splitAt' _ (Empty r  )   = Empty (Empty r)
        splitAt' n (Chunk c cs) =
          if n < fromIntegral (B.length c)
            then Chunk (B.take (fromIntegral n) c) $
                     Empty (Chunk (B.drop (fromIntegral n) c) cs)
            else Chunk c (splitAt' (n - fromIntegral (B.length c)) cs)
        splitAt' n (Go m) = Go  (fmap (splitAt' n) m)
{-# INLINABLE splitAt #-}

-- | 'takeWhile', applied to a predicate @p@ and a ByteString @xs@, returns the
-- longest prefix (possibly empty) of @xs@ of elements that satisfy @p@.
takeWhile :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m ()
takeWhile f cs0 = takeWhile' cs0
  where
    takeWhile' (Empty _)    = Empty ()
    takeWhile' (Go m)       = Go $ fmap takeWhile' m
    takeWhile' (Chunk c cs) =
      case findIndexOrEnd (not . f) c of
        0                  -> Empty ()
        n | n < B.length c -> Chunk (B.take n c) (Empty ())
          | otherwise      -> Chunk c (takeWhile' cs)
{-# INLINABLE takeWhile #-}

-- | 'dropWhile' @p xs@ returns the suffix remaining after 'takeWhile' @p xs@.
dropWhile :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m r
dropWhile p = drop' where
  drop' bs = case bs of
    Empty r    -> Empty r
    Go m       -> Go (fmap drop' m)
    Chunk c cs -> case findIndexOrEnd (not . p) c of
        0                  -> Chunk c cs
        n | n < B.length c -> Chunk (B.drop n c) cs
          | otherwise      -> drop' cs
{-# INLINABLE dropWhile #-}

-- | 'break' @p@ is equivalent to @'span' ('not' . p)@.
break :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r)
break f cs0 = break' cs0
  where break' (Empty r)        = Empty (Empty r)
        break' (Chunk c cs) =
          case findIndexOrEnd f c of
            0                  -> Empty (Chunk c cs)
            n | n < B.length c -> Chunk (B.take n c) $
                                      Empty (Chunk (B.drop n c) cs)
              | otherwise      -> Chunk c (break' cs)
        break' (Go m) = Go (fmap break' m)
{-# INLINABLE break #-}

-- | 'span' @p xs@ breaks the ByteString into two segments. It is equivalent to
-- @('takeWhile' p xs, 'dropWhile' p xs)@.
span :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r)
span p = break (not . p)
{-# INLINE span #-}

-- | /O(n)/ Splits a 'ByteString' into components delimited by separators, where
-- the predicate returns True for a separator element. The resulting components
-- do not contain the separators. Two adjacent separators result in an empty
-- component in the output. eg.
--
-- > splitWith (=='a') "aabbaca" == ["","","bb","c",""]
-- > splitWith (=='a') []        == []
splitWith :: Monad m => (Word8 -> Bool) -> ByteString m r -> Stream (ByteString m) m r
splitWith _ (Empty r)      = Return r
splitWith p (Go m)         = Effect $ fmap (splitWith p) m
splitWith p (Chunk c0 cs0) = comb [] (B.splitWith p c0) cs0
  where
-- comb :: [P.ByteString] -> [P.ByteString] -> ByteString -> [ByteString]
--  comb acc (s:[]) (Empty r)    = Step (revChunks (s:acc) (Return r))
  comb acc [s]    (Empty r)    = Step $ L.foldl' (flip Chunk)
                                                 (Empty (Return r))
                                                 (s:acc)
  comb acc [s]    (Chunk c cs) = comb (s:acc) (B.splitWith p c) cs
  comb acc b      (Go m)       = Effect (fmap (comb acc b) m)
  comb acc (s:ss) cs           = Step $ L.foldl' (flip Chunk)
                                                 (Empty (comb [] ss cs))
                                                 (s:acc)
  comb acc []  (Empty r)    = Step $ L.foldl' (flip Chunk)
                                                 (Empty (Return r))
                                                 acc
  comb acc []  (Chunk c cs) = comb acc (B.splitWith p c) cs
 --  comb acc (s:ss) cs           = Step (revChunks (s:acc) (comb [] ss cs))

{-# INLINABLE splitWith #-}

-- | /O(n)/ Break a 'ByteString' into pieces separated by the byte
-- argument, consuming the delimiter. I.e.
--
-- > split '\n' "a\nb\nd\ne" == ["a","b","d","e"]
-- > split 'a'  "aXaXaXa"    == ["","X","X","X",""]
-- > split 'x'  "x"          == ["",""]
--
-- and
--
-- > intercalate [c] . split c == id
-- > split == splitWith . (==)
--
-- As for all splitting functions in this library, this function does
-- not copy the substrings, it just constructs new 'ByteStrings' that
-- are slices of the original.
split :: Monad m => Word8 -> ByteString m r -> Stream (ByteString m) m r
split w = loop
  where
  loop !x = case x of
    Empty r      -> Return r
    Go m         -> Effect $ fmap loop m
    Chunk c0 cs0 -> comb [] (B.split w c0) cs0
  comb !acc [] (Empty r)    = Step $ revChunks acc (Return r)
  comb acc [] (Chunk c cs)  = comb acc (B.split w c) cs
  comb !acc [s] (Empty r)   = Step $ revChunks (s:acc) (Return r)
  comb acc [s] (Chunk c cs) = comb (s:acc) (B.split w c) cs
  comb acc b (Go m)         = Effect (fmap (comb acc b) m)
  comb acc (s:ss) cs        = Step $ revChunks (s:acc) (comb [] ss cs)
{-# INLINABLE split #-}

-- | The 'group' function takes a ByteString and returns a list of ByteStrings
-- such that the concatenation of the result is equal to the argument. Moreover,
-- each sublist in the result contains only equal elements. For example,
--
-- > group "Mississippi" = ["M","i","ss","i","ss","i","pp","i"]
--
-- It is a special case of 'groupBy', which allows the programmer to supply
-- their own equality test.
group :: Monad m => ByteString m r -> Stream (ByteString m) m r
group = go
  where
    go (Empty r)        = Return r
    go (Go m)           = Effect $ fmap go m
    go (Chunk c cs)
      | B.length c == 1 = Step $ to [c] (B.unsafeHead c) cs
      | otherwise       = Step $ to [B.unsafeTake 1 c] (B.unsafeHead c) (Chunk (B.unsafeTail c) cs)

    to acc !_ (Empty r) = revNonEmptyChunks acc (Empty (Return r))
    to acc !w (Go m) = Go $ to acc w <$> m
    to acc !w (Chunk c cs) = case findIndexOrEnd (/= w) c of
      0 -> revNonEmptyChunks acc (Empty (go (Chunk c cs)))
      n | n == B.length c -> to (B.unsafeTake n c : acc) w cs
        | otherwise       -> revNonEmptyChunks (B.unsafeTake n c : acc) (Empty (go (Chunk (B.unsafeDrop n c) cs)))
{-# INLINABLE group #-}

-- | The 'groupBy' function is a generalized version of 'group'.
groupBy :: Monad m => (Word8 -> Word8 -> Bool) -> ByteString m r -> Stream (ByteString m) m r
groupBy rel = go
  where
    -- go :: ByteString m r -> Stream (ByteString m) m r
    go (Empty r)        = Return r
    go (Go m)           = Effect $ fmap go m
    go (Chunk c cs)
      | B.length c == 1 = Step $ to [c] (B.unsafeHead c) cs
      | otherwise       = Step $ to [B.unsafeTake 1 c] (B.unsafeHead c) (Chunk (B.unsafeTail c) cs)

    -- to :: [B.ByteString] -> Word8 -> ByteString m r -> ByteString m (Stream (ByteString m) m r)
    to acc !_ (Empty r) = revNonEmptyChunks acc (Empty (Return r))
    to acc !w (Go m) = Go $ to acc w <$> m
    to acc !w (Chunk c cs) = case findIndexOrEnd (not . rel w) c of
      0 -> revNonEmptyChunks acc (Empty (go (Chunk c cs)))
      n | n == B.length c -> to (B.unsafeTake n c : acc) w cs
        | otherwise       -> revNonEmptyChunks (B.unsafeTake n c : acc) (Empty (go (Chunk (B.unsafeDrop n c) cs)))
{-# INLINABLE groupBy #-}

-- | /O(n)/ The 'intercalate' function takes a 'ByteString' and a list of
-- 'ByteString's and concatenates the list after interspersing the first
-- argument between each element of the list.
intercalate :: Monad m => ByteString m () -> Stream (ByteString m) m r -> ByteString m r
intercalate _ (Return r) = Empty r
intercalate s (Effect m) = Go $ fmap (intercalate s) m
intercalate s (Step bs0) = do  -- this isn't quite right
  ls <- bs0
  s
  intercalate s ls
 -- where
 --  loop (Return r) =  Empty r -- concat . (L.intersperse s)
 --  loop (Effect m) = Go $ fmap loop m
 --  loop (Step bs) = do
 --    ls <- bs
 --    case ls of
 --      Return r -> Empty r  -- no '\n' before end, in this case.
 --      x -> s >> loop x
{-# INLINABLE intercalate #-}

-- | Returns the number of times its argument appears in the `ByteString`.
--
-- > count = length . elemIndices
count_ :: Monad m => Word8 -> ByteString m r -> m Int
count_ w  = fmap (\(n :> _) -> n) . foldlChunks (\n c -> n + fromIntegral (B.count w c)) 0
{-# INLINE count_ #-}

-- | Like `count_`, but suitable for use with `Streaming.mapped`.
count :: Monad m => Word8 -> ByteString m r -> m (Of Int r)
count w cs = foldlChunks (\n c -> n + fromIntegral (B.count w c)) 0 cs
{-# INLINE count #-}

-- ---------------------------------------------------------------------
-- Searching ByteStrings

-- | /O(n)/ 'filter', applied to a predicate and a ByteString, returns a
-- ByteString containing those characters that satisfy the predicate.
filter :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m r
filter p s = go s
    where
        go (Empty r )   = Empty r
        go (Chunk x xs) = consChunk (B.filter p x) (go xs)
        go (Go m)       = Go (fmap go m)
                            -- should inspect for null
{-# INLINABLE filter #-}

-- ---------------------------------------------------------------------
-- ByteString IO
--
-- Rule for when to close: is it expected to read the whole file?
-- If so, close when done.
--

-- | Read entire handle contents /lazily/ into a 'ByteString'. Chunks are read
-- on demand, in at most @k@-sized chunks. It does not block waiting for a whole
-- @k@-sized chunk, so if less than @k@ bytes are available then they will be
-- returned immediately as a smaller chunk.
--
-- Note: the 'Handle' should be placed in binary mode with
-- 'System.IO.hSetBinaryMode' for 'hGetContentsN' to work correctly.
hGetContentsN :: MonadIO m => Int -> Handle -> ByteString m ()
hGetContentsN k h = loop -- TODO close on exceptions
  where
    loop = do
        c <- liftIO (B.hGetSome h k)
        -- only blocks if there is no data available
        if B.null c
          then Empty ()
          else Chunk c loop
{-# INLINABLE hGetContentsN #-} -- very effective inline pragma

-- | Read @n@ bytes into a 'ByteString', directly from the specified 'Handle',
-- in chunks of size @k@.
hGetN :: MonadIO m => Int -> Handle -> Int -> ByteString m ()
hGetN k h n | n > 0 = readChunks n
  where
    readChunks !i = Go $ do
        c <- liftIO $ B.hGet h (min k i)
        case B.length c of
            0 -> return $ Empty ()
            m -> return $ Chunk c (readChunks (i - m))
hGetN _ _ 0 = Empty ()
hGetN _ h n = liftIO $ illegalBufferSize h "hGet" n  -- <--- REPAIR !!!
{-# INLINABLE hGetN #-}

-- | hGetNonBlockingN is similar to 'hGetContentsN', except that it will never
-- block waiting for data to become available, instead it returns only whatever
-- data is available. Chunks are read on demand, in @k@-sized chunks.
hGetNonBlockingN :: MonadIO m => Int -> Handle -> Int ->  ByteString m ()
hGetNonBlockingN k h n | n > 0 = readChunks n
  where
    readChunks !i = Go $ do
        c <- liftIO $ B.hGetNonBlocking h (min k i)
        case B.length c of
            0 -> return (Empty ())
            m -> return (Chunk c (readChunks (i - m)))
hGetNonBlockingN _ _ 0 = Empty ()
hGetNonBlockingN _ h n = liftIO $ illegalBufferSize h "hGetNonBlocking" n
{-# INLINABLE hGetNonBlockingN #-}

illegalBufferSize :: Handle -> String -> Int -> IO a
illegalBufferSize handle fn sz =
    ioError (mkIOError illegalOperationErrorType msg (Just handle) Nothing)
    --TODO: System.IO uses InvalidArgument here, but it's not exported :-(
    where
      msg = fn ++ ": illegal ByteString size " ++ showsPrec 9 sz []
{-# INLINABLE illegalBufferSize #-}

-- | Read entire handle contents /lazily/ into a 'ByteString'. Chunks are read
-- on demand, using the default chunk size.
--
-- Note: the 'Handle' should be placed in binary mode with
-- 'System.IO.hSetBinaryMode' for 'hGetContents' to work correctly.
hGetContents :: MonadIO m => Handle -> ByteString m ()
hGetContents = hGetContentsN defaultChunkSize
{-# INLINE hGetContents #-}

-- | Pipes-style nomenclature for 'hGetContents'.
fromHandle :: MonadIO m => Handle -> ByteString m ()
fromHandle = hGetContents
{-# INLINE fromHandle #-}

-- | Pipes-style nomenclature for 'getContents'.
stdin :: MonadIO m => ByteString m ()
stdin = hGetContents IO.stdin
{-# INLINE stdin #-}

-- | Read @n@ bytes into a 'ByteString', directly from the specified 'Handle'.
hGet :: MonadIO m => Handle -> Int -> ByteString m ()
hGet = hGetN defaultChunkSize
{-# INLINE hGet #-}

-- | hGetNonBlocking is similar to 'hGet', except that it will never block
-- waiting for data to become available, instead it returns only whatever data
-- is available. If there is no data available to be read, 'hGetNonBlocking'
-- returns 'empty'.
--
-- Note: on Windows and with Haskell implementation other than GHC, this
-- function does not work correctly; it behaves identically to 'hGet'.
hGetNonBlocking :: MonadIO m => Handle -> Int -> ByteString m ()
hGetNonBlocking = hGetNonBlockingN defaultChunkSize
{-# INLINE hGetNonBlocking #-}

-- | Write a 'ByteString' to a file. Use
-- 'Control.Monad.Trans.ResourceT.runResourceT' to ensure that the handle is
-- closed.
--
-- >>> :set -XOverloadedStrings
-- >>> runResourceT $ Q.writeFile "hello.txt" "Hello world.\nGoodbye world.\n"
-- >>> :! cat "hello.txt"
-- Hello world.
-- Goodbye world.
-- >>> runResourceT $ Q.writeFile "hello2.txt" $ Q.readFile "hello.txt"
-- >>> :! cat hello2.txt
-- Hello world.
-- Goodbye world.
writeFile :: MonadResource m => FilePath -> ByteString m r -> m r
writeFile f str = do
  (key, handle) <- allocate (openBinaryFile f WriteMode) hClose
  r <- hPut handle str
  release key
  return r
{-# INLINE writeFile #-}

-- | Read an entire file into a chunked @'ByteString' IO ()@. The handle will be
-- held open until EOF is encountered. The block governed by
-- 'Control.Monad.Trans.Resource.runResourceT' will end with the closing of any
-- handles opened.
--
-- >>> :! cat hello.txt
-- Hello world.
-- Goodbye world.
-- >>> runResourceT $ Q.stdout $ Q.readFile "hello.txt"
-- Hello world.
-- Goodbye world.
readFile :: MonadResource m => FilePath -> ByteString m ()
readFile f = bracketByteString (openBinaryFile f ReadMode) hClose hGetContents
{-# INLINE readFile #-}

-- | Append a 'ByteString' to a file. Use
-- 'Control.Monad.Trans.ResourceT.runResourceT' to ensure that the handle is
-- closed.
--
-- >>> runResourceT $ Q.writeFile "hello.txt" "Hello world.\nGoodbye world.\n"
-- >>> runResourceT $ Q.stdout $ Q.readFile "hello.txt"
-- Hello world.
-- Goodbye world.
-- >>> runResourceT $ Q.appendFile "hello.txt" "sincerely yours,\nArthur\n"
-- >>> runResourceT $ Q.stdout $  Q.readFile "hello.txt"
-- Hello world.
-- Goodbye world.
-- sincerely yours,
-- Arthur
appendFile :: MonadResource m => FilePath -> ByteString m r -> m r
appendFile f str = do
  (key, handle) <- allocate (openBinaryFile f AppendMode) hClose
  r <- hPut handle str
  release key
  return r
{-# INLINE appendFile #-}

-- | Equivalent to @hGetContents stdin@. Will read /lazily/.
getContents :: MonadIO m => ByteString m ()
getContents = hGetContents IO.stdin
{-# INLINE getContents #-}

-- | Outputs a 'ByteString' to the specified 'Handle'.
hPut ::  MonadIO m => Handle -> ByteString m r -> m r
hPut h cs = dematerialize cs return (\x y -> liftIO (B.hPut h x) >> y) (>>= id)
{-# INLINE hPut #-}

-- | Pipes nomenclature for 'hPut'.
toHandle :: MonadIO m => Handle -> ByteString m r -> m r
toHandle = hPut
{-# INLINE toHandle #-}

-- | Pipes-style nomenclature for 'putStr'.
stdout ::  MonadIO m => ByteString m r -> m r
stdout = hPut IO.stdout
{-# INLINE stdout #-}

-- -- | Similar to 'hPut' except that it will never block. Instead it returns
-- any tail that did not get written. This tail may be 'empty' in the case that
-- the whole string was written, or the whole original string if nothing was
-- written. Partial writes are also possible.
--
-- Note: on Windows and with Haskell implementation other than GHC, this
-- function does not work correctly; it behaves identically to 'hPut'.
--
-- hPutNonBlocking ::  MonadIO m => Handle -> ByteString m r -> ByteString m r
-- hPutNonBlocking _ (Empty r)         = Empty r
-- hPutNonBlocking h (Go m) = Go $ fmap (hPutNonBlocking h) m
-- hPutNonBlocking h bs@(Chunk c cs) = do
--   c' <- lift $ B.hPutNonBlocking h c
--   case B.length c' of
--     l' | l' == B.length c -> hPutNonBlocking h cs
--     0                     -> bs
--     _                     -> Chunk c' cs
-- {-# INLINABLE hPutNonBlocking #-}

-- | A synonym for @hPut@, for compatibility
--
-- hPutStr :: Handle -> ByteString IO r -> IO r
-- hPutStr = hPut
--
-- -- | Write a ByteString to stdout
-- putStr :: ByteString IO r -> IO r
-- putStr = hPut IO.stdout

-- | The interact function takes a function of type @ByteString -> ByteString@
-- as its argument. The entire input from the standard input device is passed to
-- this function as its argument, and the resulting string is output on the
-- standard output device.
--
-- > interact morph = stdout (morph stdin)
interact :: (ByteString IO () -> ByteString IO r) -> IO r
interact f = stdout (f stdin)
{-# INLINE interact #-}

-- -- ---------------------------------------------------------------------
-- -- Internal utilities

-- | Used in `group` and `groupBy`.
revNonEmptyChunks :: [P.ByteString] -> ByteString m r -> ByteString m r
revNonEmptyChunks = L.foldl' (\f bs -> Chunk bs . f) id
{-# INLINE revNonEmptyChunks #-}

-- | Reverse a list of possibly-empty chunks into a lazy ByteString.
revChunks :: Monad m => [P.ByteString] -> r -> ByteString m r
revChunks cs r = L.foldl' (flip Chunk) (Empty r) cs
{-# INLINE revChunks #-}

zipWithStream
  :: (Monad m)
  =>  (forall x . a -> ByteString m x -> ByteString m x)
  -> [a]
  -> Stream (ByteString m) m r
  -> Stream (ByteString m) m r
zipWithStream op zs = loop zs
  where
    loop [] !ls      = loop zs ls
    loop a@(x:xs)  ls = case ls of
      Return r   -> Return r
      Step fls   -> Step $ fmap (loop xs) (op x fls)
      Effect mls -> Effect $ fmap (loop a) mls
{-# INLINABLE zipWithStream #-}

-- | Take a builder constructed otherwise and convert it to a genuine streaming
-- bytestring.
--
-- >>>  Q.putStrLn $ Q.toStreamingByteString $ stringUtf8 "哈斯克尔" <> stringUtf8 " " <> integerDec 98
-- 哈斯克尔 98
--
-- <https://gist.github.com/michaelt/6ea89ca95a77b0ef91f3 This benchmark> shows
-- its indistinguishable performance is indistinguishable from
-- @toLazyByteString@
toStreamingByteString :: MonadIO m => Builder -> ByteString m ()
toStreamingByteString = toStreamingByteStringWith
 (safeStrategy BI.smallChunkSize BI.defaultChunkSize)
{-# INLINE toStreamingByteString #-}

-- | Take a builder and convert it to a genuine streaming bytestring, using a
-- specific allocation strategy.
toStreamingByteStringWith :: MonadIO m => AllocationStrategy -> Builder -> ByteString m ()
toStreamingByteStringWith strategy builder0 = do
       cios <- liftIO (buildStepToCIOS strategy (runBuilder builder0))
       let loop cios0 = case cios0 of
              Yield1 bs io   -> Chunk bs $ do
                    cios1 <- liftIO io
                    loop cios1
              Finished buf r -> trimmedChunkFromBuffer buf (Empty r)
           trimmedChunkFromBuffer buffer k
              | B.null bs                            = k
              |  2 * B.length bs < bufferSize buffer = Chunk (B.copy bs) k
              | otherwise                            = Chunk bs          k
              where
                bs = byteStringFromBuffer buffer
       loop cios
{-# INLINABLE toStreamingByteStringWith #-}
{-# SPECIALIZE toStreamingByteStringWith ::  AllocationStrategy -> Builder -> ByteString IO () #-}

-- | Concatenate a stream of builders (not a streaming bytestring!) into a
-- single builder.
--
-- >>> let aa = yield (integerDec 10000) >> yield (string8 " is a number.") >> yield (char8 '\n')
-- >>> hPutBuilder IO.stdout $ concatBuilders aa
-- 10000 is a number.
concatBuilders :: Stream (Of Builder) IO () -> Builder
concatBuilders p = builder $ \bstep r -> do
  case p of
    Return _          -> runBuilderWith mempty bstep r
    Step (b :> rest)  -> runBuilderWith (b `mappend` concatBuilders rest) bstep r
    Effect m          -> m >>= \p' -> runBuilderWith (concatBuilders p') bstep r
{-# INLINABLE concatBuilders #-}

-- | A simple construction of a builder from a 'ByteString'.
--
-- >>> let aaa = "10000 is a number\n" :: Q.ByteString IO ()
-- >>>  hPutBuilder  IO.stdout $ toBuilder  aaa
-- 10000 is a number
toBuilder :: ByteString IO () -> Builder
toBuilder  =  concatBuilders . SP.map byteString . toChunks
{-# INLINABLE toBuilder #-}
