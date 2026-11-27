import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';

const _documentPath =
    'lib/src/features/sync/data/suwayomi/graphql/sync.graphql';

/// Field and input-field types by parent type, with whether each is
/// deprecated.
class _Schema {
  _Schema(DocumentNode schema) {
    for (final definition in schema.definitions) {
      switch (definition) {
        case ObjectTypeDefinitionNode(:final name, :final fields):
        case InterfaceTypeDefinitionNode(:final name, :final fields):
          this.fields[name.value] = {
            for (final field in fields)
              field.name.value: (
                type: _named(field.type),
                deprecated: _isDeprecated(field.directives),
                arguments: {
                  for (final argument in field.args)
                    argument.name.value: _named(argument.type),
                },
              ),
          };
        case InputObjectTypeDefinitionNode(:final name, :final fields):
          inputs[name.value] = {
            for (final field in fields)
              field.name.value: (
                type: _named(field.type),
                deprecated: _isDeprecated(field.directives),
              ),
          };
        default:
      }
    }
  }

  final fields =
      <
        String,
        Map<
          String,
          ({String type, bool deprecated, Map<String, String> arguments})
        >
      >{};
  final inputs = <String, Map<String, ({String type, bool deprecated})>>{};

  static String _named(TypeNode type) => switch (type) {
    NamedTypeNode(:final name) => name.value,
    ListTypeNode(:final type) => _named(type),
    _ => throw ArgumentError.value(type),
  };

  static bool _isDeprecated(List<DirectiveNode> directives) =>
      directives.any((directive) => directive.name.value == 'deprecated');
}

void main() {
  final schema = _Schema(
    parseString(File('lib/src/graphql/schema.graphql').readAsStringSync()),
  );
  final document = parseString(File(_documentPath).readAsStringSync());

  Map<String, FragmentDefinitionNode> fragmentsOf(DocumentNode document) => {
    for (final definition
        in document.definitions.whereType<FragmentDefinitionNode>())
      definition.name.value: definition,
  };

  // Deprecated or unknown fields and input fields [document] uses, as paths
  // like `SyncLibraryPage.mangas(condition).inLibrary`.
  List<String> problems(DocumentNode document) {
    final fragments = fragmentsOf(document);
    final found = <String>[];

    void checkInput(String type, ValueNode value, String path) {
      if (value is ListValueNode) {
        for (final item in value.values) {
          checkInput(type, item, path);
        }
        return;
      }
      if (value is! ObjectValueNode) return;
      final fields = schema.inputs[type];
      if (fields == null) return;
      for (final field in value.fields) {
        final info = fields[field.name.value];
        final fieldPath = '$path.${field.name.value}';
        if (info == null) {
          found.add('$fieldPath (unknown)');
        } else {
          if (info.deprecated) found.add('$fieldPath (deprecated)');
          checkInput(info.type, field.value, fieldPath);
        }
      }
    }

    void walk(String type, SelectionSetNode? selections, String path) {
      for (final selection in selections?.selections ?? <SelectionNode>[]) {
        switch (selection) {
          case FieldNode(:final name, :final arguments, :final selectionSet):
            if (name.value == '__typename') continue;
            final info = schema.fields[type]?[name.value];
            final fieldPath = '$path.${name.value}';
            if (info == null) {
              found.add('$fieldPath (unknown)');
              continue;
            }
            if (info.deprecated) found.add('$fieldPath (deprecated)');
            for (final argument in arguments) {
              final argumentType = info.arguments[argument.name.value];
              if (argumentType != null) {
                checkInput(
                  argumentType,
                  argument.value,
                  '$fieldPath(${argument.name.value})',
                );
              }
            }
            walk(info.type, selectionSet, fieldPath);
          case FragmentSpreadNode(:final name):
            final fragment = fragments[name.value]!;
            walk(
              fragment.typeCondition.on.name.value,
              fragment.selectionSet,
              '$path...${name.value}',
            );
          case InlineFragmentNode(:final typeCondition, :final selectionSet):
            walk(typeCondition?.on.name.value ?? type, selectionSet, path);
        }
      }
    }

    for (final operation
        in document.definitions.whereType<OperationDefinitionNode>()) {
      final root = switch (operation.type) {
        OperationType.query => 'Query',
        OperationType.mutation => 'Mutation',
        OperationType.subscription => 'Subscription',
      };
      walk(root, operation.selectionSet, operation.name!.value);
    }
    return found;
  }

  test('uses no deprecated or unknown fields', () {
    expect(problems(document), isEmpty);
  });

  test('reads chapter and library state through user', () {
    final fragments = fragmentsOf(document);
    for (final name in ['SyncChapterDto', 'SyncMangaDto']) {
      expect(
        fragments[name]!.selectionSet.selections.whereType<FieldNode>().map(
          (field) => field.name.value,
        ),
        contains('user'),
        reason: name,
      );
    }
  });

  test('declares the operations Sync needs', () {
    final names = {
      for (final operation
          in document.definitions.whereType<OperationDefinitionNode>())
        operation.name!.value,
    };
    expect(
      names,
      containsAll([
        'SyncLibraryPage',
        'SyncCategories',
        'SyncChaptersSince',
        'SyncChaptersOfManga',
        'SyncMangaBySourceUrl',
        'SyncExtensions',
        'SyncExtensionStores',
        'SyncChapterDownloadState',
        'SyncUpdateMangas',
        'SyncUpdateMangasCategories',
        'SyncCreateCategory',
        'SyncUpdateChapters',
        'SyncSetMangaMetas',
        'SyncFetchMangaAndChapters',
        'SyncFetchSourceManga',
        'SyncEnqueueChapterDownloads',
        'SyncDeleteDownloadedChapters',
        'SyncFetchChapterPages',
        'SyncUpdateExtension',
      ]),
    );
  });

  test('the check catches deprecated and unknown fields', () {
    final legacy = parseString('''
      fragment Legacy on ChapterType { isRead }
      query LegacyQuery {
        chapters(condition: { mangaId: 1 }) { nodes { ...Legacy name } }
        extensions(condition: { isNsfw: false }) { nodes { pkgName nope } }
      }
    ''');
    expect(problems(legacy), [
      'LegacyQuery.chapters.nodes...Legacy.isRead (deprecated)',
      'LegacyQuery.extensions(condition).isNsfw (deprecated)',
      'LegacyQuery.extensions.nodes.nope (unknown)',
    ]);
  });
}
