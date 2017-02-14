// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.analyzer.token_utils;

import 'package:front_end/src/fasta/parser/error_kind.dart' show
    ErrorKind;

import 'package:front_end/src/fasta/scanner/error_token.dart' show
    ErrorToken;

import 'package:front_end/src/fasta/scanner/keyword.dart' show
    Keyword;

import 'package:front_end/src/fasta/scanner/precedence.dart';

import 'package:front_end/src/fasta/scanner/token.dart' show
    BeginGroupToken,
    KeywordToken,
    StringToken,
    SymbolToken,
    Token;

import 'package:front_end/src/fasta/scanner/token_constants.dart';

import 'package:front_end/src/scanner/token.dart' as analyzer show
    BeginToken,
    BeginTokenWithComment,
    CommentToken,
    Keyword,
    KeywordToken,
    KeywordTokenWithComment,
    StringToken,
    StringTokenWithComment,
    Token,
    TokenWithComment;

import 'package:front_end/src/scanner/errors.dart' as analyzer show
    ScannerErrorCode;

import 'package:analyzer/dart/ast/token.dart' show
    TokenType;

import '../errors.dart' show
    internalError;

/// Converts a stream of Fasta tokens (starting with [token] and continuing to
/// EOF) to a stream of analyzer tokens.
///
/// If any error tokens are found in the stream, they are reported using the
/// [reportError] callback.
analyzer.Token toAnalyzerTokenStream(
    Token token,
    void reportError(analyzer.ScannerErrorCode errorCode, int offset,
        List<Object> arguments)) {
  var analyzerTokenHead = new analyzer.Token(null, 0);
  analyzerTokenHead.previous = analyzerTokenHead;
  var analyzerTokenTail = analyzerTokenHead;
  // TODO(paulberry,ahe): Fasta includes comments directly in the token
  // stream, rather than pointing to them via a "precedingComment" pointer, as
  // analyzer does.  This seems like it will complicate parsing and other
  // operations.
  analyzer.CommentToken currentCommentHead;
  analyzer.CommentToken currentCommentTail;
  // Note: beginTokenStack and endTokenStack are seeded with a sentinel value
  // so that we don't have to check if they're empty.
  var beginTokenStack = <analyzer.BeginToken>[null];
  var endTokenStack = <Token>[null];
  void matchGroups(Token token, analyzer.Token translatedToken) {
    // If this token closes a group, set the corresponding opener token
    // to point to it.
    if (identical(endTokenStack.last, token)) {
      beginTokenStack.last.endToken = translatedToken;
      beginTokenStack.removeLast();
      endTokenStack.removeLast();
    }
    // If this token opens a group, and there is a matching closer that's not
    // synthetic, put it on the stack.  The easiest way to tell whether the
    // closer is synthetic is to see if it has the same offset as the opener.
    if (translatedToken is analyzer.BeginToken &&
        token is BeginGroupToken &&
        token.endGroup != null &&
        token.endGroup.charOffset != token.charOffset) {
      beginTokenStack.add(translatedToken);
      endTokenStack.add(token.endGroup);
    }
  }

  while (true) {
    if (token.info.kind == BAD_INPUT_TOKEN) {
      ErrorToken errorToken = token;
      _translateErrorToken(errorToken, reportError);
    } else if (token.info.kind == COMMENT_TOKEN) {
      // TODO(paulberry,ahe): It would be nice if the scanner gave us an
      // easier way to distinguish between the two types of comment.
      var type = token.value.startsWith('/*')
          ? TokenType.MULTI_LINE_COMMENT
          : TokenType.SINGLE_LINE_COMMENT;
      var translatedToken =
          new analyzer.CommentToken(type, token.value, token.charOffset);
      if (currentCommentHead == null) {
        currentCommentHead = currentCommentTail = translatedToken;
      } else {
        currentCommentTail.setNext(translatedToken);
        currentCommentTail = translatedToken;
      }
    } else {
      var translatedToken = toAnalyzerToken(token, currentCommentHead);
      matchGroups(token, translatedToken);
      translatedToken.setNext(translatedToken);
      currentCommentHead = currentCommentTail = null;
      analyzerTokenTail.setNext(translatedToken);
      translatedToken.previous = analyzerTokenTail;
      analyzerTokenTail = translatedToken;
    }
    if (token.isEof) {
      return analyzerTokenHead.next;
    }
    token = token.next;
  }
}

