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


import ../../memory/allocator
import ../../config
import base
import iterable


type
    Entry = object
        key: ptr Obj
        value: ptr Obj
        tombstone: bool
    HashMap* = object of Iterable
        entries: ptr UncheckedArray[ptr Entry]
        actual_length: int


proc newHashMap*(): ptr HashMap =
    result = allocateObj(HashMap, ObjectType.Dict)
    result.actual_length = 0
    result.entries = nil
    result.capacity = 0
    result.length = 0


proc freeHashMap*(self: ptr HashMap) =
    discard freeArray(UncheckedArray[ptr Entry], self.entries, self.capacity)
    self.length = 0
    self.actual_length = 0
    self.capacity = 0
    self.entries = nil


proc findEntry(self: ptr UncheckedArray[ptr Entry], key: ptr Obj, capacity: int): ptr Entry =
    var capacity = uint64(capacity)
    var idx = uint64(key.hash()) mod capacity
    while true:
        result = self[idx]
        if system.`==`(result.key, nil):
            break
        elif result.tombstone:
            if result.key == key:
                break
        elif result.key == key:
            break
        idx = (idx + 1) mod capacity


proc adjustCapacity(self: ptr HashMap) =
    var newCapacity = growCapacity(self.capacity)
    var entries = allocate(UncheckedArray[ptr Entry], Entry, newCapacity)
    var oldEntry: ptr Entry
    var newEntry: ptr Entry
    self.length = 0
    for x in countup(0, newCapacity - 1):
        entries[x] = allocate(Entry, Entry, 1)
        entries[x].tombstone = false
        entries[x].key = nil
        entries[x].value = nil
    for x in countup(0, self.capacity - 1):
        oldEntry = self.entries[x]
        if not system.`==`(oldEntry.key, nil):
            newEntry = entries.findEntry(oldEntry.key, newCapacity)
            newEntry.key = oldEntry.key
            newEntry.value = oldEntry.value
            self.length += 1
    discard freeArray(UncheckedArray[ptr Entry], self.entries, self.capacity)
    self.entries = entries
    self.capacity = newCapacity


proc setEntry(self: ptr HashMap, key: ptr Obj, value: ptr Obj): bool =
    if float64(self.length + 1) >= float64(self.capacity) * MAP_LOAD_FACTOR:
        self.adjustCapacity()
    var entry = findEntry(self.entries, key, self.capacity)
    result = system.`==`(entry.key, nil)
    if result:
        self.actual_length += 1
        self.length += 1
    entry.key = key
    entry.value = value
    entry.tombstone = false


proc `[]`*(self: ptr HashMap, key: ptr Obj): ptr Obj =
    var entry = findEntry(self.entries, key, self.capacity)
    if system.`==`(entry.key, nil) or entry.tombstone:
        raise newException(KeyError, "Key not found: " & $key)
    result = entry.value


proc `[]=`*(self: ptr HashMap, key: ptr Obj, value: ptr Obj) =
    discard self.setEntry(key, value)


proc len*(self: ptr HashMap): int =
    result = self.actual_length


proc del*(self: ptr HashMap, key: ptr Obj) =
    if self.len() == 0:
        raise newException(KeyError, "delete from empty hashmap")
    var entry = findEntry(self.entries, key, self.capacity)
    if not system.`==`(entry.key, nil):
        self.actual_length -= 1
        entry.tombstone = true
    else:
        raise newException(KeyError, "Key not found: " & $key)


proc contains*(self: ptr HashMap, key: ptr Obj): bool =
    let entry = findEntry(self.entries, key, self.capacity)
    if not system.`==`(entry.key, nil) and not entry.tombstone:
        result = true
    else:
        result = false


iterator keys*(self: ptr HashMap): ptr Obj =
    var entry: ptr Entry
    for i in countup(0, self.capacity - 1):
        entry = self.entries[i]
        if not system.`==`(entry.key, nil) and not entry.tombstone:
            yield entry.key


iterator values*(self: ptr HashMap): ptr Obj =
    for key in self.keys():
        yield self[key]


iterator pairs*(self: ptr HashMap): tuple[key: ptr Obj, val: ptr Obj] =
    for key in self.keys():
        yield (key: key, val: self[key])


iterator items*(self: ptr HashMap): ptr Obj =
    for k in self.keys():
        yield k


proc `$`*(self: ptr HashMap): string =
    var i = 0
    result &= "{"
    for key, value in self.pairs():
        result &= $key & ": " & $value
        if i < self.len() - 1:
            result &= ", "
        i += 1
    result &= "}"