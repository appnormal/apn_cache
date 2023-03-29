import 'package:apn_cache/apn_cache.dart';

class MemoryCacheService extends ICacheService {
  final cacheBuckets = <String, MemoryCacheBucket<dynamic, dynamic>>{};

  @override
  MemoryCacheBucket<T, S> getBucket<T, S extends Cachable<T>>([String? suffix]) {
    throwIfDynamicType<T>();

    final bucketKey = "${T.toString()}${suffix?.isNotEmpty ?? false ? "_$suffix" : ""}";
    return cacheBuckets.putIfAbsent(bucketKey, () => MemoryCacheBucket<T, S>()) as MemoryCacheBucket<T, S>;
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
  List<S> allForKey(String streamKey) {
    return _cachedObjects.where((element) => element.streamKeys.contains(streamKey)).toList();
  }

  @override
  List<String> removeWhereId(String modelId) {
    final streamKeys = <String>[];

    // * Remove the object from the bucket
    _cachedObjects.removeWhere((element) {
      if (element.id == modelId) {
        streamKeys.addAll(element.streamKeys);
        return true;
      }
      return false;
    });

    // filter duplicates
    return streamKeys.toSet().toList();
  }

  @override
  List<String> removeKeyFromValues(String key, List<String>? modelIds) {
    final streamKeys = <String>[key];

    final removedObjects = <String>[];
    for (var element in _cachedObjects) {
      // * Remove if we have a modelIds list and the object is in the list
      final shouldRemove = modelIds == null || modelIds.contains(element.id);

      if (shouldRemove) {
        element.removeStreamKey(key);

        // * No need to keep it in memory if it has no stream keys
        if (element.streamKeys.isEmpty) {
          removedObjects.add(element.id);
        } else {
          streamKeys.addAll(element.streamKeys);
        }
      }
    }

    // * Remove objects without stream keys from the bucket
    _cachedObjects.removeWhere((element) => removedObjects.contains(element.id));

    // filter duplicates
    return streamKeys.toSet().toList();
  }
}
