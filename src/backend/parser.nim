# Copyright 2020 Mattia Giambirtone
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

## A recursive-descent top-down parser implementation

import strformat


import meta/token
import meta/ast
import meta/errors


export token, ast, errors


type 
    ParseContext = enum
        Script, Function
    
    LoopContext = enum
        Loop, None
    
    Parser* = ref object
        ## A recursive-descent top-down
        ## parser implementation
        current: int
        file: string
        tokens: seq[Token]
        context: ParseContext
        currentLoop: LoopContext


proc initParser*(): Parser = 
    ## Initializes a new Parser object
    new(result)
    result.current = 0
    result.file = ""
    result.tokens = @[]
    result.context = Script


# Handy templates to make our life easier, thanks nim!
template endOfFile: Token = Token(kind: EndOfFile, lexeme: "", line: -1)
template endOfLine(msg: string) = self.expect(Semicolon, msg)


proc peek(self: Parser, distance: int = 0): Token =
    ## Peeks at the token at the given distance.
    ## If the distance is out of bounds, an EOF
    ## token is returned. A negative distance may
    ## be used to retrieve previously consumed
    ## tokens
    if self.tokens.high() == -1 or self.current + distance > self.tokens.high() or self.current + distance < 0:
        result = endOfFile
    else:
        result = self.tokens[self.current + distance]


proc done(self: Parser): bool =
    ## Returns true if we're at the
    ## end of the file. Note that the
    ## parser expects an explicit
    ## EOF token to signal the end
    ## of the file (unless the token
    ## list is empty)
    result = self.peek().kind == EndOfFile


proc step(self: Parser, n: int = 1): Token = 
    ## Steps n tokens into the input,
    ## returning the last consumed one
    if self.done():
        result = self.peek()
    else:
        result = self.tokens[self.current]
        self.current += 1


proc error(self: Parser, message: string) =
    ## Raises a formatted ParseError exception to
    ## be catched at self.parse()
    var lexeme = if not self.done(): self.peek().lexeme else: self.step().lexeme
    var errorMessage = &"A fatal error occurred while parsing '{self.file}', line {self.peek().line} at '{lexeme}' -> {message}"
    raise newException(ParseError, errorMessage)


proc check(self: Parser, kind: TokenType, distance: int = 0): bool = 
    ## Checks if the given token at the given distance
    ## matches the expected kind and returns a boolean.
    ## The distance parameter is passed directly to
    ## self.peek()
    self.peek(distance).kind == kind


proc check(self: Parser, kind: openarray[TokenType]): bool =
    ## Calls self.check() in a loop with each entry of
    ## the given openarray of token kinds and returns
    ## at the first match. Note that this assumes
    ## that only one token may exist at a given
    ## position
    for k in kind:
        if self.check(k):
            return true
    return false


proc match(self: Parser, kind: TokenType, distance: int = 0): bool =
    ## Behaves like self.check(), except that when a token
    ## matches it is consumed
    if self.check(kind, distance):
        discard self.step()
        result = true
    else:
        result = false


proc match(self: Parser, kind: openarray[TokenType]): bool =
    ## Calls self.match() in a loop with each entry of
    ## the given openarray of token kinds and returns
    ## at the first match. Note that this assumes
    ## that only one token may exist at a given
    ## position
    for k in kind:
        if self.match(k):
            return true
    result = false


proc expect(self: Parser, kind: TokenType, message: string = "") = 
    ## Behaves like self.match(), except that
    ## when a token doesn't match an error
    ## is raised. If no error message is
    ## given, a default one is used
    if not self.match(kind):
        if message.len() == 0:
            self.error(&"expecting token of kind {kind}, found {self.peek().kind} instead")
        else:
            self.error(message)


proc unnest(self: Parser, node: ASTNode): ASTNode =
    ## Unpacks an arbitrarily nested grouping expression
    var node = node
    while node.kind == groupingExpr and GroupingExpr(node).expression != nil:
        node = GroupingExpr(node).expression
    result = node


# Forward declarations
proc expression(self: Parser): ASTNode
proc expressionStatement(self: Parser): ASTNode
proc statement(self: Parser): ASTNode
proc varDecl(self: Parser, isStatic: bool = true, isPrivate: bool = true): ASTNode
proc declaration(self: Parser): ASTNode


