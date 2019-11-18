{- |
 * Creates de abstract syntax tree with type checks
 *
 * Copyright : (c) 
 *  Manuel Gonzalez     11-10390
 *  Francisco Javier    12-11163
 *  Natascha Gamboa     12-11250
-}
module Playit.AST where

import Control.Monad (void,forM,forM_)
import Control.Monad.Trans.RWS
import qualified Data.Map as M
import Data.Maybe (fromJust, isJust, isNothing)
import Playit.CheckAST
import Playit.Errors
import Playit.SymbolTable
import Playit.AuxFuncs
import Playit.Types


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                           Create AST nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates variables ids node
var :: Id -> Pos -> MonadSymTab Var
var id p = do
    (symTab, activeScopes, _,_) <- get
    fileCode <- ask
    let infos = lookupInScopes activeScopes id symTab

    if isJust infos then do
        let vars = [Variables, Parameters Value, Parameters Reference]
            isVar symInfo = getCategory symInfo `elem` vars
            v = filter isVar (fromJust infos)

        if null v then
            error $ errorMsg "This is not a variable" fileCode p
        else
            return $ Var id (getType $ head v)

    else error $ errorMsg "Variable not declared in active scopes" fileCode p
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates idexed variables node
index :: Var -> Expr -> Pos -> Pos -> MonadSymTab Var
index var expr (lV,cV) (lE,cE) = do
    let pVar  = (lV-1, cV-1)
        pExpr = (lE-1, cE-1)

    (ok,tVar) <- checkIndex var (typeE expr) pVar pExpr
    
    if ok then return $ Index var expr tVar
    else return $ Index var expr TError -- change when no exit with first error encounter
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the registers / unions fields
field :: Var -> Id -> Pos -> MonadSymTab Var
field var field p = do
    (symTab, _, _,_) <- get
    fileCode@(file,code) <- ask
    
    -- Verify type 'var' is register / union
    let reg = case baseTypeVar var of 
                (TNew name) -> name
                _           -> ""
    
    if reg == "" then -- Type error
        error $ errorMsg "Type of field isn't a register or union" fileCode p
    else do
        
        --chequearTipo reg p
        
        let info = lookupInSymTab field symTab

        if isJust info then do
            let isInRegUnion (SymbolInfo _ _ c e) = c == Fields && getReg e == reg
                symbols = filter isInRegUnion (fromJust info )
                        
            if null symbols then
                error $ errorMsg ("Field not in '"++reg++"'") fileCode p
            else 
                return $ Field var field (getType $ head symbols) 
        else
            error $ errorMsg "Field not declared" fileCode p
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the desreferentiation variable node
desref :: Var -> Pos -> MonadSymTab Var
desref var p = do
    (ok,tVar) <- checkDesref (typeVar var) p
    
    if ok then return $ Desref var tVar
    else return $ Desref var TError -- change when no exit with first error encounter
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the TNew type
newType :: Id -> Pos -> MonadSymTab Type
newType tName p = do
    ok <- checkNewType tName p
    
    if ok then return $ TNew tName
    else return TError -- change when no exit with first error encounter
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                  Create assignations instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates an assignation node
-- TODO: revisar que el lval no sea una variable de iteracion
assig :: Var -> Expr -> Pos -> MonadSymTab Instr
assig lval expr p = do
    iter <- checkIterVar lval
    asig <- checkAssig (typeVar lval) expr p    
    if (not iter) && asig then return $ Assig lval expr
    else return $ Assig lval (Literal EmptyVal TError) -- change when no exit with first error encounter
-------------------------------------------------------------------------------

register :: [Expr] -> Expr
register e
    | all (/= TError) (map typeE e) = Literal (Register e) TRegister
    | otherwise = Literal (Register e) TError

