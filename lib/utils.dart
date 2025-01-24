String normalizeTypes(String? type) {
  return switch (type) {
    'string' => 'String',
    'int' => 'int',
    'bool' => 'bool',
    '\\Carbon\\CarbonInterface' ||
    'date' ||
    'datetime' ||
    'immutable_date' ||
    'immutable_datetime' =>
      'DateTime',
    _ => 'dynamic',
  };
}
