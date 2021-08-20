# CONFIDENTIAL
# ______________
#
#  2021 Mattia Giambirtone
#  All Rights Reserved.
#
#
# NOTICE: All information contained herein is, and remains
# the property of Mattia Giambirtone. The intellectual and technical
# concepts contained herein are proprietary to Mattia Giambirtone
# and his suppliers and may be covered by Patents and are
# protected by trade secret or copyright law.
# Dissemination of this information or reproduction of this material
# is strictly forbidden unless prior written permission is obtained
# from Mattia Giambirtone
import strformat


import meta/token
import meta/ast

export token, ast




type Parser* = ref object
    ## A recursive-descent top-down
    ## parser implementation
    current: int
    file: string
    errored*: bool
    errorMessage*: string
    tokens: seq[Token]


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


template endOfFile: Token = Token(kind: TokenType.EndOfFile, lexeme: "EOF", line: -1)


proc peek(self: Parser, distance: int = 0): Token =
    ## Peeks at the token at the given distance.
    ## If the distance is out of bounds, an EOF
    ## token is returned. A negative distance may
    ## be used to retrieve previously consumed
    ## tokens
    if self.tokens.high() == -1 or self.current + distance > self.tokens.high():
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
    self.errorMessage = &"A fatal error occurred while parsing '{self.file}', line {self.peek().line} at '{self.peek().lexeme}' -> {message}"
    

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
            self.error(&"Expecting token of kind {kind}, found {self.peek().kind} instead")
        else:
            self.error(message)

# Forward declaration
proc expression(self: Parser): ASTNode


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
            var expression = self.expression()
            if self.expect(TokenType.RightParen, "Unmatched '('"):
                result = newASTNode(self.peek(-1), NodeKind.groupingExpr, @[expression])
        else:
            self.error("Invalid syntax")


proc make_call(self: Parser, callee: ASTNode): ASTNode =
    ## Utility function called iteratively by self.call()
    ## to parse a function-like call
    var arguments: seq[ASTNode] = @[]
    arguments.add(callee)
    if not self.check(TokenType.RightParen):
        while true:
            if len(arguments) >= 255:
                self.error("Cannot have more than 255 arguments")
                break
            arguments.add(self.expression())
            if not self.match(TokenType.Comma):
                break
    if self.expect(TokenType.RightParen):
        result = newASTNode(self.peek(-1), NodeKind.callExpr, arguments)


proc call(self: Parser): ASTNode = 
    ## Parses call expressions and object
    ## accessing ("dot syntax")
    var expression = self.primary()
    while true:
        if self.match(TokenType.LeftParen):
            expression = self.make_call(expression)
        elif self.match(TokenType.Dot):
            if self.expect(TokenType.Identifier, "Expecting attribute name after '.'"):
                expression = newASTNode(self.peek(-2), NodeKind.getExpr, @[newAstNode(self.peek(-1), NodeKind.identExpr, @[expression])])
        else:
            break
    result = expression


proc unary(self: Parser): ASTNode = 
    ## Parses unary expressions
    if self.match([TokenType.Minus, TokenType.Tilde]):
        result = newASTNode(self.peek(-1), NodeKind.unaryExpr, @[self.unary()])
    else:
        result = self.call()


proc pow(self: Parser): ASTNode =
    ## Parses exponentiation expressions
    result = self.unary()
    var operator: Token
    var right: ASTNode
    while self.match(TokenType.DoubleAsterisk):
        operator = self.peek(-1)
        right = self.unary()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc mul(self: Parser): ASTNode =
    ## Parses multiplication and division expressions
    result = self.pow()
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.Slash, TokenType.Percentage, TokenType.FloorDiv]):
        operator = self.peek(-1)
        right = self.pow()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc add(self: Parser): ASTNode =
    ## Parses addition and subtraction expressions
    result = self.mul()
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.Plus, TokenType.Minus]):
        operator = self.peek(-1)
        right = self.mul()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc comparison(self: Parser): ASTNode =
    ## Parses comparison expressions
    result = self.add()
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.LessThan, TokenType.GreaterThan, TokenType.LessOrEqual, TokenType.GreaterOrEqual]):
        operator = self.peek(-1)
        right = self.add()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc equality(self: Parser): ASTNode =
    ## Parses equality expressions
    result = self.comparison()
    var operator: Token
    var right: ASTNode
    while self.match([TokenType.DoubleEqual, TokenType.NotEqual]):
        operator = self.peek(-1)
        right = self.comparison()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc logical_and(self: Parser): ASTNode =
    ## Parses logical AND expressions
    result = self.equality()
    var operator: Token
    var right: ASTNode
    while self.match(TokenType.LogicalAnd):
        operator = self.peek(-1)
        right = self.equality()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc logical_or(self: Parser): ASTNode =
    ## Parses logical OR expressions
    result = self.logical_and()
    var operator: Token
    var right: ASTNode
    while self.match(TokenType.LogicalOr):
        operator = self.peek(-1)
        right = self.logical_and()
        result = newASTNode(operator, NodeKind.binaryExpr, @[result, right])


proc expression(self: Parser): ASTNode = self.logical_or()


proc parse*(self: Parser, tokens: seq[Token], file: string): seq[ASTNode] =
    ## Parses a series of tokens into an AST node
    discard self.initParser()
    self.tokens = tokens
    self.file = file
    var program: seq[ASTNode] = @[]
    while not self.done():
        program.add(self.expression())
        if self.errored:
            program = @[]
            break
    result = program