-------------------------------------------------------------------------------
-- crearIncremento :: Var -> Pos -> Instr
-- crearIncremento lval (line, _) = Assig lval (crearSuma (Variable lval TInt) (Literal (Integer 1) TInt))
--     | typeVar lval == TInt =
--         Assig lval (crearSuma (Variable lval TInt) (Literal (Integer 1) TInt))
--     | otherwise = error("Error semantico en el incremento, variable no es de tipo Integer")
--

-- crearDecremento :: Var -> Pos -> Instr
-- crearDecremento lval (line, _) = Assig lval (crearResta (Variable lval TInt) (Literal (Integer 1) TInt))
--     | typeVar lval == TInt =
--         Assig lval (crearResta (Variable lval TInt) (Literal (Integer 1) TInt))
--     | otherwise = error("Error semantico en el decremento, variable no es de tipo Integer")
--
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                  Create operators instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the binary operator node
binary :: BinOp -> Expr -> Expr -> Pos -> MonadSymTab Expr
binary op e1 e2 p = do
    (ok,tOp) <- checkBinary op e1 e2 p
    
    if ok then return $ Binary op e1 e2 tOp
    else return $ Binary op e1 e2 TError -- Cambiar cuando no se salga del parser en checkBinary con el error
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the unary operator node
unary :: UnOp -> Expr -> Type -> Pos -> MonadSymTab Expr
unary op expr tSpected p = do
    (ok,tOp) <- checkUnary (typeE expr) tSpected p
    
    if ok then return $ Unary op expr tOp
    else return $ Unary op expr TError -- change when no exit with first error encounter
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                  Create arrays / lists instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates instert in list first index operator node
anexo :: BinOp -> Expr -> Expr -> Pos -> MonadSymTab Expr
anexo op e1 e2 p = do
    (ok,tOp) <- checkAnexo e1 e2 p
    
    if ok then return $ Binary op e1 e2 tOp
    else return $ Binary op e1 e2 TError -- change when no exit with first error encounter
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Create concat 2 lists operator node
concatLists :: BinOp -> Expr -> Expr -> Pos -> MonadSymTab Expr
concatLists op e1 e2 p
    | isList t1 && isList t2 && isJust mbtypeList  = -- <<2>>:: <<>>
        return $ Binary Concat e1 e2 (fromJust mbtypeList)
    | otherwise = do
        fileCode <- ask
        error $ semmErrorMsg (show t1) (show t2) fileCode p
        -- error $ "\n\nError: " ++ (show fileName) ++ ": " ++ (show p) ++ "\n\t" ++
        --     "La operación " ++ (show Concat)  ++ " requiere que expresion '" 
        --     ++ (show e1) ++ "' y expresion '" ++ show e2 ++ "' sean listas del mismo tipo."
    where
        t1 = typeE e1
        t2 = typeE e2
        mbtypeList = getTLists [t1,t2]
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the length operator node
len :: Expr -> Pos -> MonadSymTab Expr
len e p
    | isArray t || isList t = return $ Unary Length e TInt
    | otherwise = do     
        fileCode <- ask
        error $ semmErrorMsg "Array or List" (show t) fileCode p
        -- error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
        --     "La operacion de longitud: '" ++ (show Length) ++ "'," ++ 
        --     " requiere que el tipo de '" ++ (show e) ++ "' sea un arreglo o lista."    
    where
        t = typeE e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- TODO
-- | Creates the same type array / list node  <---(*)
arrayList :: [Expr] -> Expr
arrayList [] = ArrayList [] (TArray (Literal (Integer 0) TInt) TDummy)
arrayList e =
    ArrayList e (TArray (Literal (Integer $ length e) TInt) tipo)
    where
        mapaTipos = map typeE e
        tipoPrimero = head mapaTipos
        tipo = if all (== tipoPrimero) mapaTipos then tipoPrimero else TError
-------------------------------------------------------------------------------


