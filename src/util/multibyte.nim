# Copyright 2022 Mattia Giambirtone & All Contributors
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

## Utilities to convert from/to our 16-bit and 24-bit representations
## of numbers


proc toDouble*(input: int | uint | uint16): array[2, uint8] =
    ## Converts an int (either int, uint or uint16)
    ## to an array[2, uint8]
    result = cast[array[2, uint8]](uint16(input))


proc toTriple*(input: uint | int): array[3, uint8] =
    ## Converts an unsigned integer (int is converted
    ## to an uint and sign is lost!) to an array[3, uint8]
    result = cast[array[3, uint8]](uint(input))


proc fromDouble*(input: array[2, uint8]): uint16 =
    ## Rebuilds the output of toDouble into
    ## an uint16
    copyMem(result.addr, unsafeAddr(input), sizeof(uint16))


proc fromTriple*(input: array[3, uint8]): uint =
    ## Rebuilds the output of toTriple into
    ## an uint
    copyMem(result.addr, unsafeAddr(input), sizeof(uint8) * 3)
