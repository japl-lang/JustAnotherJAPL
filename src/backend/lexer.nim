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

## A simple tokenizer implementation with arbitrary lookahead

import strutils
import strformat
import tables
import meta/token

export `$`  # Makes $Token available when importing the lexer module


# Table of all tokens except reserved keywords
const TOKENS = to_table({
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

# Constant table storing all the reserved keywords (parsed as identifiers)
const RESERVED = to_table({
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
        tokens*: seq[Token]
        line: int
        start: int
        current: int
        errored*: bool
        file: string


func newLexer*(source: string, file: string): Lexer =
    ## Initializes the lexer
    result = Lexer(source: source, tokens: @[], line: 1, start: 0, current: 0,
            errored: false, file: file)


proc done(self: Lexer): bool =
    ## Returns true if we reached EOF
    result = self.current >= self.source.len


proc step(self: Lexer): char =
    ## Steps one character forward in the
    ## source file. A null terminator is returned
    ## if the lexer is at EOF
    if self.done():
        return '\0'
    self.current = self.current + 1
    result = self.source[self.current - 1]


proc peek(self: Lexer, distance: int = 0): char =
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


proc match(self: Lexer, what: char): bool =
    ## Returns true if the next character matches
    ## the given character, and consumes it.
    ## Otherwise, false is returned
    if self.done():
        return false
    elif self.peek() != what:
        return false
    self.current += 1
    return true


proc createToken(self: Lexer, tokenType: TokenType) =
    ## Creates a token object and adds it to the token
    ## list
    self.tokens.add(Token(kind: tokenType,
                   lexeme: self.source[self.start..<self.current],
                   line: self.line
        ))


proc error(self: Lexer, message: string) =
    ## Writes an error message to stdout
    ## and sets the error flag for the lexer

    self.errored = true
    stderr.write(&"A fatal error occurred while parsing '{self.file}', line {self.line} at '{self.peek()}' -> {message}\n")


proc parseString(self: Lexer, delimiter: char) =
    ## Parses string literals
    while self.peek() != delimiter and not self.done():
        if self.peek() == '\n':
            self.line = self.line + 1
        discard self.step()
    if self.done():
        self.error("Unexpected EOL while parsing string literal")
    discard self.step()
    self.createToken(TokenType.String)


proc parseNumber(self: Lexer) =
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


proc parseIdentifier(self: Lexer) =
    ## Parses identifiers, note that
    ## multi-character tokens such as
    ## UTF runes are not supported
    while self.peek().isAlphaNumeric() or self.peek() in {'_', }:
        discard self.step()
    var text: string = self.source[self.start..<self.current]
    if text in RESERVED:
        self.createToken(RESERVED[text])
    else:
        self.createToken(TokenType.Identifier)


proc parseComment(self: Lexer) =
    ## Parses multi-line comments. They start
    ## with /* and end with */
    var closed = false
    var text = ""
    while not self.done():
        var finish = self.peek() & self.peek(1)
        if finish == "*/":
            closed = true
            discard self.step() # Consume the two ends
            discard self.step()
            break
        else:
            text &= self.step()
    if self.done() and not closed:
        self.error("Unexpected EOF while parsing multi-line comment")
    self.tokens.add(Token(kind: TokenType.Comment, lexeme: text.strip(),
            line: self.line))


proc scanToken(self: Lexer) =
    ## Scans a single token. This method is
    ## called iteratively until the source
    ## file reaches EOF
    var single = self.step()
    if single in [' ', '\t', '\r']: # We skip whitespaces, tabs and other useless characters
        return
    elif single == '\n':
        self.line += 1
    elif single in ['"', '\'']:
        self.parseString(single)
    elif single.isDigit():
        self.parseNumber()
    elif single.isAlphaNumeric() or single == '_':
        self.parseIdentifier()
    elif single in TOKENS:
        if single == '/' and self.match('/'):
            while self.peek() != '\n' and not self.done():
                discard self.step()
        elif single == '/' and self.match('*'):
            self.parseComment()
        elif single == '=' and self.match('='):
            self.createToken(TokenType.DoubleEqual)
        elif single == '>' and self.match('='):
            self.createToken(TokenType.GreaterOrEqual)
        elif single == '>' and self.match('>'):
            self.createToken(TokenType.RightShift)
        elif single == '<' and self.match('='):
            self.createToken(TokenType.LessOrEqual)
        elif single == '<' and self.match('<'):
            self.createToken(TokenType.LeftShift)
        elif single == '!' and self.match('='):
            self.createToken(TokenType.NotEqual)
        elif single == '*' and self.match('*'):
            self.createToken(TokenType.DoubleAsterisk)
        elif single == '&' and self.match('&'):
            self.createToken(TokenType.LogicalAnd)
        elif single == '|' and self.match('|'):
            self.createToken(TokenType.LogicalOr)
        else:
            self.createToken(TOKENS[single])
    else:
        self.error(&"Unexpected token '{single}'")


proc lex*(self: Lexer): seq[Token] =
    ## Lexes a source file, converting a stream
    ## of characters into a series of tokens
    while not self.done():
        self.start = self.current
        self.scanToken()
    self.tokens.add(Token(kind: TokenType.EndOfFile, lexeme: "EOF",
            line: self.line))
    return self.tokens
