{-
* Modulo para la creacion del arbol sintactico abstracto y
* la verificacion de tipos
*
* Copyright : (c) 
*  Manuel Gonzalez     11-10390
*  Francisco Javier    12-11163
*  Natascha Gamboa     12-11250
-}
module Playit.AST where

import Control.Monad (void)
import Control.Monad.Trans.RWS
import qualified Data.Map as M
import Data.Maybe (fromJust, isJust, isNothing)
import Playit.CheckAST
import Playit.Errors
import Playit.SymbolTable
import Playit.Types


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                        Crear nodos del AST
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


chequearTipo :: Nombre -> Posicion-> MonadSymTab ()
chequearTipo name p = do
    (symTab, scopes, _) <- get
    file <- ask
    let info = lookupInScopes [1] name symTab
    if isJust info then do
        let sym = fromJust info
        if getCategory sym == Tipos then do
            return ()
        else do 
            error $ "\n\nError: " ++ file ++ ": " ++ show p ++ "\n\t" ++"Identificador : '" ++ (show name) ++ "' no es un tipo."
    else
        error $ "\n\nError: " ++ file ++ ": " ++ show p ++ "\n\t" ++"El Tipo " ++ (show name) ++ " no ha sido creado."


-------------------------------------------------------------------------------
-- Crea el nodo para identificadores de variables y verifica que estén declarados
crearIdvar :: Nombre -> Posicion -> MonadSymTab Vars
crearIdvar name p = do
    (symTab, scopes, _) <- get
    fileCode <- ask
    let infos = lookupInScopes scopes name symTab

    if isJust infos then do
        let vars = [Variable,Parametros Valor,Parametros Referencia]
            isVar si = getCategory si `elem` vars
            var = filter isVar (fromJust infos)

        if null var then
            error $ errorMessage "This is not a variable" fileCode p
        else
            return $ Var name (getType $ head var)

    else error $ errorMessage "Variable not declared in active scopes" fileCode p
-------------------------------------------------------------------------------

crearDeferenciacion :: Vars -> Posicion -> MonadSymTab Vars
crearDeferenciacion v p
    | isPointer tVar = let (TApuntador t) = tVar in return $ PuffValue v t
    | otherwise = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "La variable : '" ++ (show v) ++ "' no es un apuntador."
    where
        tVar = typeVar v

-------------------------------------------------------------------------------
-- Crea el nodo para variables de indexacion
crearVarIndex :: Vars -> Expr -> Posicion -> MonadSymTab Vars
crearVarIndex v e p 
    | tVar == TError = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "La variable : '" ++ (show v) ++ 
            "' no es indexable, tiene que ser un array o una lista."
    | tExpre /= TInt = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "Expresion de indexación '" ++ (show e) ++ "' no es de tipo entero."
    | otherwise = return $ VarIndex v e tVar
    where
        tVar = case typeVar v of 
                tipo@(TArray _ t) -> t
                tipo@(TLista t) -> t
                _ -> TError
        tExpre = typeE e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para los campos de los registros y uniones
crearCampo :: Vars -> Nombre -> Posicion -> MonadSymTab Vars
crearCampo v campo p = do
    (symTab, _, _) <- get
    fileCode@(file,code) <- ask
    
    -- Verificar que 'v' tiene como tipo un reg
    let reg = case typeVar' v of 
            (TNuevo name) -> name
            _ -> ""
    
    if reg == "" then -- Error de tipo
        error ("\n\nError: " ++ file ++ ": " ++ show p ++ "\n\t'" ++ show v ++ 
            " no es un registro o una union.\n")
    else do
        
        --chequearTipo tname p
        
        let info = lookupInSymTab campo symTab
        if isJust info then do
        
            let isInRegUnion (SymbolInfo typ scope cat ext) =  cat == Campos && (fromJust $ getRegName ext) == tname

            let symbols = filter isInRegUnion (fromJust info ) -- Debería tener un elemento o ninguno
                        
            if null symbols then
                error $ errorMessage ("Field not in '"++reg++"'") fileCode p
            else 
                return $ VarCompIndex v campo (getType $ head symbols) 
        else
            error $ errorMessage "Field not declared" fileCode p
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Crear el nodo para asignar a un identificador de variable una expresion
-- TODO: Modificar para que asigne el primer elemento de un arreglo/lista a la variable
crearAsignacion :: Vars -> Expr -> Posicion -> MonadSymTab Instr
crearAsignacion lval e p
    | isList(tE) && (typeArrLst tE) == TDummy && isList tV && (esTipoEscalar $ typeArrLst tV) = do -- List Tipo = <<<>>
        return $ Asignacion lval e  
    | tE == tV = return $ Asignacion lval e
    | otherwise = do
        file <- ask
        error ("\n\nError: " ++ file ++ ": " ++ show p ++ "\n\tNo se puede asignar '"++
            show e ++ "' a la variable '" ++ show lval ++ "' , los tipos no concuerdan.")

    where
        tE    = typeE e
        tV    = typeVar lval
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- TODO: Ver si es realmente necesario
-- crearIncremento :: Vars -> Posicion -> Instr
-- crearIncremento lval (line, _) = Asignacion lval (crearSuma (Variables lval TInt) (Literal (Entero 1) TInt))
-- {-    | typeVar lval == TInt =
--         Asignacion lval (crearSuma (Variables lval TInt) (Literal (Entero 1) TInt))
--     | otherwise = error("Error semantico en el incremento, variable no es de tipo Entero, en la linea " ++ show line)
-- -}

