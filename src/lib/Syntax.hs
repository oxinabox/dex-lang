-- Copyright 2019 Google LLC
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StrictData #-}

module Syntax (
    Type (..), BaseType (..), EffectTypeP (..), EffectType,
    Multiplicity (..), Kind (..), ClassName (..),
    FExpr (..), FLamExpr (..), SrcPos, Pat, FDecl (..), Var,
    TVar, FTLam (..), Expr (..), Decl (..), CExpr, Con, Atom (..), LamExpr (..),
    PrimExpr (..), PrimCon (..), LitVal (..), MonadCon (..), LensCon (..), PrimOp (..),
    VSpaceOp (..), ScalarBinOp (..), ScalarUnOp (..), CmpOp (..), SourceBlock (..),
    ReachedEOF, SourceBlock' (..), TypeEnv, SubstEnv, Scope,
    RuleAnn (..), CmdName (..), Val, TopEnv (..),
    ModuleP (..), ModuleType, Module, ModBody (..),
    FModBody (..), FModule, ImpModBody (..), ImpModule,
    Array (..), ImpProg (..), ImpStatement, ImpInstr (..), IExpr (..), IVal, IPrimOp,
    IVar, IType (..), ArrayType, SetVal (..), MonMap (..), LitProg,
    SrcCtx, Result (..), Output (..), OutFormat (..), DataFormat (..),
    Err (..), ErrType (..), Except, throw, throwIf, modifyErr, addContext,
    addSrcContext, catchIOExcept, (-->), (--@), (==>), LorT (..),
    fromL, fromT, FullEnv, unitTy, sourceBlockBoundVars,
    TraversableExpr, traverseExpr, fmapExpr, freeVars, HasVars,
    strToName, nameToStr, unzipExpr, declAsModule, exprAsModule, lbind, tbind)
  where

import Data.Tuple (swap)
import qualified Data.Map.Strict as M
import Control.Applicative
import Control.Monad.Identity
import Control.Monad.Writer
import Control.Monad.Except hiding (Except)
import Control.Exception  (Exception, catch)
import GHC.Generics
import Foreign.Ptr
import Data.Traversable
import Control.Applicative (liftA3)

import Record
import Env

-- === types ===

data Type = TypeVar TVar
          | BaseType BaseType
          | ArrowType Lin Type Type
          | IdxSetLit Int
          | TabType Type Type
          | ArrayType [Int] BaseType
          | RecType (Record Type)
          | Forall [Kind] Type
          | TypeAlias [Kind] Type
          | Monad EffectType Type
          | Lens Type Type
          | TypeApp Type [Type]
          | BoundTVar Int
          | Mult Multiplicity
          | NoAnn
            deriving (Show, Eq, Generic)

data BaseType = IntType | BoolType | RealType | StrType
                deriving (Show, Eq, Generic)
type TVar = VarP Kind

data EffectTypeP ty = Effect { readerEff :: ty
                             , writerEff :: ty
                             , stateEff  :: ty }  deriving (Show, Eq, Generic)
type EffectType = EffectTypeP Type

data Multiplicity = Lin | NonLin  deriving (Show, Eq, Generic)
type Lin = Type

data Kind = TyKind [ClassName]
          | Multiplicity
            deriving (Show, Eq, Generic)
data ClassName = Data | VSpace | IdxSet  deriving (Show, Eq, Generic)

data TopEnv = TopEnv { topTypeEnv  :: TypeEnv
                     , topSubstEnv :: SubstEnv
                     , linRules    :: Env Atom }  deriving (Show, Eq, Generic)

type TypeEnv  = FullEnv Type Kind
type SubstEnv = FullEnv Atom Type

type Scope = Env ()

type ModuleType = (TypeEnv, TypeEnv)
data ModuleP body = Module ModuleType body  deriving (Show, Eq)

-- === front-end language AST ===

