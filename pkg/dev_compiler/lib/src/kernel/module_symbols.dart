// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart debug symbol information stored by DDC.
//
// The data format below stores descriptions of dart code objects and their
// mapping to JS that is generated by DDC. Every field, except ids, describes
// dart.
// Note that 'localId' and 'scopeId' combine into a unique id that is used for
// object lookup and mapping between JS and dart concepts. As a result, it
// needs to be either stored or easily computed for each corresponding JS object
// created by DDC, so the debugger is able to look up dart symbol from JS ones.
//
// For example, to detect all dart variables in current scope and display
// their values, the debugger can do the following:
//
// - map current JS location to dart location using source maps
// - find all nested dart scopes that include the current dart location
// - collect all dart variables in scope
// - look up corresponding variables and their values in JS scope by their
//   JS ids
// - display their values (non-expanded)
//
// To display a JS value of variable 'v' (non-expanded)
//
// - v: <dart type name> (jsvalue.toString())
//
// Where <dart type name> is the dart type of the dart variable 'v'
// at runtime.
//
// TODO: describe displaying specific non-expanded JS instances in dart
// way, for example, lists, maps, types - is JS toString() enough?
//
// To display a value (expanded)
//
// - look up the JS runtime type of the value
// - find the dart value's runtime type by JS id value's runtime type id
// - collect all dart fields of that type, including the inherited fields
// - map dart fields to JS field ids and look up their values using object
//   ids referenced by the original displayed value.
// - display their values (non-expanded)
class SemanticVersion {
  final int major;
  final int minor;
  final int patch;
  const SemanticVersion(
    this.major,
    this.minor,
    this.patch,
  );
  static SemanticVersion parse(String version) {
    var parts = version.split('.');
    if (parts.length != 3) {
      throw FormatException('Version: $version '
          'does not follow simple semantic versioning format');
    }
    var major = int.parse(parts[0]);
    var minor = int.parse(parts[1]);
    var patch = int.parse(parts[2]);
    return SemanticVersion(major, minor, patch);
  }

  /// Text version.
  String get version => '$major.$minor.$patch';

  /// True if this version is compatible with [version].
  ///
  /// The minor and patch version changes never remove any fields that current
  /// version supports, so the reader can create current metadata version from
  /// any file created with a later reader, as long as the major version does
  /// not change.
  bool isCompatibleWith(String version) {
    var other = parse(version);
    return other.major == major && other.minor >= minor && other.patch >= patch;
  }
}

abstract class SymbolTableElement {
  Map<String, dynamic> toJson();
}

class ModuleSymbols implements SymbolTableElement {
  /// Current symbol information version.
  ///
  /// Version follows simple semantic versioning format 'major.minor.patch'
  /// See https://semver.org
  static const SemanticVersion current = SemanticVersion(0, 0, 1);

  /// Semantic version of the format.
  final String version;

  /// Module name as used in the module metadata
  final String moduleName;

  /// All dart libraries included in the module.
  ///
  /// Note here and below that imported elements are not included in
  /// the current module but can be referenced by their ids.
  final List<LibrarySymbol> libraries;

  /// All dart scripts included in the module.
  final List<Script> scripts;

  /// All dart classes included in the module.
  final List<ClassSymbol> classes;

  /// All dart function types included in the module.
  final List<FunctionTypeSymbol> functionTypes;

  /// All dart function types included in the module.
  final List<FunctionSymbol> functions;

  /// All dart scopes included in the module.
  ///
  /// Does not include scopes listed in other fields,
  /// such as libraries, classes, and functions.
  final List<ScopeSymbol> scopes;

  /// All Dart variables included in the module.
  List<VariableSymbol> variables;

  ModuleSymbols({
    String? version,
    required this.moduleName,
    List<LibrarySymbol>? libraries,
    List<Script>? scripts,
    List<ClassSymbol>? classes,
    List<FunctionTypeSymbol>? functionTypes,
    List<FunctionSymbol>? functions,
    List<ScopeSymbol>? scopes,
    List<VariableSymbol>? variables,
  })  : version = version ??= current.version,
        libraries = libraries ?? [],
        scripts = scripts ?? [],
        classes = classes ?? [],
        functionTypes = functionTypes ?? [],
        functions = functions ?? [],
        scopes = scopes ?? [],
        variables = variables ?? [];