/// Converts a stream of Analyzer tokens (starting with [token] and continuing
/// to EOF) to a stream of Fasta tokens.
///
/// TODO(paulberry): Analyzer tokens do not record error conditions, so a round
/// trip through this function and [toAnalyzerTokenStream] will lose error
/// information.
Token fromAnalyzerTokenStream(analyzer.Token analyzerToken) {
  Token tokenHead = new SymbolToken(EOF_INFO, -1);
  Token tokenTail = tokenHead;
  // Note: beginTokenStack and endTokenStack are seeded with a sentinel value
  // so that we don't have to check if they're empty.
  var beginTokenStack = <BeginGroupToken>[null];
  var endTokenStack = <analyzer.Token>[null];
  void matchGroups(analyzer.Token analyzerToken, Token translatedToken) {
    // If this token closes a group, set the corresponding opener token to point
    // to it.
    if (identical(endTokenStack.last, analyzerToken)) {
      beginTokenStack.last.endGroup = translatedToken;
      beginTokenStack.removeLast();
      endTokenStack.removeLast();
    }
    // If this token opens a group, and there is a matching closer, put it on
    // the stack.
    // TODO(paulberry): generate synthetic closer tokens and "UnmatchedToken"
    // tokens as appropriate.
    // TODO(paulberry): match up "<" and ">"/">>" (analyzer doesn't match
    // these).
    if (translatedToken is BeginGroupToken &&
        analyzerToken is analyzer.BeginToken &&
        analyzerToken.endToken != null) {
      beginTokenStack.add(translatedToken);
      endTokenStack.add(analyzerToken.endToken);
    }
  }

  analyzer.Token translateAndAppend(analyzer.Token analyzerToken) {
    var token = fromAnalyzerToken(analyzerToken);
    tokenTail.next = token;
    tokenTail = token;
    matchGroups(analyzerToken, token);
    return analyzerToken.next;
  }

  while (true) {
    analyzer.Token commentToken = analyzerToken.precedingComments;
    while (commentToken != null) {
      commentToken = translateAndAppend(commentToken);
    }
    // TODO(paulberry): join up begingroup/endgroup.
    if (analyzerToken.type == TokenType.EOF) {
      tokenTail.next = new SymbolToken(EOF_INFO, analyzerToken.offset);
      return tokenHead.next;
    }
    analyzerToken = translateAndAppend(analyzerToken);
  }
}

