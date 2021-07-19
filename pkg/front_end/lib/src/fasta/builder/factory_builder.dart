// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';

import '../dill/dill_member_builder.dart';

import '../kernel/class_hierarchy_builder.dart';
import '../kernel/forest.dart';
import '../kernel/internal_ast.dart';
import '../kernel/kernel_api.dart';
import '../kernel/redirecting_factory_body.dart'
    show getRedirectingFactoryBody, RedirectingFactoryBody;

import '../loader.dart' show Loader;

import '../messages.dart'
    show messageConstFactoryRedirectionToNonConst, noLength;

import '../problems.dart' show unexpected, unhandled;

import '../source/source_library_builder.dart' show SourceLibraryBuilder;

import '../type_inference/type_inferrer.dart';
import '../type_inference/type_schema.dart';

import '../util/helpers.dart';

import 'builder.dart';
import 'constructor_reference_builder.dart';
import 'formal_parameter_builder.dart';
import 'function_builder.dart';
import 'member_builder.dart';
import 'metadata_builder.dart';
import 'library_builder.dart';
import 'procedure_builder.dart';
import 'type_builder.dart';
import 'type_variable_builder.dart';

class SourceFactoryBuilder extends FunctionBuilderImpl {
  final int charOpenParenOffset;

  AsyncMarker actualAsyncModifier = AsyncMarker.Sync;

  final bool isExtensionInstanceMember = false;

  late Procedure _procedureInternal;

  SourceFactoryBuilder? actualOrigin;

  SourceFactoryBuilder(
      List<MetadataBuilder>? metadata,
      int modifiers,
      TypeBuilder returnType,
      String name,
      List<TypeVariableBuilder> typeVariables,
      List<FormalParameterBuilder>? formals,
      SourceLibraryBuilder libraryBuilder,
      int startCharOffset,
      int charOffset,
      this.charOpenParenOffset,
      int charEndOffset,
      Reference? procedureReference,
      AsyncMarker asyncModifier,
      ProcedureNameScheme procedureNameScheme,
      {String? nativeMethodName})
      : super(metadata, modifiers, returnType, name, typeVariables, formals,
            libraryBuilder, charOffset, nativeMethodName) {
    _procedureInternal = new Procedure(
        procedureNameScheme.getName(kind, name),
        isExtensionInstanceMember ? ProcedureKind.Method : kind,
        new FunctionNode(null),
        fileUri: libraryBuilder.fileUri,
        reference: procedureReference)
      ..startFileOffset = startCharOffset
      ..fileOffset = charOffset
      ..fileEndOffset = charEndOffset
      ..isNonNullableByDefault = libraryBuilder.isNonNullableByDefault;

    this.asyncModifier = asyncModifier;
  }

  SourceFactoryBuilder? get patchForTesting =>
      dataForTesting?.patchForTesting as SourceFactoryBuilder?;

  @override
  AsyncMarker get asyncModifier => actualAsyncModifier;

  @override
  Statement? get body {
    if (bodyInternal == null && !isAbstract && !isExternal) {
      bodyInternal = new EmptyStatement();
    }
    return bodyInternal;
  }

  void set asyncModifier(AsyncMarker newModifier) {
    actualAsyncModifier = newModifier;
    function.asyncMarker = actualAsyncModifier;
    function.dartAsyncMarker = actualAsyncModifier;
  }

  @override
  Member get member => _procedure;

  @override
  SourceFactoryBuilder get origin => actualOrigin ?? this;

  @override
  ProcedureKind get kind => ProcedureKind.Factory;

  Procedure get _procedure => isPatch ? origin._procedure : _procedureInternal;

  @override
  FunctionNode get function => _procedureInternal.function;

  @override
  Member? get readTarget => _procedure;

  @override
  Member? get writeTarget => null;

  @override
  Member? get invokeTarget => _procedure;

  @override
  Iterable<Member> get exportedMembers => [_procedure];

  @override
  void buildMembers(
      SourceLibraryBuilder library, void Function(Member, BuiltMemberKind) f) {
    Member member = build(library);
    f(member, BuiltMemberKind.Method);
  }

  @override
  Procedure build(SourceLibraryBuilder libraryBuilder) {
    buildFunction(libraryBuilder);
    _procedureInternal.function.fileOffset = charOpenParenOffset;
    _procedureInternal.function.fileEndOffset =
        _procedureInternal.fileEndOffset;
    _procedureInternal.isAbstract = isAbstract;
    _procedureInternal.isExternal = isExternal;
    _procedureInternal.isConst = isConst;
    updatePrivateMemberName(_procedureInternal, libraryBuilder);
    _procedureInternal.isStatic = isStatic;
    return _procedureInternal;
  }