  ModuleSymbols.fromJson(Map<String, dynamic> json)
      : version = _readAndValidateVersionFromJson(json['version']),
        moduleName = _createValue(json['moduleName']),
        libraries =
            _createObjectList(json['libraries'], LibrarySymbol.fromJson),
        scripts = _createObjectList(json['scripts'], Script.fromJson),
        classes = _createObjectList(json['classes'], ClassSymbol.fromJson),
        functionTypes = _createObjectList(
            json['functionTypes'], FunctionTypeSymbol.fromJson),
        functions =
            _createObjectList(json['functions'], FunctionSymbol.fromJson),
        scopes = _createObjectList(json['scopes'], ScopeSymbol.fromJson),
        variables =
            _createObjectList(json['variables'], VariableSymbol.fromJson);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'version': version,
      'moduleName': moduleName,
    };
    _setObjectListIfNotNullOrEmpty(json, 'libraries', libraries);
    _setObjectListIfNotNullOrEmpty(json, 'scripts', scripts);
    _setObjectListIfNotNullOrEmpty(json, 'classes', classes);
    _setObjectListIfNotNullOrEmpty(json, 'functionTypes', functionTypes);
    _setObjectListIfNotNullOrEmpty(json, 'functions', functions);
    _setObjectListIfNotNullOrEmpty(json, 'scopes', scopes);
    _setObjectListIfNotNullOrEmpty(json, 'variables', variables);
    return json;
  }

  static String _readAndValidateVersionFromJson(dynamic json) {
    if (json == null) return current.version;
    var version = _createValue<String>(json);
    if (!current.isCompatibleWith(version)) {
      throw Exception('Unsupported version $version. '
          'Current version: ${current.version}');
    }
    return version;
  }
}

class Symbol implements SymbolTableElement {
  /// Local id (such as JS name) for the symbol.
  ///
  /// Used to map from Dart objects to JS objects inside a scope.
  final String localId;

  /// Enclosing scope of the symbol.
  final String? scopeId;

  /// Source location of the symbol.
  final SourceLocation? location;

  /// Unique Id, shared with JS representation (if any).
  ///
  /// '<scope id>|<js name>'
  ///
  /// Where scope refers to a Library, Class, Function, or Scope.
  String get id => scopeId == null ? localId : '$scopeId|$localId';

  Symbol({required this.localId, this.scopeId, this.location});

  Symbol.fromJson(Map<String, dynamic> json)
      : localId = _createValue(json['localId']),
        scopeId = _createValue(json['scopeId']),
        location =
            _createNullableObject(json['location'], SourceLocation.fromJson);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'localId': localId,
      if (scopeId != null) 'scopeId': scopeId,
    };
    _setObjectIfNotNull(json, 'location', location);
    return json;
  }
}

abstract class TypeSymbol {
  String get id;
}

enum VariableSymbolKind { global, local, property, field, formal, none }

VariableSymbolKind parseVariableSymbolKind(String value) {
  return VariableSymbolKind.values.singleWhere((e) => value == '$e',
      orElse: () {
    throw ArgumentError('$value is not VariableSymbolKind');
  });
}

class VariableSymbol extends Symbol {
  /// Name of the variable in Dart source code.
  final String name;

  /// Symbol kind.
  final VariableSymbolKind kind;

  /// The declared type of this symbol in Dart source code.
  // TODO(nshahan) Only nullable until we design how to identify types from
  // other modules.
  final String? typeId;

  /// True if this variable const.
  final bool isConst;

  /// True if this variable final.
  final bool isFinal;

  /// True if this variable static.
  final bool isStatic;

  /// Property getter, if any.
  final String? getterId;

  /// Property setter, if any.
  final String? setterId;

  VariableSymbol({
    required this.name,
    required this.kind,
    required this.typeId,
    bool? isConst,
    bool? isFinal,
    bool? isStatic,
    this.getterId,
    this.setterId,
    required String localId,
    required String scopeId,
    required SourceLocation location,
  })  : isConst = isConst ?? false,
        isFinal = isFinal ?? false,
        isStatic = isStatic ?? false,
        super(localId: localId, scopeId: scopeId, location: location);