data FExpr = FDecl FDecl FExpr
           | FVar Var [Type]
           | FPrimExpr (PrimExpr Type FExpr FLamExpr)
           | Annot FExpr Type
           | SrcAnnot FExpr SrcPos -- TODO: make mandatory?
             deriving (Eq, Show, Generic)

type Pat = RecTree Var
data FLamExpr = FLamExpr Pat FExpr  deriving (Show, Eq, Generic)
type SrcPos = (Int, Int)

data FDecl = LetMono Pat FExpr
           | LetPoly Var FTLam
           | TyDef TVar Type
           | FRuleDef RuleAnn Type FTLam
             deriving (Show, Eq, Generic)

type Var  = VarP Type
data FTLam = FTLam [TVar] FExpr  deriving (Show, Eq, Generic)

data FModBody = FModBody [FDecl] (Env Type)  deriving (Show, Eq, Generic)
type FModule = ModuleP FModBody

data RuleAnn = LinearizationDef Name    deriving (Show, Eq, Generic)

-- === normalized core IR ===

data Expr = Decl Decl Expr
          | CExpr CExpr
          | Atom Atom
            deriving (Show, Eq, Generic)

data Decl = Let Var CExpr  deriving (Show, Eq, Generic)

type CExpr = PrimOp  Type Atom LamExpr
type Con   = PrimCon Type Atom LamExpr

data Atom = Var Var
          | TLam [TVar] Expr
          | Con Con
            deriving (Show, Eq, Generic)

data LamExpr = LamExpr Var Expr  deriving (Show, Eq, Generic)

data ModBody = ModBody [Decl] TopEnv  deriving (Show, Eq, Generic)
type Module = ModuleP ModBody
type Val = Atom

-- === primitive constructors and operators ===

data PrimExpr ty e lam = OpExpr  (PrimOp ty e lam)
                       | ConExpr (PrimCon ty e lam)
                         deriving (Show, Eq, Generic)

data PrimCon ty e lam =
        Lit LitVal
      | Lam ty lam
      | RecCon (Record e)
      | AsIdx Int e
      | MonadCon (EffectTypeP ty) ty e (MonadCon e)
      | Return (EffectTypeP ty) e
      | Bind e lam
      | LensCon (LensCon ty e)
      | Seq lam
      | AFor ty e
      | AGet e
      | ArrayRef Array
      | Todo ty
        deriving (Show, Eq, Generic)

data LitVal = IntLit  Int
            | RealLit Double
            | BoolLit Bool
            | StrLit  String
              deriving (Show, Eq, Generic)

data Array = Array [Int] BaseType (Ptr ())  deriving (Show, Eq)

data MonadCon e = MAsk | MTell e | MGet | MPut e  deriving (Show, Eq, Generic)
data LensCon ty e = IdxAsLens ty e | LensCompose e e | LensId ty
                    deriving (Show, Eq, Generic)

data PrimOp ty e lam =
        App ty e e
      | TApp e [ty]
      | For lam
      | TabGet e e
      | RecGet e RecField
      | ArrayGep e e
      | LoadScalar e
      | TabCon ty ty [e]
      | ScalarBinOp ScalarBinOp e e | ScalarUnOp ScalarUnOp e
      | VSpaceOp ty (VSpaceOp e) | Cmp CmpOp ty e e | Select ty e e e
      | MonadRun e e e | LensGet e e
      | Linearize lam | Transpose lam
      | IntAsIndex ty e | IdxSetSize ty
      | FFICall String [ty] ty [e]
      | NewtypeCast ty e
        deriving (Show, Eq, Generic)

data VSpaceOp e = VZero | VAdd e e deriving (Show, Eq, Generic)
data ScalarBinOp = IAdd | ISub | IMul | ICmp CmpOp | Pow
                 | FAdd | FSub | FMul | FCmp CmpOp | FDiv
                 | And | Or | Rem
                   deriving (Show, Eq, Generic)