-- crearDecremento :: Vars -> Posicion -> Instr
-- crearDecremento lval (line, _) = Asignacion lval (crearResta (Variables lval TInt) (Literal (Entero 1) TInt))
-- {-    | typeVar lval == TInt =
--         Asignacion lval (crearResta (Variables lval TInt) (Literal (Entero 1) TInt))
--     | otherwise = error("Error semantico en el decremento, variable no es de tipo Entero, en la linea " ++ show line)
-- -}
-------------------------------------------------------------------------------

    

-------------------------------------------------------------------------------
-- Crea el nodo para un operador binario
crearOpBin :: BinOp -> Expr -> Expr -> Tipo -> Tipo -> Tipo -> Posicion -> MonadSymTab Expr
crearOpBin op e1 e2 t1 t2 tOp p
    -- | tE1 == TDummy || tE2 == TDummy = TDummy
    | tE1 == t1 && tE2 == t2  = return $ OpBinario op e1 e2 tOp
    | tE1 == TFloat && tE2 == TFloat && tOp == TInt  = return $ OpBinario op e1 e2 TFloat
    | otherwise = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "La operacion: '" ++ (show op) ++ "'," ++ " requiere que el tipo de '" 
            ++ (show e1) ++ "' sea '" ++ (show t1) ++ "' y de '" ++  
            (show e2) ++ "' sea '" ++ (show t2) ++ "'"
    where
        tE1 = typeE e1
        tE2 = typeE e2