proc primary(self: Parser): ASTNode = 
    ## Parses primary expressions such
    ## as integer literals and keywords
    ## that map to builtin types (true, false, etc)
    
    case self.peek().kind:
        of True:
            discard self.step()
            result = newTrueExpr()
        of False:
            discard self.step()
            result = newFalseExpr()
        of TokenType.NotANumber:
            discard self.step()
            result = newNanExpr()
        of Nil:
            discard self.step()
            result = newNilExpr()
        of Float:
            result = newFloatExpr(self.step())
        of Integer:
            result = newIntExpr(self.step())
        of Identifier:
            result = newIdentExpr(self.step())
        of LeftParen:
            # TODO: Tuples
            discard self.step()
            if self.match(RightParen):
                # This yields an empty tuple
                result = newTupleExpr(@[])
            else:
                result = self.expression()
                if self.match(Comma):
                    var tupleObject = newTupleExpr(@[result])
                    while true:
                        tupleObject.members.add(self.expression())
                        if not self.match(Comma):
                            break
                    result = tupleObject
                    self.expect(RightParen, "unterminated tuple literal")
                else:
                    self.expect(RightParen, "unterminated parenthesized expression")
                    result = newGroupingExpr(result)
        of Yield:
            if self.context != Function:
                self.error("'yield' cannot be outside functions")
            result = newYieldExpr(self.expression())
        of Await:
            if self.context != Function:
                self.error("'await' cannot be used outside functions")
            result = newAwaitExpr(self.expression())
        of RightParen:
            # This is *technically* unnecessary: the parser would
            # throw an error regardless, but it's a little bit nicer
            # when the error message is more specific
            self.error("unmatched ')'")
        of Hex:
            result = newHexExpr(self.step())
        of Octal:
            result = newOctExpr(self.step())
        of Binary:
            result = newBinExpr(self.step())
        of String:
            result = newStrExpr(self.step())
        of Infinity:
            discard self.step()
            result = newInfExpr()
        of LeftBracket, LeftBrace:
            discard  # TODO
        else:
            self.error("invalid syntax")


proc makeCall(self: Parser, callee: ASTNode): ASTNode =
    ## Utility function called iteratively by self.call()
    ## to parse a function-like call
    var argNames: seq[ASTNode] = @[]
    var arguments: tuple[positionals: seq[ASTNode], keyword: seq[tuple[name: ASTNode, value: ASTNode]]] = (positionals: @[], keyword: @[])
    var argument: ASTNode = nil
    var argCount = 0
    if not self.check(RightParen):
        while true:
            if argCount >= 255:
                self.error("cannot store more than 255 arguments")
                break
            argument = self.expression()
            if argument.kind == assignExpr:
                if AssignExpr(argument).name in argNames:
                    self.error("duplicate keyword argument in call")
                argNames.add(AssignExpr(argument).name)
                arguments.keyword.add((name: AssignExpr(argument).name, value: AssignExpr(argument).value))
            elif arguments.keyword.len() == 0:
                arguments.positionals.add(argument)
            else:
                self.error("positional arguments cannot follow keyword arguments in call")
            if not self.match(Comma):
                break
        argCount += 1
    self.expect(RightParen)
    result = newCallExpr(callee, arguments)


proc call(self: Parser): ASTNode = 
    ## Parses call expressions and object
    ## accessing ("dot syntax")
    result = self.primary()
    while true:
        if self.match(LeftParen):
            result = self.makeCall(result)
        elif self.match(Dot):
            self.expect(Identifier, "expecting attribute name after '.'")
            result = newGetItemExpr(result, newIdentExpr(self.peek(-1)))
        else:
            break


proc unary(self: Parser): ASTNode = 
    ## Parses unary expressions
    if self.match([Minus, Tilde]):
        result = newUnaryExpr(self.peek(-1), self.unary())
    else:
        result = self.call()


proc pow(self: Parser): ASTNode =
    ## Parses exponentiation expressions
    result = self.unary()
    var operator: Token
    var right: ASTNode
    while self.match(DoubleAsterisk):
        operator = self.peek(-1)
        right = self.unary()
        result = newBinaryExpr(result, operator, right)


proc mul(self: Parser): ASTNode =
    ## Parses multiplication and division expressions
    result = self.pow()
    var operator: Token
    var right: ASTNode
    while self.match([Slash, Percentage, FloorDiv, Asterisk]):
        operator = self.peek(-1)
        right = self.pow()
        result = newBinaryExpr(result, operator, right)


