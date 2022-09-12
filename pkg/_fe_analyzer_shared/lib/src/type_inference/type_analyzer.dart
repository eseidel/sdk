// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../flow_analysis/flow_analysis.dart';
import 'type_analysis_result.dart';
import 'type_operations.dart';
import 'variable_bindings.dart';

/// Information supplied by the client to [TypeAnalyzer.analyzeSwitchExpression]
/// or [TypeAnalyzer.analyzeSwitchStatement] about a single case head.
///
/// The client is free to `implement` or `extend` this class.
class CaseHeadInfo<Node extends Object, Expression extends Node> {
  /// The AST node for this `case` or `default` clause.  This is used for error
  /// reporting, in case errors arise from mismatch among the variables bound by
  /// various cases that share a body.
  final Node node;

  /// For a `case` clause, the case pattern.  For a `default` clause, `null`.
  final Node? pattern;

  /// For a `case` clause that has a `when` part, the expression following
  /// `when`.  Otherwise `null`.
  final Expression? when;

  CaseHeadInfo({required this.node, required this.pattern, this.when});
}

/// Information supplied by the client to [TypeAnalyzer.analyzeSwitchExpression]
/// about an individual `case` or `default` clause.
///
/// The client is free to `implement` or `extend` this class.
class ExpressionCaseInfo<Node extends Object, Expression extends Node>
    extends CaseHeadInfo<Node, Expression> {
  /// The body of the `case` or `default` clause.
  final Expression body;

  ExpressionCaseInfo(
      {required super.node,
      required super.pattern,
      super.when,
      required this.body});
}

/// Information supplied by the client to [TypeAnalyzer.analyzeSwitchStatement]
/// about an individual `case` or `default` clause.
///
/// The client is free to `implement` or `extend` this class.
class StatementCaseInfo<Node extends Object, Statement extends Node,
    Expression extends Node> {
  /// The list of case heads for this case.
  ///
  /// The reason this is a list rather than a single head is because the front
  /// end merges together cases that share a body at parse time.
  final List<CaseHeadInfo<Node, Expression>> heads;

  /// The labels preceding this `case` or `default` clause, if any.
  final List<Node> labels;

  /// The statements following this `case` or `default` clause.  If this list is
  /// empty, and this is not the last `case` or `default` clause, this clause
  /// will be considered to share a body with the `case` or `default` clause
  /// that follows.
  final List<Statement> body;

  StatementCaseInfo(this.heads, this.body, {this.labels = const []});
}

