import 'package:apn_cache/apn_cache.dart';
import 'package:test/test.dart';

import 'helpers/helpers.dart';
import 'helpers/models.dart';

void main() {
  test('Remove single with emit=true will update the listeners', () async {
    final models = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '13', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
      User(id: '15', age: 38, name: 'Mark'),
    ];

    final modelsWithout13 = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
      User(id: '15', age: 38, name: 'Mark'),
    ];
    final cacheService = MemoryCacheService();

    final stream = cacheService.getList<User>(
      key: 'models',
      idFinder: (u) => u.id,
      updateData: () async => models,
    );

    expect(stream, emitsInOrder([models, modelsWithout13, emitsDone]));

    await tick;

    cacheService.removeSingle<User>('models', '13');

    cacheService.dispose();
  });

  test('Remove single with emit=false will not update the listeners', () async {
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

    expect(stream, emitsInOrder([models, emitsDone]));

    await tick;

    cacheService.removeSingle<User>('models', '13', emit: false);

    cacheService.dispose();
  });

  test('Remove list with emit=true will  update the listeners', () async {
    final models = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '13', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
      User(id: '15', age: 38, name: 'Mark'),
    ];
    final updatedModels = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
    ];
    final cacheService = MemoryCacheService();

    final stream = cacheService.getList<User>(
      key: 'models',
      idFinder: (u) => u.id,
      updateData: () async => models,
    );

    expect(stream, emitsInOrder([models, updatedModels, emitsDone]));

    await tick;

    cacheService.removeList<User>('models', modelIds: ['13', '15']);

    cacheService.dispose();
  });

  test('Remove without models with emit=true will remove all and update the listeners with an empty list', () async {
    final models = [
      User(id: '12', age: 38, name: 'Mark'),
      User(id: '13', age: 38, name: 'Mark'),
      User(id: '14', age: 38, name: 'Mark'),
      User(id: '15', age: 38, name: 'Mark'),
    ];
    final updatedModels = [];

    final cacheService = MemoryCacheService();

    final stream = cacheService.getList<User>(
      key: 'models',
      idFinder: (u) => u.id,
      updateData: () async => models,
    );

    expect(stream, emitsInOrder([models, updatedModels, emitsDone]));

    await tick;

    cacheService.removeList<User>('models');

    cacheService.dispose();
  });
}
