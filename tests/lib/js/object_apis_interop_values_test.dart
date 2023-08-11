// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library js_interop_test;

import 'package:expect/expect.dart';
import 'package:js/js.dart';

import 'object_apis_utils.dart';

@JS()
external dynamic eval(String code);

@JS()
class JavaScriptClass {
  external factory JavaScriptClass();
  external int get instanceGetter;
}

void main() {
  // Install a class that is accessible through interop.
  eval('''
self.JavaScriptClass = class JavaScriptClass {
  constructor() {}
  get instanceGetter() { return 42; }
}
''');
  var instanceOfClass = JavaScriptClass();
  var other = JavaScriptClass();
  Expect.equals(42, instanceOfClass.instanceGetter);
  testHashCode(instanceOfClass);
  testRuntimeType(instanceOfClass);
  testNoSuchMethod(instanceOfClass);
  testNoSuchMethodTearoff(instanceOfClass);
  testToString(instanceOfClass);
  testToStringTearoff(instanceOfClass);
  testEquals(instanceOfClass, other);

  var emptyObject = eval('Object.create({})');
  testHashCode(emptyObject);
  testRuntimeType(emptyObject);
  testNoSuchMethod(emptyObject);
  testNoSuchMethodTearoff(emptyObject);
  testToString(emptyObject);
  testToStringTearoff(emptyObject);
  testEquals(emptyObject, other);

  var objectWithNoProto = eval('Object.create(null)');
  testHashCode(objectWithNoProto);
  testRuntimeType(objectWithNoProto);
  testNoSuchMethod(objectWithNoProto);
  testNoSuchMethodTearoff(objectWithNoProto);
  // These operations throwing is only testing for consistency, and does not
  // imply a choice for the desired behavior. This is simply the state of
  // JavaScript interop at the time this test was written.
  Expect.throws(() => objectWithNoProto.toString());
  Expect.throws(() {
    // DDC will fail at the point of the tearoff.
    var toStringTearoff = objectWithNoProto.toString;
    // Dart2js fails if you call the tearoff.
    toStringTearoff();
  });
  testEquals(objectWithNoProto, other);

  var jsNull = eval('null');
  testHashCode(jsNull);
  testRuntimeType(jsNull);
  testNoSuchMethod(jsNull);
  testNoSuchMethodTearoff(jsNull);
  testToString(jsNull);
  testToStringTearoff(jsNull);
  testEquals(jsNull, other);
}
