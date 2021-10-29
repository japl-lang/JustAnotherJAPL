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

## A simple and modular tokenizer implementation with arbitrary lookahead

import strutils
import parseutils
import strformat
import tables

import meta/token
import meta/errors


export token # Makes Token available when importing the lexer module
export errors


# Tables of all character tokens that are not keywords

# Table of all single-character tokens
const tokens = to_table({
              '(': LeftParen, ')': RightParen,
              '{': LeftBrace, '}': RightBrace,
              '.': Dot, ',': Comma, '-': Minus, 
              '+': Plus, '*': Asterisk,
              '>': GreaterThan, '<': LessThan, '=': Equal,
              '~': Tilde, '/': Slash, '%': Percentage,
              '[': LeftBracket, ']': RightBracket,
              ':': Colon, '^': Caret, '&': Ampersand,
              '|': Pipe, ';': Semicolon})

# Table of all double-character tokens
const double = to_table({"**": DoubleAsterisk,
                         ">>": RightShift,
                         "<<": LeftShift,
                         "==": DoubleEqual,
                         "!=": NotEqual,
                         ">=": GreaterOrEqual,
                         "<=": LessOrEqual,
                         "//": FloorDiv,
                         "+=": InplaceAdd,
                         "-=": InplaceSub,
                         "/=": InplaceDiv,
                         "*=": InplaceMul,
                         "^=": InplaceXor,
                         "&=": InplaceAnd,
                         "|=": InplaceOr,
                         "~=": InplaceNot,
                         "%=": InplaceMod,
    })

# Table of all triple-character tokens
const triple = to_table({"//=": InplaceFloorDiv,
                         "**=": InplacePow
    })


# Constant table storing all the reserved keywords (which are parsed as identifiers)
const keywords = to_table({
                "fun": Fun, "raise": Raise,
                "if": If, "else": Else,
                "for": For, "while": While,
                "var": Var, "nil": Nil,
                "true": True, "false": False,
                "return": Return, "break": Break,
                "continue": Continue, "inf": Infinity,
                "nan": NotANumber, "is": Is,
                "lambda": Lambda, "class": Class,
                "async": Async, "import": Import,
                "isnot": IsNot, "from": From,
                "const": Const,
                "assert": Assert, "or": LogicalOr,
                "and": LogicalAnd, "del": Del,
                "async": Async, "await": Await,
                "foreach": Foreach, "yield": Yield,
                "private": Private, "public": Public,
                "static": Static, "dynamic": Dynamic,
                "as": As, "of": Of, "defer": Defer,
                "except": Except, "finally": Finally,
                "try": Try
    })


type
    Lexer* = ref object
        ## A lexer object
        source: string
        tokens: seq[Token]
        line: int
        start: int
        current: int
        file: string


proc initLexer*(self: Lexer = nil): Lexer =
    ## Initializes the lexer or resets
    ## the state of an existing one
    new(result)
    if self != nil:
        result = self
    result.source = ""
    result.tokens = @[]
    result.line = 1
    result.start = 0
    result.current = 0
    result.file = ""


proc done(self: Lexer): bool =
    ## Returns true if we reached EOF
    result = self.current >= self.source.len


proc step(self: Lexer, n: int = 1): char =
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


proc peek(self: Lexer, distance: int = 0): char =
    ## Returns the character in the source file at
    ## the given distance without consuming it.
    ## A null terminator is returned if the lexer
    ## is at EOF. The distance parameter may be
    ## negative to retrieve previously consumed
    ## tokens, while the default distance is 0
    ## (retrieves the next token to be consumed).
    ## If the given distance goes beyond EOF, a
    ## null terminator is returned
    if self.done() or self.current + distance > self.source.high():
        result = '\0'
    else:
        result = self.source[self.current + distance]


proc error(self: Lexer, message: string) =
    ## Raises a lexing error with a formatted
    ## error message
    raise newException(LexingError, &"A fatal error occurred while parsing '{self.file}', line {self.line} at '{self.peek()}' -> {message}")


proc check(self: Lexer, what: char, distance: int = 0): bool =
    ## Behaves like match, without consuming the
    ## token. False is returned if we're at EOF
    ## regardless of what the token to check is.
    ## The distance is passed directly to self.peek()
    if self.done():
        return false
    return self.peek(distance) == what


proc check(self: Lexer, what: string): bool =
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


proc check(self: Lexer, what: openarray[char]): bool =
    ## Calls self.check() in a loop with
    ## each character from the given seq of
    ## char and returns at the first match.
    ## Useful to check multiple tokens in a situation
    ## where only one of them may match at one time
    for chr in what:
        if self.check(chr):
            return true
    return false


