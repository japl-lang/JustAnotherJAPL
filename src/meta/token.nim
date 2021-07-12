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

# Token object

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
    Struct, Function, Break, Lambda,
    Continue, Var, Let, Const, Is,
    Return

    # Basic types

    Integer, Float, String, Identifier

    # Brackets, parentheses and other
    # symbols

    LeftParen, RightParen,  # ()
    LeftBrace, RightBrace,  # {}
    LeftBracket, RightBracket, # []
    Dot, Semicolon, Colon, Comma,  # . ; : ,
    Plus, Minus, Slash, Asterisk,  # + - / *
    Percentage, DoubleAsterisk,    # % **
    Caret, Pipe, Ampersand, Tilde,  # ^ | & ~
    Equal, GreaterThan, LessThan,   # = > <
    LessOrEqual, GreaterOrEqual, # >= <= 
    ExclamationMark, DoubleEqual,   # ! ==
    NotEqual, RightShift, LeftShift, # != >> <<
    

    # Misc

    EndOfFile, Comment


  Token* = object
    kind*: TokenType
    lexeme*: string
    line*: int
