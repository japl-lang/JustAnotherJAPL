# Copyright 2021 Mattia Giambirtone
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

## An Abstract Syntax Tree (AST) structure for our recursive-descent
## top-down parser. For more info, check out docs/grammar.md


import strformat
import strutils


import token


type
    NodeKind* = enum
        ## Enumeration of the AST
        ## node types, sorted by
        ## precedence

        # Declarations
        classDecl = 0u8,
        funDecl,
        varDecl,
        # Statements
        forStmt,  # Unused for now (for loops are compiled to while loops)
        ifStmt,
        returnStmt,
        breakStmt,
        continueStmt,
        whileStmt,
        forEachStmt,
        blockStmt,
        raiseStmt,
        assertStmt,
        delStmt,
        tryStmt,
        yieldStmt,
        awaitStmt,
        fromImportStmt,
        importStmt,
        deferStmt,
        # An expression followed by a semicolon
        exprStmt,
        # Expressions
        assignExpr,
        lambdaExpr,
        awaitExpr,
        yieldExpr,
        setItemExpr,  # Set expressions like a.b = "c"
        binaryExpr,
        unaryExpr,
        sliceExpr,
        callExpr,
        getItemExpr,  # Get expressions like a.b
        # Primary expressions
        groupingExpr,  # Parenthesized expressions such as (true) and (3 + 4)
        trueExpr,
        listExpr,
        tupleExpr,
        dictExpr,
        setExpr,
        falseExpr,
        strExpr,
        intExpr,
        floatExpr,
        hexExpr,
        octExpr,
        binExpr,
        nilExpr,
        nanExpr,
        infExpr,
        identExpr,   # Identifier


    ASTNode* = ref object of RootObj
        ## An AST node
        kind*: NodeKind

    # Here I would've rather used object variants, and in fact that's what was in
    # place before, but not being able to re-declare a field of the same type in
    # another case branch is kind of a deal breaker long-term, so until that is
    # fixed (check out https://github.com/nim-lang/RFCs/issues/368 for more info)
    # I'll stick to using inheritance instead

    LiteralExpr* = ref object of ASTNode
        # Using a string for literals makes it much easier to handle numeric types, as
        # there is no overflow nor underflow or float precision issues during parsing.
        # Numbers are just serialized as strings and then converted back to numbers
        # before being passed to the VM, which also keeps the door open in the future
        # to implementing bignum arithmetic that can take advantage of natively supported
        # machine types, meaning that if a numeric type fits into a 64 bit signed/unsigned
        # int then it is stored in such a type to save space, otherwise it is just converted
        # to a bigint. Bigfloats with arbitrary-precision arithmetic would also be nice,
        # although arguably less useful (and probably significantly slower than bigints)
        literal*: Token

    IntExpr* = ref object of LiteralExpr
    OctExpr* = ref object of LiteralExpr
    HexExpr* = ref object of LiteralExpr
    BinExpr* = ref object of LiteralExpr
    FloatExpr* = ref object of LiteralExpr
    StrExpr* = ref object of LiteralExpr

    # There are technically keywords, not literals!
    TrueExpr* = ref object of ASTNode
    FalseExpr* = ref object of ASTNode
    NilExpr* = ref object of ASTNode
    NanExpr* = ref object of ASTNode
    InfExpr* = ref object of ASTNode

    # Although this is *technically* a literal, Nim doesn't
    # allow us to redefine fields from supertypes so it's
    # a tough luck for us
    ListExpr* = ref object of ASTNode
        members*: seq[ASTNode]
    
    SetExpr* = ref object of ListExpr

    TupleExpr* = ref object of ListExpr

    DictExpr* = ref object of ASTNode
        keys*: seq[ASTNode]
        values*: seq[ASTNode]
    
    IdentExpr* = ref object of ASTNode
        name*: Token
    
    GroupingExpr* = ref object of ASTNode
        expression*: ASTNode
    
    GetItemExpr* = ref object of ASTNode
        obj*: ASTNode
        name*: ASTNode
    
    SetItemExpr* = ref object of GetItemExpr
        # Since a setItem expression is just
        # a getItem one followed by an assignment,
        # inheriting it from getItem makes sense
        value*: ASTNode

    CallExpr* = ref object of ASTNode
        callee*: ASTNode  # The thing being called
        arguments*: tuple[positionals: seq[ASTNode], keyword: seq[tuple[name: ASTNode, value: ASTNode]]]

    UnaryExpr* = ref object of ASTNode
        operator*: Token
        a*: ASTNode

    BinaryExpr* = ref object of UnaryExpr
        # Binary expressions can be seen here as unary
        # expressions with an extra operand so we just
        # inherit from that and add a second operand
        b*: ASTNode

    YieldExpr* = ref object of ASTNode
        expression*: ASTNode

    AwaitExpr* = ref object of ASTNode
        awaitee*: ASTNode

    LambdaExpr* = ref object of ASTNode
        body*: ASTNode
        arguments*: seq[ASTNode]
        # This is, in order, the list of each default argument
        # the function takes. It maps 1:1 with self.arguments
        # although it may be shorter (in which case this maps
        # 1:1 with what's left of self.arguments after all
        # positional arguments have been consumed)
        defaults*: seq[ASTNode]
        isGenerator*: bool

    SliceExpr* = ref object of ASTNode
        slicee*: ASTNode
        ends*: seq[ASTNode]

    AssignExpr* = ref object of ASTNode
        name*: ASTNode
        value*: ASTNode

    ExprStmt* = ref object of ASTNode
        expression*: ASTNode

    ImportStmt* = ref object of ASTNode
        moduleName*: ASTNode

    FromImportStmt* = ref object of ASTNode
        fromModule*: ASTNode
        fromAttributes*: seq[ASTNode]

    DelStmt* = ref object of ASTNode
        name*: ASTNode

    AssertStmt* = ref object of ASTNode
        expression*: ASTNode

    RaiseStmt* = ref object of ASTNode
        exception*: ASTNode

    BlockStmt* = ref object of ASTNode
        code*: seq[ASTNode]

    ForStmt* = ref object of ASTNode
        discard   # Unused
    
    ForEachStmt* = ref object of ASTNode
        identifier*: ASTNode
        expression*: ASTNode
        body*: ASTNode

    DeferStmt* = ref object of ASTNode
        deferred*: ASTNode
    
    TryStmt* = ref object of ASTNode
        body*: ASTNode
        handlers*: seq[tuple[body: ASTNode, exc: ASTNode, name: ASTNode]]
        finallyClause*: ASTNode
        elseClause*: ASTNode

    WhileStmt* = ref object of ASTNode
        condition*: ASTNode
        body*: ASTNode
    
    AwaitStmt* = ref object of ASTNode
        awaitee*: ASTNode

    BreakStmt* = ref object of ASTNode
    
    ContinueStmt* = ref object of ASTNode

    ReturnStmt* = ref object of ASTNode
        value*: ASTNode

    IfStmt* = ref object of ASTNode
        condition*: ASTNode
        thenBranch*: ASTNode
        elseBranch*: ASTNode

    YieldStmt* = ref object of ASTNode
        expression*: ASTNode

    VarDecl* = ref object of ASTNode
        name*: ASTNode
        value*: ASTNode
        isConst*: bool
        isStatic*: bool
        isPrivate*: bool

    FunDecl* = ref object of ASTNode
        name*: ASTNode
        body*: ASTNode
        arguments*: seq[ASTNode]
        # This is, in order, the list of each default argument
        # the function takes. It maps 1:1 with self.arguments
        # although it may be shorter (in which case this maps
        # 1:1 with what's left of self.arguments after all
        # positional arguments have been consumed)
        defaults*: seq[ASTNode]
        isAsync*: bool
        isGenerator*: bool
        isStatic*: bool
        isPrivate*: bool

    ClassDecl* = ref object of ASTNode
        name*: ASTNode
        body*: ASTNode
        parents*: seq[ASTNode]
        isStatic*: bool
        isPrivate*: bool

    Expression* = LiteralExpr | ListExpr | GetItemExpr | SetItemExpr | UnaryExpr | BinaryExpr | CallExpr | AssignExpr |
                  GroupingExpr | IdentExpr | DictExpr | TupleExpr | SetExpr | TrueExpr | FalseExpr | NilExpr |
                  NanExpr | InfExpr

    Statement* = ExprStmt | ImportStmt | FromImportStmt | DelStmt | AssertStmt | RaiseStmt | BlockStmt | ForStmt | WhileStmt |
                 ForStmt | BreakStmt | ContinueStmt | ReturnStmt | IfStmt

    Declaration* = VarDecl | FunDecl | ClassDecl



