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

## An Abstract Syntax Tree (AST) structure for our recursive-descent
## top-down parser. For more info, check out docs/grammar.md

import token

import strformat
import strutils


type
    NodeKind* = enum
        ## Enumeration of the AST
        ## node types, sorted by
        ## precedence

        # Declarations
        classDecl = 0u8,
        funDecl,
        asyncFunDecl,
        varDecl,
        # Statements
        forStmt,  # Unused for now (for loops are compiled to while loops)
        foreachStmt,
        ifStmt,
        returnStmt,
        breakStmt,
        continueStmt,
        whileStmt,
        blockStmt,
        raiseStmt,
        assertStmt,
        delStmt,
        fromStmt,
        importStmt,
        # An expression followed by a semicolon
        exprStmt,
        # Expressions
        assignExpr,
        setExpr,  # Set expressions like a.b = "c"
        awaitExpr,
        binaryExpr,
        unaryExpr,
        callExpr,
        getExpr,  # Get expressions like a.b
        # Primary expressions
        groupingExpr,  # Parenthesized expressions such as (true) and (3 + 4)
        trueExpr,
        falseExpr,
        strExpr,
        intExpr,
        floatExpr,
        hexExpr,
        octExpr,
        binExpr,
        nilExpr,
        nanExpr,
        infExpr,
        identExpr,   # Identifier


    ASTNode* = ref object
        ## An AST node
        token*: Token
        kind*: NodeKind
        # This makes our life easier
        # because we don't need object
        # variants or inheritance to
        # determine how many (if any)
        # child nodes we need/have. The 
        # functions processing the AST
        # node will take care of that
        children*: seq[ASTNode]
        pos*: tuple[start, stop: int]
    

proc newASTNode*(token: Token, kind: NodeKind, children: seq[ASTNode] = @[], pos: tuple[start, stop: int] = (-1, -1)): ASTNode =
    ## Initializes a new ASTNode object
    new(result)
    result.token = token
    result.kind = kind
    result.children = children
    result.pos = pos


proc `$`*(self: ASTNode): string = 
    result &= "ASTNode("
    if self.token.kind != TokenType.EndOfFile:
        result &= &"token={self.token}, "
    result &= &"kind={self.kind}"
    if self.children.len() > 0:
        result &= &", children=[{self.children.join(\", \")}]"
    result &= ")"
    