-------------------------------------------------------------------------------
-- Crea el nodo para un operador binario
crearOpBinComparable :: BinOp -> Expr -> Expr -> [Tipo] -> Tipo -> Posicion -> MonadSymTab Expr
crearOpBinComparable op e1 e2 tcomp tOp p
    -- | tE1 == TDummy || tE2 == TDummy = TDummy
    | tE1 `elem` allcomps && tE2 == tE1  = return $ OpBinario op e1 e2 tOp
    | esopigualdad && isArray tE1 && isArray tE2 && tE1 == tE2 = 
        return $ OpBinario op e1 e2 tOp
    | esopigualdad && sonlistas && isJust (obtTipoListas [tE1,tE2])  =  -- <<>> == <<2>>
        return $ OpBinario op e1 e2 tOp
    | esopigualdad && isPointer tE1 && isPointer tE2 && tE1 == tE2 = 
        return $ OpBinario op e1 e2 tOp
    --  TODO: | TRegistro,TUnion
    | otherwise = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ 
            "\n\t" ++"La operacion: '" ++ (show op) ++ "'," ++ 
            " requiere que el tipo de '" ++ (show e1) ++ "' y de '" ++  
            (show e2) ++ "' sean de tipos comparables entre ellos."
    where
        tE1 = typeE e1
        tE2 = typeE e2
        sonlistas = isList tE1 && isList tE2
        esopigualdad = (op == Igual || op == Desigual)
        allcomps = [TChar,TFloat,TInt,TStr] ++ tcomp

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para un operador unario
crearOpUn :: UnOp -> Expr -> Tipo -> Tipo -> Posicion -> MonadSymTab Expr
crearOpUn op e t tOp p
    | tE == t = return $ OpUnario op e tOp
    | otherwise = do     
        if (tE == TFloat && tOp == TInt) then do
          {- Conversión automática que se encarga el compilador, ejemplo: -2.0 = -2.0 -}
            return $ OpUnario op e TFloat
        else do
            fileName <- ask
            error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
                "La operacion: '" ++ (show op) ++ "'," ++ 
                " requiere que el tipo de '" ++ (show e) ++ "' sea '" ++ (show tOp) ++ "'"
    where
        tE = typeE e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--              Crear Nodos de las instrucciones con arreglos y listas
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para el operador concatenar 2 listas
crearOpConcat ::Expr -> Expr -> Posicion -> MonadSymTab Expr
crearOpConcat e1 e2 p  
    | isList te1 && isList te2 && isJust mbtypeList  = do -- <<2>>:: <<>>
        return $ OpBinario Concatenacion e1 e2 (fromJust mbtypeList)
    | otherwise = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "La operación " ++ (show Concatenacion)  ++ " requiere que expresion '" 
            ++ (show e1) ++ "' y expresion '" ++ show e2 ++ "' sean listas del mismo tipo."
    where
        te1 = typeE e1
        te2 = typeE e2
        mbtypeList = obtTipoListas [te1,te2]
        
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para el operador agregar un elemento al inicio de la lista
crearOpAnexo ::  Expr -> Expr -> Posicion-> MonadSymTab Expr
crearOpAnexo e1 e2 p
    | isJust typeLR = do
        return $ OpBinario Anexo e1 e2 (fromJust typeLR)
    | not $ isList typee2  = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "El segundo operando de : '" ++ (show Anexo) ++ "'," ++ 
            "'" ++ (show e2) ++ "' debe ser una lista."
    | typee1 /= typeArrLst typee2  = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "El emento a anexar '" ++ (show e1) ++ "'," ++ "' debe ser de tipo '" 
            ++ show (typeArrLst typee2) ++ "'."

    where
        typee1 = typeE e1
        typee2 = typeE e2
        typeLR = obtTipoListaAnexo typee1 typee2
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para el operador tamaño de array o lista
crearOpLen :: Expr -> Posicion -> MonadSymTab Expr
crearOpLen e p
    | isArray t || isList t = return $ OpUnario Longitud e TInt
    | otherwise = do     
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "La operacion de longitud: '" ++ (show Longitud) ++ "'," ++ 
            " requiere que el tipo de '" ++ (show e) ++ "' sea un arreglo o lista."
    where
        t = typeE e
-------------------------------------------------------------------------------



crearLista :: [Expr] -> Posicion -> MonadSymTab Expr
crearLista [] p = return $ ArrLstExpr [] (TLista TDummy) -- TODO : Recordar quitar el TDummy
crearLista e  p
    | isJust tipo  = do
        return $ ArrLstExpr e (TLista (fromJust tipo))
    | otherwise = do
        fileName <- ask
        error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
            "Las expresiones de la lista deben ser del mismo tipo."
    where
        mapaTipos   = map typeE e
        tipo = obtTipoListas mapaTipos