proc newASTNode*(kind: NodeKind): ASTNode =
    ## Initializes a new generic ASTNode object
    new(result)
    result.kind = kind


proc isConst*(self: ASTNode): bool {.inline.} = self.kind in {intExpr, hexExpr, binExpr, octExpr, strExpr,
                                                              falseExpr, trueExpr, infExpr, nanExpr,
                                                              floatExpr}


proc isLiteral*(self: ASTNode): bool {.inline.} = self.isConst() or self.kind in {tupleExpr, dictExpr, setExpr, listExpr}


proc newIntExpr*(literal: Token): IntExpr =
    result = IntExpr(kind: intExpr)
    result.literal = literal


proc newOctExpr*(literal: Token): OctExpr =
    result = OctExpr(kind: octExpr)
    result.literal = literal


proc newHexExpr*(literal: Token): HexExpr =
    result = HexExpr(kind: hexExpr)
    result.literal = literal


proc newBinExpr*(literal: Token): BinExpr =
    result = BinExpr(kind: binExpr)
    result.literal = literal


proc newFloatExpr*(literal: Token): FloatExpr =
    result = FloatExpr(kind: floatExpr)
    result.literal = literal


proc newTrueExpr*: LiteralExpr {.inline.} = LiteralExpr(kind: trueExpr)
proc newFalseExpr*: LiteralExpr {.inline.} = LiteralExpr(kind: falseExpr)
proc newNaNExpr*: LiteralExpr {.inline.} = LiteralExpr(kind: nanExpr)
proc newNilExpr*: LiteralExpr {.inline.} = LiteralExpr(kind: nilExpr)
proc newInfExpr*: LiteralExpr {.inline.} = LiteralExpr(kind: infExpr)