/// Type analysis logic to be shared between the analyzer and front end.  The
/// intention is that the client's main type inference visitor class can include
/// this mix-in and call shared analysis logic as needed.
///
/// Concrete methods in this mixin, typically named `analyzeX` for some `X`,
/// are intended to be called by the client in order to analyze an AST node (or
/// equivalent) of type `X`; a client's `visit` method shouldn't have to do much
/// than call the corresponding `analyze` method, passing in AST node's children
/// and other properties, possibly take some client-specific actions with the
/// returned value (such as storing intermediate inference results), and then
/// return the returned value up the call stack.
///
/// Abstract methods in this mixin are intended to be implemented by the client;
/// these are called by the `analyzeX` methods to report analysis results, to
/// query the client-specific information (e.g. to obtain the client's
/// representation of core types), and to trigger recursive analysis of child
/// AST nodes.
///
/// Note that calling an `analyzeX` method is guaranteed to call `dispatch` on
/// all its subexpressions.  However, we don't specify the precise order in
/// which this will happen, nor do we always specify which callbacks will be
/// invoked during analysis, because these details are considered part of the
/// implementation of type analysis, not its API.  Instead, we specify the
/// effect that each method has on a conceptual "stack" of entities.
///
/// In documentation, the entities in the stack are listed in low-to-high order.
/// So, for example, if the documentation says the stack contains "(K, L)", then
/// an entity of kind L is on the top of the stack, with an entity of kind K
/// under it.  This low-to-high order is used when describing pushes and pops
/// too, so, for example a method documented with "pushes (K, L)" pushes K
/// first, then L, whereas a method documented with "pops (K, L)" pops L first,
/// then K.
///
/// In the paragraph above, "K" and "L" are just variables for illustrating the
/// conventions.  The actual kinds used by the analyzer are concepts from the
/// language itself such as "Statement", "Expression", "Pattern", etc.  See the
/// `Kind` enum in `test/mini_ir.dart` for a discussion of all possible kinds of
/// stack entries.
///
/// If multiple stack entries share a kind, we will sometimes add a name to
/// clarify which stack entry is which, e.g. analyzeIfStatement pushes
/// "(Expression condition, Statement ifTrue, Statement ifFalse)".
///
/// We'll also use the convention that "n * K" represents n consecutive entities
/// in the stack, each with kind K.
///
/// The kind associated with all pushes and pops is statically known (and
/// documented, and unit tested), and entities never change from one kind to
/// another.  This fact gives the client considerable freedom in how to actually
/// represent the stack in practice; for example, they might choose to ignore
/// some kinds entirely, or represent certain kinds with a block of multiple
/// stack entries instead of just one.  Or they might choose to multiple stacks,
/// one for each kind.  It's also possible that some clients won't need to keep
/// a stack at all.
///
/// Reasons a client might want to actually have a stack include:
/// - Constructing a lowered intermediate representation of the code as a side
///   effect of analysis,
/// - Building up a symbolic representation of the program's runtime behavior,
/// - Or keeping track of AST nodes that need to be replaced (e.g. replacing an
///   `integer literal` node with a `double literal` node when int->double
///   conversion happens).
///
/// The unit tests in the `_fe_analyzer_shared` package associate a simple
/// intermediate representation with each stack entry, and also record the kind
/// of each entry in order to verify that when an entity is popped, it has the
/// expected kind.
mixin TypeAnalyzer<Node extends Object, Statement extends Node,
        Expression extends Node, Variable extends Object, Type extends Object>
    implements VariableBindingCallbacks<Node, Variable, Type> {
  /// Returns the type `bool`.
  Type get boolType;

  /// Returns the type `double`.
  Type get doubleType;

  /// Returns the type `dynamic`.
  Type get dynamicType;

  @override
  TypeAnalyzerErrors<Node, Statement, Expression, Variable, Type>? get errors;

  /// Returns the client's [FlowAnalysis] object.
  ///
  /// May be `null`, because the analyzer doesn't have a flow analysis object
  /// in play when analyzing top level initializers (see
  /// https://github.com/dart-lang/sdk/issues/49701).
  FlowAnalysis<Node, Statement, Expression, Variable, Type>? get flow;

  /// Returns the type `int`.
  Type get intType;

  /// Returns the unknown type context (`?`) used in type inference.
  Type get unknownType;

  /// Analyzes a constant pattern or literal pattern.  [node] is the pattern
  /// itself, and [expression] is the constant or literal expression.  Depending
  /// on the client's representation, [node] and [expression] might or might not
  /// be identical.
  ///
  /// Stack effect: none.
  PatternDispatchResult<Node, Expression, Variable, Type>
      analyzeConstOrLiteralPattern(Node node, Expression expression) {
    return new _ConstOrLiteralPatternDispatchResult<Node, Expression, Variable,
        Type>(this, node, expression);
  }

  /// Analyzes an expression.  [node] is the expression to analyze, and
  /// [context] is the type schema which should be used for type inference.
  ///
  /// Stack effect: pushes (Expression).
  Type analyzeExpression(Expression node, Type? context) {
    // Stack: ()
    if (context == null || typeOperations.isDynamic(context)) {
      context = unknownType;
    }
    ExpressionTypeAnalysisResult<Type> result =
        dispatchExpression(node, context);
    // Stack: (Expression)
    if (typeOperations.isNever(result.provisionalType)) {
      flow?.handleExit();
    }
    return result.resolveShorting();
  }

  /// Analyzes a variable declaration statement of the form
  /// `pattern = initializer;`.
  ///
  /// [node] should be the AST node for the entire declaration, [pattern] for
  /// the pattern, and [initializer] for the initializer.  [isFinal] and
  /// [isLate] indicate whether this is a final declaration and/or a late
  /// declaration, respectively.
  ///
  /// Note that the only kind of pattern allowed in a late declaration is a
  /// variable pattern; [TypeAnalyzerErrors.patternDoesNotAllowLate] will be
  /// reported if any other kind of pattern is used.
  ///
  /// Stack effect: pushes (Expression, Pattern).
  void analyzeInitializedVariableDeclaration(
      Node node, Node pattern, Expression initializer,
      {required bool isFinal, required bool isLate}) {
    // Stack: ()
    PatternDispatchResult<Node, Expression, Variable, Type>
        patternDispatchResult = dispatchPattern(pattern);
    if (isLate &&
        patternDispatchResult is! _VariablePatternDispatchResult<Object, Object,
            Object, Object>) {
      errors?.patternDoesNotAllowLate(pattern);
    }
    if (isLate) {
      flow?.lateInitializer_begin(node);
    }
    Type initializerType =
        analyzeExpression(initializer, patternDispatchResult.typeSchema);
    // Stack: (Expression)
    if (isLate) {
      flow?.lateInitializer_end();
    }
    VariableBindings<Node, Variable, Type> bindings =
        new VariableBindings(this);
    patternDispatchResult.match(
        initializerType,
        bindings,
        new MatchContext(
            isFinal: isFinal,
            isLate: isLate,
            initializer: initializer,
            irrefutableContext: node,
            topPattern: pattern));
    // Stack: (Expression, Pattern)
  }

  /// Analyzes an integer literal, given the type context [context].
  ///
  /// Stack effect: none.
  IntTypeAnalysisResult<Type> analyzeIntLiteral(Type context) {
    bool convertToDouble = !typeOperations.isSubtypeOf(intType, context) &&
        typeOperations.isSubtypeOf(doubleType, context);
    Type type = convertToDouble ? doubleType : intType;
    return new IntTypeAnalysisResult<Type>(
        type: type, convertedToDouble: convertToDouble);
  }

  /// Analyzes an expression of the form `switch (expression) { cases }`.
  ///
  /// Stack effect: pushes (Expression, n * ExpressionCase), where n is the
  /// number of cases.
  SimpleTypeAnalysisResult<Type> analyzeSwitchExpression(
      Expression node, Expression scrutinee, int numCases, Type context) {
    // Stack: ()
    Type expressionType = analyzeExpression(scrutinee, unknownType);
    // Stack: (Expression)
    handleSwitchScrutinee(expressionType);
    flow?.switchStatement_expressionEnd(null);
    Type? lubType;
    for (int i = 0; i < numCases; i++) {
      // Stack: (Expression, i * ExpressionCase)
      ExpressionCaseInfo<Node, Expression> caseInfo =
          getExpressionCaseInfo(node, i);
      flow?.switchStatement_beginCase();
      VariableBindings<Node, Variable, Type> bindings =
          new VariableBindings(this);
      Node? pattern = caseInfo.pattern;
      if (pattern != null) {
        dispatchPattern(pattern).match(
            expressionType,
            bindings,
            new MatchContext<Node, Expression>(
                isFinal: false,
                switchScrutinee: scrutinee,
                topPattern: pattern));
        // Stack: (Expression, i * ExpressionCase, Pattern)
        Expression? when = caseInfo.when;
        bool hasWhen = when != null;
        if (hasWhen) {
          analyzeExpression(when, boolType);
          // Stack: (Expression, i * ExpressionCase, Pattern, Expression)
          flow?.switchStatement_afterWhen(when);
        } else {
          handleNoWhenCondition(node, i);
          // Stack: (Expression, i * ExpressionCase, Pattern, Expression)
        }
        handleCaseHead(node, caseIndex: i, subIndex: 0);
      } else {
        handleDefault(node, i);
      }
      // Stack: (Expression, i * ExpressionCase, CaseHead)
      Type type = analyzeExpression(caseInfo.body, context);
      // Stack: (Expression, i * ExpressionCase, CaseHead, Expression)
      if (lubType == null) {
        lubType = type;
      } else {
        lubType = typeOperations.lub(lubType, type);
      }
      finishExpressionCase(node, i);
      // Stack: (Expression, (i + 1) * ExpressionCase)
    }
    // Stack: (Expression, numCases * ExpressionCase)
    flow?.switchStatement_end(true);
    return new SimpleTypeAnalysisResult<Type>(type: lubType!);
  }

  /// Analyzes a statement of the form `switch (expression) { cases }`.
  ///
  /// Stack effect: pushes (Expression, n * StatementCase), where n is the
  /// number of cases after merging together cases that share a body.
  SwitchStatementTypeAnalysisResult<Type> analyzeSwitchStatement(
      Statement node, Expression scrutinee, int numCases) {
    // Stack: ()
    Type scrutineeType = analyzeExpression(scrutinee, unknownType);
    // Stack: (Expression)
    handleSwitchScrutinee(scrutineeType);
    flow?.switchStatement_expressionEnd(node);
    int numExecutionPaths = 0;
    int i = 0;
    bool hasDefault = false;
    bool lastCaseTerminates = true;
    while (i < numCases) {
      // Stack: (Expression, numExecutionPaths * StatementCase)
      int firstCaseInThisExecutionPath = i;
      int numHeads = 0;
      VariableBindings<Node, Variable, Type> bindings =
          new VariableBindings(this);
      flow?.switchStatement_beginCase();
      bindings.startAlternatives();
      flow?.switchStatement_beginAlternatives();
      bool hasLabels = false;
      List<Statement> body = const [];
      while (i < numCases) {
        // Stack: (Expression, numExecutionPaths * StatementCase,
        //         numHeads * CaseHead)
        StatementCaseInfo<Node, Statement, Expression> caseInfo =
            getStatementCaseInfo(node, i);
        if (caseInfo.labels.isNotEmpty) {
          hasLabels = true;
          for (Node label in caseInfo.labels) {
            // Labels count as empty patterns for the purposes of bindings.
            bindings.startAlternative(label);
            bindings.finishAlternative();
          }
        }
        List<CaseHeadInfo<Node, Expression>> heads = caseInfo.heads;
        for (int j = 0; j < heads.length; j++) {
          CaseHeadInfo<Node, Expression> head = heads[j];
          bindings.startAlternative(head.node);
          Node? pattern = head.pattern;
          if (pattern != null) {
            dispatchPattern(pattern).match(
                scrutineeType,
                bindings,
                new MatchContext<Node, Expression>(
                    isFinal: false,
                    switchScrutinee: scrutinee,
                    topPattern: pattern));
            // Stack: (Expression, numExecutionPaths * StatementCase,
            //         numHeads * CaseHead, Pattern),
            Expression? when = head.when;
            bool hasWhen = when != null;
            if (hasWhen) {
              analyzeExpression(when, boolType);
              // Stack: (Expression, numExecutionPaths * StatementCase,
              //         numHeads * CaseHead, Pattern, Expression),
              flow?.switchStatement_afterWhen(when);
            } else {
              handleNoWhenCondition(node, i);
            }
            handleCaseHead(node, caseIndex: i, subIndex: j);
          } else {
            hasDefault = true;
            handleDefault(node, i);
          }
          numHeads++;
          // Stack: (Expression, numExecutionPaths * StatementCase,
          //         numHeads * CaseHead),
          flow?.switchStatement_endAlternative();
          bindings.finishAlternative();
          body = caseInfo.body;
        }
        i++;
        if (body.isNotEmpty) break;
      }
      // Stack: (Expression, numExecutionPaths * StatementCase,
      //         numHeads * CaseHead)
      bindings.finishAlternatives();
      flow?.switchStatement_endAlternatives(node, hasLabels: hasLabels);
      handleCase_afterCaseHeads(node, firstCaseInThisExecutionPath, numHeads);
      // Stack: (Expression, numExecutionPaths * StatementCase, CaseHeads)
      for (Statement statement in body) {
        dispatchStatement(statement);
      }
      // Stack: (Expression, numExecutionPaths * StatementCase, CaseHeads,
      //         n * Statement), where n = body.length
      lastCaseTerminates = flow == null || !flow!.isReachable;
      if (i < numCases &&
          options.nullSafetyEnabled &&
          !options.patternsEnabled &&
          !lastCaseTerminates) {
        errors?.switchCaseCompletesNormally(node, firstCaseInThisExecutionPath,
            i - firstCaseInThisExecutionPath);
      }
      finishStatementCase(node,
          caseIndex: i - 1,
          executionPathIndex: numExecutionPaths,
          numStatements: body.length);
      // Stack: (Expression, (numExecutionPaths + 1) * StatementCase)
      hasLabels = false;
      numExecutionPaths++;
    }
    // Stack: (Expression, numExecutionPaths * StatementCase)
    bool isExhaustive = hasDefault || isSwitchExhaustive(node, scrutineeType);
    flow?.switchStatement_end(isExhaustive);
    return new SwitchStatementTypeAnalysisResult<Type>(
        hasDefault: hasDefault,
        isExhaustive: isExhaustive,
        lastCaseTerminates: lastCaseTerminates,
        numExecutionPaths: numExecutionPaths,
        scrutineeType: scrutineeType);
  }

  /// Analyzes a variable declaration of the form `type variable;` or
  /// `var variable;`.
  ///
  /// [node] should be the AST node for the entire declaration, [variable] for
  /// the variable, and [declaredType] for the type (if present).  [isFinal] and
  /// [isLate] indicate whether this is a final declaration and/or a late
  /// declaration, respectively.
  ///
  /// Stack effect: none.
  ///
  /// Returns the inferred type of the variable.
  Type analyzeUninitializedVariableDeclaration(
      Node node, Variable variable, Type? declaredType,
      {required bool isFinal, required bool isLate}) {
    Type inferredType = declaredType ?? dynamicType;
    flow?.declare(variable, false);
    setVariableType(variable, inferredType);
    return inferredType;
  }

  /// Analyzes a variable pattern.  [node] is the pattern itself, [variable] is
  /// the variable, and [declaredType] is the explicitly declared type (if
  /// present).
  ///
  /// Stack effect: none.
  PatternDispatchResult<Node, Expression, Variable, Type>
      analyzeVariablePattern(Node node, Variable variable, Type? declaredType) {
    return new _VariablePatternDispatchResult<Node, Expression, Variable, Type>(
        this, node, variable, declaredType);
  }

  /// Calls the appropriate `analyze` method according to the form of
  /// [expression], and then adjusts the stack as needed to combine any
  /// sub-structures into a single expression.
  ///
  /// For example, if [node] is a binary expression (`a + b`), calls
  /// [analyzeBinaryExpression].
  ///
  /// Stack effect: pushes (Expression).
  ExpressionTypeAnalysisResult<Type> dispatchExpression(
      Expression node, Type context);

  /// Calls the appropriate `analyze` method according to the form of [pattern].
  ///
  /// Stack effect: none.
  PatternDispatchResult<Node, Expression, Variable, Type> dispatchPattern(
      Node pattern);

  /// Calls the appropriate `analyze` method according to the form of
  /// [statement], and then adjusts the stack as needed to combine any
  /// sub-structures into a single statement.
  ///
  /// For example, if [statement] is a `while` loop, calls [analyzeWhileLoop].
  ///
  /// Stack effect: pushes (Statement).
  void dispatchStatement(Statement statement);

  /// Called after visiting an expression case.
  ///
  /// [node] is the enclosing switch expression, and [caseIndex] is the index of
  /// this code path within the switch expression's cases.
  ///
  /// Stack effect: pops (CaseHead, Expression) and pushes (ExpressionCase).
  void finishExpressionCase(Expression node, int caseIndex);

  /// Called after visiting a merged statement case.
  ///
  /// [node] is enclosing switch statement, [caseIndex] is the index of the last
  /// `case` or `default` clause in the merged statement case, and
  /// [numStatements] is the number of statements in the case body.
  ///
  /// Stack effect: pops (CaseHeads, numStatements * Statement) and pushes
  /// (StatementCase).
  void finishStatementCase(Statement node,
      {required int caseIndex,
      required int executionPathIndex,
      required int numStatements});

  /// Returns an [ExpressionCaseInfo] object describing the [index]th `case` or
  /// `default` clause in the switch expression [node].
  ///
  /// Note: it is allowed for the client's AST nodes for `case` and `default`
  /// clauses to implement [ExpressionCaseInfo], in which case this method can
  /// simply return the [index]th `case` or `default` clause.
  ///
  /// See [analyzeSwitchExpression].
  ExpressionCaseInfo<Node, Expression> getExpressionCaseInfo(
      Expression node, int index);

  /// Returns a [StatementCaseInfo] object describing the [index]th `case` or
  /// `default` clause in the switch statement [node].
  ///
  /// Note: it is allowed for the client's AST nodes for `case` and `default`
  /// clauses to implement [StatementCaseInfo], in which case this method can
  /// simply return the [index]th `case` or `default` clause.
  ///
  /// See [analyzeSwitchStatement].
  StatementCaseInfo<Node, Statement, Expression> getStatementCaseInfo(
      Statement node, int caseIndex);

  /// Called after visiting a merged set of `case` / `default` clauses.
  ///
  /// [node] is the enclosing switch statement, [caseIndex] is the index of the
  /// first `case` / `default` clause to be merged, and [numHeads] is the number
  /// of `case` / `default` clauses to be merged.
  ///
  /// Stack effect: pops (numHeads * CaseHead) and pushes (CaseHeads).
  void handleCase_afterCaseHeads(Statement node, int caseIndex, int numHeads);

  /// Called after visiting a single `case` clause, consisting of a pattern and
  /// a `when` condition.
  ///
  /// [node] is the enclosing switch statement or switch expression and
  /// [caseIndex] is the index of the `case` clause.
  ///
  /// Stack effect: pops (Pattern, Expression) and pushes (CaseHead).
  void handleCaseHead(Node node,
      {required int caseIndex, required int subIndex});

  /// Called when matching a constant pattern or a literal pattern.
  ///
  /// [node] is the AST node for the pattern and [matchedType] is the static
  /// type of the expression being matched.
  ///
  /// Stack effect: pops (Expression) and pushes (Pattern).
  void handleConstOrLiteralPattern(Node node, {required Type matchedType});

  /// Called after visiting a `default` clause.
  ///
  /// [node] is the enclosing switch statement or switch expression and
  /// [caseIndex] is the index of the `default` clause.
  ///
  /// Stack effect: pushes (CaseHead).
  void handleDefault(Node node, int caseIndex);

  /// Called when visiting a `case` that lacks a `when` clause.  Since the lack
  /// of a `when` clause is semantically equivalent to `when true`, this method
  /// should behave similarly to visiting the boolean literal `true`.
  ///
  /// [node] is the enclosing switch statement or switch expression and
  /// [caseIndex] is the index of the `case`.
  ///
  /// Stack effect: pushes (Expression).
  void handleNoWhenCondition(Node node, int caseIndex);

  /// Called after visiting the scrutinee part of a switch statement or switch
  /// expression.  This is a hook to allow the client to start exhaustiveness
  /// analysis.
  ///
  /// [type] is the static type of the scrutinee expression.
  ///
  /// TODO(paulberry): move exhaustiveness analysis into the shared code and
  /// eliminate this method.
  ///
  /// Stack effect: none.
  void handleSwitchScrutinee(Type type);

  /// Called when matching a variable pattern.
  ///
  /// [node] is the AST node for the pattern, [matchedType] is the static type
  /// of the expression being matched, and [staticType] is the static type of
  /// the variable.
  ///
  /// Stack effect: pushes (Pattern).
  void handleVariablePattern(Node node,
      {required Type matchedType, required Type staticType});

  /// Queries whether the switch statement or expression represented by [node]
  /// was exhaustive.  [expressionType] is the static type of the scrutinee.
  ///
  /// Will only be called if the switch statement or expression lacks a
  /// `default` clause.
  bool isSwitchExhaustive(Node node, Type expressionType);

  /// Records that type inference has assigned a [type] to a [variable].  This
  /// is called once per variable, regardless of whether the variable's type is
  /// explicit or inferred.
  void setVariableType(Variable variable, Type type);

  /// Computes the type that should be inferred for an implicitly typed variable
  /// whose initializer expression has static type [type].
  Type variableTypeFromInitializerType(Type type);
}