-------------------------------------------------------------------------------
-- TODO
-- Crea el nodo para representar arreglos o lista de expresiones del mismo tipo <---(*)
crearArrLstExpr :: [Expr] -> Expr
crearArrLstExpr [] = ArrLstExpr [] (TArray (Literal (Entero 0) TInt) TDummy)
crearArrLstExpr e =
    ArrLstExpr e (TArray (Literal (Entero $ length e) TInt) tipo)
    where
        mapaTipos = map typeE e
        tipoPrimero = head mapaTipos
        tipo = if all (== tipoPrimero) mapaTipos then tipoPrimero else TError
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--              Crear Nodos de las instrucciones de condicionales
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para una instruccion If
crearGuardiaIF :: Expr -> SecuenciaInstr -> Posicion -> (Expr, SecuenciaInstr)
crearGuardiaIF exprCond seqInstrs (line, _) = (exprCond, seqInstrs)
{-crearGuardiaIF exprCond seqInstrs (line,_)
    | tExpreCondicional == TBool = IF [(exprCond, seqInstrs)]
    | otherwise = 
        error ("\n\nError semantico en la expresion del if: '" ++ showE exprCond
                ++ "', de tipo: " ++ showType tExpreCondicional ++ ". En la linea: "
                ++ show line ++ "\n")
    where
        tExpreCondicional = typeE exprCond-}
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
crearIfSimple :: Expr -> Expr -> Expr -> Tipo ->  Posicion -> MonadSymTab Expr
crearIfSimple cond v f t p
    | tCond == TBool &&  tFalse== tTrue = return $ IfSimple cond v f tTrue
    | otherwise = do
        
        if (((tFalse == TFloat) && (tTrue == TInt)) || 
            ((tTrue == TFloat) && (tFalse == TInt))) then do
          {- Conversión automática que se encarga el compilador, (1 > 0) ? 1.3 : 5 -}
            return $ IfSimple cond v f TFloat
        else do        
            fileName <- ask
            if tCond /= TBool then do 
                error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
                    "Condicion '" ++ (show tCond) ++ "' del operador ternario '? :'" ++ 
                    " no es booleana."
            else do
                error $ "\n\nError: " ++ fileName ++ ": " ++ show p ++ "\n\t" ++
                    "El operador ternario '? :'" ++ " requiere que el tipo de '" ++ 
                    (show v) ++ "' y de '" ++  (show f) ++ "' sean iguales."
  where 
    tCond = typeE cond
    tFalse = typeE f
    tTrue = typeE v

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
crearIF :: [(Expr, SecuenciaInstr)] -> Posicion -> Instr
crearIF casos (line, col) = IF casos
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--              Crear Nodos de las instrucciones de iteraciones
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para una instruccion For
crearFor :: Nombre -> Expr -> Expr -> SecuenciaInstr -> SymTab -> Alcance -> Posicion 
            -> MonadSymTab Instr
crearFor var e1 e2 i st scope pos@(line,_) = return $ For var e1 e2 i
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
-- Crea el nodo para la instruccion de for con condicion
crearForWhile :: Nombre -> Expr -> Expr -> Expr -> SecuenciaInstr -> SymTab
    -> Alcance -> Posicion  -> MonadSymTab Instr