proc newStrExpr*(literal: Token): StrExpr =
    result = StrExpr(kind: strExpr)
    result.literal = literal


proc newIdentExpr*(name: Token): IdentExpr =
    result = IdentExpr(kind: identExpr)
    result.name = name


proc newGroupingExpr*(expression: ASTNode): GroupingExpr =
    result = GroupingExpr(kind: groupingExpr)
    result.expression = expression


proc newLambdaExpr*(arguments, defaults: seq[ASTNode], body: ASTNode, isGenerator: bool): LambdaExpr =
    result = LambdaExpr(kind: lambdaExpr)
    result.body = body
    result.arguments = arguments
    result.defaults = defaults
    result.isGenerator = isGenerator


proc newGetItemExpr*(obj: ASTNode, name: ASTNode): GetItemExpr =
    result = GetItemExpr(kind: getItemExpr)
    result.obj = obj
    result.name = name


proc newListExpr*(members: seq[ASTNode]): ListExpr =
    result = ListExpr(kind: listExpr)
    result.members = members


proc newSetExpr*(members: seq[ASTNode]): SetExpr =
    result = SetExpr(kind: setExpr)
    result.members = members


proc newTupleExpr*(members: seq[ASTNode]): TupleExpr =
    result = TupleExpr(kind: tupleExpr)
    result.members = members


