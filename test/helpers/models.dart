import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

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

  User copyWith({
    String? id,
    String? name,
    int? age,
    String? description,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      description: description ?? this.description,
    );
  }
}