data ScalarUnOp = Not | FNeg | IntToReal | BoolToInt | IndexAsInt
                  deriving (Show, Eq, Generic)

data CmpOp = Less | Greater | Equal | LessEqual | GreaterEqual
             deriving (Show, Eq, Generic)

type PrimName = PrimExpr () () ()

builtinNames :: M.Map String PrimName
builtinNames = M.fromList
  [ ("iadd", binOp IAdd), ("isub", binOp ISub), ("imul", binOp IMul)
  , ("fadd", binOp FAdd), ("fsub", binOp FSub), ("fmul", binOp FMul)
  , ("fdiv", binOp FDiv), ("pow" , binOp Pow ), ("rem" , binOp Rem )
  , ("and" , binOp And ), ("or"  , binOp Or  ), ("not" , unOp  Not )
  , ("fneg", unOp  FNeg)
  , ("inttoreal", unOp IntToReal)
  , ("booltoint", unOp BoolToInt)
  , ("asint"    , unOp IndexAsInt)
  , ("idxSetSize"      , OpExpr $ IdxSetSize ())
  , ("linearize"       , OpExpr $ Linearize ())
  , ("linearTranspose" , OpExpr $ Transpose ())
  , ("asidx"           , OpExpr $ IntAsIndex () ())
  , ("vzero"           , OpExpr $ VSpaceOp () $ VZero)
  , ("vadd"            , OpExpr $ VSpaceOp () $ VAdd () ())
  , ("newtypecast"     , OpExpr $ NewtypeCast () ())
  , ("select"          , OpExpr $ Select () () () ())
  , ("run"             , OpExpr $ MonadRun () () ())
  , ("lensGet"         , OpExpr $ LensGet () ())
  , ("ask"        , ConExpr $ MonadCon eff () () $ MAsk)
  , ("tell"       , ConExpr $ MonadCon eff () () $ MTell ())
  , ("get"        , ConExpr $ MonadCon eff () () $ MGet)
  , ("put"        , ConExpr $ MonadCon eff () () $ MPut  ())
  , ("return"     , ConExpr $ Return eff ())
  , ("idxAsLens"  , ConExpr $ LensCon $ IdxAsLens () ())
  , ("lensCompose", ConExpr $ LensCon $ LensCompose () ())
  , ("lensId"     , ConExpr $ LensCon $ LensId ())
  , ("seq"        , ConExpr $ Seq ())
  , ("todo"       , ConExpr $ Todo ())]
  where
    binOp op = OpExpr $ ScalarBinOp op () ()
    unOp  op = OpExpr $ ScalarUnOp  op ()
    eff = Effect () () ()

strToName :: String -> Maybe PrimName
strToName s = M.lookup s builtinNames

nameToStr :: PrimName -> String
nameToStr prim = case lookup prim $ map swap $ M.toList builtinNames of
  Just s  -> s
  Nothing -> show prim

-- === top-level constructs ===

