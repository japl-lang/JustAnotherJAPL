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

## An Abstract Syntax Tree (AST) structure for our recursive-descent
## top-down parser
## 
## Our grammar is taken from the Lox language, from Bob Nystrom's
## "Crafting Interpreters" book available at https://craftinginterpreters.com
## and uses the EBNF syntax, but for clarity it will be explained below.
## 
## The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
## "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
## document are to be interpreted as described in RFC2119 (https://datatracker.ietf.org/doc/html/rfc2119).
## 
## Below is the full grammar, but first a few notes:
## - a sequence of 2 slashes (character code 47) is used to mark comments. A comment lasts until the
##   a CRLF or LF character (basically the end of the line) is encountered. It is RECOMMENDED to use 
##   them to clarify each rule, or group of rules, to simplify human inspection of the specification
## - whitespaces, tabs , newlines and form feeds (character code 32, 9, 10 and 12) are not relevant to the grammar and
##   SHOULD be ignored by automated parsers and parser generators
## - * (character code 42) is used for repetition of a rule, meaning it MUST match 0 or more times
## - + (character code 43) is used for repetition of a rule, meaning it MUST 1 or more times
## - | (character code 123) is used to signify alternatives and means a rule may match either the first or
##   the second rule. This operator can be chained to obtain something like "foo | bar | baz", meaning that either
##   foo, bar or baz are valid matches for the rule
## - {x,y} is used for repetition, meaning a rule MUST match from x to y times (start to end, inclusive).
##   Omitting x means the rule MUST match at least 0 times and at most x times, while omitting y means the rule
##   MUST match exactly y times. Omitting both x and y is the same as using *
## - lines end with an ASCII semicolon (character code 59) and each rule must end with one
## - rules are listed in descending order: the highest-precedence rule MUST come first and all others follow
## - an "arrow" (character code 45 followed by character code 62) MUST be used to separate rule names from their
##   definition.
##   A rule definition then looks something like this (without quotes): "name -> rule definition here; // optional comment"
## - literal numbers can be expressed in their decimal form (i.e. with arabic numbers). Other supported formats are 
##   hexadecimal using the prefix 0x, octal using the prefix 0o, and binary using the prefix 0b. For example,
##   the literals 0x7F, 0b1111111 and 0o177 all represent the decimal number 127 in hexadecimal, binary and
##   octal respectively
## - the literal "EOF" (without quotes), represents the end of the input stream and is a shorthand for "End Of File"
## - ranges can be defined by separating the start and the end of the range with three dots (character code 46) and
##   are inclusive at both ends. Both the start and the end of the range are mandatory and it is RECOMMENDED that they
##   be separated by the three dots with a space for easier reading. Ranges can define numerical sets like in "0 ... 9",
##   or lexicographical ones such as "'a' ... 'z'", in which case the range should be interpreted as a sequence of the 
##   character codes between the start and end of the range. It is REQUIRED that the first element in the range is greater
##   or equal to the last one: backwards ranges are illegal. In addition to this, although numerical ranges can use any 
##   combination of the supported number representation (meaning '0 ... 0x10' is a valid range encompassing all decimal
##   numbers from 0 to 16) it is RECOMMENDED that the representation used is consistent across the start and end of the range.
##   Finally, ranges can have a character and a number as either start or end of them, in which case the character is to be
##   interpreted as its character code in decimal
##  - for readability purposes, it is RECOMMENTED that the grammar text be left aligned and that spaces are used between
##    operators
##    
## 
## 
## program → declaration* EOF; // An entire program (Note: an empty program is a valid program)
## declaration    → classDecl | funDecl | varDecl | statement;
## funDecl        → "fun" function ;
## varDecl        → "var" IDENTIFIER ( "=" expression )? ";" ;

import token


type
    NodeKind* = enum
        ## Enumeration of all node types,
        ## sorted by precedence. This
        ## can be seen as a grammar of sorts

        
        StructDeclaration = 0u8,
        # A statement
        Statement,
        ExpressionStatement,
        Expression,

    ASTNode* = ref object of RootObj
        token*: Token