proc newDictExpr*(keys, values: seq[ASTNode]): DictExpr =
    result = DictExpr(kind: dictExpr)
    result.keys = keys
    result.values = values


proc newSetItemExpr*(obj, name, value: ASTNode): SetItemExpr =
    result = SetItemExpr(kind: setItemExpr)
    result.obj = obj
    result.name = name
    result.value = value


proc newCallExpr*(callee: ASTNode, arguments: tuple[positionals: seq[ASTNode], keyword: seq[tuple[name: ASTNode, value: ASTNode]]]): CallExpr =
    result = CallExpr(kind: callExpr)
    result.callee = callee
    result.arguments = arguments


proc newSliceExpr*(slicee: ASTNode, ends: seq[ASTNode]): SliceExpr =
    result = SliceExpr(kind: sliceExpr)
    result.slicee = slicee
    result.ends = ends


proc newUnaryExpr*(operator: Token, a: ASTNode): UnaryExpr =
    result = UnaryExpr(kind: unaryExpr)
    result.operator = operator
    result.a = a


proc newBinaryExpr*(a: ASTNode, operator: Token, b: ASTNode): BinaryExpr =
    result = BinaryExpr(kind: binaryExpr)
    result.operator = operator
    result.a = a
    result.b = b


proc newYieldExpr*(expression: ASTNode): YieldExpr =
    result = YieldExpr(kind: yieldExpr)
    result.expression = expression


proc newAssignExpr*(name, value: ASTNode): AssignExpr =
    result = AssignExpr(kind: assignExpr)
    result.name = name
    result.value = value


proc newAwaitExpr*(awaitee: ASTNode): AwaitExpr =
    result = AwaitExpr(kind: awaitExpr)
    result.awaitee = awaitee


proc newExprStmt*(expression: ASTNode): ExprStmt =
    result = ExprStmt(kind: exprStmt)
    result.expression = expression


proc newImportStmt*(moduleName: ASTNode): ImportStmt =
    result = ImportStmt(kind: importStmt)
    result.moduleName = moduleName


proc newFromImportStmt*(fromModule: ASTNode, fromAttributes: seq[ASTNode]): FromImportStmt =
    result = FromImportStmt(kind: fromImportStmt)
    result.fromModule = fromModule
    result.fromAttributes = fromAttributes


proc newDelStmt*(name: ASTNode): DelStmt =
    result = DelStmt(kind: delStmt)
    result.name = name


proc newYieldStmt*(expression: ASTNode): YieldStmt =
    result = YieldStmt(kind: yieldStmt)
    result.expression = expression


proc newAwaitStmt*(awaitee: ASTNode): AwaitExpr =
    result = AwaitExpr(kind: awaitExpr)
    result.awaitee = awaitee


proc newAssertStmt*(expression: ASTNode): AssertStmt =
    result = AssertStmt(kind: assertStmt)
    result.expression = expression


proc newDeferStmt*(deferred: ASTNode): DeferStmt =
    result = DeferStmt(kind: deferStmt)
    result.deferred = deferred


proc newRaiseStmt*(exception: ASTNode): RaiseStmt =
    result = RaiseStmt(kind: raiseStmt)
    result.exception = exception


proc newTryStmt*(body: ASTNode, handlers: seq[tuple[body: ASTNode, exc: ASTNode, name: ASTNode]],
                 finallyClause: ASTNode,
                 elseClause: ASTNode): TryStmt =
    result = TryStmt(kind: tryStmt)
    result.body = body
    result.handlers = handlers
    result.finallyClause = finallyClause
    result.elseClause = elseClause


proc newBlockStmt*(code: seq[ASTNode]): BlockStmt =
    result = BlockStmt(kind: blockStmt)
    result.code = code


proc newWhileStmt*(condition: ASTNode, body: ASTNode): WhileStmt =
    result = WhileStmt(kind: whileStmt)
    result.condition = condition
    result.body = body