proc add(self: Parser): ASTNode =
    ## Parses addition and subtraction expressions
    result = self.mul()
    var operator: Token
    var right: ASTNode
    while self.match([Plus, Minus]):
        operator = self.peek(-1)
        right = self.mul()
        result = newBinaryExpr(result, operator, right)


proc comparison(self: Parser): ASTNode =
    ## Parses comparison expressions
    result = self.add()
    var operator: Token
    var right: ASTNode
    while self.match([LessThan, GreaterThan, LessOrEqual, GreaterOrEqual, Is]):
        operator = self.peek(-1)
        right = self.add()
        result = newBinaryExpr(result, operator, right)


proc equality(self: Parser): ASTNode =
    ## Parses equality expressions
    result = self.comparison()
    var operator: Token
    var right: ASTNode
    while self.match([DoubleEqual, NotEqual]):
        operator = self.peek(-1)
        right = self.comparison()
        result = newBinaryExpr(result, operator, right)


proc logicalAnd(self: Parser): ASTNode =
    ## Parses logical AND expressions
    result = self.equality()
    var operator: Token
    var right: ASTNode
    while self.match(LogicalAnd):
        operator = self.peek(-1)
        right = self.equality()
        result = newBinaryExpr(result, operator, right)


proc logicalOr(self: Parser): ASTNode =
    ## Parses logical OR expressions
    result = self.logicalAnd()
    var operator: Token
    var right: ASTNode
    while self.match(LogicalOr):
        operator = self.peek(-1)
        right = self.logicalAnd()
        result = newBinaryExpr(result, operator, right)


proc bitwiseAnd(self: Parser): ASTNode =
    ## Parser a & b expressions
    result = self.logicalOr()
    var operator: Token
    var right: ASTNode
    while self.match(Pipe):
        operator = self.peek(-1)
        right = self.logicalOr()
        result = newBinaryExpr(result, operator, right)


proc bitwiseOr(self: Parser): ASTNode =
    ## Parser a | b expressions
    result = self.bitwiseAnd()
    var operator: Token
    var right: ASTNode
    while self.match(Ampersand):
        operator = self.peek(-1)
        right = self.bitwiseAnd()
        result = newBinaryExpr(result, operator, right)


proc assignment(self: Parser): ASTNode =
    ## Parses assignment, the highest-level
    ## expression (including stuff like a.b = 1)
    result = self.bitwiseOr()
    if self.match(Equal):
        var value = self.expression()
        if result.kind == identExpr:
            result = newAssignExpr(result, value)
        elif result.kind == getItemExpr:
            result = newSetItemExpr(GetItemExpr(result).obj, GetItemExpr(result).name, value)
        else:
            self.error("invalid assignment target")


proc delStmt(self: Parser): ASTNode =
    ## Parses "del" statements,
    ## which unbind a name from its
    ## value in the current scope and
    ## calls its destructor
    var expression = self.expression()
    var temp = expression
    endOfLIne("missing semicolon after del statement")
    if expression.kind == groupingExpr:
        # We unpack grouping expressions
        temp = self.unnest(temp)
    if temp.isLiteral():
        self.error("cannot delete a literal")
    elif temp.kind in {binaryExpr, unaryExpr}:
        self.error("cannot delete operator")
    elif temp.kind == callExpr:
        self.error("cannot delete function call")
    else:
        result = newDelStmt(expression)


proc assertStmt(self: Parser): ASTNode =
    ## Parses "assert" statements,
    ## raise an error if the expression
    ## fed into them is falsey
    var expression = self.expression()
    endOfLine("missing semicolon after assert statement")
    result = newAssertStmt(expression)


proc blockStmt(self: Parser): ASTNode =
    ## Parses block statements. A block
    ## statement simply opens a new local
    ## scope
    var code: seq[ASTNode] = @[]
    while not self.check(RightBrace) and not self.done():
        code.add(self.declaration())
    self.expect(RightBrace, "unterminated block statement")
    result = newBlockStmt(code)


proc breakStmt(self: Parser): ASTNode =
    ## Parses break statements
    if self.currentLoop != Loop:
        self.error("'break' cannot be used outside loops")
    endOfLine("missing semicolon after break statement")
    result = newBreakStmt()


