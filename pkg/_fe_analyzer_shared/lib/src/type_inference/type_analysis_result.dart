// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'type_analyzer.dart';
import 'variable_bindings.dart';

/// Container for the result of running type analysis on an expression.
///
/// This class keeps track of a provisional type of the expression (prior to
/// resolving null shorting) as well as the information necessary to resolve
/// null shorting.
abstract class ExpressionTypeAnalysisResult<Type extends Object> {
  /// Type of the expression before resolving null shorting.
  ///
  /// For example, if `this` is the result of analyzing `(... as int?)?.isEven`,
  /// [provisionalType] will be `bool`, because the `isEven` getter returns
  /// `bool`, and it is not yet known (until looking at the surrounding code)
  /// whether there will be additional selectors after `isEven` that should act
  /// on the `bool` type.
  Type get provisionalType;

  /// Resolves any pending null shorting.  For example, if `this` is the result
  /// of analyzing `(... as int?)?.isEven`, then calling [resolveShorting] will
  /// cause the `?.` to be desugared (if code generation is occurring) and will
  /// return the type `bool?`.
  ///
  /// TODO(paulberry): document what calls back to the client might be made by
  /// invoking this method.
  Type resolveShorting();
}

/// Container for the result of running type analysis on an integer literal.
class IntTypeAnalysisResult<Type extends Object>
    extends SimpleTypeAnalysisResult<Type> {
  /// Whether the integer literal was converted to a double.
  final bool convertedToDouble;

  IntTypeAnalysisResult({required super.type, required this.convertedToDouble});
}

/// Information about the code context surrounding a pattern match.
class MatchContext<Node extends Object, Expression extends Node> {
  /// Simple case where the match context is non-final and there's nothing else
  /// special going on.
  static const MatchContext<Never, Never> simpleNonFinal =
      const MatchContext(isFinal: false, topPattern: null);

  /// If non-`null`, the match is being done in an irrefutable context, and this
  /// is the surrounding AST node that establishes the irrefutable context.
  final Node? irrefutableContext;

  /// Indicates whether variables declared in the pattern should be `final`.
  final bool isFinal;

  /// Indicates whether variables declared in the pattern should be `late`.
  final bool isLate;

  /// The top level pattern in this pattern match.
  final Node? topPattern;

  /// The initializer being assigned to this pattern via a variable declaration
  /// statement, or `null` if this pattern does not occur in a variable
  /// declaration statement.
  final Expression? _initializer;

  /// The switch scrutinee, or `null` if this pattern does not occur in a switch
  /// statement or switch expression.
  final Expression? _switchScrutinee;

  const MatchContext(
      {Expression? initializer,
      this.irrefutableContext,
      required this.isFinal,
      this.isLate = false,
      Expression? switchScrutinee,
      required this.topPattern})
      : _initializer = initializer,
        _switchScrutinee = switchScrutinee;

  /// If the pattern [pattern] is the [topPattern] and there is a corresponding
  /// initializer expression, returns it.  Otherwise returns `null`.
  ///
  /// Note: the type of [pattern] is `Object` to avoid a runtime covariance
  /// check (which would fail if this method is called on [simpleNonFinal]).
  Expression? getInitializer(Object pattern) =>
      identical(pattern, topPattern) ? _initializer : null;

  /// If the pattern [pattern] is the [topPattern] and there is a corresponding
  /// switch scrutinee expression, returns it.  Otherwise returns `null`.
  ///
  /// Note: the type of [pattern] is `Object` to avoid a runtime covariance
  /// check (which would fail if this method is called on [simpleNonFinal]).
  Expression? getSwitchScrutinee(Object pattern) =>
      identical(pattern, topPattern) ? _switchScrutinee : null;

  /// Returns a modified version of `this`, with [irrefutableContext] set to
  /// `null`.  This is used to suppress cascading errors after reporting
  /// [TypeAnalyzerErrors.refutablePatternInIrrefutableContext].
  MatchContext<Node, Expression> makeRefutable() => irrefutableContext == null
      ? this
      : new MatchContext(
          initializer: _initializer,
          isFinal: isFinal,
          isLate: isLate,
          switchScrutinee: _switchScrutinee,
          topPattern: topPattern);
}

/// Data structure returned by the [TypeAnalyzer] `analyze` methods for
/// patterns.
abstract class PatternDispatchResult<Node extends Object,
    Expression extends Node, Variable extends Object, Type extends Object> {
  /// The AST node for this pattern.
  Node get node;

  /// The type schema for this pattern.
  Type get typeSchema;

  /// Called by the [TypeAnalyzer] when an attempt is made to match this
  /// pattern.
  ///
  /// [matchedType] is the type of the thing being matched (for a variable
  /// declaration, this is the type of the initializer or substructure thereof;
  /// for a switch statement this is the type of the scrutinee or substructure
  /// thereof).
  ///
  /// [bindings] is a data structure keeping track of the variable patterns seen
  /// so far and their type information.
  ///
  /// [isFinal] and [isLate] only apply to variable patterns, and indicate
  /// whether the variable in question should be late and/or final.
  ///
  /// [initializer] is only present if [node] is the principal pattern of a
  /// variable declaration; it is the variable declaration's initializer
  /// expression.  This is used by flow analysis to track when the truth or
  /// falsity of a boolean variable causes other variables to be promoted.
  ///
  /// If the match is happening in an irrefutable context, [irrefutableContext]
  /// should be the containing AST node that establishes the context as
  /// irrefutable.  Otherwise it should be `null`.
  ///
  /// Stack effect (see [TypeAnalyzer] for explanation): pushes (Pattern).
  void match(Type matchedType, VariableBindings<Node, Variable, Type> bindings,
      MatchContext<Node, Expression> context);
}

/// Container for the result of running type analysis on an expression that does
/// not contain any null shorting.
class SimpleTypeAnalysisResult<Type extends Object>
    implements ExpressionTypeAnalysisResult<Type> {
  /// The static type of the expression.
  final Type type;

  SimpleTypeAnalysisResult({required this.type});

  @override
  Type get provisionalType => type;

  @override
  Type resolveShorting() => type;
}

/// Container for the result of running type analysis on an integer literal.
class SwitchStatementTypeAnalysisResult<Type> {
  /// Whether the switch statement had a `default` clause.
  final bool hasDefault;

  /// Whether the switch statement was exhaustive.
  final bool isExhaustive;

  /// Whether the last case body in the switch statement terminated.
  final bool lastCaseTerminates;

  /// The number of case bodies in the switch statement (after merging cases
  /// that share a body).
  final int numExecutionPaths;

  /// The static type of the scrutinee expression.
  final Type scrutineeType;

  SwitchStatementTypeAnalysisResult(
      {required this.hasDefault,
      required this.isExhaustive,
      required this.lastCaseTerminates,
      required this.numExecutionPaths,
      required this.scrutineeType});
}
