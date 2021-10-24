# NimVM - Formal Grammar Specification

## Rationale
The purpose of this document is to provide an unambiguous formal specification of NimVM's syntax for use in automated
compiler generators (known as "compiler compilers") and parsers.

Our grammar is inspired by (and extended from) the Lox language as described in Bob Nystrom's book "Crafting Interpreters", 
available at https://craftinginterpreters.com, and follows the EBNF standard, but for clarity the relevant syntax will
be explained below.

## Disclaimer
----------------------------------------------
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in [RFC2119](https://datatracker.ietf.org/doc/html/rfc2119).

Literals in this document will be often surrounded by double quotes to make it obvious they're not part of a sentence. To
avoid ambiguity, this document will always specify explicitly if double quotes need to be considered as part of a term or not,
which means that if it is not otherwise stated they are to be considered part of said term. In addition to quotes, literals
may be formatted in monospace to make them stand out more in the document.

## EBNF Syntax & Formatting rules
----------------------------------------------
As a refresher to experienced users as well as to facilitate reading to newcomers, the variation of EBNF used in this
document can be summarized with the following points:
- A pair of 2 forward-slashes (character code 47) is used to mark comments. A comment lasts until the
  a CRLF or LF character (basically the end of a line) is encountered. It is RECOMMENDED to use 
  them to clarify each rule, or a group of rules, to simplify human inspection of the specification
- The literal "LF" (without quotes) is a shorthand for "Line Feed" and is platform-independent
- Whitespaces, tabs, newlines and form feeds (character code 32, 9, 10 and 12 respectively) are not 
  relevant to the grammar and MUST be ignored by automated parsers and parser generators
- `"*"` (without quotes, character code 42) is used for repetition of a rule, meaning it MUST match 0 or more times
- `"?"` (without quotes, character code 63) means a rule can match 0 or 1 times
- `"+"` (character code 43) is used for repetition of a rule, meaning it MUST match 1 or more times
- `"|"` (without quotes, character code 123) is used to indicate alternatives and means a rule may match either the first or
  the second rule. This operator can be chained to obtain something like "foo | bar | baz", meaning that either
  foo, bar or baz are valid matches for the rule
- `"{x,y}"` (without quotes) is used for repetition, meaning a rule MUST match from x to y times (start to end, inclusive).
  Omitting x means the rule MUST match at least 0 times and at most x times, while omitting y means the rule
  MUST match exactly y times. Omitting both x and y is the same as using *
- Lines end with an ASCII semicolon (";" without quotes, character code 59) and each rule must end with one
- Rules are listed in descending order: the last rule is the highest-precedence one. Think of it as a "more complex rules
  come first"
- An "arrow" (character code 8594) MUST be used to separate rule names from their definition.
  A rule definition, then, looks something like this (without quotes): "name → rule definition here; // optional comment"
- Literal numbers can be expressed in their decimal form (i.e. with arabic numbers). Other supported formats are 
  hexadecimal using the prefix 0x, octal using the prefix 0o, and binary using the prefix 0b. For example,
  the literals 0x7F, 0b1111111 and 0o177 all represent the decimal number 127 in hexadecimal, binary and
  octal respectively
- The literal "EOF" (without quotes), represents the end of the input stream and is a shorthand for "End Of File"
- Ranges can be defined by separating the start and the end of the range with three dots (character code 46) and
  are inclusive at both ends. Both the start and the end of the range are mandatory and it is RECOMMENDED that they
  be separated by the three dots with a space for easier reading. Ranges can define numerical sets like in `"0 ... 9"` (without quotes),
  or lexicographical ones such as `"'a' ... 'z'"` (without quotes), in which case the range should be interpreted as a sequence of the 
  character codes between the start and end of the range. It is REQUIRED that the first element in the range is greater
  or equal to the last one: backwards ranges are illegal. In addition to this, although numerical ranges can use any 
  combination of the supported number representation (meaning `'0 ... 0x10'` is a valid range encompassing all decimal
  numbers from 0 to 16) it is RECOMMENDED that the representation used is consistent across the start and end of the range.
  Finally, ranges can have a character and a number as either start or end of them, in which case the character is to be
  interpreted as its character code in decimal
 - For readability purposes, it is RECOMMENTED that the grammar text be left aligned and that spaces are used between
   operators
 - Literal strings MUST be delimited by matching pairs of double or single quotes (character code 34 and 39) and SHOULD be separated
   by any other term in the grammar by a space
 - Terminal symbols SHOULD use all-uppercase names to ease readability
 - Characters inside strings can be escaped using backslashes. For example, to add a literal double quote inside a double-quoted string, one MUST
   write `"\""` (without quotes), althoguh it is recommended to use single quotes in this case (i.e. `'"'` instead)

## EBNF Grammar
----------------------------------------------
Below you can find the EBNF specification of NimVM's grammar.

```   
// Top-level code
program        → declaration* EOF; // An entire program (Note: an empty program is a valid program)

// Declarations (rules that bind a name to an object in the current scope and produce side effects)
declaration    → classDecl | funDecl | varDecl | statement;  // A program is composed by a list of declarations
classDecl      → declModifiers? "class" IDENTIFIER ("<" IDENTIFIER ("," IDENTIFIER)*)? blockStmt;   // Declares a class
funDecl        → declModifiers? "async"? "fun" function;   // Function declarations
// Constants still count as "variable" declarations in the grammar
varDecl        → declModifiers? ("var" | | "const") IDENTIFIER ( "=" expression )? ";";

// Statements (rules that produce side effects but without binding a name. Well, mostly: import, for and foreach do, but w/e)
statement      → exprStmt | forStmt | ifStmt | returnStmt| whileStmt| blockStmt;  // The set of all statements
exprStmt       → expression ";";  // Any expression followed by a semicolon is technically a statement
returnStmt     → "return" expression? ";";  // Returns from a function, illegal in top-level code
breakStmt      → "break" ";";
importStmt     -> ("from" IDENTIFIER)? "import" (IDENTIFIER ("as" IDENTIFIER)? ","?)+ ";";
assertStmt     → "assert" expression ";";
delStmt        → "del" expression ";";
yieldStmt      → "yield" expression ";"; 
awaitStmt      → "await" expression ";";
continueStmt   → "continue" ";";
blockStmt      → "{" declaration* "}";  // Blocks create a new scope that lasts until they're closed
ifStmt         → "if" "(" expression ")" statement ("else" statement)?;  // If statements are conditional jumps
whileStmt      → "while" "(" expression ")" statement;  // While loops run until their condition is truthy
forStmt        → "for" "(" (varDecl | exprStmt | ";") expression? ";" expression? ")" statement;  // C-style for loops
// For-each loops iterate over a collection type
foreachStmt    → "foreach" "(" (IDENTIFIER ":" expression) ")" statement;

// Expressions (rules that produce a value, but also have side effects)
expression     → assignment;
assignment     → (call ".")? IDENTIFIER "=" assignment | lambdaExpr;  // Assignment is the highest-level expression
asExpr         → expression "as" expression;
lambdaExpr     → declModifiers? "async"? "lambda" lambda;  // Lambdas are anonymous functions, so they act as expressions
yieldExpr      → "yield" expression;
awaitExpr      → "await" expression;
logic_or       → logic_and ("and" logic_and)*;
logic_and      → equality ("or" equality)*;
equality       → comparison (( "!=" | "==" ) comparison )*;
comparison     → term (( ">" | ">=" | "<" | "<=" ) term )*;
term           → factor (( "-" | "+" ) factor )*;  // Precedence for + and - in operations
factor         → unary (("/" | "*" | "**" | "^" | "&") unary)*;  // All other binary operators have the same precedence
unary          → ("!" | "-" | "~") unary | call;
call           → primary ("(" arguments? ")" | "." IDENTIFIER)*;
// Below are some collection literals: lists, sets, dictionaries and tuples
listExpr       → "[" arguments? "]"
setExpr        → "{" arguments? "}"
dictExpr       → "{" (expression ":" expression ("," expression ":" expression)*)? "}"  // {key: value, ...}
tupleExpr      → "(" arguments? ")"
primary        → "nan" | "true" | "false" | "nil" | "inf" | NUMBER | STRING | IDENTIFIER | "(" expression ")" "." IDENTIFIER;

// Utility rules to avoid repetition
function       → IDENTIFIER ("(" parameters? ")")? blockStmt;
lambda         → ("(" parameters? ")")? blockStmt
parameters     → IDENTIFIER ("," IDENTIFIER)*;
arguments      → expression ("," expression)*;
declModifiers  → ("private" | "public")? ("static" | "dynamic")?

// Lexical grammar that defines terminals in a non-recursive (regular) fashion
COMMENT        → "#" UNICODE* LF;
SINGLESTRING   → QUOTE UNICODE* QUOTE;
DOUBLESTRING   → DOUBLEQUOTE UNICODE* DOUBLEQUOTE;
SINGLEMULTI    → QUOTE{3} UNICODE* QUOTE{3};   // Single quoted multi-line strings
DOUBLEMULTI    → DOUBLEQUOTE{3} UNICODE* DOUBLEQUOTE{3};  // Single quoted multi-line string
DECIMAL        → DIGIT+;
FLOAT          → DIGIT+ ("." DIGIT+)? (("e" | "E") DIGIT+)?;
BIN            → "0b" ("0" | "1")+;
OCT            → "0o" ("0" ... "7")+;
HEX            → "0x" ("0" ... "9" | "A" ... "F" | "a" ... "f")+;
NUMBER         → DECIMAL | FLOAT | BIN | HEX | OCT;  // Numbers encompass integers, floats (even stuff like 1e5), binary numbers, hex numbers and octal numbers
STRING         → ("r"|"b"|"f") SINGLESTRING | DOUBLESTRING | SINGLEMULTI | DOUBLEMULTI;  // Encompasses all strings
IDENTIFIER     → ALPHA (ALPHA | DIGIT)*;  // Valid identifiers are only alphanumeric!
QUOTE          → "'";
DOUBLEQUOTE    → "\"";
ALPHA          → "a" ... "z" | "A" ... "Z" | "_";  // Alphanumeric characters
UNICODE        → 0x00 ... 0x10FFFD;  // This covers the whole unicode range
DIGIT          → "0" ... "9";  // Arabic digits
```