proc continueStmt(self: Parser): ASTNode =
    ## Parses break statements
    if self.currentLoop != Loop:
        self.error("'continue' cannot be used outside loops")
    endOfLine("missing semicolon after continue statement")
    result = newContinueStmt()


proc returnStmt(self: Parser): ASTNode =
    ## Parses return statements
    if self.context != Function:
        self.error("'return' cannot be used outside functions")
    var value: ASTNode
    if not self.check(Semicolon):
        # Since return can be used on its own too
        # (in which case it implicitly returns nil),
        # we need to check if there's an actual value
        # to return or not
        value = self.expression()
    endOfLine("missing semicolon after return statement")
    result = newReturnStmt(value)


proc yieldStmt(self: Parser): ASTNode =
    ## Parses yield Statements
    if self.context != Function:
        self.error("'yield' cannot be used outside functions")
    result = newYieldExpr(self.expression)
    endOfLine("missing semicolon after yield statement")


proc awaitStmt(self: Parser): ASTNode =
    ## Parses yield Statements
    if self.context != Function:
        self.error("'await' cannot be used outside functions")
    result = newAwaitExpr(self.expression)
    endOfLine("missing semicolon after yield statement")


proc raiseStmt(self: Parser): ASTNode =
    ## Parses raise statements
    var exception: ASTNode
    if not self.check(Semicolon):
        # Raise can be used on its own, in which
        # case it re-raises the last exception
        exception = self.expression()
    endOfLine("missing semicolon after raise statement")
    result = newRaiseStmt(exception)


proc forEachStmt(self: Parser): ASTNode =
    var enclosingLoop = self.currentLoop
    self.currentLoop = Loop
    self.expect(LeftParen, "expecting '(' after 'foreach'")
    self.expect(Identifier)
    var identifier = newIdentExpr(self.peek(-1))
    self.expect(Colon)
    var expression = self.expression()
    self.expect(RightParen)
    var body = self.statement()
    result = newForEachStmt(identifier, expression, body)
    self.currentLoop = enclosingLoop


proc importStmt(self: Parser): ASTNode =
    ## Parses import statements
    result = self.expression()
    if result.kind != identExpr:
        self.error("expecting module name after import statement")
    endOfLine("missing semicolon after import statement")
    result = newImportStmt(result)


proc fromStmt(self: Parser): ASTNode =
    self.expect(Identifier)
    result = newIdentExpr(self.peek(-1))
    var attributes: seq[ASTNode] = @[]
    var attribute: ASTNode
    self.expect(Import)
    self.expect(Identifier)
    attribute = newIdentExpr(self.peek(-1))
    attributes.add(attribute)
    while self.match(Comma):
        self.expect(Identifier)
        attribute = newIdentExpr(self.peek(-1))
        attributes.add(attribute)
    endOfLine("missing semicolon after from ... import statement")
    result = newFromImportStmt(result, attributes)


proc whileStmt(self: Parser): ASTNode =
    ## Parses a C-style while loop statement
    var enclosingLoop = self.currentLoop
    self.currentLoop = Loop
    self.expect(LeftParen, "expecting '(' before while loop condition")
    var condition = self.expression()
    self.expect(RightParen, "unterminated while loop condition")
    result = newWhileStmt(condition, self.statement())
    self.currentLoop = enclosingLoop


proc forStmt(self: Parser): ASTNode = 
    ## Parses a C-style for loop
    var enclosingLoop = self.currentLoop
    self.currentLoop = Loop
    self.expect(LeftParen, "expecting '(' before for loop condition")
    var initializer: ASTNode = nil
    var condition: ASTNode = nil
    var increment: ASTNode = nil
    if self.match(Var):
        initializer = self.varDecl()
    else:
        initializer = self.expressionStatement()
    if not self.check(Semicolon):
        condition = self.expression()
    self.expect(Semicolon, "expecting ';' after for loop condition")
    if not self.check(RightParen):
        increment = self.expression()
    self.expect(RightParen, "unterminated for loop condition")
    var body = self.statement()
    if increment != nil:
        # The increment runs at each iteration, so we
        # inject it into the block as the first statement
        body = newBlockStmt(@[body, increment])
    if condition == nil:
        ## An empty condition is functionally
        ## equivalent to "true"
        condition = newTrueExpr()
    if initializer != nil:
        # Nested blocks, so the initializer is
        # only executed once
        body = newBlockStmt(@[initializer, body])
    # We can use a while loop, which in this case works just as well
    body = newWhileStmt(condition, body)
    result = body
    self.currentLoop = enclosingLoop