/// Converts a single analyzer token into a Fasta token.
Token fromAnalyzerToken(analyzer.Token token) {
  Token beginGroup(PrecedenceInfo info) =>
      new BeginGroupToken(info, token.offset);
  Token string(PrecedenceInfo info) =>
      new StringToken.fromString(info, token.lexeme, token.offset);
  Token symbol(PrecedenceInfo info) => new SymbolToken(info, token.offset);
  switch (token.type) {
    case TokenType.DOUBLE:
      return string(DOUBLE_INFO);
    case TokenType.HEXADECIMAL:
      return string(HEXADECIMAL_INFO);
    case TokenType.IDENTIFIER:
      // Certain identifiers have special grammatical meanings even though they
      // are neither keywords nor built-in identifiers (e.g. "async").  Analyzer
      // represents these as identifiers.  Fasta represents them as keywords
      // with the "isPseudo" property.
      var keyword = Keyword.keywords[token.lexeme];
      if (keyword != null) {
        assert(keyword.isPseudo);
        return new KeywordToken(keyword, token.offset);
      } else {
        return string(IDENTIFIER_INFO);
      }
      break;
    case TokenType.INT:
      return string(INT_INFO);
    case TokenType.KEYWORD:
      var keyword = Keyword.keywords[token.lexeme];
      if (keyword != null) {
        return new KeywordToken(keyword, token.offset);
      } else {
        return internalError("Unrecognized keyword: '${token.lexeme}'.");
      }
      break;
    case TokenType.MULTI_LINE_COMMENT:
      return string(COMMENT_INFO);
    // case TokenType.SCRIPT_TAG
    case TokenType.SINGLE_LINE_COMMENT:
      return string(COMMENT_INFO);
    case TokenType.STRING:
      return string(STRING_INFO);
    case TokenType.AMPERSAND:
      return symbol(AMPERSAND_INFO);
    case TokenType.AMPERSAND_AMPERSAND:
      return symbol(AMPERSAND_AMPERSAND_INFO);
    // case TokenType.AMPERSAND_AMPERSAND_EQ
    case TokenType.AMPERSAND_EQ:
      return symbol(AMPERSAND_EQ_INFO);
    case TokenType.AT:
      return symbol(AT_INFO);
    case TokenType.BANG:
      return symbol(BANG_INFO);
    case TokenType.BANG_EQ:
      return symbol(BANG_EQ_INFO);
    case TokenType.BAR:
      return symbol(BAR_INFO);
    case TokenType.BAR_BAR:
      return symbol(BAR_BAR_INFO);
    // case TokenType.BAR_BAR_EQ
    case TokenType.BAR_EQ:
      return symbol(BAR_EQ_INFO);
    case TokenType.COLON:
      return symbol(COLON_INFO);
    case TokenType.COMMA:
      return symbol(COMMA_INFO);
    case TokenType.CARET:
      return symbol(CARET_INFO);
    case TokenType.CARET_EQ:
      return symbol(CARET_EQ_INFO);
    case TokenType.CLOSE_CURLY_BRACKET:
      return symbol(CLOSE_CURLY_BRACKET_INFO);
    case TokenType.CLOSE_PAREN:
      return symbol(CLOSE_PAREN_INFO);
    case TokenType.CLOSE_SQUARE_BRACKET:
      return symbol(CLOSE_SQUARE_BRACKET_INFO);
    case TokenType.EQ:
      return symbol(EQ_INFO);
    case TokenType.EQ_EQ:
      return symbol(EQ_EQ_INFO);
    case TokenType.FUNCTION:
      return symbol(FUNCTION_INFO);
    case TokenType.GT:
      return symbol(GT_INFO);
    case TokenType.GT_EQ:
      return symbol(GT_EQ_INFO);
    case TokenType.GT_GT:
      return symbol(GT_GT_INFO);
    case TokenType.GT_GT_EQ:
      return symbol(GT_GT_EQ_INFO);
    case TokenType.HASH:
      return symbol(HASH_INFO);
    case TokenType.INDEX:
      return symbol(INDEX_INFO);
    case TokenType.INDEX_EQ:
      return symbol(INDEX_EQ_INFO);
    case TokenType.LT:
      return symbol(LT_INFO);
    case TokenType.LT_EQ:
      return symbol(LT_EQ_INFO);
    case TokenType.LT_LT:
      return symbol(LT_LT_INFO);
    case TokenType.LT_LT_EQ:
      return symbol(LT_LT_EQ_INFO);
    case TokenType.MINUS:
      return symbol(MINUS_INFO);
    case TokenType.MINUS_EQ:
      return symbol(MINUS_EQ_INFO);
    case TokenType.MINUS_MINUS:
      return symbol(MINUS_MINUS_INFO);
    case TokenType.OPEN_CURLY_BRACKET:
      return beginGroup(OPEN_CURLY_BRACKET_INFO);
    case TokenType.OPEN_PAREN:
      return beginGroup(OPEN_PAREN_INFO);
    case TokenType.OPEN_SQUARE_BRACKET:
      return beginGroup(OPEN_SQUARE_BRACKET_INFO);
    case TokenType.PERCENT:
      return symbol(PERCENT_INFO);
    case TokenType.PERCENT_EQ:
      return symbol(PERCENT_EQ_INFO);
    case TokenType.PERIOD:
      return symbol(PERIOD_INFO);
    case TokenType.PERIOD_PERIOD:
      return symbol(PERIOD_PERIOD_INFO);
    case TokenType.PLUS:
      return symbol(PLUS_INFO);
    case TokenType.PLUS_EQ:
      return symbol(PLUS_EQ_INFO);
    case TokenType.PLUS_PLUS:
      return symbol(PLUS_PLUS_INFO);
    case TokenType.QUESTION:
      return symbol(QUESTION_INFO);
    case TokenType.QUESTION_PERIOD:
      return symbol(QUESTION_PERIOD_INFO);
    case TokenType.QUESTION_QUESTION:
      return symbol(QUESTION_QUESTION_INFO);
    case TokenType.QUESTION_QUESTION_EQ:
      return symbol(QUESTION_QUESTION_EQ_INFO);
    case TokenType.SEMICOLON:
      return symbol(SEMICOLON_INFO);
    case TokenType.SLASH:
      return symbol(SLASH_INFO);
    case TokenType.SLASH_EQ:
      return symbol(SLASH_EQ_INFO);
    case TokenType.STAR:
      return symbol(STAR_INFO);
    case TokenType.STAR_EQ:
      return symbol(STAR_EQ_INFO);
    case TokenType.STRING_INTERPOLATION_EXPRESSION:
      return beginGroup(STRING_INTERPOLATION_INFO);
    case TokenType.STRING_INTERPOLATION_IDENTIFIER:
      return symbol(STRING_INTERPOLATION_IDENTIFIER_INFO);
    case TokenType.TILDE:
      return symbol(TILDE_INFO);
    case TokenType.TILDE_SLASH:
      return symbol(TILDE_SLASH_INFO);
    case TokenType.TILDE_SLASH_EQ:
      return symbol(TILDE_SLASH_EQ_INFO);
    case TokenType.BACKPING:
      return symbol(BACKPING_INFO);
    case TokenType.BACKSLASH:
      return symbol(BACKSLASH_INFO);
    case TokenType.PERIOD_PERIOD_PERIOD:
      return symbol(PERIOD_PERIOD_PERIOD_INFO);
    // case TokenType.GENERIC_METHOD_TYPE_ASSIGN
    // case TokenType.GENERIC_METHOD_TYPE_LIST
    default:
      return internalError('Unhandled token type ${token.type}');
  }
}