  VariableSymbol.fromJson(Map<String, dynamic> json)
      : name = _createValue(json['name']),
        kind = _createValue(json['kind'],
            parse: parseVariableSymbolKind, ifNull: VariableSymbolKind.none),
        typeId = _createValue(json['typeId']),
        isConst = _createValue(json['isConst']),
        isFinal = _createValue(json['isFinal']),
        isStatic = _createValue(json['isStatic']),
        getterId = _createValue(json['getterId']),
        setterId = _createValue(json['setterId']),
        super.fromJson(json);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        'kind': kind.toString(),
        if (typeId != null) 'typeId': typeId,
        'isConst': isConst,
        'isFinal': isFinal,
        'isStatic': isStatic,
        if (getterId != null) 'getterId': getterId,
        if (setterId != null) 'setterId': setterId,
      };
}

class ClassSymbol extends ScopeSymbol implements TypeSymbol {
  /// The name of this class in Dart source code.
  final String name;

  /// True if this class is abstract.
  final bool isAbstract;

  /// True if this class is const.
  final bool isConst;

  /// The superclass of this class, if any.
  final String? superClassId;

  /// A list of interface types for this class.
  final List<String> interfaceIds;

  /// Mapping of type parameter Dart names to JS names.
  final Map<String, String> typeParameters;

  /// Library that contains this class.
  String get libraryId => scopeId!;

  /// Fields in this class.
  ///
  /// Including static fields, methods, and properties.
  List<String> get fieldIds => variableIds;

  /// Functions in this class.
  ///
  /// Includes all static functions, methods, getters,
  /// and setters in the current class.
  ///
  /// Does not include functions from superclasses.
  List<String> get functionIds => scopeIds;

  ClassSymbol({
    required this.name,
    bool? isAbstract,
    bool? isConst,
    this.superClassId,
    List<String>? interfaceIds,
    Map<String, String>? typeParameters,
    required String localId,
    required String scopeId,
    required SourceLocation location,
    List<String>? variableIds,
    List<String>? scopeIds,
  })  : isAbstract = isAbstract ?? false,
        isConst = isConst ?? false,
        interfaceIds = interfaceIds ?? [],
        typeParameters = typeParameters ?? {},
        super(
            localId: localId,
            scopeId: scopeId,
            variableIds: variableIds,
            scopeIds: scopeIds,
            location: location);

  ClassSymbol.fromJson(Map<String, dynamic> json)
      : name = _createValue(json['name']),
        isAbstract = _createValue(json['isAbstract']),
        isConst = _createValue(json['isConst']),
        superClassId = _createValue(json['superClassId']),
        interfaceIds = _createValueList(json['interfaceIds']),
        typeParameters = _createValueMap(json['typeParameters']),
        super.fromJson(json);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        'isAbstract': isAbstract,
        'isConst': isConst,
        if (superClassId != null) 'superClassId': superClassId,
        if (interfaceIds.isNotEmpty) 'interfaceIds': interfaceIds,
        if (typeParameters.isNotEmpty) 'typeParameters': typeParameters,
      };
}

class FunctionTypeSymbol extends Symbol implements TypeSymbol {
  /// Mapping of dart type parameter names to JS names.
  final Map<String, String> typeParameters;

  /// Types for positional parameters for this function.
  final List<String> parameterTypeIds;

  /// Types for optional positional parameters for this function.
  final List<String> optionalParameterTypeIds;

  /// Names and types for named parameters for this function.
  final Map<String, String> namedParameterTypeIds;

  /// The return type for this function.
  final String returnTypeId;

  FunctionTypeSymbol({
    Map<String, String>? typeParameters,
    List<String>? parameterTypeIds,
    List<String>? optionalParameterTypeIds,
    Map<String, String>? namedParameterTypeIds,
    required this.returnTypeId,
    required String localId,
    required String scopeId,
    required SourceLocation location,
  })  : typeParameters = typeParameters ?? {},
        parameterTypeIds = parameterTypeIds ?? [],
        optionalParameterTypeIds = optionalParameterTypeIds ?? [],
        namedParameterTypeIds = namedParameterTypeIds ?? {},
        super(localId: localId, scopeId: scopeId, location: location);

