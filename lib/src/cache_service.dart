import 'dart:async';

class UnknownTypeException implements Exception {}

abstract class ICacheService {
  final Map<String, StreamController<List<dynamic>>> _streams = {};

  /// Returns a stream containing a list of object with
  /// type `Model` that have the given streamkey.
  Stream<List<T>> fetchAndWatchMultiple<T, S extends Cachable<T>>({
    // Key where the data is stored
    required String key,
    // To store the data we need a cachable model, so a converter is required
    required S Function(T model) converter,
    // When ttl from cache is expired (or when there is no cache, we
    // call this method to fetch the new data)
    required Future<List<T>?> Function() updateData,
  }) {
    final controller = _getOrCreateStreamController<T>(key);

    // * Trigger a data load, without waiting on the result
    updateData().then((List<T>? updatedData) {
      if (updatedData == null) return;

      putList<T, S>(
        key,
        updatedData.map(converter).toList(),
      );
    }).onError((Object error, StackTrace? stackTrace) {
      // * Pass errors from future to the stream
      controller.addError(error, stackTrace);
    });

    // * Get the stream of data tied to this key
    return controller.stream;
  }

  Stream<T> fetchAndWatch<T, S extends Cachable<T>>({
    // With generic type and this id we can fetch the required model
    required Object id,
    // To store the data we need a cachable model, so a converter is required
    required S Function(T model) converter,
    // When ttl from cache is expired (or when there is no cache, we
    // call this method to fetch the new data)
    required Future<T?> Function() updateData,
  }) {
    final modelStreamKey = '${T.toString()}_${id.toString()}';
    final detailModelStreamKey = '${modelStreamKey}_detail';

    final controller = _getOrCreateStreamController<T>(modelStreamKey);

    // Update data
    updateData().then((T? model) {
      if (model == null) return;

      //* Update object in all lists that contain the id
      putSingle<T, S>(modelStreamKey, converter(model));
      //* Update detail object in cache
      putSingle<T, S>(detailModelStreamKey, converter(model));
    }).onError((Object error, StackTrace? stackTrace) {
      controller.addError(error, stackTrace);
    });

    // * Get the cached value if we have it from detail objects
    final detailCache = getBucket<T, S>().allForKey(modelStreamKey);

    if (detailCache.isNotEmpty) {
      Future.microtask(() => controller.add(detailCache));
    } else {
      // * Get the cached value if we have it from list
      final listCache = getBucket<T, S>().allForKey(modelStreamKey);

      if (listCache.isNotEmpty) {
        // Emit the cached value async, so that the stream
        // is fully initialized and listened to
        Future.microtask(() => controller.add(listCache));
      }
    }

    return controller.stream.map((event) => event.first);
  }

  /// Returns a stream containing a single object of given type `Model`
  /// and id `id`.
  Stream<T> watch<T, S extends Cachable<T>>(Object id) {
    final modelStreamKey = '${T.toString()}_${id.toString()}';
    final controller = _getOrCreateStreamController<T>(modelStreamKey);

    // * Get the cached value if we have it
    final cache = getBucket<T, S>().allForKey(modelStreamKey);
    if (cache.isNotEmpty) {
      // Emit the cached value async, so that the stream
      // is fully initialized and listened to
      Future.microtask(() => controller.add(cache));
    }

    return controller.stream.map((event) => event.first);
  }

  void putSingle<T, S extends Cachable<T>>(String key, S value) {
    putList<T, S>(key, [value]);
  }

  void putList<T, S extends Cachable<T>>(String key, List<S> value) {
    if (T.toString() == "dynamic") {
      throw UnknownTypeException();
    }

    // // Also let listeners know that we got an empty list as value.
    // if (value.isEmpty) {
    //   _getOrCreateStreamController<T>(key).add([]);
    // }

    final bucket = getBucket<T, S>();

    // Remove old data tied to this key
    bucket.removeKeyFromValues(key);

    final allStreamKeys = <String>[];
    for (final S v in value) {
      // Add the value to the bucket.
      allStreamKeys.addAll(bucket.put(key, v));
    }

    // Make stream keys unique
    final uniqueStreamKeys = allStreamKeys.toSet().toList();

    // Notify all listeners of the values that are updated
    for (final element in uniqueStreamKeys) {
      final values = bucket.allForKey(element);
      _getOrCreateStreamController<T>(element).add(values);
    }
  }

  StreamController<List<T>> _getOrCreateStreamController<T>(String key) {
    if (_streams[key] == null) {
      _streams[key] = StreamController<List<T>>.broadcast();
    }
    return _streams[key]! as StreamController<List<T>>;
  }

  void dispose() {
    _streams.forEach((_, value) => value.close());
  }

  CacheBucket<T, S> getBucket<T, S extends Cachable<T>>();
}

class MemoryCacheService extends ICacheService {
  final cacheBuckets = <String, MemoryCacheBucket<dynamic, dynamic>>{};

  @override
  MemoryCacheBucket<T, S> getBucket<T, S extends Cachable<T>>() {
    return cacheBuckets.putIfAbsent(T.toString(), () => MemoryCacheBucket<T, S>()) as MemoryCacheBucket<T, S>;
  }
}

abstract class CacheBucket<T, S extends Cachable<T>> {
  List<String> put(String streamKey, S value);

  List<T> allForKey(String streamKey);

  void removeKeyFromValues(String name);
}

class MemoryCacheBucket<T, S extends Cachable<T>> extends CacheBucket<T, S> {
  final List<S> _cachedObjects = [];

  @override
  List<String> put(String streamKey, S value) {
    final modelStreamKey = '${T.toString()}_${value.id}';
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

    // Add the individual model stream key so we can watch changes on the individual model.
    object.addStreamKeyIfNotExists(modelStreamKey);

    // Replace the model with the new one
    object.model = value.model;

    // Return all stream keys for this object
    return object._streamKeys;
  }

  @override
  List<T> allForKey(String streamKey) {
    return _cachedObjects
        .where((element) => element._streamKeys.contains(streamKey))
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

class Cachable<T> {
  Cachable(
    this.model,
    this._id, [
    DateTime? lastUpdate,
  ])  : createdAt = DateTime.now(),
        updatedAt = lastUpdate ?? DateTime.now();

  // * Can be used to calculate TTL and stale data
  final DateTime createdAt;

  // * Can be used to determine is the object is newer than a previous version of the data
  final DateTime updatedAt;

  // * Holds all keys that can be used to retrieve this model
  final _streamKeys = <String>[];

  // * A id that is unique to the given model
  final Object _id;

  // * The object to cache
  T model;

  // * A string representation of the model id
  String get id => _id.toString();

  void addStreamKeyIfNotExists(String key) {
    if (!_streamKeys.contains(key)) {
      _streamKeys.add(key);
    }
  }

  void removeStreamKey(String key) {
    _streamKeys.remove(key);
  }
}
