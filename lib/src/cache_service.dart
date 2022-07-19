import 'dart:async';

import 'package:apn_cache/src/exceptions/unknown_type_exception.dart';

// * When the key ends in `detail`, it will be saved in a separate bucket.
// * This allows us to update the detail models separately from the main models.
const detailSuffix = 'detail';

abstract class ICacheService {
  final Map<String, StreamController<List<dynamic>>> _streams = {};

  /// Returns a stream containing a list of object with
  /// type `Model` that have the given streamkey.
  Stream<List<T>> fetchAndWatchMultiple<T>({
    // Key where the data is stored
    required String key,
    // To store the data we need a cachable model, so a converter is required
    required IdFinder<T> idFinder,
    // Will be called directly to refresh (or insert the first entry of) the data to be cached
    required Future<List<T>?> Function() updateData,
  }) {
    final controller = _getCacheStream<T>(
      key: key,
      idFinder: idFinder,
      updateData: updateData,
    );

    // * Get the stream of data tied to this key
    return controller.stream;
  }

  Stream<T> fetchAndWatch<T>({
    // Key where the data is stored
    required String key,
    // To store the data we need a cachable model, so a converter is required
    required IdFinder<T> idFinder,
    // Will be called directly to refresh (or insert the first entry of) the data to be cached
    required Future<T?> Function() updateData,
  }) {
    Future<List<T>> listUpdateData() async {
      final model = await updateData();
      if (model == null) return [];
      return [model];
    }

    final controller = _getCacheStream<T>(
      key: key,
      idFinder: idFinder,
      updateData: listUpdateData,
    );

    return controller.stream.map((event) => event.first);
  }

  /// Returns a stream containing a single object of given type `T`
  /// and id `id`.
  Stream<T> watchModel<T>(Object id) {
    return watchByKey(modelStreamKey<T>(id));
  }

  Stream<T> watchDetail<T>(Object id) {
    return watchByKey(detailStreamKey<T>(id), detailSuffix);
  }

  Stream<T> watchByKey<T>(String key, [String? buckedSuffix]) {
    return _getCacheStream<T>(
      key: key,
      bucketSuffix: buckedSuffix,
    ).stream.map((event) => event.first);
  }

  // * Used to update the cache and fetch the current cache
  StreamController<List<T>> _getCacheStream<T>({
    required String key,
    IdFinder<T>? idFinder,
    Future<List<T>?> Function()? updateData,
    String? bucketSuffix,
  }) {
    if (updateData != null && idFinder == null) {
      throw Exception('Converter is required when updating data');
    }

    final controller = _getOrCreateStreamController<T>(key, bucketSuffix);

    // Update data
    updateData?.call().then((List<T>? models) {
      if (models == null || models.isEmpty == true) return;

      //* Update object in all lists that contain the id
      putList<T>(key, models, idFinder!);
    }).onError((Object error, StackTrace? stackTrace) {
      controller.addError(error, stackTrace);
    });

    // TOIMPROVE: add TTL (Time to live) and check if it is expired,
    // only return non-stale cache and call udpateData when needed

    // * Get the cached value if we have it from list
    final cache = getBucket<T, Cachable<T>>(bucketSuffix).allForKey(key);

    if (cache.isNotEmpty) {
      // Emit the cached value async, so that the stream
      // is fully initialized and listened to
      Future.microtask(() => controller.add(cache));
    }

    return controller;
  }

  // * A unique model key given a Type T and an id
  String modelStreamKey<T>(Object id) {
    throwIfDynamicType<T>();

    return '${T.toString()}_${id.toString()}';
  }

  // * A unique detail key given an Type T and an id
  String detailStreamKey<T>(Object id) => '${modelStreamKey<T>(id)}_detail';

  void updateModel<T>(T value, Object id) {
    putSingle<T>(modelStreamKey<T>(id), value, id);
  }

  void updateDetail<T>(T value, Object id) {
    putSingle<T>(detailStreamKey<T>(id), value, id);
  }

  void putSingle<T>(String key, T value, Object id) {
    putList<T>(key, [value], <T>(_) => id);
  }

  void putList<T>(String key, List<T> value, IdFinder<T> idFinder) {
    // * Update main models only if we are not updating a detail model
    final isDetailKey = key.endsWith(detailSuffix) == true;

    // * Update the main models only if we are not updating a detail model
    if (!isDetailKey) {
      _updateValueInBucket<T>(key, value, idFinder);
    }

    // * Update detail models, and insert them when missing when needed
    _updateValueInBucket<T>(
      null,
      value,
      idFinder,
      bucketSuffix: detailSuffix,
      insertWhenMissing: !isDetailKey,
    );
  }

  void _updateValueInBucket<T>(
    String? key,
    List<T> value,
    IdFinder<T> idFinder, {
    String? bucketSuffix,
    bool insertWhenMissing = false,
  }) {
    final bucket = getBucket<T, Cachable<T>>(bucketSuffix);

    final realKey = [key, bucketSuffix].where((element) => element != null).join('_');

    // Remove old data tied to this key
    bucket.removeKeyFromValues(realKey);

    final allStreamKeys = <String>[];
    for (final T v in value) {
      final modelId = idFinder(v).toString();
      final bool shouldAdd;
      if (insertWhenMissing) {
        shouldAdd = bucket.allForKey(modelId).isEmpty;
      } else {
        shouldAdd = true;
      }

      if (shouldAdd) {
        final cacheValue = Cachable(v, modelId);
        allStreamKeys.addAll(bucket.put(detailStreamKey<T>(modelId), cacheValue));
        allStreamKeys.addAll(bucket.put(realKey, cacheValue));
      }
    }

    // Make stream keys unique
    final uniqueStreamKeys = allStreamKeys.toSet().toList();

    // Notify all listeners of the values that are updated
    for (final element in uniqueStreamKeys) {
      final values = bucket.allForKey(element);
      _getOrCreateStreamController<T>(element, bucketSuffix).add(values);
    }
  }

  StreamController<List<T>> _getOrCreateStreamController<T>(String key, String? bucketSuffix) {
    final realKey = [key, bucketSuffix].where((element) => element != null).join('_');

    if (_streams[realKey] == null) {
      _streams[realKey] = StreamController<List<T>>.broadcast();
    }
    return _streams[realKey]! as StreamController<List<T>>;
  }

  void dispose() {
    _streams.forEach((_, value) => value.close());
  }

  CacheBucket<T, S> getBucket<T, S extends Cachable<T>>([String? suffix]);
}

abstract class CacheBucket<T, S extends Cachable<T>> {
  List<String> put(String streamKey, S value);

  List<T> allForKey(String streamKey);

  void removeKeyFromValues(String name);
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