/// Determines whether the given [charOffset], which came from the non-EOF token
/// [token], represents the end of the input.
bool _isAtEnd(Token token, int charOffset) {
  while (true) {
    // Skip to the next token.
    token = token.next;
    // If we've found an EOF token, its charOffset indicates where the end of
    // the input is.
    if (token.isEof) return token.charOffset == charOffset;
    // If we've found a non-error token, then we know there is additional input
    // text after [charOffset].
    if (token.info.kind != BAD_INPUT_TOKEN) return false;
    // Otherwise keep looking.
  }
}

/// Translates the given error [token] into an analyzer error and reports it
/// using [reportError].
void _translateErrorToken(
    ErrorToken token,
    void reportError(analyzer.ScannerErrorCode errorCode, int offset,
        List<Object> arguments)) {
  int charOffset = token.charOffset;
  // TODO(paulberry,ahe): why is endOffset sometimes null?
  int endOffset = token.endOffset ?? charOffset;
  void _makeError(analyzer.ScannerErrorCode errorCode, List<Object> arguments) {
    if (_isAtEnd(token, charOffset)) {
      // Analyzer never generates an error message past the end of the input,
      // since such an error would not be visible in an editor.
      // TODO(paulberry,ahe): would it make sense to replicate this behavior
      // in fasta, or move it elsewhere in analyzer?
      charOffset--;
    }
    reportError(errorCode, charOffset, arguments);
  }

  var errorCode = token.errorCode;
  switch (errorCode) {
    case ErrorKind.UnterminatedString:
      // TODO(paulberry,ahe): Fasta reports the error location as the entire
      // string; analyzer expects the end of the string.
      charOffset = endOffset;
      return _makeError(
          analyzer.ScannerErrorCode.UNTERMINATED_STRING_LITERAL, null);
    case ErrorKind.UnmatchedToken:
      return null;
    case ErrorKind.UnterminatedComment:
      // TODO(paulberry,ahe): Fasta reports the error location as the entire
      // comment; analyzer expects the end of the comment.
      charOffset = endOffset;
      return _makeError(
          analyzer.ScannerErrorCode.UNTERMINATED_MULTI_LINE_COMMENT, null);
    case ErrorKind.MissingExponent:
      // TODO(paulberry,ahe): Fasta reports the error location as the entire
      // number; analyzer expects the end of the number.
      charOffset = endOffset;
      return _makeError(analyzer.ScannerErrorCode.MISSING_DIGIT, null);
    case ErrorKind.ExpectedHexDigit:
      // TODO(paulberry,ahe): Fasta reports the error location as the entire
      // number; analyzer expects the end of the number.
      charOffset = endOffset;
      return _makeError(analyzer.ScannerErrorCode.MISSING_HEX_DIGIT, null);
    case ErrorKind.NonAsciiIdentifier:
    case ErrorKind.NonAsciiWhitespace:
      return _makeError(
          analyzer.ScannerErrorCode.ILLEGAL_CHARACTER, [token.character]);
    case ErrorKind.UnexpectedDollarInString:
      return null;
    default:
      throw new UnimplementedError('$errorCode');
  }
}

