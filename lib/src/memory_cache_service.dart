import 'package:apn_cache/apn_cache.dart';

class MemoryCacheService extends ICacheService {
  final cacheBuckets = <String, MemoryCacheBucket<dynamic, dynamic>>{};

  @override
  MemoryCacheBucket<T, S> getBucket<T, S extends Cachable<T>>() {
    throwIfDynamicType<T>();

    return cacheBuckets.putIfAbsent(T.toString(), () => MemoryCacheBucket<T, S>()) as MemoryCacheBucket<T, S>;
  }
}

class MemoryCacheBucket<T, S extends Cachable<T>> extends CacheBucket<T, S> {
  // * All cached objects will be saved in memory in here
  final List<S> _cachedObjects = [];

  @override
  List<String> put(String streamKey, S value) {
    // Search if an object with the same id (value.id) is already in the _cachedObjects.
    int objectIndex = _cachedObjects.indexWhere((element) => element.id == value.id);

    // Add in the cache if it is not already there.
    if (objectIndex == -1) {
      _cachedObjects.add(value);
      objectIndex = _cachedObjects.length - 1;
    }

    final object = _cachedObjects[objectIndex];

    // If not exists, add the streamKey
    object.addStreamKeyIfNotExists(streamKey);

    // Replace the model with the new one
    object.model = value.model;

    // Return all stream keys for this object
    return object.streamKeys;
  }

  @override
  List<T> allForKey(String streamKey) {
    return _cachedObjects
        .where((element) => element.streamKeys.contains(streamKey))
        .map((element) => element.model)
        .toList();
  }

  @override
  void removeKeyFromValues(String name) {
    for (var element in _cachedObjects) {
      element.removeStreamKey(name);
    }
  }
}
