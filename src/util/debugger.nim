# Copyright 2021 Mattia Giambirtone & All Contributors
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

import ../frontend/meta/bytecode
import ../frontend/meta/ast
import multibyte


import strformat
import strutils
import terminal


proc nl = stdout.write("\n")


proc printDebug(s: string, newline: bool = false) =
    stdout.write(&"DEBUG - Disassembler -> {s}")
    if newline:
        nl()


proc printName(name: string, newline: bool = false) =
    setForegroundColor(fgRed)
    stdout.write(name)
    setForegroundColor(fgGreen)
    if newline:
        nl()


proc printInstruction(instruction: OpCode, newline: bool = false) =
    printDebug("Instruction: ")
    printName($instruction)
    if newline:
        nl()


proc simpleInstruction(instruction: OpCode, offset: int): int =
    printInstruction(instruction)
    nl()
    return offset + 1


proc stackTripleInstruction(instruction: OpCode, chunk: Chunk, offset: int): int =
    ## Debugs instructions that operate on a single value on the stack using a 24-bit operand
    var slot = [chunk.code[offset + 1], chunk.code[offset + 2], chunk.code[offset + 3]].fromTriple()
    printInstruction(instruction)
    stdout.write(&", points to stack index ")
    setForegroundColor(fgYellow)
    stdout.write(&"{slot}")
    nl()
    return offset + 4


proc stackDoubleInstruction(instruction: OpCode, chunk: Chunk, offset: int): int =
    ## Debugs instructions that operate on a single value on the stack using a 16-bit operand
    var slot = [chunk.code[offset + 1], chunk.code[offset + 2]].fromDouble()
    printInstruction(instruction)
    stdout.write(&", points to stack index ")
    setForegroundColor(fgYellow)
    stdout.write(&"{slot}")
    nl()
    return offset + 3


proc argumentDoubleInstruction(instruction: OpCode, chunk: Chunk, offset: int): int =
    ## Debugs instructions that operate on a hardcoded value value on the stack using a 16-bit operand
    var slot = [chunk.code[offset + 1], chunk.code[offset + 2]].fromDouble()
    printInstruction(instruction)
    stdout.write(&", has argument ")
    setForegroundColor(fgYellow)
    stdout.write(&"{slot}")
    nl()
    return offset + 3


proc constantInstruction(instruction: OpCode, chunk: Chunk, offset: int): int =
    ## Debugs instructions that operate on the constant table
    var constant = [chunk.code[offset + 1], chunk.code[offset + 2], chunk.code[offset + 3]].fromTriple()
    printInstruction(instruction)
    stdout.write(&", points to constant at position ")
    setForegroundColor(fgYellow)
    stdout.write(&"{constant}")
    nl()
    let obj = chunk.consts[constant]
    setForegroundColor(fgGreen)
    printDebug("Operand: ") 
    setForegroundColor(fgYellow)
    stdout.write(&"{obj}\n")
    setForegroundColor(fgGreen)
    printDebug("Value kind: ")
    setForegroundColor(fgYellow)
    stdout.write(&"{obj.kind}\n")
    return offset + 4


proc jumpInstruction(instruction: OpCode, chunk: Chunk, offset: int): int =
    ## Debugs jumps
    var jump: int
    case instruction:
        of JumpIfFalse, JumpIfTrue, JumpIfFalsePop, JumpForwards, JumpBackwards:
            jump = [chunk.code[offset + 1], chunk.code[offset + 2]].fromDouble().int()
        of LongJumpIfFalse, LongJumpIfTrue, LongJumpIfFalsePop, LongJumpForwards, LongJumpBackwards:
            jump = [chunk.code[offset + 1], chunk.code[offset + 2], chunk.code[offset + 3]].fromTriple().int()
        else:
            discard  # Unreachable
    printInstruction(instruction, true)
    printDebug("Jump size: ")
    setForegroundColor(fgYellow)
    stdout.write($jump)
    nl()
    return offset + 3


proc collectionInstruction(instruction: OpCode, chunk: Chunk, offset: int): int =
    ## Debugs instructions that push collection types on the stack
    var elemCount = int([chunk.code[offset + 1], chunk.code[offset + 2], chunk.code[offset + 3]].fromTriple())
    printInstruction(instruction, true)
    case instruction:
        of BuildList, BuildTuple, BuildSet:
            var elements: seq[ASTNode] = @[]
            for n in countup(0, elemCount - 1):
                elements.add(chunk.consts[n])
            printDebug("Elements: ")
            setForegroundColor(fgYellow)
            stdout.write(&"""[{elements.join(", ")}]""")
            setForegroundColor(fgGreen)
        of BuildDict:
            var elements: seq[tuple[key: ASTNode, value: ASTNode]] = @[]
            for n in countup(0, (elemCount - 1) * 2, 2):
                elements.add((key: chunk.consts[n], value: chunk.consts[n + 1]))
            printDebug("Elements: ")
            setForegroundColor(fgYellow)
            stdout.write(&"""[{elements.join(", ")}]""")
            setForegroundColor(fgGreen)
        else:
            discard  # Unreachable
    echo ""
    return offset + 4


proc disassembleInstruction*(chunk: Chunk, offset: int): int =
    ## Takes one bytecode instruction and prints it
    setForegroundColor(fgGreen)
    printDebug("Offset: ")
    setForegroundColor(fgYellow)
    echo offset
    setForegroundColor(fgGreen)
    printDebug("Line: ")
    setForegroundColor(fgYellow)
    stdout.write(&"{chunk.getLine(offset)}\n")
    setForegroundColor(fgGreen)
    var opcode = OpCode(chunk.code[offset])
    case opcode:
        of simpleInstructions:
            result = simpleInstruction(opcode, offset)
        of constantInstructions:
            result = constantInstruction(opcode, chunk, offset)
        of stackDoubleInstructions:
            result = stackDoubleInstruction(opcode, chunk, offset)
        of stackTripleInstructions:
            result = stackTripleInstruction(opcode, chunk, offset)
        of argumentDoubleInstructions:
            result = argumentDoubleInstruction(opcode, chunk, offset)
        of jumpInstructions:
            result = jumpInstruction(opcode, chunk, offset)
        of collectionInstructions:
            result = collectionInstruction(opcode, chunk, offset)
        else:
            echo &"DEBUG - Unknown opcode {opcode} at index {offset}"
            result = offset + 1


proc disassembleChunk*(chunk: Chunk, name: string) =
    ## Takes a chunk of bytecode, and prints it
    echo &"==== JAPL Bytecode Debugger - Chunk '{name}' ====\n"
    var index = 0
    while index < chunk.code.len:
        index = disassembleInstruction(chunk, index)
        echo ""
    setForegroundColor(fgDefault)
    echo &"==== Debug session ended - Chunk '{name}' ===="


