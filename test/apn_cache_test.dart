import 'package:test/test.dart';

import 'package:apn_cache/apn_cache.dart';

import 'helpers/helpers.dart';
import 'helpers/models.dart';

void main() {
  test('cache is saved when saving a model', () {
    final model = User(id: '12', age: 38, name: 'Mark');

    final cacheService = MemoryCacheService();

    cacheService.putSingle(model, model.id);

    final results = cacheService.cacheBuckets['User_single']?.allForKey('12');

    expect(results, isNotNull);
    expect(results!.length, 1);
    expect((results.first as Cachable<User>).model, model);
  });

  test(
    'When updating a single model, the list will also update',
    () async {
      final models = [
        User(id: '12', age: 38, name: 'Mark'),
        User(id: '13', age: 38, name: 'Mark'),
        User(id: '14', age: 38, name: 'Mark'),
        User(id: '15', age: 38, name: 'Mark'),
      ];

      final cacheService = MemoryCacheService();

      final stream = cacheService.getList<User>(
        key: 'models',
        idFinder: (u) => u.id,
        updateData: () async => models,
      );

      final updated = User(id: '12', age: 40, name: 'Markie');
      final updatedList = models.map((e) => e.id == updated.id ? updated : e).toList();

      expect(stream, emitsInOrder([models, updatedList, emitsDone]));

      await tick;

      cacheService.putSingle(updated, updated.id);

      cacheService.dispose();
    },
  );

  test(
    'A model will have a _single model key to be used for caching the detail with more information',
    () async {
      final models = [
        User(id: '12', age: 38, name: 'Mark'),
        User(id: '13', age: 38, name: 'Mark'),
        User(id: '14', age: 38, name: 'Mark'),
        User(id: '15', age: 38, name: 'Mark'),
      ];

      final cacheService = MemoryCacheService();

      expect(cacheService.cacheBuckets['User'], isNull);

      final stream = cacheService.getList(
        key: 'models',
        idFinder: (User u) => u.id,
        updateData: () async => models,
      );

      final updated = User(id: '12', age: 40, name: 'Markie');
      final updatedList = models.map((e) => e.id == updated.id ? updated : e).toList();

      // * Will get the updated data when detail info is updated
      expect(stream, emitsInOrder([models, updatedList, emitsDone]));

      await tick;

      expect(cacheService.cacheBuckets['User'], isNotNull);
      expect(cacheService.cacheBuckets['User_single'], isNotNull);

      final modelDetailKey = '12';
      expect(cacheService.cacheBuckets['User_single']!.allForKey(modelDetailKey), hasLength(1));
      expect(cacheService.cacheBuckets['User_single']!.allForKey(modelDetailKey).first.model, models[0]);

      cacheService.putSingle(updated, updated.id);

      expect(cacheService.cacheBuckets['User_single']!.allForKey(modelDetailKey).first.model, updated);
      expect(cacheService.cacheBuckets['User']!.allForKey(modelDetailKey).first.model, updated);

      cacheService.dispose();
    },
  );

  test(
    'When updating a list, the single object will not update',
    () async {
      final single = User(id: '12', age: 38, name: 'Mark', description: 'Markie is a cool guy');

      final models = [
        User(id: '12', age: 38, name: 'Mark'),
        User(id: '13', age: 38, name: 'Mark'),
        User(id: '14', age: 38, name: 'Mark'),
        User(id: '15', age: 38, name: 'Mark'),
      ];

      final cacheService = MemoryCacheService();

      final listStream = cacheService.getList<User>(
        key: 'models',
        idFinder: (u) => u.id,
        updateData: () async => models,
      );

      final updatedListWithDescription = models.map((e) => e.id == single.id ? single : e).toList();

      expect(
          listStream,
          emitsInOrder([
            // The initial data given in updateData (no cache yet)
            models,
            // This emit is the updated data because the putSingle was called with updated data
            updatedListWithDescription,
            // List is updated with original data again, missing description on 12
            models,
            // We, done
            emitsDone,
          ]));

      await tick;

      final singleStream = cacheService.getSingle<User?>(
        id: single.id,
        updateData: () async => single,
      );

      // Make sure we don't get a updated single object
      expect(
          singleStream,
          emitsInOrder([
            // Cached data from list
            models.first,
            // Updated data from singleStream.updateData
            single,
            // Done, we dont get the putList original data for ID 12
            emitsDone,
          ]));

      // * Await the put single
      await tick;

      // * Put a new list in the cache and make sure the detail remains
      cacheService.putList<User>("models", models, (u) => u.id);

      cacheService.dispose();
    },
  );

  test('When adding data a list, it will be appended to the cache', () async {
    List<User> firstList = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '13', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
      User(id: '15', age: 38, name: 'Mark'),
    ];

    final secondList = [
      User(id: '16', age: 38, name: 'Mark'),
      User(id: '17', age: 38, name: 'Mark'),
      User(id: '18', age: 38, name: 'Mark'),
      User(id: '19', age: 38, name: 'Mark'),
    ];

    final cacheService = MemoryCacheService();

    final listStream = cacheService.getList<User>(
      key: 'models',
      idFinder: (u) => u.id,
      updateData: () async => firstList,
    );

    expect(
        listStream,
        emitsInOrder(
          [
            // Check for initial data (firstList)
            firstList,
            // Check for updated list with data appended (secondList)
            [...firstList, ...secondList],
            // Make sure we're done
            emitsDone,
          ],
        ));

    await tick;

    // * Put a new list in the cache and make sure the detail remains
    cacheService.putList<User>("models", secondList, (u) => u.id);

    await tick;

    cacheService.dispose();
  });

  test('Clearing the cache will clear the correct bucket', () async {
    final models = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '13', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
      User(id: '15', age: 38, name: 'Mark'),
    ];

    final cacheService = MemoryCacheService();

    final stream = cacheService.getList<User>(
      key: 'models',
      idFinder: (u) => u.id,
      updateData: () async => models,
    );

    expect(
        stream,
        emitsInOrder(
          [
            models,
            emitsDone,
          ],
        ));

    await tick;

    cacheService.removeList<User>('models', emit: false);
    expect(cacheService.cacheBuckets['User']?.allForKey('models'), isEmpty);

    await tick;

    cacheService.dispose();
  });

  test('Getting a value from getSingle when no values are present will result in nothing', () async {
    final cacheService = MemoryCacheService();

    final stream = cacheService.getSingle<User?>(id: '123');

    await tick;

    expect(stream, emitsDone);

    cacheService.dispose();
  });
}
