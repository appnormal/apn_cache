import 'dart:async';

import 'package:meta/meta.dart';

// * When the key ends in `single`, it will be saved in a separate bucket.
// * This allows us to update the single models separately from the main models.
const _singleSuffix = 'single';

abstract class ICacheService {
  final Map<String, StreamController<List<dynamic>>> _streams = {};

  T? getSingleSync<T>(Object id) {
    final cache = getBucket<T, Cachable<T>>(_singleSuffix).allForKey(id.toString());
    return cache.isEmpty ? null : cache.first.model;
  }

  Stream<T?> getSingle<T>({
    // Key where the data is stored
    required Object id,
    // Will be called directly to refresh (or insert the first entry of) the data to be cached
    Future<T?> Function()? updateData,
  }) {
    final Future<List<T>?> Function()? listUpdateData;
    if (updateData != null) {
      listUpdateData = () async {
        final model = await updateData();
        if (model == null) return [];
        return <T>[model];
      };
    } else {
      listUpdateData = null;
    }

    final controller = _getCacheStream<T>(
      key: id.toString(),
      idFinder: (_) => id,
      updateData: listUpdateData,
      bucketSuffix: _singleSuffix,
    );

    return controller.stream.map((event) {
      if(event.isNotEmpty){
       return event.first;
      }
      return null;
    });
  }

  void putSingle<T>(T value, Object id) {
    putList<T>(id.toString(), [value], <T>(_) => id);
  }

  void remove<T>(String modelId, {bool emit = true}) {
    _removeSingle<T>(modelId, emit: emit);
    _removeSingle<T>(modelId, emit: emit, bucketSuffix: _singleSuffix);
  }

  /// Returns a stream containing a list of objects withd
  /// type `T` that have the given streamkey.
  Stream<List<T>> getList<T>({
    // Key where the data is stored
    required String key,
    // To store the data we need to know the id of the object.
    IdFinder<T>? idFinder,
    // Will be called directly to refresh (or insert the first entry of) the data to be cached
    Future<List<T>?> Function()? updateData,
  }) {
    final controller = _getCacheStream<T>(
      key: key,
      idFinder: idFinder,
      updateData: updateData,
    );

    // * Get the stream of data tied to this key
    return controller.stream;
  }

  void putList<T>(String key, List<T> value, IdFinder<T> idFinder) {
    // * Update the main models only if we are not updating a single model
    _updateValueInBucket<T>(key, value, idFinder, false);

    // * Update main models only if we are not updating a single model
    final isSingle = value.length == 1 && idFinder(value.first).toString() == key;

    // * Update single models, and insert them when missing when needed
    _updateValueInBucket<T>(
      key,
      value,
      idFinder,
      true,
      insertWhenMissing: !isSingle,
    );
  }

  void _removeSingle<T>(
    String modelId, {
    bool emit = true,
    String? bucketSuffix,
  }) {
    final bucket = getBucket<T, Cachable<T>>(bucketSuffix);

    // if modelIds=null means we want to remove all models from this key
    final streamKeys = bucket.removeWhereId(modelId);

    // * Broadcast the remove to all listeners
    if (emit) {
      for (final element in streamKeys) {
        final values = bucket.allForKey(element);
        _getOrCreateStreamController<T>(element, bucketSuffix).add(values.map((e) => e.model).toList());
      }
    }
  }

  // * Remove model references from this key
  void removeList<T>(
    String key, {
    List<String>? modelIds,
    bool emit = true,
    String? bucketSuffix,
  }) {
    final bucket = getBucket<T, Cachable<T>>(bucketSuffix);

    // if modelIds=null means we want to remove all models from this key
    final streamKeys = bucket.removeKeyFromValues(key, modelIds);

    // * Broadcast the remove to all listeners
    if (emit) {
      for (final element in streamKeys) {
        final values = bucket.allForKey(element);
        _getOrCreateStreamController<T>(element, bucketSuffix).add(values.map((e) => e.model).toList());
      }
    }
  }

