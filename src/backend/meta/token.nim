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

import strformat


type
  TokenType* {.pure.} = enum
    ## Token types enumeration

    # Booleans
    True, False,

    # Other singleton types
    Inf, NaN, Nil

    # Control-flow statements
    If, Else,

    # Looping statements
    While, For,

    # Keywords
    Function, Break, Lambda,
    Continue, Var, Let, Const, Is,
    Return, Async, Class, Import, From,
    IsNot, Raise, Assert, Del

    # Basic types

    Integer, Float, String, Identifier,
    Binary, Octal, Hex

    # Brackets, parentheses and other
    # symbols

    LeftParen, RightParen, # ()
    LeftBrace, RightBrace, # {}
    LeftBracket, RightBracket, # []
    Dot, Semicolon, Colon, Comma, # . ; : ,
    Plus, Minus, Slash, Asterisk, # + - / *
    Percentage, DoubleAsterisk, # % **
    Caret, Pipe, Ampersand, Tilde, # ^ | & ~
    Equal, GreaterThan, LessThan, # = > <
    LessOrEqual, GreaterOrEqual, # >= <=
    ExclamationMark, DoubleEqual, # ! ==
    NotEqual, RightShift, LeftShift, # != >> <<
    LogicalAnd, LogicalOr, FloorDiv, # && || //
    InplaceAdd, InplaceSub, InplaceDiv, # += -= /=
    InplaceMod, InplaceMul, InplaceXor, # %= *= ^=
    InplaceAnd, InplaceOr, InplaceNot, # &= |= ~=
    InplaceFloorDiv, InplacePow # //= **=

    # Miscellaneous

    EndOfFile


  Token* = ref object
    ## A token object
    kind*: TokenType
    lexeme*: string
    line*: int
    pos*: tuple[start, stop: int]


proc `$`*(self: Token): string = &"Token(kind={self.kind}, lexeme=\"{self.lexeme}\", line={self.line}, pos=({self.pos.start}, {self.pos.stop}))"
