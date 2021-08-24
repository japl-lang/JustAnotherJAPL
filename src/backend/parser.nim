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

export token, ast


type Parser* = ref object
    ## A recursive-descent top-down
    ## parser implementation
    current*: int
    file: string
    errored*: bool
    errorMessage*: string
    tokens*: seq[Token]


proc initParser*(self: Parser = nil): Parser = 
    ## Initializes a new Parser object
    ## or resets an already existing one
    if self != nil:
        result = self
    new(result)
    result.current = 0
    result.file = ""
    result.errored = false
    result.errorMessage = ""
    result.tokens = @[]


template endOfFile: Token = Token(kind: TokenType.EndOfFile, lexeme: "", line: -1)
template endOfLine(msg: string) = discard self.expect(TokenType.Semicolon, msg)


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
    result = self.peek().kind == TokenType.EndOfFile


proc step(self: Parser, n: int = 1): Token = 
    ## Steps n tokens into the input,
    ## returning the last consumed one
    if self.done():
        result = self.peek()
    else:
        result = self.tokens[self.current]
        self.current += 1


proc error(self: Parser, message: string) =
    ## Sets the appropriate error fields
    ## in the parser. If an error already
    ## occurred, this function is a no-op
    if self.errored:
        return
    self.errored = true
    var lexeme = if not self.done(): self.peek().lexeme else: self.peek(-1).lexeme
    self.errorMessage = &"A fatal error occurred while parsing '{self.file}', line {self.peek().line} at {lexeme} -> {message}"
    

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


proc expect(self: Parser, kind: TokenType, message: string = ""): bool = 
    ## Behaves like self.match(), except that
    ## when a token doesn't match an error
    ## is "raised". If no error message is
    ## given, a default one is used
    if self.match(kind):
        result = true
    else:
        result = false
        if message.len() == 0:
            self.error(&"expecting token of kind {kind}, found {self.peek().kind} instead")
        else:
            self.error(message)

# Forward declarations
proc expression(self: Parser): ASTNode
proc statement(self: Parser): ASTNode


proc primary(self: Parser): ASTNode = 
    ## Parses primary expressions such
    ## as integer literals and keywords
    ## that map to types (true, false, etc)
    
    case self.peek().kind:
        of TokenType.True:
            result = newASTNode(self.step(), NodeKind.trueExpr)
        of TokenType.False:
            result = newASTNode(self.step(), NodeKind.falseExpr)
        of TokenType.NaN:
            result = newASTNode(self.step(), NodeKind.nanExpr)
        of TokenType.Nil:
            result = newASTNode(self.step(), NodeKind.nilExpr)
        of TokenType.Float:
            result = newASTNode(self.step(), NodeKind.floatExpr)
        of TokenType.Integer:
            result = newASTNode(self.step(), NodeKind.intExpr)
        of TokenType.Identifier:
            result = newASTNode(self.step(), NodeKind.identExpr)
        of TokenType.LeftParen:
            discard self.step()
            result = self.expression()
            if self.expect(TokenType.RightParen, "unmatched '('"):
                result = newASTNode(self.peek(-3), NodeKind.groupingExpr, @[result])
        of TokenType.RightParen:
            self.error("unmatched ')'")
        of TokenType.Hex:
            result = newASTNode(self.step(), NodeKind.hexExpr)
        of TokenType.Octal:
            result = newASTNode(self.step(), NodeKind.octExpr)
        of TokenType.Binary:
            result = newASTNode(self.step(), NodeKind.binExpr)
        else:
            self.error("invalid syntax")


proc make_call(self: Parser, callee: ASTNode): ASTNode =
    ## Utility function called iteratively by self.call()
    ## to parse a function-like call
    var arguments: seq[ASTNode] = @[callee]
    if not self.check(TokenType.RightParen):
        while true:
            if len(arguments) >= 255:
                self.error("cannot have more than 255 arguments")
                break
            arguments.add(self.expression())
            if not self.match(TokenType.Comma):
                break
    if self.expect(TokenType.RightParen):
        result = newASTNode(self.peek(-1), NodeKind.callExpr, arguments)


