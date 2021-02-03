// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/element/type_system.dart';
import 'package:analyzer/src/dart/error/ffi_code.dart';

/// A visitor used to find problems with the way the `dart:ffi` APIs are being
/// used. See 'pkg/vm/lib/transformations/ffi_checks.md' for the specification
/// of the desired hints.
class FfiVerifier extends RecursiveAstVisitor<void> {
  static const _allocatorClassName = 'Allocator';
  static const _allocateExtensionMethodName = 'call';
  static const _allocatorExtensionName = 'AllocatorAlloc';
  static const _dartFfiLibraryName = 'dart.ffi';
  static const _opaqueClassName = 'Opaque';

  static const List<String> _primitiveIntegerNativeTypes = [
    'Int8',
    'Int16',
    'Int32',
    'Int64',
    'Uint8',
    'Uint16',
    'Uint32',
    'Uint64',
    'IntPtr'
  ];

  static const List<String> _primitiveDoubleNativeTypes = [
    'Float',
    'Double',
  ];

  static const _structClassName = 'Struct';

  /// The type system used to check types.
  final TypeSystemImpl typeSystem;

  /// The error reporter used to report errors.
  final ErrorReporter _errorReporter;

  /// A flag indicating whether we are currently visiting inside a subclass of
  /// `Struct`.
  bool inStruct = false;

  /// Initialize a newly created verifier.
  FfiVerifier(this.typeSystem, this._errorReporter);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    inStruct = false;
    // Only the Allocator, Opaque and Struct class may be extended.
    var extendsClause = node.extendsClause;
    if (extendsClause != null) {
      final TypeName superclass = extendsClause.superclass;
      if (_isDartFfiClass(superclass)) {
        final className = superclass.name.staticElement!.name;
        if (className == _structClassName) {
          inStruct = true;
          if (_isEmptyStruct(node.declaredElement!)) {
            _errorReporter.reportErrorForNode(
                FfiCode.EMPTY_STRUCT_WARNING, node, [node.name]);
          }
        } else if (className != _allocatorClassName &&
            className != _opaqueClassName) {
          _errorReporter.reportErrorForNode(
              FfiCode.SUBTYPE_OF_FFI_CLASS_IN_EXTENDS,
              superclass.name,
              [node.name.name, superclass.name.name]);
        }
      } else if (_isSubtypeOfStruct(superclass)) {
        _errorReporter.reportErrorForNode(
            FfiCode.SUBTYPE_OF_STRUCT_CLASS_IN_EXTENDS,
            superclass,
            [node.name.name, superclass.name.name]);
      }
    }

    // No classes from the FFI may be explicitly implemented.
    void checkSupertype(TypeName typename, FfiCode subtypeOfFfiCode,
        FfiCode subtypeOfStructCode) {
      final superName = typename.name.staticElement?.name;
      if (superName == _allocatorClassName) {
        return;
      }
      if (_isDartFfiClass(typename)) {
        _errorReporter.reportErrorForNode(
            subtypeOfFfiCode, typename, [node.name, typename.name]);
      } else if (_isSubtypeOfStruct(typename)) {
        _errorReporter.reportErrorForNode(
            subtypeOfStructCode, typename, [node.name, typename.name]);
      }
    }

