import 'package:apn_cache/apn_cache.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

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

      await Future.microtask(() {});

      cacheService.putSingle(updated, updated.id);

      cacheService.dispose();
    },
  );

  test(
    'A model will have a _detail model key to be used for caching the detail with more information',
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

      await Future.microtask(() {});

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

  // Add test for updating list and keeping existing detail info
}

class CachableUser extends Cachable<User> {
  CachableUser(User model, String id) : super(model, id);
}

@immutable
class User extends Equatable {
  User({
    required this.id,
    required this.name,
    required this.age,
    this.description,
  });

  final String id;
  final String name;
  final int age;
  final String? description;

  @override
  List<Object?> get props => [id, name, age, description];
}