analyzer.Token toAnalyzerToken(Token token,
    [analyzer.CommentToken commentToken]) {
  if (token == null) return null;
  analyzer.Token makeStringToken(TokenType tokenType) {
    if (commentToken == null) {
      return new analyzer.StringToken(tokenType, token.value, token.charOffset);
    } else {
      return new analyzer.StringTokenWithComment(
          tokenType, token.value, token.charOffset, commentToken);
    }
  }

  analyzer.Token makeBeginToken(TokenType tokenType) {
    if (commentToken == null) {
      return new analyzer.BeginToken(tokenType, token.charOffset);
    } else {
      return new analyzer.BeginTokenWithComment(
          tokenType, token.charOffset, commentToken);
    }
  }

  switch (token.kind) {
    case DOUBLE_TOKEN:
      return makeStringToken(TokenType.DOUBLE);

    case HEXADECIMAL_TOKEN:
      return makeStringToken(TokenType.HEXADECIMAL);

    case IDENTIFIER_TOKEN:
      return makeStringToken(TokenType.IDENTIFIER);

    case INT_TOKEN:
      return makeStringToken(TokenType.INT);

    case KEYWORD_TOKEN:
      KeywordToken keywordToken = token;
      var syntax = keywordToken.keyword.syntax;
      if (keywordToken.keyword.isPseudo) {
        // TODO(paulberry,ahe): Fasta considers "deferred" be a "pseudo-keyword"
        // (ordinary identifier which has special meaning under circumstances),
        // but analyzer and the spec consider it to be a built-in identifier
        // (identifier which can't be used in type names).
        if (!identical(syntax, 'deferred')) {
          return makeStringToken(TokenType.IDENTIFIER);
        }
      }
      // TODO(paulberry): if the map lookup proves to be too slow, consider
      // using a switch statement, or perhaps a string of
      // "if (identical(syntax, "foo"))" checks.  (Note that identical checks
      // should be safe because the Fasta scanner uses string literals for
      // the values of keyword.syntax.)
      var keyword =
          _keywordMap[syntax] ?? internalError('Unknown keyword: $syntax');
      if (commentToken == null) {
        return new analyzer.KeywordToken(keyword, token.charOffset);
      } else {
        return new analyzer.KeywordTokenWithComment(
            keyword, token.charOffset, commentToken);
      }
      break;

    case STRING_TOKEN:
      return makeStringToken(TokenType.STRING);

    case OPEN_CURLY_BRACKET_TOKEN:
    case OPEN_SQUARE_BRACKET_TOKEN:
    case OPEN_PAREN_TOKEN:
    case STRING_INTERPOLATION_TOKEN:
      return makeBeginToken(getTokenType(token));

    default:
      if (commentToken == null) {
        return new analyzer.Token(getTokenType(token), token.charOffset);
      } else {
        return new analyzer.TokenWithComment(
            getTokenType(token), token.charOffset, commentToken);
      }
      break;
  }
}

