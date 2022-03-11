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


import ../../memory/allocator
import ../../config

import baseObject
import iterable


type
    Entry = object
        ## Low-level object to store key/value pairs.
        ## Using an extra value for marking the entry as
        ## a tombstone instead of something like detecting
        ## tombstones as entries with null keys but full values
        ## may seem wasteful. The thing is, though, that since
        ## we want to implement sets on top of this hashmap and
        ## the implementation of a set is *literally* a dictionary
        ## with empty values and keys as the elements, this would
        ## confuse our findEntry method and would force us to override
        ## it to account for a different behavior.
        ## Using a third field takes up more space, but saves us
        ## from the hassle of rewriting code
        key: ptr Obj
        value: ptr Obj
        tombstone: bool
    HashMap* = object of Iterable
        ## An associative array with O(1) lookup time,
        ## similar to nim's Table type, but using raw
        ## memory to be more compatible with JAPL's runtime
        ## memory management
        entries: ptr UncheckedArray[ptr Entry]
        # This attribute counts *only* non-deleted entries
        actual_length: int


proc newHashMap*: ptr HashMap =
    ## Initializes a new, empty hashmap
    result = allocateObj(HashMap, ObjectType.Dict)
    result.actual_length = 0
    result.entries = nil
    result.capacity = 0
    result.length = 0


proc freeHashMap*(self: ptr HashMap) =
    ## Frees the memory associated with the hashmap
    discard freeArray(UncheckedArray[ptr Entry], self.entries, self.capacity)
    self.length = 0
    self.actual_length = 0
    self.capacity = 0
    self.entries = nil


proc findEntry(self: ptr UncheckedArray[ptr Entry], key: ptr Obj, capacity: int): ptr Entry =
    ## Low-level method used to find entries in the underlying
    ## array, returns a pointer to an entry
    var capacity = uint64(capacity)
    var idx = uint64(key.hash()) mod capacity
    while true:
        result = self[idx]
        if system.`==`(result.key, nil):
            # We found an empty bucket
            break
        elif result.tombstone:
            # We found a previously deleted
            # entry. In this case, we need
            # to make sure the tombstone
            # will get overwritten when the
            # user wants to add a new value
            # that would replace it, BUT also
            # for it to not stop our linear
            # probe sequence. Hence, if the
            # key of the tombstone is the same
            # as the one we're looking for,
            # we break out of the loop, otherwise
            # we keep searching
            if result.key == key:
                break
        elif result.key == key:
            # We were looking for a specific key and
            # we found it, so we also bail out
            break
        # If none of these conditions match, we have a collision!
        # This means we can just move on to the next slot in our probe
        # sequence until we find an empty slot. The way our resizing
        # mechanism works makes the empty slot invariant easy to 
        # maintain since we increase the underlying array's size 
        # before we are actually full
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