proc ifStmt(self: Parser): ASTNode =
    ## Parses if statements
    self.expect(LeftParen, "expecting '(' before if condition")
    var condition = self.expression()
    self.expect(RightParen, "expecting ')' after if condition")
    var thenBranch = self.statement()
    var elseBranch: ASTNode = nil
    if self.match(Else):
        elseBranch = self.statement()
    result = newIfStmt(condition, thenBranch, elseBranch)


proc varDecl(self: Parser, isStatic: bool = true, isPrivate: bool = true): ASTNode =
    ## Parses variable declarations
    var varKind = self.peek(-1)
    var keyword = ""
    var value: ASTNode
    case varKind.kind:
        of Const:
            keyword = "constant"
        else:
            keyword = "variable"
    self.expect(Identifier, &"expecting {keyword} name after '{varKind.lexeme}'")
    var name = newIdentExpr(self.peek(-1))
    if self.match(Equal):
        value = self.expression()
    else:
        if varKind.kind == Const:
            self.error(&"constant declaration requires a value")
        value = newNilExpr()
    self.expect(Semicolon, &"expecting semicolon after {keyword} declaration")
    case varKind.kind:
        of Var:
            result = newVarDecl(name, value, isStatic=isStatic, isPrivate=isPrivate)
        of Const:
            # Note that isStatic is ignored here, because constants are resolved differently,
            # but we leave it so the optimizer can issue a warning about it
            result = newVarDecl(name, value, isConst=true, isPrivate=isPrivate, isStatic=isStatic)
        else:
            discard  # Unreachable


proc funDecl(self: Parser, isAsync: bool = false, isStatic: bool = true, isPrivate: bool = true): FunDecl =
    ## Parses function declarations
    self.expect(Identifier, "expecting function name after 'fun'")
    var ident = newIdentExpr(self.peek(-1))
    result = newFunDecl(ident, @[], @[], nil, isStatic=isStatic, isAsync=isAsync, isGenerator=false, isPrivate=isPrivate)
    if self.match(LeftBrace):
        # Argument-less function
        discard
    else:
        var parameter: IdentExpr
        self.expect(LeftParen)
        while not self.check(RightParen):
            if result.arguments.len > 255:
                self.error("cannot have more than 255 arguments in function declaration")
            self.expect(Identifier)
            parameter = newIdentExpr(self.peek(-1))
            if parameter in result.arguments:
                self.error("duplicate parameter name in function declaration")
            result.arguments.add(parameter)
            if self.match(Equal):
                result.defaults.add(self.expression())
            elif result.defaults.len() > 0:
                self.error("positional argument(s) cannot follow default argument(s) in function declaration")
            if not self.match(Comma):
                break
        self.expect(RightParen)
        self.expect(LeftBrace)
    result.body = self.blockStmt()
    # We do some analysis on the code of the function. Namely we check
    # if the user used 'await' in a non-async function and if the
    # function has any yield expressions in them, making it a 
    # generator. Async generators are also supported
    for line in BlockStmt(result.body).code:
        if line.kind == exprStmt:
            echo ExprStmt(line).expression.kind
            if ExprStmt(line).expression.kind == yieldExpr:
                result.isGenerator = true
            elif not result.isAsync and ExprStmt(line).expression.kind == awaitExpr:
                self.error("'await' cannot be used outside async functions")
        elif line.kind == NodeKind.funDecl:
            # Nested function declarations with yield expressions as
            # default arguments are valid, but for them to work we
            # need to make the containing function a generator. These
            # yield expressions will run in the outer function's scope
            # and are lazily evaluated at runtime
            for default in FunDecl(line).defaults:
                if default.kind == NodeKind.yieldExpr:
                    result.isGenerator = true


proc classDecl(self: Parser, isStatic: bool = true, isPrivate: bool = true): ASTNode =
    ## Parses class declarations
    var parents: seq[ASTNode] = @[]
    self.expect(Identifier)
    var name = newIdentExpr(self.peek(-1))
    if self.match(LessThan):
        while true:
            self.expect(Identifier)
            parents.add(newIdentExpr(self.peek(-1)))
            if not self.match(Comma):
                break
    self.expect(LeftBrace)
    result = newClassDecl(name, self.blockStmt(), isPrivate=isPrivate, isStatic=isStatic, parents=parents)