data SourceBlock = SourceBlock
  { sbLine     :: Int
  , sbOffset   :: Int
  , sbText     :: String
  , sbContents :: SourceBlock' }  deriving (Show)

type ReachedEOF = Bool
data SourceBlock' = RunModule FModule
                  | Command CmdName (Var, FModule)
                  | GetNameType Var
                  | IncludeSourceFile String
                  | LoadData Pat DataFormat String
                  | ProseBlock String
                  | CommentLine
                  | EmptyLines
                  | UnParseable ReachedEOF String
                    deriving (Show, Eq, Generic)

data CmdName = GetType | ShowPasses | ShowPass String
             | TimeIt | Flops | EvalExpr OutFormat | Dump DataFormat String
                deriving  (Show, Eq, Generic)

declAsModule :: FDecl -> FModule
declAsModule decl = Module (freeVars decl, fDeclBoundVars decl) (FModBody [decl] mempty)

exprAsModule :: FExpr -> (Var, FModule)
exprAsModule expr = (v, Module (freeVars expr, lbind v) (FModBody body mempty))
  where v = "*ans*" :> NoAnn
        body = [LetMono (RecLeaf v) expr]

-- === imperative IR ===

data ImpModBody = ImpModBody [IVar] ImpProg TopEnv
type ImpModule = ModuleP ImpModBody

newtype ImpProg = ImpProg [ImpStatement]  deriving (Show, Semigroup, Monoid)
type ImpStatement = (Maybe IVar, ImpInstr)

data ImpInstr = Load  IExpr
              | Store IExpr IExpr  -- destination first
              | Copy  IExpr IExpr  -- destination first
              | Alloc ArrayType
              | Free IVar
              | Loop IVar Size ImpProg
              | IPrimOp IPrimOp
                deriving (Show)

data IExpr = ILit LitVal
           | IRef Array
           | IVar IVar
           | IGet IExpr Index
               deriving (Show, Eq)

type IPrimOp = PrimOp BaseType IExpr ()
type IVal = IExpr  -- only ILit and IRef constructors
type IVar = VarP IType
data IType = IValType BaseType
           | IRefType ArrayType
              deriving (Show, Eq)

type ArrayType = (BaseType, [Size])

type Size  = IExpr
type Index = IExpr

-- === some handy monoids ===

data SetVal a = Set a | NotSet
newtype MonMap k v = MonMap (M.Map k v)

instance Semigroup (SetVal a) where
  x <> NotSet = x
  _ <> Set x  = Set x

instance Monoid (SetVal a) where
  mempty = NotSet

instance (Ord k, Semigroup v) => Semigroup (MonMap k v) where
  MonMap m <> MonMap m' = MonMap $ M.unionWith (<>) m m'

instance (Ord k, Semigroup v) => Monoid (MonMap k v) where
  mempty = MonMap mempty

-- === outputs ===

type LitProg = [(SourceBlock, Result)]
type SrcCtx = Maybe SrcPos
data Result = Result [Output] (Except ())  deriving (Show, Eq)

data Output = TextOut String
            | HeatmapOut Int Int [Double]
            | ScatterOut [Double] [Double]
            | PassInfo String String String
              deriving (Show, Eq, Generic)

data OutFormat = Printed | Heatmap | Scatter   deriving (Show, Eq, Generic)
data DataFormat = DexObject | DexBinaryObject  deriving (Show, Eq, Generic)

data Err = Err ErrType SrcCtx String  deriving (Show, Eq)
instance Exception Err

data ErrType = NoErr
             | ParseErr
             | TypeErr
             | LinErr
             | UnboundVarErr
             | RepeatedVarErr
             | CompilerErr
             | NotImplementedErr
             | DataIOErr
             | MiscErr
  deriving (Show, Eq)

type Except a = Either Err a


throw :: MonadError Err m => ErrType -> String -> m a
throw e s = throwError $ Err e Nothing s

throwIf :: MonadError Err m => Bool -> ErrType -> String -> m ()
throwIf True  e s = throw e s
throwIf False _ _ = return ()

modifyErr :: MonadError e m => m a -> (e -> e) -> m a
modifyErr m f = catchError m $ \e -> throwError (f e)

addContext :: MonadError Err m => String -> m a -> m a
addContext s m = modifyErr m $ \(Err e p s') -> Err e p (s' ++ s)

addSrcContext :: MonadError Err m => SrcCtx -> m a -> m a
addSrcContext ctx m = modifyErr m updateErr
  where
    updateErr :: Err -> Err
    updateErr (Err e ctx' s) = case ctx' of Nothing -> Err e ctx  s
                                            Just _  -> Err e ctx' s

catchIOExcept :: (MonadIO m , MonadError Err m) => IO a -> m a
catchIOExcept m = do
  ans <- liftIO $ catch (liftM Right m) $ \e -> return (Left (e::Err))
  liftEither ans

-- === misc ===

infixr 1 -->
infixr 1 --@
infixr 2 ==>

(-->) :: Type -> Type -> Type
(-->) = ArrowType (Mult NonLin)

(--@) :: Type -> Type -> Type
(--@) = ArrowType (Mult Lin)

(==>) :: Type -> Type -> Type
(==>) = TabType

data LorT a b = L a | T b  deriving (Show, Eq)

fromL :: LorT a b -> a
fromL (L x) = x
fromL _ = error "Not a let-bound thing"

fromT :: LorT a b -> b
fromT (T x) = x
fromT _ = error "Not a type-ish thing"

unitTy :: Type
unitTy = RecType (Tup [])

type FullEnv v t = Env (LorT v t)

-- === substitutions ===

type Vars = TypeEnv

lbind :: Var -> Vars
lbind v@(_:>ty) = v @> L ty

tbind :: TVar -> Vars
tbind v@(_:>k) = v @> T k

class HasVars a where
  freeVars :: a -> Vars

instance HasVars FExpr where
  freeVars expr = case expr of
    FDecl decl body -> freeVars decl <> (freeVars body `envDiff` fDeclBoundVars decl)
    FVar v@(_:>ty) tyArgs -> v@>L ty <> freeVars ty <> foldMap freeVars tyArgs
    FPrimExpr e  -> freeVars e
    Annot e ty   -> freeVars e <> freeVars ty
    SrcAnnot e _ -> freeVars e

fDeclBoundVars :: FDecl -> Vars
fDeclBoundVars decl = case decl of
  LetMono p _    -> foldMap lbind p
  LetPoly v _    -> lbind v
  FRuleDef _ _ _ -> mempty
  TyDef v _      -> tbind v

sourceBlockBoundVars :: SourceBlock -> Vars
sourceBlockBoundVars block = case sbContents block of
  RunModule (Module (_,vs) _) -> vs
  LoadData p _ _           -> foldMap lbind p
  _                        -> mempty

instance HasVars FLamExpr where
  freeVars (FLamExpr p body) =
    foldMap freeVars p <> (freeVars body `envDiff` foldMap lbind p)

instance HasVars Type where
  freeVars ty = case ty of
    BaseType _ -> mempty
    TypeVar v  -> v @> T (varAnn v)
    ArrowType l a b -> freeVars l <> freeVars a <> freeVars b
    TabType a b -> freeVars a <> freeVars b
    ArrayType _ _ -> mempty
    RecType r   -> foldMap freeVars r
    TypeApp a b -> freeVars a <> foldMap freeVars b
    Forall    _ body -> freeVars body
    TypeAlias _ body -> freeVars body
    Monad eff a -> foldMap freeVars eff <> freeVars a
    Lens a b    -> freeVars a <> freeVars b
    IdxSetLit _ -> mempty
    BoundTVar _ -> mempty
    Mult _      -> mempty
    NoAnn       -> mempty

instance HasVars b => HasVars (VarP b) where
  freeVars (_ :> b) = freeVars b

instance HasVars () where
  freeVars () = mempty

instance HasVars FDecl where
   freeVars (LetMono p expr)   = foldMap freeVars p <> freeVars expr
   freeVars (LetPoly b tlam)   = freeVars b <> freeVars tlam
   freeVars (TyDef _ ty)       = freeVars ty
   freeVars (FRuleDef ann ty body) = freeVars ann <> freeVars ty <> freeVars body

instance HasVars RuleAnn where
  freeVars (LinearizationDef v) = (v:>()) @> L unitTy

instance HasVars FTLam where
  freeVars (FTLam tbs expr) = freeVars expr `envDiff` foldMap tbind tbs

instance (HasVars a, HasVars b) => HasVars (LorT a b) where
  freeVars (L x) = freeVars x
  freeVars (T x) = freeVars x

instance HasVars SourceBlock where
  freeVars block = case sbContents block of
    RunModule (Module (vs, _) _)    -> vs
    Command _ (_, Module (vs, _) _) -> vs
    GetNameType v                   -> v @> L (varAnn v)
    _ -> mempty

instance HasVars Expr where
  freeVars expr = case expr of
    Decl decl body -> freeVars decl <> (freeVars body `envDiff` declBoundVars decl)
    CExpr primop   -> freeVars primop
    Atom atom      -> freeVars atom

declBoundVars :: Decl -> Env ()
declBoundVars decl = case decl of
  Let b _ -> b@>()

instance HasVars LamExpr where
  freeVars (LamExpr b body) = freeVars b <> (freeVars body `envDiff` (b@>()))

instance HasVars Atom where
  freeVars atom = case atom of
    Var v@(_:>ty) -> v @> L ty <> freeVars ty
    TLam tvs body -> freeVars body `envDiff` foldMap (@>()) tvs
    Con con   -> freeVars con

instance HasVars Kind where
  freeVars _ = mempty

instance HasVars Decl where
  freeVars (Let bs expr) = foldMap freeVars bs <> freeVars expr

instance HasVars a => HasVars (Env a) where
  freeVars env = foldMap freeVars env

instance HasVars TopEnv where
  freeVars (TopEnv e1 e2 e3) = freeVars e1 <> freeVars e2 <> freeVars e3

instance (HasVars a, HasVars b) => HasVars (Either a b)where
  freeVars (Left  x) = freeVars x
  freeVars (Right x) = freeVars x

instance HasVars ModBody where
  freeVars (ModBody (decl:decls) results) =
    freeVars decl <> (freeVars (ModBody decls results) `envDiff` declBoundVars decl)
  freeVars (ModBody [] results) = freeVars results

fmapExpr :: TraversableExpr expr
         => expr ty e lam
         -> (ty  -> ty')
         -> (e   -> e')
         -> (lam -> lam')
         -> expr ty' e' lam'
fmapExpr e fT fE fL =
  runIdentity $ traverseExpr e (return . fT) (return . fE) (return . fL)

class TraversableExpr expr where
  traverseExpr :: Applicative f
               => expr ty e lam
               -> (ty  -> f ty')
               -> (e   -> f e')
               -> (lam -> f lam')
               -> f (expr ty' e' lam')

instance TraversableExpr PrimExpr where
  traverseExpr (OpExpr  e) fT fE fL = liftA OpExpr  $ traverseExpr e fT fE fL
  traverseExpr (ConExpr e) fT fE fL = liftA ConExpr $ traverseExpr e fT fE fL

instance TraversableExpr PrimOp where
  traverseExpr primop fT fE fL = case primop of
    App ty e1 e2         -> liftA3 App (fT ty) (fE e1) (fE e2)
    TApp e tys           -> liftA2 TApp (fE e) (traverse fT tys)
    For lam              -> liftA  For (fL lam)
    TabCon n ty xs       -> liftA3 TabCon (fT n) (fT ty) (traverse fE xs)
    TabGet e i           -> liftA2 TabGet (fE e) (fE i)
    RecGet e i           -> liftA2 RecGet (fE e) (pure i)
    ArrayGep e i         -> liftA2 ArrayGep (fE e) (fE i)
    LoadScalar e         -> liftA  LoadScalar (fE e)
    ScalarBinOp op e1 e2 -> liftA2 (ScalarBinOp op) (fE e1) (fE e2)
    ScalarUnOp  op e     -> liftA  (ScalarUnOp  op) (fE e)
    VSpaceOp ty VZero    -> liftA2 VSpaceOp (fT ty) (pure VZero)
    VSpaceOp ty (VAdd e1 e2) -> liftA2 VSpaceOp (fT ty) (liftA2 VAdd (fE e1) (fE e2))
    Cmp op ty e1 e2      -> liftA3 (Cmp op) (fT ty) (fE e1) (fE e2)
    Select ty p x y      -> liftA3 Select (fT ty) (fE p) (fE x) <*> fE y
    MonadRun r s m       -> liftA3  MonadRun (fE r) (fE s) (fE m)
    LensGet e1 e2        -> liftA2 LensGet (fE e1) (fE e2)
    Linearize lam        -> liftA  Linearize (fL lam)
    Transpose lam        -> liftA  Transpose (fL lam)
    IntAsIndex ty e      -> liftA2 IntAsIndex (fT ty) (fE e)
    IdxSetSize ty        -> liftA  IdxSetSize (fT ty)
    NewtypeCast ty e     -> liftA2 NewtypeCast (fT ty) (fE e)
    FFICall s argTys ansTy args ->
      liftA3 (FFICall s) (traverse fT argTys) (fT ansTy) (traverse fE args)

instance TraversableExpr PrimCon where
  traverseExpr op fT fE fL = case op of
    Lit l       -> pure   (Lit l)
    Lam lin lam -> liftA2 Lam (fT lin) (fL lam)
    AFor n e    -> liftA2 AFor (fT n) (fE e)
    AGet e      -> liftA  AGet (fE e)
    AsIdx n e   -> liftA  (AsIdx n) (fE e)
    RecCon r    -> liftA  RecCon (traverse fE r)
    Bind e lam  -> liftA2 Bind (fE e) (fL lam)
    MonadCon eff t l m -> liftA3 MonadCon (traverse fT eff) (fT t) (fE l) <*> (case m of
       MAsk    -> pure  MAsk
       MTell e -> liftA MTell (fE e)
       MGet    -> pure  MGet
       MPut  e -> liftA MPut  (fE e))
    Return eff e -> liftA2 Return (traverse fT eff) (fE e)
    LensCon l -> liftA LensCon $ case l of
      IdxAsLens ty e    -> liftA2 IdxAsLens (fT ty) (fE e)
      LensCompose e1 e2 -> liftA2 LensCompose (fE e1) (fE e2)
      LensId ty         -> liftA  LensId (fT ty)
    Seq lam             -> liftA  Seq (fL lam)
    Todo ty             -> liftA  Todo (fT ty)
    ArrayRef ref        -> pure $ ArrayRef ref

instance (TraversableExpr expr, HasVars ty, HasVars e, HasVars lam)
         => HasVars (expr ty e lam) where
  freeVars expr = execWriter $
    traverseExpr expr (tell . freeVars) (tell . freeVars) (tell . freeVars)

unzipExpr :: TraversableExpr expr
          => expr ty e lam -> (expr () () (), ([ty], [e], [lam]))
unzipExpr expr = (blankExpr, xs)
  where
    blankExpr = fmapExpr expr (const ()) (const ()) (const ())
    xs = execWriter $ traverseExpr expr
            (\ty  -> tell ([ty], [] , []   ))
            (\e   -> tell ([]  , [e], []   ))
            (\lam -> tell ([]  , [] , [lam]))

instance RecTreeZip Type where
  recTreeZip (RecTree r) (RecType r') = RecTree $ recZipWith recTreeZip r r'
  recTreeZip (RecLeaf x) x' = RecLeaf (x, x')
  recTreeZip (RecTree _) _ = error "Bad zip"

instance Functor EffectTypeP where
  fmap = fmapDefault

instance Foldable EffectTypeP where
  foldMap = foldMapDefault

instance Traversable EffectTypeP where
  traverse f (Effect r w s) = liftA3 Effect (f r) (f w) (f s)

instance Semigroup TopEnv where
  TopEnv e1 e2 e3 <> TopEnv e1' e2' e3' = TopEnv (e1 <> e1') (e2 <> e2') (e3 <> e3')

instance Monoid TopEnv where
  mempty = TopEnv mempty mempty mempty

instance Eq SourceBlock where
  x == y = sbText x == sbText y

instance Ord SourceBlock where
  compare x y = compare (sbText x) (sbText y)