proc call(self: Parser): ASTNode = 
    ## Parses call expressions and object
    ## accessing ("dot syntax")
    result = self.primary()
    if result == nil:
        return
    while true:
        if self.match(TokenType.LeftParen):
            result = self.make_call(result)
        elif self.match(TokenType.Dot):
            if self.expect(TokenType.Identifier, "expecting attribute name after '.'"):
                result = newASTNode(self.peek(-2), NodeKind.getExpr, @[result, newAstNode(self.peek(-1), NodeKind.identExpr)])
        else:
            break


proc unary(self: Parser): ASTNode = 
    ## Parses unary expressions
    if self.match([TokenType.Minus, TokenType.Tilde]):
        result = self.unary()
        if result == nil:
            return
        result = newASTNode(self.peek(-1), NodeKind.unaryExpr, @[result])
    else:
        result = self.call()


proc pow(self: Parser): ASTNode =
    ## Parses exponentiation expressions
    result = self.unary()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match(TokenType.DoubleAsterisk):
        operator = self.peek(-1)
        right = self.unary()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc mul(self: Parser): ASTNode =
    ## Parses multiplication and division expressions
    result = self.pow()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.Slash, TokenType.Percentage, TokenType.FloorDiv]):
        operator = self.peek(-1)
        right = self.pow()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc add(self: Parser): ASTNode =
    ## Parses addition and subtraction expressions
    result = self.mul()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.Plus, TokenType.Minus]):
        operator = self.peek(-1)
        right = self.mul()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc comparison(self: Parser): ASTNode =
    ## Parses comparison expressions
    result = self.add()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.LessThan, TokenType.GreaterThan, TokenType.LessOrEqual, TokenType.GreaterOrEqual]):
        operator = self.peek(-1)
        right = self.add()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc equality(self: Parser): ASTNode =
    ## Parses equality expressions
    result = self.comparison()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.DoubleEqual, TokenType.NotEqual]):
        operator = self.peek(-1)
        right = self.comparison()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc logical_and(self: Parser): ASTNode =
    ## Parses logical AND expressions
    result = self.equality()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match(TokenType.LogicalAnd):
        operator = self.peek(-1)
        right = self.equality()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc logical_or(self: Parser): ASTNode =
    ## Parses logical OR expressions
    result = self.logical_and()
    if result == nil:
        return
    var operator: Token
    var right: ASTNode
    while self.match(TokenType.LogicalOr):
        operator = self.peek(-1)
        right = self.logical_and()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc binary(self: Parser): ASTNode = 
    ## Parses binary expressions
    result = self.logical_or()


proc assignment(self: Parser): ASTNode =
    ## Parses assignment, the highest-level
    ## expression
    result = self.binary()
    if result == nil:
        return
    if self.match(TokenType.Equal):
        var tok = self.peek(-1)
        var value = self.assignment()
        if result.kind == NodeKind.identExpr:
            result = newASTNode(tok, NodeKind.assignExpr, @[result, value])
        elif result.kind == NodeKind.getExpr:
            result = newASTNode(tok, NodeKind.setExpr, @[result.children[0], result.children[1], value])


proc expression(self: Parser): ASTNode = 
    ## Parses expressions
    result = self.assignment()


proc expressionStatement(self: Parser): ASTNode =
    ## Parses expression statements, which
    ## are expressions followed by a semicolon
    var expression = self.expression()
    if expression == nil:
        return
    endOfLIne("missing semicolon after expression")
    result = newAstNode(self.peek(-1), NodeKind.exprStmt, @[expression])