  @override
  List<ClassMember> get localMembers =>
      throw new UnsupportedError('${runtimeType}.localMembers');

  @override
  List<ClassMember> get localSetters =>
      throw new UnsupportedError('${runtimeType}.localSetters');

  @override
  void becomeNative(Loader loader) {
    _procedureInternal.isExternal = true;
    super.becomeNative(loader);
  }

  void setRedirectingFactoryBody(Member target, List<DartType> typeArguments) {
    if (bodyInternal != null) {
      unexpected("null", "${bodyInternal.runtimeType}", charOffset, fileUri);
    }
    bodyInternal = new RedirectingFactoryBody(target, typeArguments);
    function.body = bodyInternal;
    bodyInternal?.parent = function;
    if (isPatch) {
      actualOrigin!.setRedirectingFactoryBody(target, typeArguments);
    }
  }

  @override
  void applyPatch(Builder patch) {
    if (patch is SourceFactoryBuilder) {
      if (checkPatch(patch)) {
        patch.actualOrigin = this;
        dataForTesting?.patchForTesting = patch;
      }
    } else {
      reportPatchMismatch(patch);
    }
  }

  @override
  int finishPatch() {
    if (!isPatch) return 0;

    // TODO(ahe): restore file-offset once we track both origin and patch file
    // URIs. See https://github.com/dart-lang/sdk/issues/31579
    origin._procedure.fileUri = fileUri;
    origin._procedure.startFileOffset = _procedureInternal.startFileOffset;
    origin._procedure.fileOffset = _procedureInternal.fileOffset;
    origin._procedure.fileEndOffset = _procedureInternal.fileEndOffset;
    origin._procedure.annotations
        .forEach((m) => m.fileOffset = _procedureInternal.fileOffset);

    origin._procedure.isAbstract = _procedureInternal.isAbstract;
    origin._procedure.isExternal = _procedureInternal.isExternal;
    origin._procedure.function = _procedureInternal.function;
    origin._procedure.function.parent = origin._procedure;
    origin._procedure.isRedirectingFactoryConstructor =
        _procedureInternal.isRedirectingFactoryConstructor;
    return 1;
  }
}

class RedirectingFactoryBuilder extends SourceFactoryBuilder {
  final ConstructorReferenceBuilder redirectionTarget;
  List<DartType>? typeArguments;

  RedirectingFactoryBuilder(
      List<MetadataBuilder>? metadata,
      int modifiers,
      TypeBuilder returnType,
      String name,
      List<TypeVariableBuilder> typeVariables,
      List<FormalParameterBuilder>? formals,
      SourceLibraryBuilder libraryBuilder,
      int startCharOffset,
      int charOffset,
      int charOpenParenOffset,
      int charEndOffset,
      Reference? procedureReference,
      ProcedureNameScheme procedureNameScheme,
      String? nativeMethodName,
      this.redirectionTarget)
      : super(
            metadata,
            modifiers,
            returnType,
            name,
            typeVariables,
            formals,
            libraryBuilder,
            startCharOffset,
            charOffset,
            charOpenParenOffset,
            charEndOffset,
            procedureReference,
            AsyncMarker.Sync,
            procedureNameScheme,
            nativeMethodName: nativeMethodName);

  @override
  Statement? get body => bodyInternal;

  @override
  void setRedirectingFactoryBody(Member target, List<DartType> typeArguments) {
    if (bodyInternal != null) {
      unexpected("null", "${bodyInternal.runtimeType}", charOffset, fileUri);
    }

    // Ensure that constant factories only have constant targets/bodies.
    if (isConst && !target.isConst) {
      library.addProblem(messageConstFactoryRedirectionToNonConst, charOffset,
          noLength, fileUri);
    }

    bodyInternal = new RedirectingFactoryBody(target, typeArguments);
    function.body = bodyInternal;
    bodyInternal?.parent = function;
    _procedure.isRedirectingFactoryConstructor = true;
    if (isPatch) {
      // ignore: unnecessary_null_comparison
      if (function.typeParameters != null) {
        Map<TypeParameter, DartType> substitution = <TypeParameter, DartType>{};
        for (int i = 0; i < function.typeParameters.length; i++) {
          substitution[function.typeParameters[i]] =
              new TypeParameterType.withDefaultNullabilityForLibrary(
                  actualOrigin!.function.typeParameters[i], library.library);
        }
        typeArguments = new List<DartType>.generate(typeArguments.length,
            (int i) => substitute(typeArguments[i], substitution),
            growable: false);
      }
      actualOrigin!.setRedirectingFactoryBody(target, typeArguments);
    }
  }

