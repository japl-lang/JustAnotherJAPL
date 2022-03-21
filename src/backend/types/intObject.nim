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


type Integer* = object of Obj
    value: int64


proc newInteger*(value: int64): ptr Integer =
    ## Initializes a new JAPL
    ## integer object from
    ## a machine native integer
    result = allocateObj(Integer, ObjectType.Integer)
    result.value = value


proc toNativeInteger*(self: ptr Integer): int64 =
    ## Returns the integer's machine
    ## native underlying value
    result = self.value


proc `$`*(self: ptr Integer): string = $self.value 
proc hash*(self: ptr Integer): int64 = self.value