  FunctionTypeSymbol.fromJson(Map<String, dynamic> json)
      : parameterTypeIds = _createValueList(json['parameterTypeIds']),
        optionalParameterTypeIds =
            _createValueList(json['optionalParameterTypeIds']),
        typeParameters = _createValueMap(json['typeParameters']),
        namedParameterTypeIds = _createValueMap(json['namedParameterTypeIds']),
        returnTypeId = _createValue(json['returnTypeId']),
        super.fromJson(json);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (typeParameters.isNotEmpty) 'typeParameters': typeParameters,
        if (parameterTypeIds.isNotEmpty) 'parameterTypeIds': parameterTypeIds,
        if (optionalParameterTypeIds.isNotEmpty)
          'optionalParameterTypeIds': optionalParameterTypeIds,
        if (namedParameterTypeIds.isNotEmpty)
          'namedParameterTypeIds': namedParameterTypeIds,
        'returnTypeId': returnTypeId,
      };
}

class FunctionSymbol extends ScopeSymbol {
  /// The name of this function.
  final String name;

  /// Unique Id, shared with JS representation (if any).
  ///
  /// Format:
  ///   '<scope id>|<js name>'
  ///
  /// Where scope refers to a Library, Class, Function, or Scope.
  /// String id;
  /// Declared type of this function.
  // TODO(nshahan) Only nullable because unused at this time.
  final String? typeId;

  /// True if this function is static.
  final bool isStatic;

  /// True if this function is const.
  final bool isConst;

  FunctionSymbol({
    required this.name,
    required this.typeId,
    bool? isStatic,
    bool? isConst,
    required String localId,
    required String scopeId,
    List<String>? variableIds,
    List<String>? scopeIds,
    required SourceLocation location,
  })  : isStatic = isStatic ?? false,
        isConst = isConst ?? false,
        super(
          localId: localId,
          scopeId: scopeId,
          variableIds: variableIds,
          scopeIds: scopeIds,
          location: location,
        );

  FunctionSymbol.fromJson(Map<String, dynamic> json)
      : name = _createValue(json['name']),
        typeId = _createValue(json['typeId']),
        isStatic = _createValue(json['isStatic']),
        isConst = _createValue(json['isConst']),
        super.fromJson(json);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (typeId != null) 'typeId': typeId,
        'isStatic': isStatic,
        'isConst': isConst,
      };
}

class LibrarySymbol extends ScopeSymbol {
  /// The name of this library.
  final String name;

  /// The uri of this library.
  final String uri;

  /// A list of the imports for this library.
  final List<LibrarySymbolDependency> dependencies;

  /// A list of the scripts which constitute this library.
  final List<String> scriptIds;

  LibrarySymbol({
    String? name,
    required this.uri,
    List<LibrarySymbolDependency>? dependencies,
    required this.scriptIds,
    List<String>? variableIds,
    List<String>? scopeIds,
  })  : name = name ?? '',
        dependencies = dependencies ?? [],
        super(
          localId: uri,
          variableIds: variableIds,
          scopeIds: scopeIds,
        );

  LibrarySymbol.fromJson(Map<String, dynamic> json)
      : name = _createValue(json['name'], ifNull: ''),
        uri = _createValue(json['uri']),
        scriptIds = _createValueList(json['scriptIds']),
        dependencies = _createObjectList(
            json['dependencies'], LibrarySymbolDependency.fromJson),
        super.fromJson(json);

  @override
  Map<String, dynamic> toJson() {
    final json = {
      ...super.toJson(),
      if (name.isNotEmpty) 'name': name,
      'uri': uri,
      if (scriptIds.isNotEmpty) 'scriptIds': scriptIds,
    };
    _setObjectListIfNotNullOrEmpty(json, 'dependencies', dependencies);
    return json;
  }
}

class LibrarySymbolDependency implements SymbolTableElement {
  /// True if this dependency an import, false if an export.
  final bool isImport;

  /// True if this dependency is deferred.
  final bool isDeferred;

  /// The prefix of an 'as' import, or null.
  final String? prefix;

  /// The library being imported or exported.
  final String targetId;

  LibrarySymbolDependency({
    required this.isImport,
    bool? isDeferred,
    this.prefix,
    required this.targetId,
  }) : isDeferred = isDeferred ?? false;

  LibrarySymbolDependency.fromJson(Map<String, dynamic> json)
      : isImport = _createValue(json['isImport']),
        isDeferred = _createValue(json['isDeferred']),
        prefix = _createValue(json['prefix']),
        targetId = _createValue(json['targetId']);

  @override
  Map<String, dynamic> toJson() => {
        'isImport': isImport,
        'isDeferred': isDeferred,
        if (prefix != null) 'prefix': prefix,
        'targetId': targetId,
      };
}

