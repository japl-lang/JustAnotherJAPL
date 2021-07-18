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

        program = 0u8,
        # Declarations
        structDecl,
        funDecl,
        varDecl,
        # An expression followed by a semicolon
        exprStmt,
        # Statements
        forStmt,
        ifStmt,
        returnStmt,
        breakStmt,
        continueStmt,
        whileStmt,
        blockStmt,
        # Expressions
        assignExpr,
        binaryExpr,
        unaryExpr,
        callExpr,
        primaryExpr


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


proc `$`*(self: ASTNode): string = &"ASTNode(token={self.token}, kind={self.kind}, children=[{self.children.join(\", \")}])"
