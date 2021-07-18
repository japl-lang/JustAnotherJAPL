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

## A simple and modular tokenizer implementation with arbitrary lookahead

import strutils
import strformat
import tables
import meta/token

export token # Makes Token available when importing the lexer module


# Table of all tokens except reserved keywords
const tokens = to_table({
              '(': TokenType.LeftParen, ')': TokenType.RightParen,
              '{': TokenType.LeftBrace, '}': TokenType.RightBrace,
              '.': TokenType.Dot, ',': TokenType.Comma,
              '-': TokenType.Minus, '+': TokenType.Plus,
              ';': TokenType.Semicolon, '*': TokenType.Asterisk,
              '>': TokenType.GreaterThan, '<': TokenType.LessThan,
              '=': TokenType.Equal, '~': TokenType.Tilde,
              '/': TokenType.Slash, '%': TokenType.Percentage,
              '[': TokenType.LeftBracket, ']': TokenType.RightBracket,
              ':': TokenType.Colon, '^': TokenType.Caret,
              '&': TokenType.Ampersand, '|': TokenType.Pipe,
              '!': TokenType.ExclamationMark})

# Table of all double-character tokens
const double = to_table({"**": TokenType.DoubleAsterisk,
                         "||": TokenType.LogicalOr,
                         "&&": TokenType.LogicalAnd,
                         ">>": TokenType.RightShift,
                         "<<": TokenType.LeftShift,
                         "==": TokenType.DoubleEqual,
                         "!=": TokenType.NotEqual,
                         ">=": TokenType.GreaterOrEqual,
                         "<=": TokenType.LessOrEqual,
    })

# Constant table storing all the reserved keywords (parsed as identifiers)
const reserved = to_table({
                "fun": TokenType.Function, "struct": TokenType.Struct,
                "if": TokenType.If, "else": TokenType.Else,
                "for": TokenType.For, "while": TokenType.While,
                "var": TokenType.Var, "nil": TokenType.NIL,
                "true": TokenType.True, "false": TokenType.False,
                "return": TokenType.Return, "break": TokenType.Break,
                "continue": TokenType.Continue, "inf": TokenType.Inf,
                "nan": TokenType.NaN, "is": TokenType.Is,
                "lambda": TokenType.Lambda
    })
type
    Lexer* = ref object
        ## A lexer object
        source: string
        tokens: seq[Token]
        line: int
        start: int
        current: int
        errored*: bool
        file: string
        errorMessage*: string


func newLexer*(source: string, file: string): Lexer =
    ## Initializes the lexer
    result = Lexer(source: source, tokens: @[], line: 1, start: 0, current: 0,
            errored: false, file: file, errorMessage: "")


func done(self: Lexer): bool =
    ## Returns true if we reached EOF
    result = self.current >= self.source.len


func step(self: Lexer, n: int = 1): char =
    ## Steps n characters forward in the
    ## source file (default = 1). A null
    ## terminator is returned if the lexer
    ## is at EOF. Note that only the first
    ## consumed character token is returned,
    ## the other ones are skipped over
    if self.done():
        return '\0'
    self.current = self.current + n
    result = self.source[self.current - n]


func peek(self: Lexer, distance: int = 0): char =
    ## Returns the character in the source file at
    ## the given distance without consuming it.
    ## A null terminator is returned if the lexer
    ## is at EOF. The distance parameter may be
    ## negative to retrieve previously consumed
    ## tokens, while the default distance is 0
    ## (retrieves the next token to be consumed)
    if self.done():
        result = '\0'
    else:
        result = self.source[self.current + distance]


func error(self: Lexer, message: string) =
    ## Sets the errored and errorMessage fields
    ## for the lexer. The lex method will not
    ## continue tokenizing if it finds out
    ## an error occurred
    self.errored = true
    self.errorMessage = &"A fatal error occurred while parsing '{self.file}', line {self.line} at '{self.peek()}' -> {message}\n"


func check(self: Lexer, what: char, distance: int = 0): bool =
    ## Behaves like match, without consuming the
    ## token. False is returned if we're at EOF
    ## regardless of what the token to check is.
    ## The distance is passed directly to self.peek()
    if self.done():
        return false
    return self.peek(distance) == what