proc newForEachStmt*(identifier: ASTNode, expression, body: ASTNode): ForEachStmt =
    result = ForEachStmt(kind: forEachStmt)
    result.identifier = identifier
    result.expression = expression
    result.body = body


proc newBreakStmt*: BreakStmt = BreakStmt(newASTNode(breakStmt))
proc newContinueStmt*: ContinueStmt = ContinueStmt(newASTNode(continueStmt))


proc newReturnStmt*(value: ASTNode): ReturnStmt =
    result = ReturnStmt(kind: returnStmt)
    result.value = value


proc newIfStmt*(condition: ASTNode, thenBranch, elseBranch: ASTNode): IfStmt =
    result = IfStmt(kind: ifStmt)
    result.condition = condition
    result.thenBranch = thenBranch
    result.elseBranch = elseBranch


proc newVarDecl*(name: ASTNode, value: ASTNode = newNilExpr(),
                 isStatic: bool = true, isConst: bool = false,
                 isPrivate: bool = true): VarDecl =
    result = VarDecl(kind: varDecl)
    result.name = name
    result.value = value
    result.isConst = isConst
    result.isStatic = isStatic
    result.isPrivate = isPrivate


proc newFunDecl*(name: ASTNode, arguments, defaults: seq[ASTNode],
                 body: ASTNode, isStatic: bool = true, isAsync,
                 isGenerator: bool, isPrivate: bool = true): FunDecl =
    result = FunDecl(kind: funDecl)
    result.name = name
    result.arguments = arguments
    result.defaults = defaults
    result.body = body
    result.isAsync = isAsync
    result.isGenerator = isGenerator
    result.isStatic = isStatic
    result.isPrivate = isPrivate


proc newClassDecl*(name: ASTNode, body: ASTNode,
                   parents: seq[ASTNode], isStatic: bool = true,
                   isPrivate: bool = true): ClassDecl =
    result = ClassDecl(kind: classDecl)
    result.name = name
    result.body = body
    result.parents = parents
    result.isStatic = isStatic
    result.isPrivate = isPrivate


