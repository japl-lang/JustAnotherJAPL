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


import strformat


import token


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
        forStmt,  # Unused for now (for loops are compiled to while loops)
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
        pos*: tuple[start, stop: int]
        case kind*: NodeKind
            of intExpr, floatExpr, hexExpr, binExpr, octExpr, strExpr:
                # This makes it much easier to handle numeric types, as
                # there is no overflow/underflow or precision to deal with.
                # Numbers are just serialized as strings and then converted
                # before being passed to the VM, which also makes it easier
                # to implement a potential bignum arithmetic that is compatible
                # with machine types, i.e. if a type fits into 8, 16, 32 or 64 bits
                # then it is stored in such a type to save space, else it will be
                # converted to a bigint. Bigfloats with arbitrary-precision arithmetic
                # would also be nice, although arguably less useful
                literal*: Token
            of identExpr:
                name*: Token
            of groupingExpr:
                wrapped*: ASTNode
            # Sadly nim doesn't allow to re-declare
            # a field in a case statement yet, even if it
            # is of the same type. 
            # Check out https://github.com/nim-lang/RFCs/issues/368 
            # for more info, but currently this is the least
            # ugly workaround
            of getExpr:
                getObj*: ASTNode
                getName*: ASTNode
            of setExpr:
                setObj*: ASTNode
                setName*: ASTNode
                setValue*: ASTNode
            of callExpr:
                callee*: ASTNode  # The identifier being called
                args*: tuple[positionals: seq[ASTNode], keyword: seq[ASTNode]]
                # Due to how our bytecode is represented, functions can't have
                # more than 255 arguments, so why bother using a full int for
                # that? And plus, if your functions need more than arguments, you've
                # got far bigger problems to deal with in your code, trust me.
                # Oh and btw, arity is the number of arguments the function takes:
                # see it as len(self.args.positionals) + len(self.args.keyword)
                # (because it's what it is)
                arity*: int8
            of unaryExpr:
                unOp*: Token
                operand*: ASTNode
            of binaryExpr:
                binOp*: Token
                a*: ASTNode
                b*: ASTNode 
            of awaitExpr:
                # The awaited object (well, in this
                # case an AST node representing it)
                awaitee*: ASTNode
            of assignExpr:
                assignName*: ASTNode
                assignValue*: ASTNode
            of exprStmt:
                expression*: ASTNode
            of importStmt:
                moduleName*: ASTNode
            of fromStmt:
                fromModule*: ASTNode
                fromAttributes*: seq[ASTNode]
            of delStmt:
                delName*: ASTNode
            of assertStmt:
                assertExpr*: ASTNode
            of raiseStmt:
                exception*: ASTNode
            of blockStmt:
                statements*: seq[ASTNode]
            of whileStmt:
                whileCondition*: ASTNode
                loopBody*: seq[ASTNode]
            of returnStmt:
                retValue*: ASTNode
            of ifStmt:
                ifCondition*: ASTNode
                thenBranch*: ASTNode
                elseBranch*: ASTNode
            of funDecl:
                funcName*: ASTNode
                funcBody*: ASTNode
                arguments*: tuple[positionals: seq[ASTNode], keyword: seq[ASTNode], defaults: seq[ASTNode]]
                isAsync*: bool
                isGenerator*: bool
            of classDecl:
                className*: ASTNode
                classBody*: ASTNode
                parents*: seq[ASTNode]
            else:
                # Types such as booleans and singletons
                # in general don't need any extra metadata.
                # This branch is also used for extra types
                # that don't have a use yet
                discard
    

proc newASTNode*(kind: NodeKind, pos: tuple[start, stop: int] = (-1, -1)): ASTNode =
    ## Initializes a new ASTNode object
    new(result)
    result.kind = kind
    result.pos = pos


proc `$`*(self: ASTNode): string = 
    result = &"ASTNode(kind={self.kind})"
    