proc match(self: Lexer, what: char): bool =
    ## Returns true if the next character matches
    ## the given character, and consumes it.
    ## Otherwise, false is returned
    if self.done():
        self.error("unexpected EOF")
        return false
    elif not self.check(what):
        self.error(&"expecting '{what}', got '{self.peek()}' instead")
        return false
    self.current += 1
    return true


proc match(self: Lexer, what: string): bool =
    ## Calls self.match() in a loop with
    ## each character from the given source
    ## string. Useful to match multi-character
    ## strings in one go
    for chr in what:
        if not self.match(chr):
            return false
    return true


proc createToken(self: Lexer, tokenType: TokenType) =
    ## Creates a token object and adds it to the token
    ## list
    var tok = new(Token)
    tok.kind = tokenType
    tok.lexeme = self.source[self.start..<self.current]
    tok.line = self.line
    tok.pos =  (start: self.start, stop: self.current)
    self.tokens.add(tok)


proc parseEscape(self: Lexer) =
    # Boring escape sequence parsing. For more info check out
    # https://en.wikipedia.org/wiki/Escape_sequences_in_C.
    # As of now, \u and \U are not supported, but they'll
    # likely be soon. Another notable limitation is that
    # \xhhh and \nnn are limited to the size of a char
    # (i.e. uint8, or 256 values)
    case self.peek():
        of 'a':
            self.source[self.current] = cast[char](0x07)
        of 'b':
            self.source[self.current] = cast[char](0x7f)
        of 'e':
            self.source[self.current] = cast[char](0x1B)
        of 'f':
            self.source[self.current] = cast[char](0x0C)
        of 'n':
            when defined(windows):
                # We natively convert LF to CRLF on Windows, and
                # gotta thank Microsoft for the extra boilerplate!
                self.source[self.current] = cast[char](0x0D)
                self.source &= cast[char](0X0A)
            else:
                when defined(darwin):
                    # Thanks apple, lol
                    self.source[self.current] = cast[char](0x0A)
                else:
                    self.source[self.current] = cast[char](0X0D)
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
        of '0'..'9':
            var code = ""
            var value = 0
            var i = self.current
            while i < self.source.high() and (let c = self.source[i].toLowerAscii(); c in '0'..'7') and len(code) < 3:
                code &= self.source[i]
                i += 1
            assert parseOct(code, value) == code.len()
            self.source[self.current] = cast[char](value)
        of 'u':
            self.error("unicode escape sequences are not supported (yet)")
        of 'U':
            self.error("unicode escape sequences are not supported (yet)")
        of 'x':
            var code = ""
            var value = 0
            var i = self.current
            while i < self.source.high() and (let c = self.source[i].toLowerAscii(); c in 'a'..'f' or c in '0'..'9'):
                code &= self.source[i]
                i += 1
            assert parseHex(code, value) == code.len()
            self.source[self.current] = cast[char](value)
        else:
            self.error(&"invalid escape sequence '\\{self.peek()}'")


proc parseString(self: Lexer, delimiter: char, mode: string = "single") =
    ## Parses string literals. They can be expressed using matching pairs
    ## of either single or double quotes. Most C-style escape sequences are
    ## supported, moreover, a specific prefix may be prepended
    ## to the string to instruct the lexer on how to parse it:
    ## - b -> declares a byte string, where each character is
    ##     interpreted as an integer instead of a character
    ## - r -> declares a raw string literal, where escape sequences
    ##     are not parsed and stay as-is
    ## - f -> declares a format string, where variables may be
    ##     interpolated using curly braces like f"Hello, {name}!".
    ##     Braces may be escaped using a pair of them, so to represent
    ##     a literal "{" in an f-string, one would use {{ instead
    ## Multi-line strings can be declared using matching triplets of
    ## either single or double quotes. They can span across multiple
    ## lines and escape sequences in them are not parsed, like in raw
    ## strings, so a multi-line string prefixed with the "r" modifier
    ## is redundant, although multi-line byte strings are supported
    while not self.check(delimiter) and not self.done():
        if self.check('\n'):
            if mode == "multi":
                self.line = self.line + 1
            else:
                self.error("unexpected EOL while parsing string literal")
        if mode in ["raw", "multi"]:
            discard self.step()
        if self.check('\\'):
            # This madness here serves to get rid of the slash, since \x is mapped
            # to a one-byte sequence but the string '\x' actually 2 bytes (or more, 
            # depending on the specific escape sequence)
            self.source = self.source[0..<self.current] & self.source[self.current + 1..^1]
            self.parseEscape()
        if mode == "format" and self.check('{'):
            discard self.step()
            if self.check('{'):
                self.source = self.source[0..<self.current] & self.source[self.current + 1..^1]
                continue
            while not self.check(['}', '"']):
                discard self.step()
            if self.check('"'):
                self.error("unclosed '{' in format string")
        elif mode == "format" and self.check('}'):
            if not self.check('}', 1):
                self.error("unmatched '}' in format string")
            else:
                self.source = self.source[0..<self.current] & self.source[self.current + 1..^1]
        discard self.step()
    if self.done():
        self.error("unexpected EOF while parsing string literal")
        return
    if mode == "multi":
        if not self.match(delimiter.repeat(3)):
            self.error("unexpected EOL while parsing multi-line string literal")
    else:
        discard self.step()
    self.createToken(String)


