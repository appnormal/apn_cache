import 'dart:async';

abstract class ICacheService {
  final Map<String, StreamController<List<dynamic>>> _streams = {};

  /// Returns a stream containing a list of object with
  /// type `Model` that have the given streamkey.
  Stream<List<Model>> fetchAndWatchMultiple<Model, CachableModel extends Cachable<Model>>({
    // Key where the data is stored
    required String key,
    // To store the data we need a cachable model, so a converter is required
    required CachableModel Function(Model model) converter,
    // When ttl from cache is expired (or when there is no cache, we
    // call this method to fetch the new data)
    required Future<List<Model>?> Function() updateData,
  }) {
    final controller = _getOrCreateStreamController<Model>(key);

    // * Trigger a data load, without waiting on the result
    updateData().then((List<Model>? updatedData) {
      if (updatedData == null) return;

      putList<Model, CachableModel>(
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

  Stream<Model> fetchAndWatch<Model, CachableModel extends Cachable<Model>>({
    // With generic type and this id we can fetch the required model
    required Object id,
    // To store the data we need a cachable model, so a converter is required
    required CachableModel Function(Model model) converter,
    // When ttl from cache is expired (or when there is no cache, we
    // call this method to fetch the new data)
    required Future<Model?> Function() updateData,
  }) {
    final modelStreamKey = '${Model.toString()}_${id.toString()}';
    final detailModelStreamKey = '${modelStreamKey}_detail';

    final controller = _getOrCreateStreamController<Model>(modelStreamKey);

    // Update data
    updateData().then((Model? model) {
      if (model == null) return;

      //* Update object in all lists that contain the id
      putSingle<Model, CachableModel>(modelStreamKey, converter(model));
      //* Update detail object in cache
      putSingle<Model, CachableModel>(detailModelStreamKey, converter(model));
    }).onError((Object error, StackTrace? stackTrace) {
      controller.addError(error, stackTrace);
    });

    // * Get the cached value if we have it from detail objects
    final detailCache = getBucket<Model, CachableModel>().allForKey(modelStreamKey);

    if (detailCache.isNotEmpty) {
      Future.microtask(() => controller.add(detailCache));
    } else {
      // * Get the cached value if we have it from list
      final listCache = getBucket<Model, CachableModel>().allForKey(modelStreamKey);

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
  Stream<Model> watch<Model, CachableModel extends Cachable<Model>>(Object id) {
    final modelStreamKey = '${Model.toString()}_${id.toString()}';
    final controller = _getOrCreateStreamController<Model>(modelStreamKey);

    // * Get the cached value if we have it
    final cache = getBucket<Model, CachableModel>().allForKey(modelStreamKey);
    if (cache.isNotEmpty) {
      // Emit the cached value async, so that the stream
      // is fully initialized and listened to
      Future.microtask(() => controller.add(cache));
    }

    return controller.stream.map((event) => event.first);
  }

  void putSingle<Model, CachableModel extends Cachable<Model>>(String key, CachableModel value) {
    putList<Model, CachableModel>(key, [value]);
  }

  void putList<Model, CachableModel extends Cachable<Model>>(String key, List<CachableModel> value) {
    // Also let listeners know that we got an empty list as value.
    if (value.isEmpty) {
      _getOrCreateStreamController<Model>(key).add([]);
    }

    final bucket = getBucket<Model, CachableModel>();

    // Remove old data tied to this key
    bucket.removeKeyFromValues(key);

    final allStreamKeys = <String>[];
    for (final v in value) {
      // Add the value to the bucket.
      allStreamKeys.addAll(bucket.put(key, v));
    }

    // Make stream keys unique
    final uniqueStreamKeys = allStreamKeys.toSet().toList();

    // Notify all listeners of the values that are updated
    for (final element in uniqueStreamKeys) {
      final values = bucket.allForKey(element);
      _getOrCreateStreamController<Model>(element).add(values);
    }
  }

  StreamController<List<T>> _getOrCreateStreamController<T>(String key) {
    if (_streams[key] == null) {
      _streams[key] = StreamController<List<T>>.broadcast();
    }
    return _streams[key]! as StreamController<List<T>>;
  }

  CacheBucket<Model, CachableModel> getBucket<Model, CachableModel extends Cachable<Model>>();
}

class MemoryCacheService extends ICacheService {
  final cacheBuckets = <String, MemoryCacheBucket<dynamic, dynamic>>{};

  @override
  MemoryCacheBucket<Model, CachableModel> getBucket<Model, CachableModel extends Cachable<Model>>() {
    return cacheBuckets.putIfAbsent(Model.toString(), () => MemoryCacheBucket<Model, CachableModel>())
        as MemoryCacheBucket<Model, CachableModel>;
  }
}

abstract class CacheBucket<Model, CachableModel extends Cachable<Model>> {
  List<String> put(String streamKey, CachableModel value);

  List<Model> allForKey(String streamKey);

  void removeKeyFromValues(String name);
}

class MemoryCacheBucket<Model, CachableModel extends Cachable<Model>> extends CacheBucket<Model, CachableModel> {
  final List<CachableModel> _cachedObjects = [];

  @override
  List<String> put(String streamKey, CachableModel value) {
    final modelStreamKey = '${Model.toString()}_${value.id}';
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
  List<Model> allForKey(String streamKey) {
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

class Cachable<Model> {
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
  Model model;

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