class Script implements SymbolTableElement {
  /// The uri from which this script was loaded.
  final String uri;

  /// Unique Id.
  ///
  /// This can be just an integer. The mapping from JS to dart script
  /// happens using the source map. The id is only used for references
  /// in other elements.
  final String localId;

  final String libraryId;

  String get id => '$libraryId|$localId';

  Script({
    required this.uri,
    required this.localId,
    required this.libraryId,
  });

  Script.fromJson(Map<String, dynamic> json)
      : uri = _createValue(json['uri']),
        localId = _createValue(json['localId']),
        libraryId = _createValue(json['libraryId']);

  @override
  Map<String, dynamic> toJson() => {
        'uri': uri,
        'localId': localId,
        'libraryId': libraryId,
      };
}

class ScopeSymbol extends Symbol {
  /// A list of the top-level variables in this scope.
  final List<String> variableIds;

  /// Enclosed scopes.
  ///
  /// Includes all top classes, functions, inner scopes.
  final List<String> scopeIds;

  ScopeSymbol({
    List<String>? variableIds,
    List<String>? scopeIds,
    required String localId,
    String? scopeId,
    SourceLocation? location,
  })  : variableIds = variableIds ?? [],
        scopeIds = scopeIds ?? [],
        super(
          localId: localId,
          scopeId: scopeId,
          location: location,
        );

  ScopeSymbol.fromJson(Map<String, dynamic> json)
      : variableIds = _createValueList(json['variableIds']),
        scopeIds = _createValueList(json['scopeIds']),
        super.fromJson(json);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (variableIds.isNotEmpty) 'variableIds': variableIds,
        if (scopeIds.isNotEmpty) 'scopeIds': scopeIds,
      };
}

class SourceLocation implements SymbolTableElement {
  /// The script containing the source location.
  final String scriptId;

  /// The first token of the location.
  final int tokenPos;

  /// The last token of the location if this is a range.
  final int? endTokenPos;

  SourceLocation({
    required this.scriptId,
    required this.tokenPos,
    this.endTokenPos,
  });

  SourceLocation.fromJson(Map<String, dynamic> json)
      : scriptId = _createValue(json['scriptId']),
        tokenPos = _createValue(json['tokenPos']),
        endTokenPos = _createValue(json['endTokenPos']);

  @override
  Map<String, dynamic> toJson() => {
        'scriptId': scriptId,
        'tokenPos': tokenPos,
        if (endTokenPos != null) 'endTokenPos': endTokenPos,
      };
}

List<T> _createObjectList<T>(
    dynamic json, T Function(Map<String, dynamic>) creator) {
  if (json == null) return <T>[];
  if (json is List) {
    return json.map((e) => _createObject(e, creator)).toList();
  }
  throw ArgumentError('Not a list: $json');
}

T _createObject<T>(dynamic json, T Function(Map<String, dynamic>) creator) {
  if (json is Map<String, dynamic>) {
    return creator(json);
  }
  throw ArgumentError('Not a map: $json');
}

T? _createNullableObject<T>(
        dynamic json, T Function(Map<String, dynamic>) creator) =>
    json == null ? null : _createObject(json, creator);

List<T> _createValueList<T>(dynamic json,
    {T? ifNull, T Function(String)? parse}) {
  if (json == null) return <T>[];
  if (json is List) {
    return json
        .map((e) => _createValue<T>(e, ifNull: ifNull, parse: parse))
        .toList();
  }
  throw ArgumentError('Not a list: $json');
}

Map<String, T> _createValueMap<T>(dynamic json) {
  if (json == null) return <String, T>{};
  return Map<String, T>.from(json as Map<String, dynamic>);
}

T _createValue<T>(dynamic json, {T? ifNull, T Function(String)? parse}) {
  if (json == null && ifNull is T) return ifNull;
  if (json is T) {
    return json;
  }
  if (json is String && parse != null) {
    return parse(json);
  }
  throw ArgumentError('Cannot parse $json as $T');
}

void _setObjectListIfNotNullOrEmpty<T extends SymbolTableElement>(
    Map<String, dynamic> json, String key, List<T>? values) {
  if (values == null || values.isEmpty) return;
  json[key] = values.map((e) => e.toJson()).toList();
}

void _setObjectIfNotNull<T extends SymbolTableElement>(
    Map<String, dynamic> json, String key, T? value) {
  if (value == null) return;
  json[key] = value.toJson();
}