proc delStmt(self: Parser): ASTNode =
    ## Parses "del" statements,
    ## which unbind a name from its
    ## value in the current scope and
    ## calls its destructor
    var expression = self.expression()
    if expression == nil:
        return
    var temp = expression
    endOfLIne("missing semicolon after del statement")
    if expression.kind == NodeKind.groupingExpr:
        # We unpack grouping expressions
        while temp.kind == NodeKind.groupingExpr and temp.children.len() > 0:
            temp = temp.children[0]
    if temp.kind in {NodeKind.falseExpr, NodeKind.trueExpr, NodeKind.intExpr, 
                           NodeKind.binExpr, NodeKind.hexExpr, NodeKind.octExpr,
                           NodeKind.floatExpr, NodeKind.strExpr, NodeKind.nilExpr,
                           NodeKind.nanExpr, }:
        self.error("cannot delete a literal")
    elif temp.kind in {NodeKind.binaryExpr, NodeKind.unaryExpr}:
        self.error("cannot delete operator")
    else:
        result = newASTNode(self.peek(-1), NodeKind.delStmt, @[expression])


proc assertStmt(self: Parser): ASTNode =
    ## Parses "assert" statements,
    ## raise an error if the expression
    ## fed into them is falsey
    var expression = self.expression()
    endOfLine("missing semicolon after del statement")
    result = newASTNode(self.peek(), NodeKind.assertStmt, @[expression])


proc blockStmt(self: Parser): ASTNode =
    ## Parses block statements. A block
    ## statement simply opens a new local
    ## scope
    var statements: seq[ASTNode] = @[]
    while not self.check(TokenType.RightBrace) and not self.done():
        statements.add(self.statement())
    discard self.expect(TokenType.RightBrace)
    result = newASTNode(self.peek(-1), NodeKind.blockStmt, statements)


proc breakStmt(self: Parser): ASTNode =
    ## Parses break statements
    endOfLine("missing semicolon after break statement")
    result = newASTNode(self.peek(-1), NodeKind.breakStmt)


proc continueStmt(self: Parser): ASTNode =
    ## Parses break statements
    endOfLine("missing semicolon after continue statement")
    result = newASTNode(self.peek(-1), NodeKind.continueStmt)


proc returnStmt(self: Parser): ASTNode =
    ## Parses return statements
    var value: seq[ASTNode] = @[]
    if not self.check(TokenType.Semicolon):
        # Since return can be used on its own too
        # (in which case it implicitly returns nil),
        # we need to check if there's an actual value
        # to return or not
        value.add(self.expression())
    endOfLine("missing semicolon after return statement")
    result = newASTNode(self.peek(-1), NodeKind.returnStmt, value)


proc importStmt(self: Parser): ASTNode =
    ## Parses import statements
    var name = self.expression()
    if name == nil:
        return
    if name.kind != NodeKind.identExpr:
        self.error("expecting module name after import statement")
    endOfLine("missing semicolon after import statement")
    result = newASTNode(self.peek(-1), NodeKind.importStmt, @[name])


proc statement(self: Parser): ASTNode =
    ## Parses statements
    case self.peek().kind:
        of TokenType.Del:
            discard self.step()
            result = self.delStmt()
        of TokenType.Assert:
            discard self.step()
            result = self.assertStmt()
        of TokenType.Break:
            discard self.step()
            result = self.breakStmt()
        of TokenType.Continue:
            discard self.step()
            result = self.continueStmt()
        of TokenType.Return:
            discard self.step()
            result = self.returnStmt()
        of TokenType.Import:
            discard self.step()
            result = self.importStmt()
        of TokenType.Async, TokenType.Await, TokenType.Dynamic, TokenType.Foreach:
            discard self.step()  # TODO: Reserved for future use
        of TokenType.LeftBrace:
            discard self.step()
            result = self.blockStmt()
        else:
            result = self.expressionStatement()


proc declaration(self: Parser): ASTNode =
    ## Parses declarations
    # TODO
    result = self.statement()


proc parse*(self: Parser, tokens: seq[Token], file: string): seq[ASTNode] =
    ## Parses a series of tokens into an AST node
    discard self.initParser()
    self.tokens = tokens
    self.file = file
    while not self.done():
        result.add(self.declaration())
        if self.errored:
            result = @[]
            break