list :: [Expr] -> Pos -> MonadSymTab Expr
list [] p = return $ ArrayList [] (TList TDummy) -- TODO : Recordar quitar el TDummy
list e  p
    | isJust tipo =
        return $ ArrayList e (TList (fromJust tipo))
    | otherwise = do
        fileCode <- ask
        error $ semmErrorMsg (show tipo) (show mapaTipos) fileCode p
    where
        mapaTipos = map typeE e
        tipo = getTLists mapaTipos


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                  Creates the selection instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the selection instruction node
if' :: [(Expr, InstrSeq)] -> Pos -> Instr
if' cases p = IF cases
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the guards of the selection instruction node
guard :: Expr -> InstrSeq -> Pos -> MonadSymTab (Expr, InstrSeq)
guard cond i p = do
    fileCode <- ask
    let tCond = typeE cond

    if tCond /= TError then return (cond, i)    -- its this really ok???
    else
        error $ semmErrorMsg "Battle" (show tCond) fileCode p
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the simple if instruction node
ifSimple :: Expr -> Expr -> Expr -> Pos -> MonadSymTab Expr
ifSimple cond true false p = do
    (ok,t) <- checkIfSimple (typeE cond) (typeE true) (typeE false) p
    return $ IfSimple cond true false t
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                 Creates the iterations instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the determined iteration instruction node
for :: Id -> Expr -> Expr -> InstrSeq -> SymTab -> Scope -> Pos 
            -> MonadSymTab Instr
for var e1 e2 i st scope pos@(line,_) = return $ For var e1 e2 i
-- | tE1 == TInt && tE2 == TInt =
    --     do
    --         let newI = map (changeTDummyFor TInt st scope) i
    --         checkInfSup e1 e2 pos st
    --         return $ For var e1 e2 newI
    -- --------------------------------------------------------------------------
    -- | tE1 == TInt =
    --     error ("\n\nError semantico en segunda la expresion del 'for': '"
    --             ++ expr2 ++ "', de tipo: " ++ showType tE2
    --             ++ ". En la linea: " ++ show line ++ "\n")
    -- --------------------------------------------------------------------------
    -- | tE2 == TInt =
    --     error ("\n\nError semantico en la primera expresion del 'for': '"
    --             ++ expr1 ++ "', de tipo: " ++ showType tE1 ++ ". En la linea: "
    --             ++ show line ++ "\n")
    -- --------------------------------------------------------------------------
    -- | otherwise =
    --     error ("\n\nError semantico en la primera expresion: '" ++ expr1 ++
    --             "', de tipo: " ++ showType tE1 ++ ", y segunda expresion: '"
    --             ++ expr2 ++ "', de tipo: " ++ showType tE2 ++
    --             ", del 'for'. En la linea: " ++ show line ++ "\n")

    -- where
    --     expr1 = showE e1
    --     expr2 = showE e2
    --     tE1 = typeE e1
    --     tE2 = typeE e2
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- | Creates the determined conditional iteration instruction node
forWhile :: Id -> Expr -> Expr -> Expr -> InstrSeq -> SymTab -> Scope
                -> Pos -> MonadSymTab Instr
forWhile var e1 e2 e3 i st scope pos@(line,_) = return $ ForWhile var e1 e2 e3 i
{-forWhile var e1 e2 e3 i st scope pos@(line,_)
    | tE1 == TInt && tE2 == TInt && tE3 == TBool =
        do
            let newI = map (changeTDummyFor TInt st scope) i
            checkInfSup e1 e2 pos st
            return $ For var e1 e2 newI st
    --------------------------------------------------------------------------
    | tE1 == TInt =
        error ("\n\nError semantico en segunda la expresion del 'for': '"
                ++ expr2 ++ "', de tipo: " ++ showType tE2
                ++ ". En la linea: " ++ show line ++ "\n")
    --------------------------------------------------------------------------
    | tE2 == TInt =
        error ("\n\nError semantico en la primera expresion del 'for': '"
                ++ expr1 ++ "', de tipo: " ++ showType tE1 ++ ". En la linea: "
                ++ show line ++ "\n")
    --------------------------------------------------------------------------
    | tE3 == TBool =
        error ("\n\nError semantico en la primera expresion: '" ++ expr1 ++
                "', de tipo: " ++ showType tE1 ++ ", y segunda expresion: '"
                ++ expr2 ++ "', de tipo: " ++ showType tE2 ++
                ", del 'for'. En la linea: " ++ show line ++ "\n")
    --------------------------------------------------------------------------
    | otherwise =
        error ("\n\nError semantico en la primera expresion: '" ++ expr1 ++
                "', de tipo: " ++ showType tE1 ++ ", segunda expresion: '"
                ++ expr2 ++ "', de tipo: " ++ showType tE2 ++
                ", y tercera expresion: '" ++ expr3 ++ "', de tipo: " ++ showType tE3 ++
                ", del 'for'. En la linea: " ++ show line ++ "\n")
    where
        expr1 = showE e1
        expr2 = showE e2
        expr3 = showE e3
        tE1 = typeE e1
        tE2 = typeE e2
        tE3 = typeE e3 -}