  // * Used to update the cache and fetch the current cache
  StreamController<List<T>> _getCacheStream<T>({
    required String key,
    IdFinder<T>? idFinder,
    Future<List<T>?> Function()? updateData,
    String? bucketSuffix,
  }) {
    if (updateData != null && idFinder == null) {
      throw Exception('IdFinder is required when updateData is not null');
    }

    final controller = _getOrCreateStreamController<T>(key, bucketSuffix);

    // Update data
    updateData?.call().then((List<T>? models) {
      if (models == null || models.isEmpty == true) {
        controller.add([]);
        return;
      }

      //* Update object in all lists that contain the id
      putList<T>(key, models, idFinder!);
    }).onError((Object error, StackTrace? stackTrace) {
      controller.addError(error, stackTrace);
    });

    // * Get the cached value if we have it from list
    final cache = getBucket<T, Cachable<T>>(bucketSuffix).allForKey(key);

    // TOIMPROVE: add TTL (Time to live) and check if it is expired,
    // only return non-stale cache and call udpateData when needed

    if (cache.isNotEmpty) {
      // Emit the cached value async, so that the stream
      // is fully initialized and listened to
      controller.onListen = () {
        controller.add(cache.map((e) => e.model).toList());
      };
    }

    return controller;
  }

  void _updateValueInBucket<T>(
    String key,
    List<T> values,
    IdFinder<T> idFinder,
    bool isSingle, {
    bool insertWhenMissing = false,
  }) {
    final bucketSuffix = isSingle ? _singleSuffix : null;
    final bucket = getBucket<T, Cachable<T>>(bucketSuffix);

    // Notify listener when there is no server data available.
    if (values.isEmpty) {
      _getOrCreateStreamController<T>(key, bucketSuffix).add([]);
      return;
    }

    final allStreamKeys = <String>[];
    for (final value in values) {
      final modelId = idFinder(value).toString();

      final bool shouldAdd;
      if (insertWhenMissing) {
        shouldAdd = bucket.allForKey(modelId).isEmpty;
      } else {
        shouldAdd = true;
      }

      if (shouldAdd) {
        final cacheValue = Cachable(value, modelId);

        allStreamKeys.addAll(bucket.put(isSingle ? modelId : key, cacheValue));
      }
    }

    // Make stream keys unique
    final uniqueStreamKeys = allStreamKeys.toSet().toList();

    // Notify all listeners of the values that are updated
    for (final element in uniqueStreamKeys) {
      final values = bucket.allForKey(element);
      _getOrCreateStreamController<T>(element, bucketSuffix).add(values.map((e) => e.model).toList());
    }
  }

  StreamController<List<T>> _getOrCreateStreamController<T>(String key, String? bucketSuffix) {
    final realKey = [T.toString(), key, bucketSuffix].where((element) => element != null).join('_');

    if (_streams[realKey] == null) {
      _streams[realKey] = StreamController<List<T>>.broadcast();
    }
    return _streams[realKey]! as StreamController<List<T>>;
  }

  void dispose() {
    _streams.forEach((_, value) => value.close());
  }

  @protected
  CacheBucket<T, S> getBucket<T, S extends Cachable<T>>([String? suffix]);
}

abstract class CacheBucket<T, S extends Cachable<T>> {
  List<String> put(String streamKey, S value);

  List<S> allForKey(String streamKey);

  List<String> removeKeyFromValues(String key, List<String>? modelIds);

  List<String> removeWhereId(String modelId);
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
  final streamKeys = <String>[];

  // * A id that is unique to the given model
  final Object _id;

  // * The object to cache
  T model;

  // * A string representation of the model id
  String get id => _id.toString();

  void addStreamKeyIfNotExists(String key) {
    if (!streamKeys.contains(key)) {
      streamKeys.add(key);
    }
  }

  void removeStreamKey(String key) {
    streamKeys.remove(key);
  }
}

typedef IdFinder<T> = Object Function(T);
