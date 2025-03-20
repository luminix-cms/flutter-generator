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
  final relations = model['relations'] as Map<String, dynamic>?;

  final classBuilder = ClassBuilder()
    ..name = schemaName.toPascalCase()
    ..extend =
        refer('BaseModel', 'package:luminix_flutter/luminix_flutter.dart')
    ..constructors.add(Constructor((b) => b
      ..optionalParameters.add(Parameter((b) => b
        ..toSuper = true
        ..name = 'attributes'))));

  classBuilder.methods.add(Method(
    (b) => b
      ..annotations.add(refer('override'))
      ..name = 'makeRelations'
      ..returns = refer('void')
      ..body = Code(relations?.keys.map((relationName) {
            return '${relationName.toCamelCase()}Relation();';
          }).join('\n') ??
          ''),
  ));

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..lambda = true
    ..type = MethodType.getter
    ..returns = refer('String')
    ..name = 'schemaName'
    ..body = Code("'$schemaName'")));

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..lambda = true
    ..type = MethodType.getter
    ..returns = refer('String')
    ..name = 'primaryKey'
    ..body = Code("'${model['primaryKey']}'")));

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..lambda = true
    ..type = MethodType.getter
    ..returns = refer('String')
    ..name = 'type'
    ..body = Code("'$schemaName'")));

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..lambda = true
    ..type = MethodType.getter
    ..returns = refer('Map<String, dynamic>')
    ..name = 'schema'
    ..body = Code(
        "{'primaryKey':'${model['primaryKey']}','fillable':${jsonEncode(model['fillable'])},'relations':${jsonEncode(model['relations'])}}")));

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..name = 'query'
    ..returns = refer('Builder<${schemaName.toPascalCase()}>')
    ..body = Code(
        'return Builder(schemaKey:"$schemaName",modelBuilder:${schemaName.toPascalCase()}.new,route:route,config:config,schema:schema,);')));

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..type = MethodType.getter
    ..name = 'attributeTypes'
    ..returns = refer('Map<String, String>')
    ..body = Code(
        'return ${jsonEncode(fields.fold<Map<String, String>>({}, (map, field) => map..addAll({
                field['name'] as String: normalizeTypes(field['phpType'])
              })))};')));

  // Generate relation methods
  relations?.forEach((relationName, relationDetails) {
    final relationType = relationDetails['type'] as String;
    final relatedModel = relationDetails['model'] as String;
    final foreignKey = relationDetails['foreignKey'] as String?;
    final ownerKey = relationDetails['ownerKey'] as String?;

    classBuilder.methods.add(Method((b) => b
      ..lambda = true
      ..name = relationName.toCamelCase()
      ..type = MethodType.getter
      ..returns = refer('${relatedModel.toPascalCase()}?')
      ..body = Code(
          '${relationName.toCamelCase()}Relation().getLoadedItems() as ${relatedModel.toPascalCase()}?')));

    classBuilder.methods.add(Method((b) => b
      ..name = '${relationName.toCamelCase()}Relation'
      ..returns = refer(relationType)
      ..body = Code('''
          return ${relationType.toCamelCase()}(
            modelBuilder: ${relatedModel.toPascalCase()}.new as BaseModelFactory,
            relation: "$relationName",
            meta: {'name':'$relationName','type':'$relationType','model':'$relatedModel','foreignKey':'$foreignKey','ownerKey':'$ownerKey'},
            parent: this,
          );
        ''')));
  });

  // Generate attribute getters and setters
  for (final field in fields) {
    final fieldName = (field['name'] as String).toCamelCase();
    final attributeName = field['name'] as String;
    final fieldType =
        '${normalizeTypes(field['phpType'])}${normalizeTypes(field['phpType']) == 'dynamic' ? '' : '?'}';

    // Getter
    classBuilder.methods.add(Method((b) => b
      ..lambda = true
      ..type = MethodType.getter
      ..returns = refer(fieldType)
      ..name = fieldName
      ..body = Code('getAttribute("$attributeName")')));

    // Setter
    classBuilder.methods.add(Method((b) => b
      ..type = MethodType.setter
      ..name = fieldName
      ..requiredParameters.add(Parameter((p) => p
        ..name = 'value'
        ..type = refer(fieldType)))
      ..body = Code('setAttribute("$attributeName", value);')));
  }

  classBuilder.methods.add(Method((b) => b
    ..annotations.add(refer('override'))
    ..name = 'toString'
    ..returns = refer('String')
    ..body = Code(
        'return "${schemaName.toPascalCase()}(${fields.map((field) => "${(field['name'] as String).toCamelCase()}: \$${(field['name'] as String).toCamelCase()}").join(', ')})";')));

  final mixin = classBuilder.build();
  final emitter = DartEmitter();
  return '${mixin.accept(emitter)}';
}