-------------------------------------------------------------------------------
-- | Creates the determined iteration instruction node for arrays / list
forEach :: Id -> Expr -> InstrSeq -> Pos -> MonadSymTab Instr
forEach var e i p = return $ ForEach var e i
-------------------------------------------------------------------------------
    

-------------------------------------------------------------------------------
-- | Creates the indetermined iteration instruction node
while :: Expr -> InstrSeq -> Pos -> Instr
while cond i p = While cond i
{-    | tE == TBool = While e i
    | otherwise = 
        error ("\n\nError semantico en la expresion del 'while': '" ++
                showE e ++ "', de tipo: " ++ showType tE ++
                ". En la linea: " ++ show line ++ "\n")
    where
        tE = typeE e
        -}
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                   Procedures / Functions calls nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

checkPromises ::  MonadSymTab ()
checkPromises = do
    (symTab, activeScopes, scopes ,promises) <- get
    fileCode <- ask

    forM promises $ \(PromiseSubrutine name args t p ) -> do
        if t /= TPDummy then
            error $ errorMsg ("Function '" ++ name ++ "' is not defined") fileCode p
        else 
            error $ errorMsg ("Procedure '" ++ name ++ "' is not defined") fileCode p
        return ()
    
    return ()

updateInfoSubrutine:: Id -> Category -> [(Type,Id)] -> Type -> MonadSymTab ()
updateInfoSubrutine name cat p t = do
    (symTab, activeScopes, scopes ,promises) <- get
    fileCode <- ask
    let paramsF = reverse p
    let promise = getPromiseSubrutine name promises

    if isJust promise then do
        let promise' = fromJust promise
        let paramsP = getParamsPromise promise'
        let typeP = getTypePromise promise'

        if  any (/=True) [t1 == t2 | (t1,(t2,id2)) <- zip paramsP paramsF ] then
            error $ errorMsg (" Wrong type of arguments") fileCode (getPosPromise promise')
        else if  length(paramsP) /= length(paramsF) then
            let msj = "Amount of arguments: " ++ show (length(paramsP)) ++
                    " not equal to expected:" ++ show (length(paramsF))
            in error $ errorMsg msj fileCode (getPosPromise promise')
        else if typeP /= TPDummy && typeP /= t then
            error $ semmErrorMsg (show typeP) (show t) fileCode (getPosPromise promise')
        else  do
            put(symTab, activeScopes, scopes ,filter (/= promise') promises)
            return () 
    else return()

    updateExtraInfo name cat [Params paramsF]
    updateType name 1 t


    return ()
  
-------------------------------------------------------------------------------

-- | Creates subroutine call instruction node
-- Considerar quitar esta función
call :: Id -> Params -> Pos -> MonadSymTab (Subroutine,Pos)
call subroutine args p = do
    (symTab, activeScopes, scopes ,promises) <- get
    fileCode <- ask
    let symInfos = lookupInScopes [1,0] subroutine symTab
    
    if isJust symInfos then do
        let isSubroutine si = getCategory si `elem` [Procedures, Functions]
            subroutine' = filter isSubroutine (fromJust symInfos)

        if null subroutine' then
            error $ errorMsg "This is not a subroutine" fileCode p
        else do
            let nParams = fromJust $ getNParams $ getExtraInfo $ head subroutine'
                nArgs = length args
            
            if nArgs == nParams then
                return (Call subroutine args,p)
            else
                let msj = "Amount of arguments: " ++ show nArgs ++
                        " not equal to expected:" ++ show nParams
                in error $ errorMsg msj fileCode p
    else do
        -- Add a promise to create subroutine
        put(symTab, activeScopes, scopes , promises ++ [PromiseSubrutine subroutine (map (typeE) args) TPDummy p] )

        return (Call subroutine args,p)
-------------------------------------------------------------------------------


procCall:: Subroutine -> Pos -> MonadSymTab Instr
procCall procedure@(Call name args) p = do
    (symTab, activeScopes, scope,promises) <- get

    fileCode <- ask
    let symInfos = lookupInScopes [1,0] name symTab
    if isJust symInfos then do
        let isProcedure symInfo = getCategory symInfo == Procedures
            procedure' = filter isProcedure (fromJust symInfos)

        if null procedure' then
            error $ errorMsg ("'" ++ name  ++ "' is not a procedure") fileCode p
        else do
            return $ ProcCall procedure
    else do
        -- If no is declared but maybe(It has to be a promise) is a promise
        let promise = getPromiseSubrutine name promises
        if isJust promise then do
            let info = [SymbolInfo TVoid 1 Procedures [Params [(typeE e,show i)| (e,i) <- zip args [1..]]]]
            put (insertSymbols [name] info symTab, activeScopes, scope,promises)
            return $ ProcCall procedure
        else do
            error $ "Error interno:  Procedure '" ++ name ++ "' doesn't have a promise,"

        -------------------------------------------------------------------------------
-- | Creates function call expresion node
-- NOTE: Its already verified that subroutine's defined with 'call', because
--      its excuted first
funcCall :: Subroutine -> Pos -> MonadSymTab Expr
funcCall function@(Call name args) p = do

    (symTab, activeScopes, scope,promises) <- get

    fileCode <- ask
    let symInfos = lookupInScopes [1,0] name symTab
    if isJust symInfos then do
        let isFunction symInfo = getCategory symInfo == Functions
            function' = filter isFunction (fromJust symInfos)

        if null function' then
            error $ errorMsg ("'" ++ name  ++ "' is not a function") fileCode p
        else do
            return $ FuncCall function (getType $ head function')
    else do
        -- If no is declared but maybe(It has to be a promise) is a promise
        let promise = getPromiseSubrutine name promises
        if isJust promise then do
            let info = [SymbolInfo TDummy 1 Functions [Params [(typeE e,show i)| (e,i) <- zip args [1..]]]]
            put (insertSymbols [name] info symTab, activeScopes, scope,promises)
            return $ FuncCall function TPDummy
        else do
            error $ "Error interno:  Function '" ++ name ++ "' doesn't have a promise,"

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                          I/O instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the print instruction node
print' :: [Expr] -> Pos -> MonadSymTab Instr
print' e p
    | all (/= TError) (map typeE e) = return $ Print e
    | otherwise = do
        fileCode <- ask
        error $ semmErrorMsg "Good-typed expression" "Error" fileCode p 
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the read instruction node
read' :: Expr -> Pos -> Expr
read' e _ = Read e TRead
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                        Pointers instructions nodes
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Creates the free memory instruction node
free :: Id -> Pos -> MonadSymTab Instr
free var p = do
    (symTab, activeScopes, _,_) <- get
    fileCode <- ask
    let infos = lookupInScopes activeScopes var symTab
    
    if isJust infos then return $ Free var
    else error $ errorMsg "Variable not declared in active scopes" fileCode p
-------------------------------------------------------------------------------