/// Interface used by the shared [TypeAnalyzer] logic to report error conditions
/// up to the client.
abstract class TypeAnalyzerErrors<Node extends Object, Statement extends Node,
    Expression extends Node, Variable extends Object, Type extends Object> {
  /// Called when the [TypeAnalyzer] encounters a condition which should be
  /// impossible if the user's code is free from static errors, but which might
  /// arise as a result of error recovery.  To verify this invariant, the client
  /// should double check (preferably using an assertion) that at least one
  /// error is reported.
  ///
  /// Note that the error might be reported after this method is called.
  void assertInErrorRecovery();

  /// Called if pattern support is disabled and a case constant's static type
  /// doesn't properly match the scrutinee's static type.
  void caseExpressionTypeMismatch(
      {required Expression scrutinee,
      required Expression caseExpression,
      required scrutineeType,
      required caseExpressionType,
      required bool nullSafetyEnabled});

  /// Called if a single variable is bound using two different types within the
  /// same pattern, or between two patterns in a set of case clauses that share
  /// a body.
  ///
  /// [pattern] is the variable pattern that was being processed at the time the
  /// inconsistency was discovered, and [type] is its type (which might have
  /// been inferred).  [previousPattern] is the previous variable pattern that
  /// was binding the same variable, and [previousType] is its type.
  void inconsistentMatchVar(
      {required Node pattern,
      required Type type,
      required Node previousPattern,
      required Type previousType});

  /// Called if a single variable is bound both with an explicit type and with
  /// an implicit type within the same pattern, or between two patterns in a set
  /// of case clauses that share a body.
  ///
  /// [pattern] is the variable pattern that was being processed at the time the
  /// inconsistency was discovered.  [previousPattern] is the previous variable
  /// pattern that was binding the same variable.
  ///
  /// TODO(paulberry): the spec might be changed so that this is not an error
  /// condition.  See https://github.com/dart-lang/language/issues/2424.
  void inconsistentMatchVarExplicitness(
      {required Node pattern, required Node previousPattern});

  /// Called if two subpatterns of a pattern attempt to declare the same
  /// variable (with the exception of `_` and logical-or patterns).
  ///
  /// [pattern] is the variable pattern that was being processed at the time the
  /// overlap was discovered.  [previousPattern] is the previous variable
  /// pattern that overlaps with it.
  void matchVarOverlap({required Node pattern, required Node previousPattern});

  /// Called if a variable is bound by one of the alternatives of a logical-or
  /// pattern but not the other, or if it is bound by one of the cases in a set
  /// of case clauses that share a body, but not all of them.
  ///
  /// [alternative] is the AST node which fails to bind the variable.  This will
  /// either be one of the immediate sub-patterns of a logical-or pattern, or a
  /// value of [StatementCaseInfo.node].
  ///
  /// [variable] is the variable that is not bound within [alternative].
  void missingMatchVar(Node alternative, Variable variable);

  /// Called if a pattern is illegally used in a variable declaration statement
  /// that is marked `late`, and that pattern is not allowed in such a
  /// declaration.  The only kind of pattern that may be used in a late variable
  /// declaration is a variable pattern.
  ///
  /// [pattern] is the AST node of the illegal pattern.
  void patternDoesNotAllowLate(Node pattern);

  /// Called if a refutable pattern is illegally used in an irrefutable context.
  ///
  /// [pattern] is the AST node of the refutable pattern, and [context] is the
  /// containing AST node that established an irrefutable context.
  void refutablePatternInIrrefutableContext(Node pattern, Node context);

  /// Called if one of the case bodies of a switch statement completes normally
  /// (other than the last case body), and the "patterns" feature is not
  /// enabled.
  ///
  /// [node] is the AST node of the switch statement.  [caseIndex] is the index
  /// of the first case sharing the erroneous case body.  [numMergedCases] is
  /// the number of case heads sharing the erroneous case body.
  void switchCaseCompletesNormally(
      Statement node, int caseIndex, int numMergedCases);
}

