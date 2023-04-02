// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../../client/completion_driver_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CaseClauseTest1);
    defineReflectiveTests(CaseClauseTest2);
  });
}

@reflectiveTest
class CaseClauseTest1 extends AbstractCompletionDriverTest
    with CaseClauseTestCases {
  @override
  TestingCompletionProtocol get protocol => TestingCompletionProtocol.version1;
}

@reflectiveTest
class CaseClauseTest2 extends AbstractCompletionDriverTest
    with CaseClauseTestCases {
  @override
  TestingCompletionProtocol get protocol => TestingCompletionProtocol.version2;
}

mixin CaseClauseTestCases on AbstractCompletionDriverTest {
  Future<void> test_afterCase_inIfElement() async {
    await computeSuggestions('''
var v = [ if (o case ^) ];
''');
    assertResponse(r'''
suggestions
  const
    kind: keyword
  false
    kind: keyword
  final
    kind: keyword
  null
    kind: keyword
  true
    kind: keyword
  var
    kind: keyword
''');
  }

  Future<void> test_afterCase_inIfStatement() async {
    await computeSuggestions('''
void f(Object o) {
  if (o case ^) {}
}
''');
    assertResponse(r'''
suggestions
  const
    kind: keyword
  false
    kind: keyword
  final
    kind: keyword
  null
    kind: keyword
  true
    kind: keyword
  var
    kind: keyword
''');
  }

  Future<void> test_afterCaseClause_inIfElement() async {
    await computeSuggestions('''
var v = [ if (o case != '' ^) ];
''');
    assertResponse(r'''
suggestions
  when
    kind: keyword
''');
  }

  @FailingTest(reason: "We're proposing 'when' but shouldn't be")
  Future<void> test_afterCaseClause_inIfStatement_beforeExpression1() async {
    // The `true` isn't in the `IfStatement`, but we don't catch that case.
    await computeSuggestions('''
void f(Object o) {
  if (o case != '' ^ true) {}
}
''');
    assertResponse(r'''
suggestions
''');
  }

  Future<void> test_afterCaseClause_inIfStatement_beforeExpression2() async {
    // The `true` isn't in the `IfStatement`. The only reason we don't suggest
    // `when` in this case is because the completion point is computed to be
    // just before the closing paren, but because the previous token is a number
    // we short circuit the `KeywordContributor`.
    await computeSuggestions('''
void f(Object o) {
  if (o case != '' ^ o.length > 3) {}
}
''');
    assertResponse(r'''
suggestions
''');
  }

  Future<void> test_afterCaseClause_inIfStatement_beforeParen() async {
    await computeSuggestions('''
void f(Object o) {
  if (o case != '' ^) {}
}
''');
    assertResponse(r'''
suggestions
  when
    kind: keyword
''');
  }

  Future<void> test_afterWhen_inIfElement() async {
    await computeSuggestions('''
var v = [ if (o case != '' when true ^) ];
''');
    assertResponse(r'''
suggestions
''');
  }

  Future<void> test_afterWhen_inIfStatement() async {
    await computeSuggestions('''
void f(Object o) {
  if (o case != '' when true ^) {}
}
''');
    assertResponse(r'''
suggestions
''');
  }

  Future<void> test_partialCase_inIfElement() async {
    await computeSuggestions('''
var v = [ if (o c^) ];
''');
    if (isProtocolVersion2) {
      assertResponse(r'''
replacement
  left: 1
suggestions
  case
    kind: keyword
''');
    } else {
      assertResponse(r'''
replacement
  left: 1
suggestions
  case
    kind: keyword
  is
    kind: keyword
''');
    }
  }

  Future<void> test_partialCase_inIfStatement() async {
    await computeSuggestions('''
void f(Object o) {
  if (o ca^) {}
}
''');
    if (isProtocolVersion2) {
      assertResponse(r'''
replacement
  left: 2
suggestions
  case
    kind: keyword
''');
    } else {
      assertResponse(r'''
replacement
  left: 2
suggestions
  case
    kind: keyword
  is
    kind: keyword
''');
    }
  }
}
