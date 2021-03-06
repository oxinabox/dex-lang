-- Copyright 2019 Google LLC
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

{-# LANGUAGE OverloadedStrings #-}

module LLVMExec (showLLVM, evalJit, showAsm) where

import qualified LLVM.Analysis as L
import qualified LLVM.AST as L
import qualified LLVM.Module as Mod
import qualified LLVM.PassManager as P
import qualified LLVM.ExecutionEngine as EE
import qualified LLVM.Target as T
import LLVM.Context

import Foreign.Ptr
import Control.Exception
import Control.Monad
import Data.ByteString.Char8 (unpack)

foreign import ccall "dynamic"
  haskFun :: FunPtr (IO ()) -> IO ()

evalJit :: L.Module -> IO ()
evalJit m = do
  T.initializeAllTargets
  withContext $ \c ->
    Mod.withModuleFromAST c m $ \m' -> do
      L.verify m'
      runPasses m'
      jit c $ \ee ->
         EE.withModuleInEngine ee m' $ \eee -> do
           f <- EE.getFunction eee (L.Name "thefun")
           case f of
             Just f' -> runJitted f'
             Nothing -> error "Failed to fetch \"thefun\" from LLVM"

jit :: Context -> (EE.MCJIT -> IO a) -> IO a
jit c = EE.withMCJIT c (Just 3) Nothing Nothing Nothing

runJitted :: FunPtr a -> IO ()
runJitted fn = haskFun (castFunPtr fn :: FunPtr (IO ()))

runPasses :: Mod.Module -> IO ()
runPasses m = P.withPassManager passes $ \pm -> void $ P.runPassManager pm m

showLLVM :: L.Module -> IO String
showLLVM m = do
  T.initializeAllTargets
  withContext $ \c ->
    Mod.withModuleFromAST c m $ \m' -> do
      verifyErr <- verifyAndRecover m'
      prePass <- showModule m'
      runPasses m'
      postPass <- showModule m'
      return $ verifyErr ++ "Input LLVM:\n\n" ++ prePass
            ++ "\nAfter passes:\n\n" ++ postPass
  where
    showModule :: Mod.Module -> IO String
    showModule m' = liftM unpack $ Mod.moduleLLVMAssembly m'

verifyAndRecover :: Mod.Module -> IO String
verifyAndRecover m =
  (L.verify m >> return  "") `catch`
    (\e -> return ("\nVerification error:\n" ++ show (e::SomeException) ++ "\n"))

showAsm :: L.Module -> IO String
showAsm m =
  withContext $ \c ->
    Mod.withModuleFromAST c m $ \m' -> do
      runPasses m'
      T.withHostTargetMachine $ \t ->
        liftM unpack $ Mod.moduleTargetAssembly t m'

passes :: P.PassSetSpec
passes = P.defaultCuratedPassSetSpec {P.optLevel = Just 3}
