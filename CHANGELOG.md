## 1.0.0

* BREAKING: Changed removeSingle to not include a key. And renamed the method to `remove` to indicate the object will be removed from the cache.

## 0.1.2

* Fix: Only return first element from getSingle when stream has events
  
## 0.1.1

* Fix: Notify listeners when there is no server data available. 

## 0.1.0 - BREAKING

* BREAKING: Renamed clearCache to removeList. Migrate to `removeList(key, emit: false)` to reproduce old behaviour
* Added removeSingle
* Added option to remove select models by id via removeList(modelIds:[string]) and removeSingle(string)
* Added option to broadcast removals from cache via removeList(emit: bool), removeSingle(emit: bool) default true
* Added tests for the new functionality

## 0.0.2

* Avoid name clashes in the internal stream keys, to make sure different Types T are given unique steams

## 0.0.1

* Extracted working version with single model and list of models