  @override
  void buildMembers(
      SourceLibraryBuilder library, void Function(Member, BuiltMemberKind) f) {
    Member member = build(library);
    f(member, BuiltMemberKind.RedirectingFactory);
  }

  @override
  Procedure build(SourceLibraryBuilder libraryBuilder) {
    buildFunction(libraryBuilder);
    _procedureInternal.function.fileOffset = charOpenParenOffset;
    _procedureInternal.function.fileEndOffset =
        _procedureInternal.fileEndOffset;
    _procedureInternal.isAbstract = isAbstract;
    _procedureInternal.isExternal = isExternal;
    _procedureInternal.isConst = isConst;
    _procedureInternal.isStatic = isStatic;
    _procedureInternal.isRedirectingFactoryConstructor = true;
    if (redirectionTarget.typeArguments != null) {
      typeArguments = new List<DartType>.generate(
          redirectionTarget.typeArguments!.length,
          (int i) => redirectionTarget.typeArguments![i].build(library),
          growable: false);
    }
    updatePrivateMemberName(_procedureInternal, libraryBuilder);
    return _procedureInternal;
  }

  @override
  void buildOutlineExpressions(
      SourceLibraryBuilder library,
      CoreTypes coreTypes,
      List<DelayedActionPerformer> delayedActionPerformers) {
    super.buildOutlineExpressions(library, coreTypes, delayedActionPerformers);
    LibraryBuilder thisLibrary = this.library;
    if (thisLibrary is SourceLibraryBuilder) {
      RedirectingFactoryBody redirectingFactoryBody =
          _procedure.function.body as RedirectingFactoryBody;
      if (redirectingFactoryBody.typeArguments != null &&
          redirectingFactoryBody.typeArguments!.any((t) => t is UnknownType)) {
        TypeInferrerImpl inferrer = thisLibrary.loader.typeInferenceEngine
                .createLocalTypeInferrer(
                    fileUri, classBuilder!.thisType, thisLibrary, null)
            as TypeInferrerImpl;
        inferrer.helper = thisLibrary.loader
            .createBodyBuilderForOutlineExpression(
                thisLibrary, classBuilder, this, classBuilder!.scope, fileUri);
        Builder? targetBuilder = redirectionTarget.target;
        Member target;
        if (targetBuilder is FunctionBuilder) {
          target = targetBuilder.member;
        } else if (targetBuilder is DillMemberBuilder) {
          target = targetBuilder.member;
        } else {
          unhandled("${targetBuilder.runtimeType}", "buildOutlineExpressions",
              charOffset, fileUri);
        }
        Arguments targetInvocationArguments;
        {
          List<Expression> positionalArguments = <Expression>[];
          for (VariableDeclaration parameter
              in _procedure.function.positionalParameters) {
            inferrer.flowAnalysis.declare(parameter, true);
            positionalArguments.add(
                new VariableGetImpl(parameter, forNullGuardedAccess: false));
          }
          List<NamedExpression> namedArguments = <NamedExpression>[];
          for (VariableDeclaration parameter
              in _procedure.function.namedParameters) {
            inferrer.flowAnalysis.declare(parameter, true);
            namedArguments.add(new NamedExpression(parameter.name!,
                new VariableGetImpl(parameter, forNullGuardedAccess: false)));
          }
          // If arguments are created using [Forest.createArguments], and the
          // type arguments are omitted, they are to be inferred.
          targetInvocationArguments = const Forest().createArguments(
              _procedure.fileOffset, positionalArguments,
              named: namedArguments);
        }
        InvocationInferenceResult result = inferrer.inferInvocation(
            function.returnType,
            charOffset,
            target.function!.computeFunctionType(Nullability.nonNullable),
            targetInvocationArguments,
            staticTarget: target);
        List<DartType> typeArguments;
        if (result.inferredType is InterfaceType) {
          typeArguments = (result.inferredType as InterfaceType).typeArguments;
        } else {
          // Assume that the error is reported elsewhere, use 'dynamic' for
          // recovery.
          typeArguments = new List<DartType>.filled(
              target.enclosingClass!.typeParameters.length, const DynamicType(),
              growable: true);
        }
        member.function!.body =
            new RedirectingFactoryBody(target, typeArguments);
      }
    }
  }

  @override
  int finishPatch() {
    if (!isPatch) return 0;

    super.finishPatch();

    SourceFactoryBuilder redirectingOrigin = origin;
    if (redirectingOrigin is RedirectingFactoryBuilder) {
      redirectingOrigin.typeArguments = typeArguments;
    }

    return 1;
  }

  List<DartType>? getTypeArguments() {
    return getRedirectingFactoryBody(_procedure)!.typeArguments;
  }
}
