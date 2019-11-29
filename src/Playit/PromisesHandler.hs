{- |
 * Maneja el tipo TPDummy que representa el tipo de retorno de una función que todavía
 no ha sido declarado,
 *
 * Copyright : (c) 
 *  Manuel Gonzalez     11-10390
 *  Francisco Javier    12-11163
 *  Natascha Gamboa     12-11250
-}

module Playit.PromisesHandler where


import Control.Monad (when,unless,void,forM,forM_)
import Control.Monad.Trans.RWS
--import qualified Data.Map as M
import Data.Maybe (isJust,fromJust,fromMaybe)
import Playit.AuxFuncs
import Playit.Errors
import Playit.SymbolTable
import Playit.Types



-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                               Updates
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
{- |
  Dada una expresion cuyo tipo de sus llamadas a funciones no se ha decidido. 
  Ejemplo:
    // Donde funcion1 y funcion2 no se han declarado y no se sabe si es suma de
    // enteros o flotantes
    funcion1() + funcion2()

  Le asigna a las promesas funcion1 y funcion2 el tipo de retorno t
-}
updateExpr :: Expr -> Type -> MonadSymTab Expr
updateExpr (Binary op e1 e2 TPDummy) t = do
  ne1 <- updateExpr e1 t
  ne2 <- updateExpr e2 t
  return (Binary op ne1 ne2 t)

updateExpr (Binary Anexo e1 e2 _) tl@(TList t) = do    
  ne1 <- updateExpr e1 t
  ne2 <- updateExpr e2 tl

  let ntr = fromMaybe TError (getTLists [TList (typeE ne1),typeE ne2])
  return (Binary Anexo ne1 ne2 ntr)

updateExpr (FuncCall (Call name args) tf ) t =
  updatePromise name t >> return (FuncCall (Call name args) t)

updateExpr (ArrayList exprs _ ) tl@(TList t)  = do
  -- nexprs <- mapM (\e -> updateExpr e t) exprs
  nexprs <- mapM (`updateExpr` t) exprs
  let
    mapTypes = map typeE nexprs
    ntr      = case getTLists mapTypes of
      Just nt -> TList nt
      Nothing -> TError

  return (ArrayList nexprs ntr)

updateExpr e _   = return e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- |  Le asigna a una funcion promesa el tipo de retorno pasado como argumento.
updatePromise :: Id -> Type -> MonadSymTab ()
updatePromise name t = do
  (symTab, activeScopes, scope, promises) <- get
  let promise = getPromiseSubroutine name promises

  if isJust promise then

    let
      promise'    = fromJust promise
      typePromise = getTypePromise promise'
    in
    if isJust (getTLists [typePromise,t]) then do
      let 
          modifyTypePromise prom@(Promise id p _ pos ch) = 
              if id == name then Promise id p t pos ch else prom

      put(symTab, activeScopes, scope , map modifyTypePromise promises)
      updateType name 1 t
      checkExpresionesPromise promise' t

    else {-when (typePromise /= t) $-} do
      -- error $ semmErrorMsg (show t) (show typePromise) fileCode p
      error "Internal error updatePromise: IS THIS GONNA GET EXECUTED? LOL"
      -- return ()
  else do
    -- error $ "Internal error updatePromise: Promise for '"  ++ name ++ "' is not defined!"
    return ()
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Dada una expresion en donde aparecen llamadas a funciones con tipo de retorno
-- indeterminados, se buscan todas esas llamadas y se les agrega una expresion
-- que se debe chequear cuando se actualizen los datos de las llamadas a la funcion
addLateCheck :: Expr -> Expr -> [Pos] -> [Id] -> MonadSymTab ()
addLateCheck (Binary op e1 e2 _) e lpos lids =
  addLateCheck e1 e lpos lids >> addLateCheck e2 e lpos lids

addLateCheck (IfSimple e1 e2 e3 _) e lpos lids =
  addLateCheck e1 e lpos lids >> addLateCheck e2 e lpos lids >> addLateCheck e3 e lpos lids

addLateCheck (ArrayList exprs _ ) e lpos lids =
    mapM_ (\e1 -> addLateCheck e1 e lpos lids) exprs

addLateCheck (FuncCall (Call name _) TPDummy ) e lpos lids =
    addSubroutinePromiseLateChecks name e lpos lids
--addLateCheck (FuncCall (Call name _) TDummy ) e lpos lids   = do
    --addSubroutinePromiseLateChecks name e lpos lids

