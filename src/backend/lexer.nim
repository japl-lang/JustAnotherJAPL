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

# Table of all triple-character tokens
const triple = to_table({"//=": TokenType.InplaceFloorDiv,
                         "**=": TokenType.InplacePow
    })


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
                         "//": TokenType.FloorDiv,
                         "+=": TokenType.InplaceAdd,
                         "-=": TokenType.InplaceSub,
                         "/=": TokenType.InplaceDiv,
                         "*=": TokenType.InplaceMul,
                         "^=": TokenType.InplaceXor,
                         "&=": TokenType.InplaceAnd,
                         "|=": TokenType.InplaceOr,
                         "~=": TokenType.InplaceNot,
                         "%=": TokenType.InplaceMod
    })

# Constant table storing all the reserved keywords (parsed as identifiers)
const reserved = to_table({
                "fun": TokenType.Function, "raise": TokenType.Raise,
                "if": TokenType.If, "else": TokenType.Else,
                "for": TokenType.For, "while": TokenType.While,
                "var": TokenType.Var, "nil": TokenType.NIL,
                "true": TokenType.True, "false": TokenType.False,
                "return": TokenType.Return, "break": TokenType.Break,
                "continue": TokenType.Continue, "inf": TokenType.Inf,
                "nan": TokenType.NaN, "is": TokenType.Is,
                "lambda": TokenType.Lambda, "class": TokenType.Class,
                "async": TokenType.Async, "import": TokenType.Import,
                "isnot": TokenType.IsNot, "from": TokenType.From,
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


func newLexer*(self: Lexer = nil): Lexer =
    ## Initializes the lexer or resets
    ## the state of an existing one
    if self == nil:
        result = Lexer(source: "", tokens: @[], line: 1, start: 0, current: 0,
            errored: false, file: "", errorMessage: "")
    else:
        self.source = ""
        self.tokens = @[]
        self.line = 1
        self.start = 0
        self.current = 0
        self.errored = false
        self.file = ""
        self.errorMessage = ""
        result = self


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
    ## (retrieves the next token to be consumed).
    if self.done() or self.current + distance > self.source.high():
        result = '\0'
    else:
        result = self.source[self.current + distance]


func error(self: Lexer, message: string) =
    ## Sets the errored and errorMessage fields
    ## for the lexer. The lex method will not
    ## continue tokenizing if it finds out
    ## an error occurred
    self.errored = true
    self.errorMessage = &"A fatal error occurred while parsing '{self.file}', line {self.line} at '{self.peek()}' -> {message}"


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



func check(self: Lexer, what: openarray[char]): bool =
    ## Calls self.check() in a loop with
    ## each character from the given seq of
    ## char and returns at the first match.
    ## Useful to check multiple tokens in a situation
    ## where only one of them may match at one time
    for i, chr in what:
        if self.check(chr, i):
            return true
    return false


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


func match(self: Lexer, what: openarray[char]): bool =
    ## Calls self.match() in a loop with
    ## each character from the given seq of
    ## char and returns at the first match.
    ## Useful to match multiple tokens in a situation
    ## where only one of them may match at one time
    for chr in what:
        if self.match(chr):
            return true
    return false


func createToken(self: Lexer, tokenType: TokenType) =
    ## Creates a token object and adds it to the token
    ## list
    self.tokens.add(Token(kind: tokenType,
                   lexeme: self.source[self.start..<self.current],
                   line: self.line
        ))


func parseString(self: Lexer, delimiter: char, mode: string = "single") =
    ## Parses string literals
    while not self.check(delimiter) and not self.done():
        if self.check('\n') and mode == "multi":
            self.line = self.line + 1
        else:
            self.error("Unexpected EOL while parsing string literal")
            return
        if mode in ["raw", "multi"]:
            discard self.step()
        elif self.check('\\'):
            # Escape sequences.
            # We currently support only the basic
            # ones, so stuff line \nnn, \xhhh, \uhhhh and
            # \Uhhhhhhhh are not supported
            discard self.step()
            case self.peek(-1):
                of 'a':
                    self.source[self.current] = cast[char](0x07)
                of 'b':
                    self.source[self.current] = cast[char](0x7f)
                of 'e':
                    self.source[self.current] = cast[char](0x1B)
                of 'f':
                    self.source[self.current] = cast[char](0x0C)
                of 'n':
                    self.source[self.current] = cast[char](0x0)
                of 'r':
                    self.source[self.current] = cast[char](0x0D)
                of 't':
                    self.source[self.current] = cast[char](0x09)
                of 'v':
                    self.source[self.current] = cast[char](0x0B)
                of '"':
                    self.source[self.current] = '"'
                of '\'':
                    self.source[self.current] = '\''
                of '\\':
                    self.source[self.current] = cast[char](0x5C)
                else:
                    self.error(&"Invalid escape sequence '\\{self.peek()}'")
                    return
    if self.done():
        self.error(&"Unexpected EOF while parsing string literal")
        return
    if mode == "multi":
        if not self.match(delimiter.repeat(3)):
            self.error("Unexpected EOL while parsing multi-line string literal")
    else:
        discard self.step()
    self.createToken(TokenType.String)


func parseNumber(self: Lexer) =
    ## Parses numeric literals
    var kind: TokenType = TokenType.Integer
    while isDigit(self.peek()):
        discard self.step()
    if self.check(['.', 'e', 'E']):
        # Scientific notation is supported
        while self.peek().isDigit():
            discard self.step()
        kind = TokenType.Float
    self.createToken(kind)


proc parseIdentifier(self: Lexer) =
    ## Parses identifiers. Note that
    ## multi-character tokens such as
    ## UTF runes are not supported
    while self.peek().isAlphaNumeric() or self.check('_'):
        discard self.step()
    var text: string = self.source[self.start..<self.current]
    if text in reserved:
        # It's a keyword
        self.createToken(reserved[text])
    else:
        # Identifier!
        self.createToken(TokenType.Identifier)


proc next(self: Lexer) =
    ## Scans a single token. This method is
    ## called iteratively until the source
    ## file reaches EOF
    if self.done():
        return
    var single = self.step()
    if single in [' ', '\t', '\r', '\f',
            '\e']: # We skip whitespaces, tabs and other useless characters
        return
    elif single == '\n':
        self.line += 1
    elif single in ['"', '\'']:
        if self.check(single) and self.check(single, 1):
            # Multiline strings start with 3 apexes
            self.parseString(single, "multi")
        else:
            self.parseString(single)
    elif single.isDigit():
        self.parseNumber()
    elif single.isAlphaNumeric() and self.check(['"', '\'']):
        # Like Python, we support bytes and raw literals
        case single:
            of 'r':
                self.parseString(self.peek(-1), "raw")
            of 'b':
                self.parseString(self.peek(-1), "bytes")
            else:
                # TODO: Format strings? (f"{hello}")
                self.error(&"Unknown string prefix '{single}'")
                return
    elif single.isAlphaNumeric() or single == '_':
        self.parseIdentifier()
    else:
        # Comments are a special case
        if single == '#':
            while not self.check('\n'):
                discard self.step()
            return
        # We start by checking for multi-character tokens,
        # in descending length so //= doesn't translate
        # to the pair of tokens (//, =) for example
        for key in triple.keys():
            if key[0] == single and self.check(key[1..^1]):
                discard self.step(2)  # We step 2 characters
                self.createToken(triple[key])
                return
        for key in double.keys():
            if key[0] == single and self.check(key[1]):
                discard self.step()
                self.createToken(double[key])
                return
        if single in tokens:
            # Eventually we emit a single token
            self.createToken(tokens[single])
        else:
            self.error(&"Unexpected token '{single}'")


proc lex*(self: Lexer, source, file: string): seq[Token] =
    ## Lexes a source file, converting a stream
    ## of characters into a series of tokens.
    ## If an error occurs, this procedure
    ## returns an empty sequence and the lexer's
    ## errored and errorMessage fields will be set
    discard self.newLexer()
    self.source = source
    self.file = file
    while not self.done():
        self.next()
        self.start = self.current
        if self.errored:
            return @[]
    self.tokens.add(Token(kind: TokenType.EndOfFile, lexeme: "EOF",
            line: self.line))
    return self.tokens