    var implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (TypeName type in implementsClause.interfaces) {
        checkSupertype(type, FfiCode.SUBTYPE_OF_FFI_CLASS_IN_IMPLEMENTS,
            FfiCode.SUBTYPE_OF_STRUCT_CLASS_IN_IMPLEMENTS);
      }
    }
    var withClause = node.withClause;
    if (withClause != null) {
      for (TypeName type in withClause.mixinTypes) {
        checkSupertype(type, FfiCode.SUBTYPE_OF_FFI_CLASS_IN_WITH,
            FfiCode.SUBTYPE_OF_STRUCT_CLASS_IN_WITH);
      }
    }

    if (inStruct && node.declaredElement!.typeParameters.isNotEmpty) {
      _errorReporter.reportErrorForNode(
          FfiCode.GENERIC_STRUCT_SUBCLASS, node.name, [node.name]);
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    if (inStruct) {
      _errorReporter.reportErrorForNode(
          FfiCode.FIELD_INITIALIZER_IN_STRUCT, node);
    }
    super.visitConstructorFieldInitializer(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (inStruct) {
      _validateFieldsInStruct(node);
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    var element = node.staticElement;
    if (element is MethodElement) {
      var enclosingElement = element.enclosingElement;
      if (enclosingElement is ExtensionElement) {
        if (_isAllocatorExtension(enclosingElement) &&
            element.name == _allocateExtensionMethodName) {
          _validateAllocate(node);
        }
      }
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    var element = node.staticElement;
    if (element is MethodElement) {
      var enclosingElement = element.enclosingElement;
      if (enclosingElement is ExtensionElement) {
        if (_isNativeStructPointerExtension(enclosingElement)) {
          if (element.name == '[]') {
            _validateRefIndexed(node);
          }
        }
      }
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    var element = node.methodName.staticElement;
    if (element is MethodElement) {
      Element enclosingElement = element.enclosingElement;
      if (enclosingElement is ClassElement) {
        if (_isPointer(enclosingElement)) {
          if (element.name == 'fromFunction') {
            _validateFromFunction(node, element);
          } else if (element.name == 'elementAt') {
            _validateElementAt(node);
          }
        }
      }
      if (enclosingElement is ExtensionElement) {
        if (_isNativeFunctionPointerExtension(enclosingElement)) {
          if (element.name == 'asFunction') {
            _validateAsFunction(node, element);
          }
        } else if (_isDynamicLibraryExtension(enclosingElement) &&
            element.name == 'lookupFunction') {
          _validateLookupFunction(node);
        }
      }
    } else if (element is FunctionElement) {
      var enclosingElement = element.enclosingElement;
      if (enclosingElement is CompilationUnitElement) {
        if (element.library.name == 'dart.ffi') {
          if (element.name == 'sizeOf') {
            _validateSizeOf(node);
          }
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    var element = node.staticElement;
    if (element != null) {
      var enclosingElement = element.enclosingElement;
      if (enclosingElement is ExtensionElement) {
        if (_isNativeStructPointerExtension(enclosingElement)) {
          if (element.name == 'ref') {
            _validateRefPrefixedIdentifier(node);
          }
        }
      }
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    var element = node.propertyName.staticElement;
    if (element != null) {
      var enclosingElement = element.enclosingElement;
      if (enclosingElement is ExtensionElement) {
        if (_isNativeStructPointerExtension(enclosingElement)) {
          if (element.name == 'ref') {
            _validateRefPropertyAccess(node);
          }
        }
      }
    }
    super.visitPropertyAccess(node);
  }

  /// Return `true` if the given [element] represents the extension
  /// `AllocatorAlloc`.
  bool _isAllocatorExtension(Element element) =>
      element.name == _allocatorExtensionName &&
      element.library?.name == _dartFfiLibraryName;

  /// Return `true` if the [typeName] is the name of a type from `dart:ffi`.
  bool _isDartFfiClass(TypeName typeName) =>
      _isDartFfiElement(typeName.name.staticElement);

  /// Return `true` if the [element] is a class element from `dart:ffi`.
  bool _isDartFfiElement(Element? element) {
    if (element is ConstructorElement) {
      element = element.enclosingElement;
    }
    return element is ClassElement &&
        element.library.name == _dartFfiLibraryName;
  }

  /// Return `true` if the given [element] represents the extension
  /// `DynamicLibraryExtension`.
  bool _isDynamicLibraryExtension(Element element) =>
      element.name == 'DynamicLibraryExtension' &&
      element.library?.name == _dartFfiLibraryName;

  bool _isEmptyStruct(ClassElement classElement) {
    final fields = classElement.fields;
    var structFieldCount = 0;
    for (final field in fields) {
      final declaredType = field.type;
      if (declaredType.isDartCoreInt) {
        structFieldCount++;
      } else if (declaredType.isDartCoreDouble) {
        structFieldCount++;
      } else if (_isPointer(declaredType.element)) {
        structFieldCount++;
      } else if (_isStructClass(declaredType)) {
        structFieldCount++;
      }
    }
    return structFieldCount == 0;
  }

  bool _isHandle(Element? element) =>
      element != null &&
      element.name == 'Handle' &&
      element.library?.name == _dartFfiLibraryName;

  /// Returns `true` iff [nativeType] is a `ffi.NativeFunction<???>` type.
  bool _isNativeFunctionInterfaceType(DartType nativeType) {
    if (nativeType is InterfaceType) {
      final element = nativeType.element;
      if (element.library.name == _dartFfiLibraryName) {
        return element.name == 'NativeFunction' &&
            nativeType.typeArguments.length == 1;
      }
    }
    return false;
  }

  bool _isNativeFunctionPointerExtension(Element? element) =>
      element != null &&
      element.name == 'NativeFunctionPointer' &&
      element.library?.name == _dartFfiLibraryName;

  bool _isNativeStructPointerExtension(Element element) =>
      element.name == 'StructPointer' && element.library?.name == 'dart.ffi';

  /// Returns `true` iff [nativeType] is a `ffi.NativeType` type.
  bool _isNativeTypeInterfaceType(DartType nativeType) {
    if (nativeType is InterfaceType) {
      final element = nativeType.element;
      if (element.library.name == _dartFfiLibraryName) {
        return element.name == 'NativeType';
      }
    }
    return false;
  }

  /// Returns `true` iff [nativeType] is a opaque type, i.e. a subtype of `Opaque`.
  bool _isOpaqueClass(DartType nativeType) {
    if (nativeType is InterfaceType) {
      final superType = nativeType.element.supertype;
      if (superType == null) {
        return false;
      }
      final superClassElement = superType.element;
      if (superClassElement.library.name == _dartFfiLibraryName) {
        return superClassElement.name == _opaqueClassName;
      }
    }
    return false;
  }

  /// Return `true` if the given [element] represents the class `Pointer`.
  bool _isPointer(Element? element) =>
      element != null &&
      element.name == 'Pointer' &&
      element.library?.name == _dartFfiLibraryName;

  /// Returns `true` iff [nativeType] is a `ffi.Pointer<???>` type.
  bool _isPointerInterfaceType(DartType nativeType) {
    if (nativeType is InterfaceType) {
      final element = nativeType.element;
      if (element.library.name == _dartFfiLibraryName) {
        return element.name == 'Pointer' &&
            nativeType.typeArguments.length == 1;
      }
    }
    return false;
  }

  /// Returns `true` iff [nativeType] is a struct type.
  bool _isStructClass(DartType nativeType) {
    if (nativeType is InterfaceType) {
      final superType = nativeType.element.supertype;
      if (superType == null) {
        return false;
      }
      final superClassElement = superType.element;
      if (superClassElement.library.name == _dartFfiLibraryName) {
        return superClassElement.name == _structClassName &&
            nativeType.typeArguments.isEmpty;
      }
    }
    return false;
  }

  /// Return `true` if the [typeName] represents a subtype of `Struct`.
  bool _isSubtypeOfStruct(TypeName typeName) {
    var superType = typeName.name.staticElement;
    if (superType is ClassElement) {
      bool isStruct(InterfaceType? type) {
        return type != null &&
            type.element.name == _structClassName &&
            type.element.library.name == _dartFfiLibraryName;
      }

      return isStruct(superType.supertype) ||
          superType.interfaces.any(isStruct) ||
          superType.mixins.any(isStruct);
    }
    return false;
  }

  /// Validates that the given type is a valid dart:ffi native function
  /// signature.
  bool _isValidFfiNativeFunctionType(DartType nativeType) {
    if (nativeType is FunctionType && !nativeType.isDartCoreFunction) {
      if (nativeType.namedParameterTypes.isNotEmpty ||
          nativeType.optionalParameterTypes.isNotEmpty) {
        return false;
      }
      if (!_isValidFfiNativeType(nativeType.returnType, true, false)) {
        return false;
      }

      for (final DartType typeArg in nativeType.normalParameterTypes) {
        if (!_isValidFfiNativeType(typeArg, false, false)) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  /// Validates that the given [nativeType] is a valid dart:ffi native type.
  // TODO(https://dartbug.com/44747): Change to named arguments.
  bool _isValidFfiNativeType(
      DartType? nativeType, bool allowVoid, bool allowEmptyStruct) {
    if (nativeType is InterfaceType) {
      // Is it a primitive integer/double type (or ffi.Void if we allow it).
      final primitiveType = _primitiveNativeType(nativeType);
      if (primitiveType != _PrimitiveDartType.none &&
          (primitiveType != _PrimitiveDartType.void_ || allowVoid)) {
        return true;
      }
      if (_isNativeFunctionInterfaceType(nativeType)) {
        return _isValidFfiNativeFunctionType(nativeType.typeArguments.single);
      }
      if (_isPointerInterfaceType(nativeType)) {
        final nativeArgumentType = nativeType.typeArguments.single;
        return _isValidFfiNativeType(nativeArgumentType, true, true) ||
            _isStructClass(nativeArgumentType) ||
            _isNativeTypeInterfaceType(nativeArgumentType);
      }
      if (_isStructClass(nativeType)) {
        if (!allowEmptyStruct) {
          if (_isEmptyStruct(nativeType.element)) {
            // TODO(dartbug.com/36780): This results in an error message not
            // mentioning empty structs at all.
            return false;
          }
        }
        return true;
      }
      if (_isOpaqueClass(nativeType)) {
        return true;
      }
    } else if (nativeType is FunctionType) {
      return _isValidFfiNativeFunctionType(nativeType);
    }
    return false;
  }

  _PrimitiveDartType _primitiveNativeType(DartType nativeType) {
    if (nativeType is InterfaceType) {
      final element = nativeType.element;
      if (element.library.name == _dartFfiLibraryName) {
        final String name = element.name;
        if (_primitiveIntegerNativeTypes.contains(name)) {
          return _PrimitiveDartType.int;
        }
        if (_primitiveDoubleNativeTypes.contains(name)) {
          return _PrimitiveDartType.double;
        }
        if (name == 'Void') {
          return _PrimitiveDartType.void_;
        }
        if (name == 'Handle') {
          return _PrimitiveDartType.handle;
        }
      }
    }
    return _PrimitiveDartType.none;
  }

  /// Return an indication of the Dart type associated with the [annotation].
  _PrimitiveDartType _typeForAnnotation(Annotation annotation) {
    var element = annotation.element;
    if (element is ConstructorElement) {
      String name = element.enclosingElement.name;
      if (_primitiveIntegerNativeTypes.contains(name)) {
        return _PrimitiveDartType.int;
      } else if (_primitiveDoubleNativeTypes.contains(name)) {
        return _PrimitiveDartType.double;
      }
    }
    return _PrimitiveDartType.none;
  }

  void _validateAllocate(FunctionExpressionInvocation node) {
    final typeArgumentTypes = node.typeArgumentTypes;
    if (typeArgumentTypes == null || typeArgumentTypes.length != 1) {
      return;
    }
    final DartType dartType = typeArgumentTypes[0];
    if (!_isValidFfiNativeType(dartType, true, true)) {
      final AstNode errorNode = node;
      _errorReporter.reportErrorForNode(
          FfiCode.NON_CONSTANT_TYPE_ARGUMENT,
          errorNode,
          ['$_allocatorExtensionName.$_allocateExtensionMethodName']);
    }
  }

  /// Validate that the [annotations] include exactly one annotation that
  /// satisfies the [requiredTypes]. If an error is produced that cannot be
  /// associated with an annotation, associate it with the [errorNode].
  void _validateAnnotations(AstNode errorNode, NodeList<Annotation> annotations,
      _PrimitiveDartType requiredType) {
    bool requiredFound = false;
    List<Annotation> extraAnnotations = [];
    for (Annotation annotation in annotations) {
      if (_isDartFfiElement(annotation.element)) {
        if (requiredFound) {
          extraAnnotations.add(annotation);
        } else {
          _PrimitiveDartType foundType = _typeForAnnotation(annotation);
          if (foundType == requiredType) {
            requiredFound = true;
          } else {
            extraAnnotations.add(annotation);
          }
        }
      }
    }
    if (extraAnnotations.isNotEmpty) {
      if (!requiredFound) {
        Annotation invalidAnnotation = extraAnnotations.removeAt(0);
        _errorReporter.reportErrorForNode(
            FfiCode.MISMATCHED_ANNOTATION_ON_STRUCT_FIELD, invalidAnnotation);
      }
      for (Annotation extraAnnotation in extraAnnotations) {
        _errorReporter.reportErrorForNode(
            FfiCode.EXTRA_ANNOTATION_ON_STRUCT_FIELD, extraAnnotation);
      }
    } else if (!requiredFound) {
      _errorReporter.reportErrorForNode(
          FfiCode.MISSING_ANNOTATION_ON_STRUCT_FIELD, errorNode);
    }
  }

  /// Validate the invocation of the instance method
  /// `Pointer<T>.asFunction<F>()`.
  void _validateAsFunction(MethodInvocation node, MethodElement element) {
    var typeArguments = node.typeArguments?.arguments;
    if (typeArguments != null && typeArguments.length == 1) {
      if (_validateTypeArgument(typeArguments[0], 'asFunction')) {
        return;
      }
    }
    var target = node.realTarget!;
    var targetType = target.staticType;
    if (targetType is InterfaceType &&
        _isPointer(targetType.element) &&
        targetType.typeArguments.length == 1) {
      final DartType T = targetType.typeArguments[0];
      if (!_isNativeFunctionInterfaceType(T) ||
          !_isValidFfiNativeFunctionType(
              (T as InterfaceType).typeArguments.single)) {
        final AstNode errorNode =
            typeArguments != null ? typeArguments[0] : node;
        _errorReporter.reportErrorForNode(
            FfiCode.NON_NATIVE_FUNCTION_TYPE_ARGUMENT_TO_POINTER,
            errorNode,
            [T]);
        return;
      }

      final DartType TPrime = T.typeArguments[0];
      final DartType F = node.typeArgumentTypes![0];
      if (!_validateCompatibleFunctionTypes(F, TPrime)) {
        _errorReporter.reportErrorForNode(
            FfiCode.MUST_BE_A_SUBTYPE, node, [TPrime, F, 'asFunction']);
      }
    }
  }

  /// Validates that the given [nativeType] is, when native types are converted
  /// to their Dart equivalent, a subtype of [dartType].
  bool _validateCompatibleFunctionTypes(
      DartType dartType, DartType nativeType) {
    // We require both to be valid function types.
    if (dartType is! FunctionType ||
        dartType.isDartCoreFunction ||
        nativeType is! FunctionType ||
        nativeType.isDartCoreFunction) {
      return false;
    }

    // We disallow any optional parameters.
    final int parameterCount = dartType.normalParameterTypes.length;
    if (parameterCount != nativeType.normalParameterTypes.length) {
      return false;
    }
    // We disallow generic function types.
    if (dartType.typeFormals.isNotEmpty || nativeType.typeFormals.isNotEmpty) {
      return false;
    }
    if (dartType.namedParameterTypes.isNotEmpty ||
        dartType.optionalParameterTypes.isNotEmpty ||
        nativeType.namedParameterTypes.isNotEmpty ||
        nativeType.optionalParameterTypes.isNotEmpty) {
      return false;
    }

    // Validate that the return types are compatible.
    if (!_validateCompatibleNativeType(
        dartType.returnType, nativeType.returnType, false)) {
      return false;
    }

    // Validate that the parameter types are compatible.
    for (int i = 0; i < parameterCount; ++i) {
      if (!_validateCompatibleNativeType(dartType.normalParameterTypes[i],
          nativeType.normalParameterTypes[i], true)) {
        return false;
      }
    }

    // Signatures have same number of parameters and the types match.
    return true;
  }

  /// Validates that, if we convert [nativeType] to it's corresponding
  /// [dartType] the latter is a subtype of the former if
  /// [checkCovariance].
  bool _validateCompatibleNativeType(
      DartType dartType, DartType nativeType, bool checkCovariance) {
    final nativeReturnType = _primitiveNativeType(nativeType);
    if (nativeReturnType == _PrimitiveDartType.int) {
      return dartType.isDartCoreInt;
    } else if (nativeReturnType == _PrimitiveDartType.double) {
      return dartType.isDartCoreDouble;
    } else if (nativeReturnType == _PrimitiveDartType.void_) {
      return dartType.isVoid;
    } else if (nativeReturnType == _PrimitiveDartType.handle) {
      InterfaceType objectType = typeSystem.objectStar;
      return checkCovariance
          ? /* everything is subtype of objectStar */ true
          : typeSystem.isSubtypeOf(objectType, dartType);
    } else if (dartType is InterfaceType && nativeType is InterfaceType) {
      return checkCovariance
          ? typeSystem.isSubtypeOf(dartType, nativeType)
          : typeSystem.isSubtypeOf(nativeType, dartType);
    } else {
      // If the [nativeType] is not a primitive int/double type then it has to
      // be a Pointer type atm.
      return false;
    }
  }

  void _validateElementAt(MethodInvocation node) {
    var targetType = node.realTarget?.staticType;
    if (targetType is InterfaceType &&
        _isPointer(targetType.element) &&
        targetType.typeArguments.length == 1) {
      final DartType T = targetType.typeArguments[0];

      if (!_isValidFfiNativeType(T, true, true)) {
        final AstNode errorNode = node;
        _errorReporter.reportErrorForNode(
            FfiCode.NON_CONSTANT_TYPE_ARGUMENT_WARNING,
            errorNode,
            ['elementAt']);
      }
    }
  }

  /// Validate that the fields declared by the given [node] meet the
  /// requirements for fields within a struct class.
  void _validateFieldsInStruct(FieldDeclaration node) {
    if (node.isStatic) {
      return;
    }
    VariableDeclarationList fields = node.fields;
    NodeList<Annotation> annotations = node.metadata;
    var fieldType = fields.type;
    if (fieldType == null) {
      _errorReporter.reportErrorForNode(
          FfiCode.MISSING_FIELD_TYPE_IN_STRUCT, fields.variables[0].name);
    } else {
      DartType declaredType = fieldType.type!;
      if (declaredType.isDartCoreInt) {
        _validateAnnotations(fieldType, annotations, _PrimitiveDartType.int);
      } else if (declaredType.isDartCoreDouble) {
        _validateAnnotations(fieldType, annotations, _PrimitiveDartType.double);
      } else if (_isPointer(declaredType.element)) {
        _validateNoAnnotations(annotations);
      } else if (_isStructClass(declaredType)) {
        final clazz = (declaredType as InterfaceType).element;
        if (_isEmptyStruct(clazz)) {
          _errorReporter
              .reportErrorForNode(FfiCode.EMPTY_STRUCT, node, [clazz.name]);
        }
      } else {
        _errorReporter.reportErrorForNode(FfiCode.INVALID_FIELD_TYPE_IN_STRUCT,
            fieldType, [fieldType.toSource()]);
      }
    }
    for (VariableDeclaration field in fields.variables) {
      if (field.initializer != null) {
        _errorReporter.reportErrorForNode(
            FfiCode.FIELD_IN_STRUCT_WITH_INITIALIZER, field.name);
      }
    }
  }

  /// Validate the invocation of the static method
  /// `Pointer<T>.fromFunction(f, e)`.
  void _validateFromFunction(MethodInvocation node, MethodElement element) {
    final int argCount = node.argumentList.arguments.length;
    if (argCount < 1 || argCount > 2) {
      // There are other diagnostics reported against the invocation and the
      // diagnostics generated below might be inaccurate, so don't report them.
      return;
    }

    final DartType T = node.typeArgumentTypes![0];
    if (!_isValidFfiNativeFunctionType(T)) {
      _errorReporter.reportErrorForNode(
          FfiCode.MUST_BE_A_NATIVE_FUNCTION_TYPE, node, [T, 'fromFunction']);
      return;
    }

    Expression f = node.argumentList.arguments[0];
    DartType FT = f.staticType!;
    if (!_validateCompatibleFunctionTypes(FT, T)) {
      _errorReporter.reportErrorForNode(
          FfiCode.MUST_BE_A_SUBTYPE, f, [f.staticType, T, 'fromFunction']);
      return;
    }

    // TODO(brianwilkerson) Validate that `f` is a top-level function.
    final DartType R = (T as FunctionType).returnType;
    if ((FT as FunctionType).returnType.isVoid ||
        _isPointer(R.element) ||
        _isHandle(R.element) ||
        _isStructClass(R)) {
      if (argCount != 1) {
        _errorReporter.reportErrorForNode(
            FfiCode.INVALID_EXCEPTION_VALUE, node.argumentList.arguments[1]);
      }
    } else if (argCount != 2) {
      _errorReporter.reportErrorForNode(
          FfiCode.MISSING_EXCEPTION_VALUE, node.methodName);
    } else {
      Expression e = node.argumentList.arguments[1];
      // TODO(brianwilkerson) Validate that `e` is a constant expression.
      if (!_validateCompatibleNativeType(e.staticType!, R, true)) {
        _errorReporter.reportErrorForNode(
            FfiCode.MUST_BE_A_SUBTYPE, e, [e.staticType, R, 'fromFunction']);
      }
    }
  }

  /// Validate the invocation of the instance method
  /// `DynamicLibrary.lookupFunction<S, F>()`.
  void _validateLookupFunction(MethodInvocation node) {
    final typeArguments = node.typeArguments?.arguments;
    if (typeArguments?.length != 2) {
      // There are other diagnostics reported against the invocation and the
      // diagnostics generated below might be inaccurate, so don't report them.
      return;
    }

    final List<DartType> argTypes = node.typeArgumentTypes!;
    final DartType S = argTypes[0];
    final DartType F = argTypes[1];
    if (!_isValidFfiNativeFunctionType(S)) {
      final AstNode errorNode = typeArguments![0];
      _errorReporter.reportErrorForNode(FfiCode.MUST_BE_A_NATIVE_FUNCTION_TYPE,
          errorNode, [S, 'lookupFunction']);
      return;
    }
    if (!_validateCompatibleFunctionTypes(F, S)) {
      final AstNode errorNode = typeArguments![1];
      _errorReporter.reportErrorForNode(
          FfiCode.MUST_BE_A_SUBTYPE, errorNode, [S, F, 'lookupFunction']);
    }
  }

  /// Validate that none of the [annotations] are from `dart:ffi`.
  void _validateNoAnnotations(NodeList<Annotation> annotations) {
    for (Annotation annotation in annotations) {
      if (_isDartFfiElement(annotation.element)) {
        _errorReporter.reportErrorForNode(
            FfiCode.ANNOTATION_ON_POINTER_FIELD, annotation);
      }
    }
  }

  void _validateRefIndexed(IndexExpression node) {
    var targetType = node.realTarget.staticType;
    if (!_isValidFfiNativeType(targetType, false, true)) {
      final AstNode errorNode = node;
      _errorReporter.reportErrorForNode(
          FfiCode.NON_CONSTANT_TYPE_ARGUMENT, errorNode, ['[]']);
    }
  }

  /// Validate the invocation of the extension method
  /// `Pointer<T extends Struct>.ref`.
  void _validateRefPrefixedIdentifier(PrefixedIdentifier node) {
    var targetType = node.prefix.staticType!;
    if (!_isValidFfiNativeType(targetType, false, true)) {
      final AstNode errorNode = node;
      _errorReporter.reportErrorForNode(
          FfiCode.NON_CONSTANT_TYPE_ARGUMENT, errorNode, ['ref']);
    }
  }

  void _validateRefPropertyAccess(PropertyAccess node) {
    var targetType = node.realTarget.staticType;
    if (!_isValidFfiNativeType(targetType, false, true)) {
      final AstNode errorNode = node;
      _errorReporter.reportErrorForNode(
          FfiCode.NON_CONSTANT_TYPE_ARGUMENT, errorNode, ['ref']);
    }
  }

  void _validateSizeOf(MethodInvocation node) {
    final typeArgumentTypes = node.typeArgumentTypes;
    if (typeArgumentTypes == null || typeArgumentTypes.length != 1) {
      return;
    }
    final DartType T = typeArgumentTypes[0];
    if (!_isValidFfiNativeType(T, true, true)) {
      final AstNode errorNode = node;
      _errorReporter.reportErrorForNode(
          FfiCode.NON_CONSTANT_TYPE_ARGUMENT_WARNING, errorNode, ['sizeOf']);
    }
  }

  /// Validate that the given [typeArgument] has a constant value. Return `true`
  /// if a diagnostic was produced because it isn't constant.
  bool _validateTypeArgument(TypeAnnotation typeArgument, String functionName) {
    if (typeArgument.type is TypeParameterType) {
      _errorReporter.reportErrorForNode(
          FfiCode.NON_CONSTANT_TYPE_ARGUMENT, typeArgument, [functionName]);
      return true;
    }
    return false;
  }
}

enum _PrimitiveDartType {
  double,
  int,
  void_,
  handle,
  none,
}
