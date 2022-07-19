import 'package:apn_cache/apn_cache.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

void main() {
  test('cache is saved when saving a model', () {
    final model = User(id: '12', age: 38, name: 'Mark');

    final cacheService = MemoryCacheService();

    cacheService.putSingle<User, CachableUser>('my_user', CachableUser(model, model.id));

    final results = cacheService.cacheBuckets['User']?.allForKey('my_user');

    expect(results, isNotNull);
    expect(results!.length, 1);

    expect(cacheService.cacheBuckets['User']?.allForKey('my_user').first, model);
  });

  test('model cannot be cached when type is dynamic', () {
    final model = User(id: '12', age: 38, name: 'Mark');

    final cacheService = MemoryCacheService();

    expect(
      () => cacheService.putSingle('key', CachableUser(model, model.id)),
      throwsA(TypeMatcher<UnknownTypeException>()),
    );
  });

  test(
    'A list of models can be saved and listen for changes',
    () async {
      final models = [
        User(id: '12', age: 38, name: 'Mark'),
        User(id: '13', age: 38, name: 'Mark'),
        User(id: '14', age: 38, name: 'Mark'),
        User(id: '15', age: 38, name: 'Mark'),
      ];

      final cacheService = MemoryCacheService();

      final stream = cacheService.fetchAndWatchMultiple(
        key: 'models',
        converter: (User u) => CachableUser(u, u.id),
        updateData: () async => models,
      );

      final updated = User(id: '12', age: 40, name: 'Markie');
      final updatedList = models.map((e) => e.id == updated.id ? updated : e).toList();

      final detailStream = cacheService.watchDetail<User, CachableUser>(updated.id);

      expect(stream, emitsInOrder([models, updatedList, emitsDone]));
      expect(detailStream, emitsInOrder([models[0], updated, emitsDone]));

      await Future.microtask(() {});

      cacheService.putSingle<User, CachableUser>('my_user', CachableUser(updated, updated.id));

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

      final stream = cacheService.fetchAndWatchMultiple(
        key: 'models',
        converter: (User u) => CachableUser(u, u.id),
        updateData: () async => models,
      );

      final updated = User(id: '12', age: 40, name: 'Markie');

      // * Will not get the updated data when only the detail is updated
      expect(stream, emitsInOrder([models, emitsDone]));

      await Future.microtask(() {});

      expect(cacheService.cacheBuckets['User'], isNotNull);
      expect(cacheService.cacheBuckets['User_detail'], isNotNull);

      final modelDetailKey = cacheService.detailStreamKey<User>(updated.id);

      expect(cacheService.cacheBuckets['User_detail']!.allForKey(modelDetailKey), hasLength(1));
      expect(cacheService.cacheBuckets['User_detail']!.allForKey(modelDetailKey).first, models[0]);

      cacheService.updateDetail<User, CachableUser>(CachableUser(updated, updated.id));
      expect(cacheService.cacheBuckets['User_detail']!.allForKey(modelDetailKey).first, updated);

      cacheService.dispose();
    },
  );
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