/// Options affecting the behavior of [TypeAnalyzer].
///
/// The client is free to `implement` or `extend` this class.
class TypeAnalyzerOptions {
  final bool nullSafetyEnabled;

  final bool patternsEnabled;

  TypeAnalyzerOptions(
      {required this.nullSafetyEnabled, required this.patternsEnabled});
}

/// Specialization of [PatternDispatchResult] returned by
/// [TypeAnalyzer.analyzeConstOrLiteralPattern]
class _ConstOrLiteralPatternDispatchResult<Node extends Object,
        Expression extends Node, Variable extends Object, Type extends Object>
    extends _PatternDispatchResultImpl<Node, Expression, Variable, Type> {
  /// The constant or literal expression.
  ///
  /// Depending on the client's representation, this might or might not be
  /// identical to [node].
  final Expression _expression;

  _ConstOrLiteralPatternDispatchResult(
      super.typeAnalyzer, super.node, this._expression);

  @override
  Type get typeSchema {
    // Note: the type schema only matters for patterns that appear in variable
    // declarations, and variable declarations are not allowed to contain
    // constant patterns.  So this code should only be reachable during error
    // recovery.
    _typeAnalyzer.errors?.assertInErrorRecovery();
    return _typeAnalyzer.unknownType;
  }

  @override
  void match(Type matchedType, VariableBindings<Node, Variable, Type> bindings,
      MatchContext<Node, Expression> context) {
    // Stack: ()
    Node? irrefutableContext = context.irrefutableContext;
    if (irrefutableContext != null) {
      _typeAnalyzer.errors
          ?.refutablePatternInIrrefutableContext(node, irrefutableContext);
    }
    Type staticType = _typeAnalyzer.analyzeExpression(_expression, matchedType);
    // Stack: (Expression)
    TypeAnalyzerErrors<Node, Node, Expression, Variable, Type>? errors =
        _typeAnalyzer.errors;
    TypeAnalyzerOptions options = _typeAnalyzer.options;
    if (errors != null && !options.patternsEnabled) {
      Expression? switchScrutinee = context.getSwitchScrutinee(node);
      if (switchScrutinee != null) {
        TypeOperations2<Type> typeOperations = _typeAnalyzer.typeOperations;
        bool nullSafetyEnabled = options.nullSafetyEnabled;
        bool matches = nullSafetyEnabled
            ? typeOperations.isSubtypeOf(staticType, matchedType)
            : typeOperations.isAssignableTo(staticType, matchedType);
        if (!matches) {
          errors.caseExpressionTypeMismatch(
              caseExpression: _expression,
              scrutinee: switchScrutinee,
              caseExpressionType: staticType,
              scrutineeType: matchedType,
              nullSafetyEnabled: nullSafetyEnabled);
        }
      }
    }
    _typeAnalyzer.handleConstOrLiteralPattern(node, matchedType: matchedType);
    // Stack: (Pattern)
  }
}

