module Juvix.Compiler.Core.Extra
  ( module Juvix.Compiler.Core.Extra,
    module Juvix.Compiler.Core.Extra.Base,
    module Juvix.Compiler.Core.Extra.Recursors,
    module Juvix.Compiler.Core.Extra.Info,
    module Juvix.Compiler.Core.Extra.Equality,
    module Juvix.Compiler.Core.Extra.Recursors.Fold.Named,
    module Juvix.Compiler.Core.Extra.Recursors.Map.Named,
  )
where

import Data.HashMap.Strict qualified as HashMap
import Data.HashSet qualified as HashSet
import Juvix.Compiler.Core.Data.InfoTable
import Juvix.Compiler.Core.Extra.Base
import Juvix.Compiler.Core.Extra.Equality
import Juvix.Compiler.Core.Extra.Info
import Juvix.Compiler.Core.Extra.Recursors
import Juvix.Compiler.Core.Extra.Recursors.Fold.Named
import Juvix.Compiler.Core.Extra.Recursors.Map.Named
import Juvix.Compiler.Core.Info.NameInfo
import Juvix.Compiler.Core.Info.TypeInfo
import Juvix.Compiler.Core.Language

isClosed :: Node -> Bool
isClosed = not . has freeVars

freeVarsSet :: Node -> HashSet Var
freeVarsSet n = HashSet.fromList (n ^.. freeVars)

freeVars :: SimpleFold Node Var
freeVars f = ufoldNA reassemble go
  where
    go k = \case
      NVar var@(Var _ idx)
        | idx >= k -> NVar <$> f (shiftVar (-k) var)
      n -> pure n

getIdents :: Node -> HashSet Ident
getIdents n = HashSet.fromList (n ^.. nodeIdents)

nodeIdents :: Traversal' Node Ident
nodeIdents f = ufoldA reassemble go
  where
    go = \case
      NIdt i -> NIdt <$> f i
      n -> pure n

countFreeVarOccurrences :: Index -> Node -> Int
countFreeVarOccurrences idx = gatherN go 0
  where
    go k acc = \case
      NVar (Var _ idx') | idx' == idx + k -> acc + 1
      _ -> acc

shiftVar :: Index -> Var -> Var
shiftVar m = over varIndex (+ m)

-- | increase all free variable indices by a given value
shift :: Index -> Node -> Node
shift 0 = id
shift m = umapN go
  where
    go k = \case
      NVar v
        | v ^. varIndex >= k -> NVar (shiftVar m v)
      n -> n

-- | Prism for NLam
_NLam :: SimpleFold Node Lambda
_NLam f = \case
  NLam l -> NLam <$> f l
  n -> pure n

-- | Fold over all of the transitive descendants of a Node, including itself.
cosmos :: SimpleFold Node Node
cosmos f = ufoldA reassemble f

-- | The list should not contain repeated indices. The 'Info' corresponds to the
-- binder of the variable.
-- if fv = x1, x2, .., xn
-- the result is of the form λx1 λx2 .. λ xn b
captureFreeVars :: [(Index, Binder)] -> Node -> Node
captureFreeVars fv
  | n == 0 = id
  | otherwise = mkLambdasB infos . mapFreeVars
  where
    (indices, infos) = unzip fv
    n = length fv
    s :: HashMap Index Index
    s = HashMap.fromList (zip (reverse indices) [0 ..])
    mapFreeVars :: Node -> Node
    mapFreeVars = dmapN go
      where
        go :: Index -> Node -> Node
        go k = \case
          NVar (Var i u)
            | Just v <- s ^. at (u - k) -> NVar (Var i (v + k))
          m -> m

-- | subst for multiple bindings
substs :: [Node] -> Node -> Node
substs t = umapN go
  where
    len = length t
    go k n = case n of
      NVar (Var i idx)
        | idx >= k, idx - k < len -> shift k (t !! (idx - k))
        | idx > k -> mkVar i (idx - len)
      _ -> n

-- | substitute a term t for the free variable with de Bruijn index 0, avoiding
-- variable capture; shifts all free variabes with de Bruijn index > 0 by -1 (as
-- if the topmost binder was removed)
subst :: Node -> Node -> Node
subst t = substs [t]

-- | reduce all beta redexes present in a term and the ones created immediately
-- downwards (i.e., a "beta-development")
developBeta :: Node -> Node
developBeta = umap go
  where
    go :: Node -> Node
    go n = case n of
      NApp (App _ (NLam (Lambda {..})) arg) -> subst arg _lambdaBody
      _ -> n

etaExpand :: Int -> Node -> Node
etaExpand 0 n = n
etaExpand k n = mkLambdas' k (mkApps' (shift k n) (map mkVar' (reverse [0 .. k - 1])))

-- | substitution of all free variables for values in an environment
substEnv :: Env -> Node -> Node
substEnv env
  | null env = id
  | otherwise = umapN go
  where
    go k n = case n of
      NVar (Var _ idx)
        | idx >= k -> env !! (idx - k)
      _ -> n

convertClosures :: Node -> Node
convertClosures = umap go
  where
    go :: Node -> Node
    go n = case n of
      Closure env (Lambda i bi b) -> substEnv env (mkLambda i bi b)
      _ -> n

convertRuntimeNodes :: Node -> Node
convertRuntimeNodes = convertClosures

argumentInfoFromBinder :: Binder -> ArgumentInfo
argumentInfoFromBinder i =
  ArgumentInfo
    { _argumentName = i ^. binderName,
      _argumentType = i ^. binderType,
      _argumentIsImplicit = Explicit
    }

infoFromArgumentInfo :: ArgumentInfo -> Info
infoFromArgumentInfo arg =
  setInfoType (arg ^. argumentType) $
    setName
      mempty
  where
    setName :: Info -> Info
    setName i = maybe i (`setInfoName` i) (arg ^. argumentName)