proc `$`*(self: ASTNode): string = 
    case self.kind:
        of intExpr, floatExpr, hexExpr, binExpr, octExpr, strExpr, trueExpr, falseExpr, nanExpr, nilExpr, infExpr:
            if self.kind in {trueExpr, falseExpr, nanExpr, nilExpr, infExpr}:
                result &= &"Literal({($self.kind)[0..^5]})"
            elif self.kind == strExpr:
                result &= &"Literal({LiteralExpr(self).literal.lexeme.escape()})"
            else:
                result &= &"Literal({LiteralExpr(self).literal.lexeme})"
        of identExpr:
            result &= &"Identifier('{IdentExpr(self).name.lexeme}')"
        of groupingExpr:
            result &= &"Grouping({GroupingExpr(self).expression})"
        of getItemExpr:
            var self = GetItemExpr(self)
            result &= &"GetItem(obj={self.obj}, name={self.name})"
        of setItemExpr:
            var self = SetItemExpr(self)
            result &= &"SetItem(obj={self.obj}, name={self.value}, value={self.value})"
        of callExpr:
            var self = CallExpr(self)
            result &= &"Call({self.callee}, arguments=(positionals=[{self.arguments.positionals.join(\", \")}], keyword=[{self.arguments.keyword.join(\", \")}]))"
        of unaryExpr:
            var self = UnaryExpr(self)
            result &= &"Unary(Operator('{self.operator.lexeme}'), {self.a})"
        of binaryExpr:
            var self = BinaryExpr(self)
            result &= &"Binary({self.a}, Operator('{self.operator.lexeme}'), {self.b})"
        of assignExpr:
            var self = AssignExpr(self)
            result &= &"Assign(name={self.name}, value={self.value})"
        of exprStmt:
            var self = ExprStmt(self)
            result &= &"ExpressionStatement({self.expression})"
        of importStmt:
            var self = ImportStmt(self)
            result &= &"Import({self.moduleName})"
        of fromImportStmt:
            var self = FromImportStmt(self)
            result &= &"FromImport(fromModule={self.fromModule}, fromAttributes=[{self.fromAttributes.join(\", \")}])"
        of delStmt:
            var self = DelStmt(self)
            result &= &"Del({self.name})"
        of assertStmt:
            var self = AssertStmt(self)
            result &= &"Assert({self.expression})"
        of raiseStmt:
            var self = RaiseStmt(self)
            result &= &"Raise({self.exception})"
        of blockStmt:
            var self = BlockStmt(self)
            result &= &"Block([{self.code.join(\", \")}])"
        of whileStmt:
            var self = WhileStmt(self)
            result &= &"While(condition={self.condition}, body={self.body})"
        of forEachStmt:
            var self = ForEachStmt(self)
            result &= &"ForEach(identifier={self.identifier}, expression={self.expression}, body={self.body})"
        of returnStmt:
            var self = ReturnStmt(self)
            result &= &"Return({self.value})"
        of yieldExpr:
            var self = YieldExpr(self)
            result &= &"Yield({self.expression})"
        of awaitExpr:
            var self = AwaitExpr(self)
            result &= &"Await({self.awaitee})"
        of ifStmt:
            var self = IfStmt(self)
            if self.elseBranch == nil:
                result &= &"If(condition={self.condition}, thenBranch={self.thenBranch}, elseBranch=nil)"
            else:
                result &= &"If(condition={self.condition}, thenBranch={self.thenBranch}, elseBranch={self.elseBranch})"
        of yieldStmt:
            var self = YieldStmt(self)
            result &= &"YieldStmt({self.expression})"
        of awaitStmt:
            var self = AwaitStmt(self)
            result &= &"AwaitStmt({self.awaitee})"
        of varDecl:
            var self = VarDecl(self)
            result &= &"Var(name={self.name}, value={self.value}, const={self.isConst}, static={self.isStatic}, private={self.isPrivate})"
        of funDecl:
            var self = FunDecl(self)
            result &= &"FunDecl(name={self.name}, body={self.body}, arguments=[{self.arguments.join(\", \")}], defaults=[{self.defaults.join(\", \")}], async={self.isAsync}, generator={self.isGenerator}, static={self.isStatic}, private={self.isPrivate})"
        of classDecl:
            var self = ClassDecl(self)
            result &= &"Class(name={self.name}, body={self.body}, parents=[{self.parents.join(\", \")}], static={self.isStatic}, private={self.isPrivate})"
        of tupleExpr:
            var self = TupleExpr(self)
            result &= &"Tuple([{self.members.join(\", \")}])"
        of setExpr:
            var self = SetExpr(self)
            result &= &"Set([{self.members.join(\", \")}])"
        of listExpr:
            var self = ListExpr(self)
            result &= &"List([{self.members.join(\", \")}])"
        of dictExpr:
            var self = DictExpr(self)
            result &= &"Dict(keys=[{self.keys.join(\", \")}], values=[{self.values.join(\", \")}])"
        of lambdaExpr:
            var self = LambdaExpr(self)
            result &= &"Lambda(body={self.body}, arguments=[{self.arguments.join(\", \")}], defaults=[{self.defaults.join(\", \")}], generator={self.isGenerator})"
        of deferStmt:
            var self = DeferStmt(self)
            result &= &"Defer({self.deferred})"
        of sliceExpr:
            var self = SliceExpr(self)
            result &= &"Slice({self.slicee}, ends=[{self.ends.join(\", \")}])"
        of tryStmt:
            var self = TryStmt(self)
            result &= &"TryStmt(body={self.body}, handlers={self.handlers}"
            if self.finallyClause != nil:
                result &= &", finallyClause={self.finallyClause}"
            else:
                result &= ", finallyClause=nil"
            if self.elseClause != nil:
                result &= &", elseClause={self.elseClause}"
            else:
                result &= ", elseClause=nil"
            result &= ")"
        else:
            discard    