final _keywordMap = {
  "assert": analyzer.Keyword.ASSERT,
  "break": analyzer.Keyword.BREAK,
  "case": analyzer.Keyword.CASE,
  "catch": analyzer.Keyword.CATCH,
  "class": analyzer.Keyword.CLASS,
  "const": analyzer.Keyword.CONST,
  "continue": analyzer.Keyword.CONTINUE,
  "default": analyzer.Keyword.DEFAULT,
  "do": analyzer.Keyword.DO,
  "else": analyzer.Keyword.ELSE,
  "enum": analyzer.Keyword.ENUM,
  "extends": analyzer.Keyword.EXTENDS,
  "false": analyzer.Keyword.FALSE,
  "final": analyzer.Keyword.FINAL,
  "finally": analyzer.Keyword.FINALLY,
  "for": analyzer.Keyword.FOR,
  "if": analyzer.Keyword.IF,
  "in": analyzer.Keyword.IN,
  "new": analyzer.Keyword.NEW,
  "null": analyzer.Keyword.NULL,
  "rethrow": analyzer.Keyword.RETHROW,
  "return": analyzer.Keyword.RETURN,
  "super": analyzer.Keyword.SUPER,
  "switch": analyzer.Keyword.SWITCH,
  "this": analyzer.Keyword.THIS,
  "throw": analyzer.Keyword.THROW,
  "true": analyzer.Keyword.TRUE,
  "try": analyzer.Keyword.TRY,
  "var": analyzer.Keyword.VAR,
  "void": analyzer.Keyword.VOID,
  "while": analyzer.Keyword.WHILE,
  "with": analyzer.Keyword.WITH,
  "is": analyzer.Keyword.IS,
  "abstract": analyzer.Keyword.ABSTRACT,
  "as": analyzer.Keyword.AS,
  "covariant": analyzer.Keyword.COVARIANT,
  "dynamic": analyzer.Keyword.DYNAMIC,
  "export": analyzer.Keyword.EXPORT,
  "external": analyzer.Keyword.EXTERNAL,
  "factory": analyzer.Keyword.FACTORY,
  "get": analyzer.Keyword.GET,
  "implements": analyzer.Keyword.IMPLEMENTS,
  "import": analyzer.Keyword.IMPORT,
  "library": analyzer.Keyword.LIBRARY,
  "operator": analyzer.Keyword.OPERATOR,
  "part": analyzer.Keyword.PART,
  "set": analyzer.Keyword.SET,
  "static": analyzer.Keyword.STATIC,
  "typedef": analyzer.Keyword.TYPEDEF,
  "deferred": analyzer.Keyword.DEFERRED,
};