crearForWhile var e1 e2 e3 i st scope pos@(line,_) = return $ ForWhile var e1 e2 e3 i
{-crearForWhile var e1 e2 e3 i st scope pos@(line,_)
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
-- Crea el nodo para una instruccion ForEach
crearForEach :: Nombre -> Expr -> SecuenciaInstr -> Posicion -> MonadSymTab Instr
crearForEach var e i pos@(line,_) =
    return $ ForEach var e i
-------------------------------------------------------------------------------
    

-------------------------------------------------------------------------------
-- Crea el nodo para una instruccion While
-- crearWhile' = observe "Que pasa con while " crearWhile
crearWhile :: Expr -> SecuenciaInstr -> Posicion -> Instr
crearWhile e i (line,_) = While e i
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
--        Definiciones e instrucciones de procedimientos y funciones
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Actualiza el tipo y  la informacion extra de la subrutina
definirSubrutina' :: Nombre -> SecuenciaInstr -> Categoria -> MonadSymTab ()
definirSubrutina' n i c = void $ updateExtraInfo n c [AST i]
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Agrega el nombre de la subrutina a la tabla de símbolos.
definirSubrutina :: Nombre -> Categoria -> Posicion -> MonadSymTab ()
definirSubrutina nombre categoria p = do
    (symTab, activeScopes, scope) <- get
    fileCode <- ask
    let info = lookupInSymTab nombre symTab

    if isNothing info then 
        let info = [SymbolInfo TDummy 1 categoria []]
        in addToSymTab [nombre] info symTab activeScopes scope
    else
        error $ errorMessage "Redefined subroutine" fileCode p
    return ()
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Define el parametro en la tabla de simbolos
definirParam :: Vars -> MonadSymTab Nombre
definirParam (Param name t ref) = do
    (symtab, activeScopes@(activeScope:_), scope) <- get
    let info = [SymbolInfo t activeScope (Parametros ref) []]
    addToSymTab [name] info symtab activeScopes scope
    return name
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para la instruccion que llama a la subrutina
crearSubrutinaCall :: Nombre -> Parametros -> Posicion
                    -> MonadSymTab (Subrutina,Posicion)
crearSubrutinaCall nombre args p = do
    (symtab, _, _) <- get
    fileCode <- ask
    let symInfos = lookupInScopes [1,0] nombre symtab
    
    if isJust symInfos then do
        let isSubroutine si = getCategory si `elem` [Procedimientos,Funciones]
            subroutine = filter isSubroutine (fromJust symInfos)

        if null subroutine then
            error $ errorMessage "This is not a subroutine" fileCode p
        else do
            let nParams = fromJust $ getNParams $ getExtraInfo $ head subroutine
                nArgs = length args
            
            if nArgs == nParams then
                return (SubrutinaCall nombre args,p)
            else
                let msj = "Amount of arguments: " ++ show nArgs ++
                        " not equal to spected:" ++ show nParams
                in error $ errorMessage msj fileCode p
    else
        error $ errorMessage "Not defined subroutine" fileCode p
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para la instruccion que llama a la funcion
-- NOTA: Se supone que ya se verifico que la subrutina este definida con
--      crearSubrutinaCall, pues se ejecuta primero
crearFuncCall :: Subrutina -> Posicion -> MonadSymTab Expr
crearFuncCall subrutina@(SubrutinaCall nombre _) p = do
    (symtab, _, _) <- get
    fileCode <- ask
    let infos = fromJust $ lookupInScopes [1] nombre symtab
        isFunc si = getCategory si == Funciones
        func = filter isFunc infos
    
    if null func then
        error $ errorMessage "This is not a function" fileCode p
    else
        return $ FuncCall subrutina (getType $ head func)
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--                   Definiciones de registros y uniones
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Definicion de union
definirRegistro :: Nombre -> Posicion -> MonadSymTab ()
definirRegistro reg p = do
    (symTab@(SymTab table), activeScopes@(activeScope:_), scope) <- get
    fileCode <- ask
    let regInfo = lookupInScopes [1] reg symTab

    if isJust regInfo then
        error $ errorMessage "Redefined Inventory" fileCode p
    else
        let modifySym (SymbolInfo t s _ _) = SymbolInfo t s Campos [FromReg reg]
            updtSym = 
                map (\sym -> if getScope sym == activeScope then modifySym sym else sym)

        let newSymTab = SymTab $ M.map updateSymbol' table
        
        let info = [SymbolInfo TRegistro 1 Tipos [AST decls]]

        in void $ addToSymTab [reg] info newSymTab activeScopes scope
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Definicion de union
definirUnion :: Nombre -> Posicion -> MonadSymTab ()
definirUnion reg p = do
    (symTab@(SymTab table), activeScopes@(activeScope:_), scope) <- get
    fileCode <- ask
    let regInfo = lookupInScopes [1] reg symTab

    if isJust regInfo then
        error $ errorMessage "Redefined Items" fileCode p
    else
        let modifySym (SymbolInfo t s _ _) = SymbolInfo t s Campos [FromReg reg]
            updSym = 
                map (\sym -> if getScope sym == activeScope then modifySym sym else sym)

            newSymTab = SymTab $ M.map updSym table
            info = [SymbolInfo TUnion 1 Tipos []]
        in void $ addToSymTab [reg] info newSymTab activeScopes scope
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--              Crear Nodos de las instrucciones de entrada y salida
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para una instruccion Print
crearPrint :: Expr -> Posicion -> MonadSymTab Instr
crearPrint e p
    | tE /= TError = return $ Print e
    | otherwise = do
        (file,code) <- ask
        error ("\n\nError: " ++ file ++ ": " ++ show p ++
                "\nExpresion del 'print': '" ++
                show e ++ "', de tipo: " ++ show tE ++ "\n")
    where
        tE = typeE e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para una instruccion Read
crearRead :: Expr -> Posicion -> Expr
crearRead e _ = Read e
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--              Crear Nodos de las instrucciones de apuntadores
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el tipo que tenga uno o mas apuntadores a otro tipo
crearTApuntador :: Tipo -> Tipo -> Tipo
crearTApuntador (TApuntador TDummy) t = TApuntador t
crearTApuntador (TApuntador t') t = TApuntador $ crearTApuntador t' t
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Crea el nodo para una instruccion Free
crearFree :: Nombre -> Posicion -> MonadSymTab Instr
crearFree var p = do
    (symtab, activeScope:_, _) <- get
    fileCode <- ask
    let info = lookupInSymTab var symtab
    
    if isJust info then
        let scopeOk = activeScope `elem` map getScope (fromJust info) in
        
        if scopeOk then return $ Free var
        else error $ errorMessage "Variable out of scope" fileCode p
    else
        error $ errorMessage "Variable not defined" fileCode p
-------------------------------------------------------------------------------