func check(self: Lexer, what: string): bool =
    ## Calls self.check() in a loop with
    ## each character from the given source
    ## string. Useful to check multi-character
    ## strings in one go
    for i, chr in what:
        # Why "i" you ask? Well, since check
        # does not consume the tokens it checks
        # against we need some way of keeping
        # track where we are in the string the
        # caller gave us, otherwise this will
        # not behave as expected
        if not self.check(chr, i):
            return false
    return true


func match(self: Lexer, what: char): bool =
    ## Returns true if the next character matches
    ## the given character, and consumes it.
    ## Otherwise, false is returned
    if self.done():
        self.error("Unexpected EOF")
        return false
    elif not self.check(what):
        self.error(&"Expecting '{what}', got '{self.peek()}' instead")
        return false
    self.current += 1
    return true


func match(self: Lexer, what: string): bool =
    ## Calls self.match() in a loop with
    ## each character from the given source
    ## string. Useful to match multi-character
    ## strings in one go
    for chr in what:
        if not self.match(chr):
            return false
    return true


func createToken(self: Lexer, tokenType: TokenType) =
    ## Creates a token object and adds it to the token
    ## list
    self.tokens.add(Token(kind: tokenType,
                   lexeme: self.source[self.start..<self.current],
                   line: self.line
        ))


func parseString(self: Lexer, delimiter: char) =
    ## Parses string literals
    while self.peek() != delimiter and not self.done():
        if self.peek() == '\n':
            self.line = self.line + 1
        discard self.step()
    if self.done():
        self.error("Unexpected EOL while parsing string literal")
    discard self.step()
    self.createToken(TokenType.String)


func parseNumber(self: Lexer) =
    ## Parses numeric literals
    var kind: TokenType = TokenType.Integer
    while isDigit(self.peek()):
        discard self.step()
    if self.peek() in {'.', 'e', 'E'}:
        discard self.step()
        while self.peek().isDigit():
            discard self.step()
        kind = TokenType.Float
    self.createToken(kind)


func parseIdentifier(self: Lexer) =
    ## Parses identifiers, note that
    ## multi-character tokens such as
    ## UTF runes are not supported
    while self.peek().isAlphaNumeric() or self.peek() in {'_', }:
        discard self.step()
    var text: string = self.source[self.start..<self.current]
    if text in reserved:
        self.createToken(reserved[text])
    else:
        self.createToken(TokenType.Identifier)


func parseComment(self: Lexer) =
    ## Parses multi-line comments. They start
    ## with /* and end with */
    var closed = false
    var text = ""
    while not self.done():
        if self.check("*/"):
            closed = true
            discard self.step(2)
            break
        else:
            text &= self.step()
    if not closed or self.done():
        self.error("Unexpected EOF while parsing multi-line comment")
    self.tokens.add(Token(kind: TokenType.Comment, lexeme: text.strip(),
            line: self.line))


func next(self: Lexer) =
    ## Scans a single token. This method is
    ## called iteratively until the source
    ## file reaches EOF
    if self.done():
        return
    var single = self.step()
    var multi = false
    if single in [' ', '\t', '\r', '\f',
            '\e']: # We skip whitespaces, tabs and other useless characters
        return
    elif single == '\n':
        self.line += 1
    elif single in ['"', '\'']:
        self.parseString(single)
    elif single.isDigit():
        self.parseNumber()
    elif single.isAlphaNumeric() or single == '_':
        self.parseIdentifier()
    elif single in tokens:
        # These 2 are special cases (comments)
        if single == '/' and self.match('/'):
            while not self.check('\n'):
                discard self.step()
            return
        elif single == '/' and self.match('*'):
            self.parseComment()
            return
        for key in double.keys():
            if key[0] == single and key[1] == self.peek():
                discard self.step()
                multi = true
                self.createToken(double[key])
                return
        if not multi:
            self.createToken(tokens[single])
    else:
        self.error(&"Unexpected token '{single}'")


func lex*(self: Lexer): seq[Token] =
    ## Lexes a source file, converting a stream
    ## of characters into a series of tokens.
    ## If an error occurs, this procedure
    ## returns an empty sequence and the lexer's
    ## errored and errorMessage fields will be set
    while not self.done():
        self.next()
        self.start = self.current
        if self.errored:
            return @[]
    self.tokens.add(Token(kind: TokenType.EndOfFile, lexeme: "EOF",
            line: self.line))
    return self.tokens