TokenType getTokenType(Token token) {
  switch (token.kind) {
    case EOF_TOKEN: return TokenType.EOF;
    case DOUBLE_TOKEN: return TokenType.DOUBLE;
    case HEXADECIMAL_TOKEN: return TokenType.HEXADECIMAL;
    case IDENTIFIER_TOKEN: return TokenType.IDENTIFIER;
    case INT_TOKEN: return TokenType.INT;
    case KEYWORD_TOKEN: return TokenType.KEYWORD;
    // case MULTI_LINE_COMMENT_TOKEN: return TokenType.MULTI_LINE_COMMENT;
    // case SCRIPT_TAG_TOKEN: return TokenType.SCRIPT_TAG;
    // case SINGLE_LINE_COMMENT_TOKEN: return TokenType.SINGLE_LINE_COMMENT;
    case STRING_TOKEN: return TokenType.STRING;
    case AMPERSAND_TOKEN: return TokenType.AMPERSAND;
    case AMPERSAND_AMPERSAND_TOKEN: return TokenType.AMPERSAND_AMPERSAND;
    // case AMPERSAND_AMPERSAND_EQ_TOKEN:
    //   return TokenType.AMPERSAND_AMPERSAND_EQ;
    case AMPERSAND_EQ_TOKEN: return TokenType.AMPERSAND_EQ;
    case AT_TOKEN: return TokenType.AT;
    case BANG_TOKEN: return TokenType.BANG;
    case BANG_EQ_TOKEN: return TokenType.BANG_EQ;
    case BAR_TOKEN: return TokenType.BAR;
    case BAR_BAR_TOKEN: return TokenType.BAR_BAR;
    // case BAR_BAR_EQ_TOKEN: return TokenType.BAR_BAR_EQ;
    case BAR_EQ_TOKEN: return TokenType.BAR_EQ;
    case COLON_TOKEN: return TokenType.COLON;
    case COMMA_TOKEN: return TokenType.COMMA;
    case CARET_TOKEN: return TokenType.CARET;
    case CARET_EQ_TOKEN: return TokenType.CARET_EQ;
    case CLOSE_CURLY_BRACKET_TOKEN: return TokenType.CLOSE_CURLY_BRACKET;
    case CLOSE_PAREN_TOKEN: return TokenType.CLOSE_PAREN;
    case CLOSE_SQUARE_BRACKET_TOKEN: return TokenType.CLOSE_SQUARE_BRACKET;
    case EQ_TOKEN: return TokenType.EQ;
    case EQ_EQ_TOKEN: return TokenType.EQ_EQ;
    case FUNCTION_TOKEN: return TokenType.FUNCTION;
    case GT_TOKEN: return TokenType.GT;
    case GT_EQ_TOKEN: return TokenType.GT_EQ;
    case GT_GT_TOKEN: return TokenType.GT_GT;
    case GT_GT_EQ_TOKEN: return TokenType.GT_GT_EQ;
    case HASH_TOKEN: return TokenType.HASH;
    case INDEX_TOKEN: return TokenType.INDEX;
    case INDEX_EQ_TOKEN: return TokenType.INDEX_EQ;
    // case IS_TOKEN: return TokenType.IS;
    case LT_TOKEN: return TokenType.LT;
    case LT_EQ_TOKEN: return TokenType.LT_EQ;
    case LT_LT_TOKEN: return TokenType.LT_LT;
    case LT_LT_EQ_TOKEN: return TokenType.LT_LT_EQ;
    case MINUS_TOKEN: return TokenType.MINUS;
    case MINUS_EQ_TOKEN: return TokenType.MINUS_EQ;
    case MINUS_MINUS_TOKEN: return TokenType.MINUS_MINUS;
    case OPEN_CURLY_BRACKET_TOKEN: return TokenType.OPEN_CURLY_BRACKET;
    case OPEN_PAREN_TOKEN: return TokenType.OPEN_PAREN;
    case OPEN_SQUARE_BRACKET_TOKEN: return TokenType.OPEN_SQUARE_BRACKET;
    case PERCENT_TOKEN: return TokenType.PERCENT;
    case PERCENT_EQ_TOKEN: return TokenType.PERCENT_EQ;
    case PERIOD_TOKEN: return TokenType.PERIOD;
    case PERIOD_PERIOD_TOKEN: return TokenType.PERIOD_PERIOD;
    case PLUS_TOKEN: return TokenType.PLUS;
    case PLUS_EQ_TOKEN: return TokenType.PLUS_EQ;
    case PLUS_PLUS_TOKEN: return TokenType.PLUS_PLUS;
    case QUESTION_TOKEN: return TokenType.QUESTION;
    case QUESTION_PERIOD_TOKEN: return TokenType.QUESTION_PERIOD;
    case QUESTION_QUESTION_TOKEN: return TokenType.QUESTION_QUESTION;
    case QUESTION_QUESTION_EQ_TOKEN: return TokenType.QUESTION_QUESTION_EQ;
    case SEMICOLON_TOKEN: return TokenType.SEMICOLON;
    case SLASH_TOKEN: return TokenType.SLASH;
    case SLASH_EQ_TOKEN: return TokenType.SLASH_EQ;
    case STAR_TOKEN: return TokenType.STAR;
    case STAR_EQ_TOKEN: return TokenType.STAR_EQ;
    case STRING_INTERPOLATION_TOKEN:
      return TokenType.STRING_INTERPOLATION_EXPRESSION;
    case STRING_INTERPOLATION_IDENTIFIER_TOKEN:
      return TokenType.STRING_INTERPOLATION_IDENTIFIER;
    case TILDE_TOKEN: return TokenType.TILDE;
    case TILDE_SLASH_TOKEN: return TokenType.TILDE_SLASH;
    case TILDE_SLASH_EQ_TOKEN: return TokenType.TILDE_SLASH_EQ;
    case BACKPING_TOKEN: return TokenType.BACKPING;
    case BACKSLASH_TOKEN: return TokenType.BACKSLASH;
    case PERIOD_PERIOD_PERIOD_TOKEN: return TokenType.PERIOD_PERIOD_PERIOD;
    // case GENERIC_METHOD_TYPE_LIST_TOKEN:
    //   return TokenType.GENERIC_METHOD_TYPE_LIST;
    // case GENERIC_METHOD_TYPE_ASSIGN_TOKEN:
    //   return TokenType.GENERIC_METHOD_TYPE_ASSIGN;
    default:
      return internalError("Unhandled token ${token.info}");
  }
}