addLateCheck _ _ _ _   = return ()
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Dada una expresion regresa todos los identificadores de promesas a
-- funciones asociadas
getRelatedPromises :: Expr -> [Id]
getRelatedPromises (Binary _ e1 e2 _)    = l3
  where
    le1 = getRelatedPromises e1
    le2 = getRelatedPromises e2
    l3  = le1 ++ le2
getRelatedPromises (IfSimple e1 e2 e3 _) = l4
  where
    le1 = getRelatedPromises e1
    le2 = getRelatedPromises e2
    le3 = getRelatedPromises e3
    l4  = le1 ++ le2 ++ le3
getRelatedPromises (Unary _ e _)      = getRelatedPromises e
getRelatedPromises (Read e _)         = getRelatedPromises e
getRelatedPromises (ArrayList expr _) = concatMap getRelatedPromises expr
getRelatedPromises (FuncCall (Call name _) TPDummy) = [name]
getRelatedPromises _                                = []
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- rename to addLateCheks
-- | Actualiza una promesa agregandole un check que se realizara cuando se
-- actualize su tipo de retorno
addSubroutinePromiseLateChecks :: Id -> Expr->[Pos] -> [Id] ->MonadSymTab ()
addSubroutinePromiseLateChecks name expr lpos lids = do
  (symTab, activeScopes, scope, promises) <- get
  let promise = getPromiseSubroutine name promises

  if isJust promise then do

    let
      promise'    = fromJust promise
      checks      = getLateChecksPromise promise'
      typePromise = getTypePromise promise'
      nlids       = filter (/= name) lids

    if (typePromise `elem` [TPDummy,TDummy] || (isList typePromise && baseTypeT typePromise `elem` [TPDummy,TDummy])) && not (any (\c -> getLCPromiseExpr c == expr) checks) then do

      let 
        nlc = LateCheckPromise expr lpos nlids
        modifyTypePromise prom@(Promise id p t pos ch) = 
            if id == name then Promise id p t pos (ch ++ [nlc]) else prom

      put(symTab, activeScopes, scope , map modifyTypePromise promises)

    else
      when (typePromise /= TPDummy) $ do
        error $ "ADSasd " ++ show typePromise ++ " expr: " ++ show expr
        error "Internal error AddSubroutinePromiseLateChecks : IS THIS GONNA GET EXECUTED? LOL I HOPE NOT... it shouldnt...right?"

  else
    error $ "Internal error AddSubroutinePromiseLateChecks : Promise for '"  ++ name ++ "' is not defined!"
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                               Checks
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Chequea las expresiones de una promesa dado que se le actualizó su tipo
-- Se deben eliminar todos los checks debido a que solo se actualiza el tipo 
-- una sola vez
checkExpresionesPromise :: Promise -> Type-> MonadSymTab ()
checkExpresionesPromise promise tr = do
  let 
    name    = getIdPromise promise
    params  = getParamsPromise promise
    checks  = getLateChecksPromise promise

  newcheck' <- forM_ checks $ \(LateCheckPromise e1 lpos1 lids1) -> do

    (symTab, activeScopes, scope,promises) <- get
    let
      newcheck = LateCheckPromise (changeTPDummyFunctionInExpre name e1 tr) lpos1 lids1
      ne1 = getLCPromiseExpr newcheck

    checkTypesLC ne1 lpos1
    
    lnp <- forM lids1 $ \idpl -> do
      let promise = getPromiseSubroutine idpl promises
      
      if isJust promise then do
        let
          (Promise id2 p2 t2 pos2 ch2) = fromJust promise
          nch2 = map (\lcp@(LateCheckPromise e2 lpos2 lids2) -> if e2 == e1 then LateCheckPromise ne1 lpos2 lids2 else  lcp) ch2
          np = Promise id2 p2 t2 pos2 nch2

        return [np]
      else return []

    let 
      lnp2           = concat lnp
      lnpids         = map (\p -> (getIdPromise p, p)) lnp2
      isToUpdate p   = any (\(id,_) -> id == getIdPromise p) lnpids
      promTpUpdate p = snd $ head $ filter (\(id,_) -> id == getIdPromise p) lnpids
      modifyTypePromise prom = if isToUpdate prom then promTpUpdate prom else prom

    put(symTab, activeScopes, scope , map modifyTypePromise promises)
    return newcheck

  -- TODO :Eliminar solo si se actualiza a un tipo concreto
  (symTab, activeScopes, scope,promises) <- get

  let 
    modifyTypePromise prom@(Promise id p t pos ch) = 
      if id == name then Promise id p t pos (if isRealType tr then [] else newcheck') else prom

  put(symTab, activeScopes, scope, map modifyTypePromise promises)
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- rename to changeTPDummy
-- | Cambia el tipo de retorno de la función en los contextos en los cuales aparece
changeTPDummyFunctionInExpre :: Id  -> Expr -> Type -> Expr
changeTPDummyFunctionInExpre name f@(FuncCall (Call id args) _) t =
  if id == name then
    FuncCall (Call name args) t
  else f
-- Solo sucede con Anexo o + , - , * , /
changeTPDummyFunctionInExpre name (Binary op e1 e2 tb) t = Binary op ne1 ne2 ntb 
  where 
    ne1        = changeTPDummyFunctionInExpre name e1 t
    ne2        = changeTPDummyFunctionInExpre name e2 t
    tE1        = typeE ne1
    tE2        = typeE ne2
    isAritOp x = x `elem` [Add, Minus, Mult, Division]
    ntb        = case op of -- TODO: Falta caso  concatenación
      Anexo  -> fromMaybe TError (getTLists [TList tE1,tE2])
      Concat -> fromMaybe TError (getTLists [tE1,tE2])      
      x | isAritOp x && (tE1 == TPDummy || tE2 == TPDummy) ->
          TDummy
          -- TODO : Faltan inferencias aquí para e2 o e1 si el otro es concreto
        | isAritOp x && (tE1 == TInt || tE1 == TFloat) && tE2 == tE1 -> tE1
        | otherwise -> TError
      _   -> tb

changeTPDummyFunctionInExpre name (IfSimple e1 e2 e3 ti) t = IfSimple ne1 ne2 ne3 ti
  where
    ne1 = changeTPDummyFunctionInExpre name e1 t
    ne2 = changeTPDummyFunctionInExpre name e2 t
    ne3 = changeTPDummyFunctionInExpre name e3 t

changeTPDummyFunctionInExpre name (Unary op e1 tu) t       = Unary op (changeTPDummyFunctionInExpre name e1 t) tu
changeTPDummyFunctionInExpre name (Read e1 tr) t           = Read (changeTPDummyFunctionInExpre name e1 t) tr
changeTPDummyFunctionInExpre name (ArrayList expr ta) t    = ArrayList nexpr nta
  where
    nexpr = map (\e ->changeTPDummyFunctionInExpre name e t) expr
    mapTypes = map typeE nexpr
    -- TODO: Falta manejar TError en getTLists para multiples errore
    nta = case getTLists mapTypes of
      Just t ->  TList t
      Nothing -> TError

changeTPDummyFunctionInExpre name l@(Literal _ _) _  = l
changeTPDummyFunctionInExpre name v@(Variable _ _) _ = v
changeTPDummyFunctionInExpre name Null _             = Null
changeTPDummyFunctionInExpre name e _                = error $ "e : " ++ show e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
checkBinaryExpr :: BinOp -> Expr -> Pos-> Expr -> Pos -> MonadSymTab Bool
checkBinaryExpr op e1 p1 e2 p2 = do
  fileCode <- ask
  let
    tE1     = typeE e1
    tE2     = typeE e2
    eqOps   = [Eq, NotEq]
    compOps = [Eq, NotEq, GreaterEq, LessEq, Greater, Less]
    aritOps = [Add, Minus, Mult, Division]
    aritInt = [DivEntera, Module]
    boolOps = [And, Or]

  if tE1 /= tE2 then -- Si son distintos los tipos de las funciones

    if op `elem` eqOps then
      
      if isTypeComparableEq tE1 &&  not (isTypeComparableEq tE2) then
        error $ semmErrorMsg (show tE1) (show tE2) fileCode p2
      else 
        if not (isTypeComparableEq tE1) &&  isTypeComparableEq tE2 then
          error $ semmErrorMsg (show tE2) (show tE1) fileCode p1
        else
          if isTypeComparableEq tE1 && isTypeComparableEq tE2 then
            error $ semmErrorMsg (show tE1) (show tE2) fileCode p2
          else 
            error $ semmErrorMsg "Tipo comparable" (show tE1) fileCode p1

    else 

      if (op `elem` compOps ) || (op `elem` aritOps )then

        if isTypeNumber tE1 &&  not (isTypeNumber tE2) then
          error $ semmErrorMsg (show tE1) (show tE2) fileCode p2
        else 
          if not (isTypeNumber tE1) &&  isTypeNumber tE2 then
            error $ semmErrorMsg (show tE2) (show tE1) fileCode p1
          else 
            if isTypeNumber tE1  && isTypeNumber tE2 then
              error $ semmErrorMsg (show tE1) (show tE2) fileCode p2
            else 
              error $ semmErrorMsg "Power or Skill" (show tE1) fileCode p1

      else 
        if op `elem` aritInt then

          if tE1 == TInt then error $ semmErrorMsg (show tE1) (show tE2) fileCode p2
          else 
            if tE2 == TInt then error $ semmErrorMsg (show tE2) (show tE1) fileCode p1
            else error $ semmErrorMsg "Power" (show tE1) fileCode p1

        else 
          if op `elem` boolOps then

            if tE1 == TBool then error $ semmErrorMsg (show tE1) (show tE2) fileCode p2
            else 
              if (tE1 /= TBool) && (tE2 == TBool) then error $ semmErrorMsg (show tE2) (show tE1) fileCode p1
              else error $ semmErrorMsg "Battle" (show tE1) fileCode p1

          else
            when (op == Anexo) $
              let typeR = fromMaybe TError (getTLists [TList tE1,tE2])
              in
              when (typeR == TError) $
                error $ semmErrorMsg (show (TList tE1)) (show tE2) fileCode p2

  else --- Si son iguales los tipos de las expresiones 
    if op `elem` eqOps then
      unless (isTypeComparableEq tE1) $           
        error $ semmErrorMsg "Tipo comparable" (show tE1) fileCode p1
      
    else
      if op `elem` compOps || op `elem` aritOps then
        when (tE1 /= TInt) && (tE1 /= TFloat) $
          error $ semmErrorMsg "Power or Skill" (show tE1) fileCode p1
      else
        if op `elem` aritInt then
          when (tE1 /= TInt) $
            error $ semmErrorMsg "Power" (show tE1) fileCode p1
        else
          if op `elem` boolOps then
            when (tE1 /= TBool) $
              error $ semmErrorMsg "Battle" (show tE1) fileCode p1
          else
            when (op == Anexo) $ do
              -- TODO: Sin hacer
              error "Not implemented anexo with promises"

  return True
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Checkea que la expresion sea correcta
checkTypesLC :: Expr -> [Pos] -> MonadSymTab ()
checkTypesLC (Binary op e1 e2 _) pos =
  when isRealType (typeE e1) && isRealType (typeE e2) $ -- En caso que alguno todavia no se haya leido/inferido no se checkea
    checkBinaryExpr op e1 (head pos) e2 (pos !! 1)

checkTypesLC (IfSimple e1 e2 e3 _) lpos = do
  let 
    tE1 = typeE e1
    tE2 = typeE e2
    te3 = typeE e3

  when (tE1 /= TPDummy && tE2 /= TPDummy && te3 /= TPDummy) $ do
    fileCode <- ask

    if tE1 == TBool then
      let mbTypeR = getTLists [tE2,te3] -- Simula crear una lista que contiene esos dos tipos para ahorrar calculos
      in
      when (isNothing mbTypeR) $
        if isRealType tE2 && not (isRealType te3) then
          error $ semmErrorMsg (show tE2) (show te3) fileCode (lpos !! 2)
        else
          if not (isRealType tE2) && isRealType te3 then
            error $ semmErrorMsg (show te3) (show tE2) fileCode (lpos !! 1)
          else
            error $ semmErrorMsg (show tE2) (show te3) fileCode (lpos !! 2)
    else
        error $ semmErrorMsg "Battle" (show tE1) fileCode (head lpos)

checkTypesLC (ArrayList exprs _) pos = do
  let
    mapTypes = map typeE exprs
    nta = getTLists mapTypes

  unless (isJust nta) $ do
    fileCode <- ask
    let 
      exprsP = zip exprs pos
      l = filter (\(e,p) -> typeE e `notElem` [TDummy, TPDummy]) exprsP
      (e,p) = head l
      expected = typeE e
      got = head $ dropWhile (\(e,p) -> typeE e == expected) l

    error $ semmErrorMsg (show expected) (show $ typeE $ fst got) fileCode (snd got)
-------------------------------------------------------------------------------
