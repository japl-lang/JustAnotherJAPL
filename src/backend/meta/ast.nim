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
        varDecl,
        # Statements
        forStmt,
        ifStmt,
        returnStmt,
        breakStmt,
        continueStmt,
        whileStmt,
        blockStmt,
        raiseStmt,
        assertStmt
        fromStmt,
        importStmt,
        # An expression followed by a semicolon
        exprStmt,
        # Expressions
        assignExpr,
        setExpr,  # Set expressions like a.b = "c"
        binaryExpr,
        unaryExpr,
        callExpr,
        getExpr,  # Get expressions like a.b
        # Primary expressions
        groupingExpr,  # Parenthesized expressions such as (true)
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
    

proc newASTNode*(token: Token, kind: NodeKind, children: seq[ASTNode] = @[]): ASTNode =
    ## Initializes a new ASTNode object
    new(result)
    result.token = token
    result.kind = kind
    result.children = children


proc `$`*(self: ASTNode): string = 
    result &= "ASTNode("
    if self.token.kind != TokenType.EndOfFile:
        result &= &"token={self.token}, "
    result &= &"kind={self.kind}"
    if self.children.len() > 0:
        result &= &", children=[{self.children.join(\", \")}]"
    result &= ")"
    
