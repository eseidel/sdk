// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:front_end/src/fasta/parser/token_stream_rewriter.dart';
import 'package:front_end/src/fasta/scanner.dart'
    show ScannerResult, scanString;
import 'package:front_end/src/fasta/scanner/token.dart';
import 'package:front_end/src/scanner/token.dart' show Token;
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(TokenStreamRewriterTest_NoPrevious);
    defineReflectiveTests(TokenStreamRewriterTest_UsingPrevious);
  });
}

/// Abstract base class for tests of [TokenStreamRewriter].
abstract class TokenStreamRewriterTest {
  /// Indicates whether the tests should set up [Token.previous].
  bool get setPrevious;

  void test_insertTokenAfter_end_single() {
    var a = _makeToken(0, 'a');
    var b = _makeToken(1, 'b');
    var eof = _link([a]);
    var rewriter = new TokenStreamRewriter();
    expect(rewriter.insertTokenAfter(a, b), same(a));
    expect(a.next, same(b));
    expect(b.next, same(eof));
    expect(eof.previous, same(b));
    expect(b.previous, same(a));
  }

  void test_insertTokenAfter_middle_multiple() {
    var a = _makeToken(0, 'a');
    var b = _makeToken(1, 'b');
    var c = _makeToken(2, 'c');
    var d = _makeToken(3, 'd');
    var e = _makeToken(4, 'e');
    _link([a, b, e]);
    _link([c, d]);
    var rewriter = new TokenStreamRewriter();
    rewriter.insertTokenAfter(b, c);
    expect(a.next, same(b));
    expect(b.next, same(c));
    expect(c.next, same(d));
    expect(d.next, same(e));
  }

  void test_insertTokenAfter_middle_single() {
    var a = _makeToken(0, 'a');
    var b = _makeToken(1, 'b');
    var c = _makeToken(2, 'c');
    _link([a, c]);
    var rewriter = new TokenStreamRewriter();
    rewriter.insertTokenAfter(a, b);
    expect(a.next, same(b));
    expect(b.next, same(c));
  }

  void test_insertTokenAfter_second_insertion_earlier_in_stream() {
    var a = _makeToken(0, 'a');
    var b = _makeToken(1, 'b');
    var c = _makeToken(2, 'c');
    var d = _makeToken(3, 'd');
    var e = _makeToken(4, 'e');
    _link([a, c, e]);
    var rewriter = new TokenStreamRewriter();
    rewriter.insertTokenAfter(c, d);
    expect(c.next, same(d));
    expect(d.next, same(e));
    // The next call to rewriter should be able to find the insertion point
    // even though it is before the insertion point used above.
    rewriter.insertTokenAfter(a, b);
    expect(a.next, same(b));
    expect(b.next, same(c));
  }

  void test_moveSynthetic() {
    ScannerResult scanResult = scanString('Foo(bar; baz=0;');
    expect(scanResult.hasErrors, isTrue);
    Token open = scanResult.tokens.next.next;
    expect(open.lexeme, '(');
    Token close = open.endGroup;
    expect(close.isSynthetic, isTrue);
    expect(close.next.isEof, isTrue);
    var rewriter = new TokenStreamRewriter();

    Token result = rewriter.moveSynthetic(open.next, close);
    expect(result, close);
    expect(open.endGroup, close);
    expect(open.next.next, close);
    expect(close.next.isEof, isFalse);
  }

  void test_replaceTokenFollowing_multiple() {
    var a = _makeToken(0, 'a');
    var b = _makeToken(1, 'b');
    var c = _makeToken(2, 'c');
    var d = _makeToken(3, 'd');
    var e = _makeToken(4, 'e');
    var f = _makeToken(5, 'f');
    _link([a, b, e, f]);
    _link([c, d]);
    var rewriter = new TokenStreamRewriter();
    rewriter.replaceTokenFollowing(b, c);
    expect(a.next, same(b));
    expect(b.next, same(c));
    expect(c.next, same(d));
    expect(d.next, same(f));
  }

  void test_replaceTokenFollowing_single() {
    var a = _makeToken(0, 'a');
    var b = _makeToken(1, 'b');
    var c = _makeToken(2, 'c');
    var d = _makeToken(3, 'd');
    _link([a, b, d]);
    var rewriter = new TokenStreamRewriter();
    rewriter.replaceTokenFollowing(a, c);
    expect(a.next, same(c));
    expect(c.next, same(d));
  }

  /// Links together the given [tokens] and adds an EOF token to the end of the
  /// token stream.
  ///
  /// The EOF token is returned.
  Token _link(Iterable<Token> tokens) {
    Token head = new Token.eof(-1);
    if (!setPrevious) head.previous = null;
    for (var token in tokens) {
      head.next = token;
      if (setPrevious) token.previous = head;
      head = token;
    }
    int eofOffset = head.charOffset + head.lexeme.length;
    if (eofOffset < 0) eofOffset = 0;
    Token eof = new Token.eof(eofOffset);
    if (!setPrevious) eof.previous = null;
    head.next = eof;
    if (setPrevious) eof.previous = head;
    return eof;
  }

  StringToken _makeToken(int charOffset, String text) {
    return new StringToken.fromString(null, text, charOffset);
  }
}

/// Concrete implementation of [TokenStreamRewriterTest] in which
/// [Token.previous] values are set to null.
///
/// This forces [TokenStreamRewriter] to use its more complex heuristic for
/// finding previous tokens.
@reflectiveTest
class TokenStreamRewriterTest_NoPrevious extends TokenStreamRewriterTest {
  // These tests are failing because the re-writer currently depends on the
  // previous pointer.

  @override
  bool get setPrevious => false;
}

/// Concrete implementation of [TokenStreamRewriterTest] in which
/// [Token.previous] values are set to non-null.
///
/// Since [TokenStreamRewriter] makes use of [Token.previous] when it can,
/// these tests do not exercise the more complex heuristics for finding previous
/// tokens.
@reflectiveTest
class TokenStreamRewriterTest_UsingPrevious extends TokenStreamRewriterTest {
  @override
  bool get setPrevious => true;
}
