import 'dart:convert';

import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:change_case/change_case.dart';
import 'package:luminix_generator/utils.dart';
// ignore: depend_on_referenced_packages
import 'package:dart_style/dart_style.dart';

class LuminixBuilder implements Builder {
  @override
  Future build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    final json = jsonDecode(await buildStep.readAsString(inputId));

    if (json is Map<String, dynamic> &&
        json['models'] is Map<String, dynamic>) {
      final models = json['models'] as Map<String, dynamic>;
      final routes = json['routes']['luminix'] as Map<String, dynamic>;
      var output = StringBuffer();

      output
          .writeln('import \'package:luminix_flutter/luminix_flutter.dart\';');

      for (var schemaName in models.keys) {
        output.writeln(
            modelClass(schemaName, models[schemaName], routes[schemaName]));
        output.writeln(); // Optional: Add a blank line between models
      }

      await buildStep.writeAsString(
        AssetId(
          inputId.package,
          inputId.path.replaceFirst('manifest.json', 'models.dart'),
        ),
        DartFormatter().format(output.toString()),
      );
    }
  }

  @override
  final buildExtensions = const {
    'manifest.json': ['models.dart']
  };
}

String modelClass(String schemaName, Map<String, dynamic> model,
    Map<String, dynamic> routes) {
  final fields = model['attributes'] as List<dynamic>;

  final mixinBuilder = MixinBuilder()
    ..name = '${schemaName}Mixin'.toPascalCase()
    ..on = refer('BaseModel', 'package:luminix_flutter/luminix_flutter.dart');

  mixinBuilder.fields.add(Field((b) => b
    ..name = 'routes'
    ..modifier = FieldModifier.final$
    ..assignment = Code(routes.map((key, value) {
      return MapEntry('"$key"', value.map((item) => '"$item"').toList());
    }).toString())
    ..type = refer('Map<String, dynamic>')));

  mixinBuilder.methods.add(Method((b) => b
    ..name = 'query'
    ..returns = refer('Builder')
    ..body = Code(
        'return Builder(schemaKey:"$schemaName",route:RouteFacade({"$schemaName":routes}),);')));

  // Generate attribute getters and setters
  for (final field in fields) {
    final fieldName = (field['name'] as String).toCamelCase();
    final attributeName = field['name'] as String;
    final fieldType = normalizeTypes(field['phpType']);

    // Getter
    mixinBuilder.methods.add(Method((b) => b
      ..lambda = true
      ..type = MethodType.getter
      ..returns = refer(fieldType)
      ..name = fieldName
      ..body = Code('getAttribute("$attributeName")')));

    // Setter
    mixinBuilder.methods.add(Method((b) => b
      ..type = MethodType.setter
      ..name = fieldName
      ..requiredParameters.add(Parameter((p) => p
        ..name = 'value'
        ..type = refer(fieldType)))
      ..body = Code('setAttribute("$attributeName", value);')));
  }

  mixinBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..name = 'toString'
    ..returns = refer('String')
    ..body = Code(
        'return "${schemaName.toPascalCase()}(${fields.map((field) => "${(field['name'] as String).toCamelCase()}: \$${(field['name'] as String).toCamelCase()}").join(', ')})";')));

  final mixin = mixinBuilder.build();
  final emitter = DartEmitter();
  return '${mixin.accept(emitter)}';
}