/// Common base class for all specializations of [PatternDispatchResult]
/// returned by methods in [TypeAnalyzer].
abstract class _PatternDispatchResultImpl<Node extends Object,
        Expression extends Node, Variable extends Object, Type extends Object>
    implements PatternDispatchResult<Node, Expression, Variable, Type> {
  /// Pointer back to the [TypeAnalyzer].
  final TypeAnalyzer<Node, Node, Expression, Variable, Type> _typeAnalyzer;

  @override
  final Node node;

  _PatternDispatchResultImpl(this._typeAnalyzer, this.node);
}

class _VariablePatternDispatchResult<Node extends Object,
        Expression extends Node, Variable extends Object, Type extends Object>
    extends _PatternDispatchResultImpl<Node, Expression, Variable, Type> {
  final Variable _variable;

  final Type? _declaredType;

  _VariablePatternDispatchResult(
      super._typeAnalyzer, super.node, this._variable, this._declaredType);

  @override
  Type get typeSchema => _declaredType ?? _typeAnalyzer.unknownType;

  @override
  void match(Type matchedType, VariableBindings<Node, Variable, Type> bindings,
      MatchContext<Node, Expression> context) {
    // Stack: ()
    Type staticType = _declaredType ??
        _typeAnalyzer.variableTypeFromInitializerType(matchedType);
    Node? irrefutableContext = context.irrefutableContext;
    if (irrefutableContext != null &&
        !_typeAnalyzer.typeOperations.isAssignableTo(matchedType, staticType)) {
      _typeAnalyzer.errors
          ?.refutablePatternInIrrefutableContext(node, irrefutableContext);
    }
    bool isImplicitlyTyped = _declaredType == null;
    bool isFirstMatch = bindings.add(node, _variable,
        staticType: staticType, isImplicitlyTyped: isImplicitlyTyped);
    if (isFirstMatch) {
      _typeAnalyzer.flow?.declare(_variable, false);
      _typeAnalyzer.setVariableType(_variable, staticType);
      _typeAnalyzer.flow?.initialize(
          _variable, matchedType, context.getInitializer(node),
          isFinal: context.isFinal,
          isLate: context.isLate,
          isImplicitlyTyped: isImplicitlyTyped);
    }
    _typeAnalyzer.handleVariablePattern(node,
        matchedType: matchedType, staticType: staticType);
    // Stack: (Pattern)
  }
}
