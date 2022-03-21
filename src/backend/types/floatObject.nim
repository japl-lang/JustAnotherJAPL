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

## Implementation of integer types

import baseObject
import lenientops


type Float* = object of Obj
    value: float64


proc newFloat*(value: float): ptr Float =
    ## Initializes a new JAPL
    ## float object from
    ## a machine native float
    result = allocateObj(Float, ObjectType.Float)
    result.value = value


proc toNativeFloat*(self: ptr Float): float =
    ## Returns the float's machine
    ## native underlying value
    result = self.value


proc `$`*(self: ptr Float): string = $self.value


proc hash*(self: ptr Float): int64 =
    ## Implements hashing
    ## for the given float
    if self.value - int(self.value) == self.value:
        result = int(self.value)
    else:
        result = 2166136261 xor int(self.value)   # TODO: Improve this
        result *= 16777619