proc parseBinary(self: Lexer) =
    ## Parses binary numbers
    while self.peek().isDigit():
        if not self.check(['0', '1']):
            self.error(&"invalid digit '{self.peek()}' in binary literal")
        discard self.step()
    self.createToken(Binary)
    # To make our life easier, we pad the binary number in here already
    while (self.tokens[^1].lexeme.len() - 2) mod 8 != 0:
        self.tokens[^1].lexeme = "0b" & "0" & self.tokens[^1].lexeme[2..^1]

proc parseOctal(self: Lexer) =
    ## Parses octal numbers
    while self.peek().isDigit():
        if self.peek() notin '0'..'7':
            self.error(&"invalid digit '{self.peek()}' in octal literal")
        discard self.step()
    self.createToken(Octal)


proc parseHex(self: Lexer) =
    ## Parses hexadecimal numbers
    while self.peek().isAlphaNumeric():
        if not self.peek().isDigit() and self.peek().toLowerAscii() notin 'a'..'f':
            self.error(&"invalid hexadecimal literal")
        discard self.step()
    self.createToken(Hex)


proc parseNumber(self: Lexer) =
    ## Parses numeric literals, which encompass
    ## integers and floats composed of arabic digits.
    ## Floats also support scientific notation
    ## (i.e. 3e14), while the fractional part
    ## must be separated from the decimal one
    ## using a dot (which acts as a "comma").
    ## Literals such as 32.5e3 are also supported.
    ## The "e" for the scientific notation of floats
    ## is case-insensitive. Binary number literals are
    ## expressed using the prefix 0b, hexadecimal
    ## numbers with the prefix 0x and octal numbers
    ## with the prefix 0o 
    case self.peek():
        of 'b':
            discard self.step()
            self.parseBinary()
        of 'x':
            discard self.step()
            self.parseHex()
        of 'o':
            discard self.step()
            self.parseOctal()
        else:
            var kind: TokenType = Integer
            while isDigit(self.peek()):
                discard self.step()
            if self.check(['e', 'E']):
                kind = Float
                discard self.step()
                while self.peek().isDigit():
                    discard self.step()
            elif self.check('.'):
                # TODO: Is there a better way?
                discard self.step()
                if not isDigit(self.peek()):
                    self.error("invalid float number literal")
                kind = Float
                while isDigit(self.peek()):
                    discard self.step()
                if self.check(['e', 'E']):
                    discard self.step()
                while isDigit(self.peek()):
                    discard self.step()
            self.createToken(kind)


proc parseIdentifier(self: Lexer) =
    ## Parses identifiers and keywords.
    ## Note that multi-character tokens
    ## such as UTF runes are not supported
    while self.peek().isAlphaNumeric() or self.check('_'):
        discard self.step()
    var name: string = self.source[self.start..<self.current]
    if name in keywords:
        # It's a keyword
        self.createToken(keywords[name])
    else:
        # Identifier!
        self.createToken(Identifier)


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
            # Multiline strings start with 3 quotes
            discard self.step(2)
            self.parseString(single, "multi")
        else:
            self.parseString(single)
    elif single.isDigit():
        self.parseNumber()
    elif single.isAlphaNumeric() and self.check(['"', '\'']):
        # Like Python, we support bytes and raw literals
        case single:
            of 'r':
                self.parseString(self.step(), "raw")
            of 'b':
                self.parseString(self.step(), "bytes")
            of 'f':
                self.parseString(self.step(), "format")
            else:
                self.error(&"unknown string prefix '{single}'")
    elif single.isAlphaNumeric() or single == '_':
        self.parseIdentifier()
    else:
        # Comments are a special case
        if single == '#':
            while not (self.check('\n') or self.done()):
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
            self.error(&"unexpected token '{single}'")


proc lex*(self: Lexer, source, file: string): seq[Token] =
    ## Lexes a source file, converting a stream
    ## of characters into a series of tokens.
    ## If an error occurs, this procedure
    ## returns an empty sequence and the lexer's
    ## errored and errorMessage fields will be set
    discard self.initLexer()
    self.source = source
    self.file = file
    while not self.done():
        self.next()
        self.start = self.current
    self.tokens.add(Token(kind: EndOfFile, lexeme: "",
            line: self.line))
    return self.tokens