proc expression(self: Parser): ASTNode = 
    ## Parses expressions
    result = self.assignment()


proc expressionStatement(self: Parser): ASTNode =
    ## Parses expression statements, which
    ## are expressions followed by a semicolon
    var expression = self.expression()
    endOfLIne("missing semicolon after expression")
    result = newExprStmt(expression)


proc statement(self: Parser): ASTNode =
    ## Parses statements
    case self.peek().kind:
        of If:
            discard self.step()
            result = self.ifStmt()
        of Del:
            discard self.step()
            result = self.delStmt()
        of Assert:
            discard self.step()
            result = self.assertStmt()
        of Raise:
            discard self.step()
            result = self.raiseStmt()
        of Break:
            discard self.step()
            result = self.breakStmt()
        of Continue:
            discard self.step()
            result = self.continueStmt()
        of Return:
            discard self.step()
            result = self.returnStmt()
        of Import:
            discard self.step()
            result = self.importStmt()
        of From:
            discard self.step()
            result = self.fromStmt()
        of While:
            discard self.step()
            result = self.whileStmt()
        of For:
            discard self.step()
            result = self.forStmt()
        of Foreach:
            discard self.step()
            result = self.forEachStmt()
        of LeftBrace:
            discard self.step()
            result = self.blockStmt()
        of Yield:
            discard self.step()
            result = self.yieldStmt()
        of Await:
            discard self.step()
            result = self.awaitStmt()
        else:
            result = self.expressionStatement()


proc declaration(self: Parser): ASTNode =
    ## Parses declarations
    case self.peek().kind:
        of Var, Const:
            discard self.step()
            result = self.varDecl()
        of Class:
            discard self.step()
            result = self.classDecl()
        of Fun:
            self.context = Function
            discard self.step()
            result = self.funDecl()
            self.context = Script
        of Private, Public:
            discard self.step()
            var isStatic: bool
            let isPrivate = if self.peek(-1).kind == Private: true else: false
            if self.match(Dynamic):
                isStatic = false
            elif self.match(Static):
                isStatic = true
            if self.match(Async):
                self.expect(Fun)
                self.context = Function
                result = self.funDecl(isStatic=isStatic, isPrivate=isPrivate, isAsync=true)
                self.context = Script
            else:
                case self.peek().kind:
                    of Var, Const:
                        discard self.step()
                        result = self.varDecl(isStatic=isStatic, isPrivate=isPrivate)
                    of Class:
                        discard self.step()
                        result = self.classDecl(isStatic=isStatic, isPrivate=isPrivate)
                    of Fun:
                        self.context = Function
                        discard self.step()
                        result = self.funDecl(isStatic=isStatic, isPrivate=isPrivate)
                        self.context = Script
                    else:
                        self.error("invalid syntax")
        of Static, Dynamic:
            discard self.step()
            let isStatic: bool = if self.peek(-1).kind == Static: true else: false
            if self.match(Async):
                self.expect(Fun)
                self.context = Function
                result = self.funDecl(isStatic=isStatic, isPrivate=true, isAsync=true)
                self.context = Script
            else:
                case self.peek().kind:
                    of Var, Const:
                        discard self.step()
                        result = self.varDecl(isStatic=isStatic, isPrivate=true)
                    of Class:
                        discard self.step()
                        result = self.classDecl(isStatic=isStatic, isPrivate=true)
                    of Fun:
                        self.context = Function
                        discard self.step()
                        result = self.funDecl(isStatic=isStatic, isPrivate=true)
                        self.context = Script
                    else:
                        self.error("invalid syntax")
        of Async:
            discard self.step()
            self.expect(Fun)
            self.context = Function
            result = self.funDecl(isAsync=true)
            self.context = Script
        else:
            result = self.statement()


proc parse*(self: Parser, tokens: seq[Token], file: string): seq[ASTNode] =
    ## Parses a series of tokens into an AST node
    self.tokens = tokens
    self.file = file
    self.current = 0
    self.context = Script
    self.currentLoop = None
    while not self.done():
        result.add(self.declaration())
