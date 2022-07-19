class UnknownTypeException implements Exception {}

throwIfDynamicType<T>() {
  if (T.toString() == "dynamic") {
    throw UnknownTypeException();
  }
}
