// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Static field used in tests below.
var field;

/// Static getter with no side effects. Used in tests below.
/*element: emptyGetter:SideEffects(reads nothing; writes nothing)*/
get emptyGetter => null;

/// Static getter with a single side effect of reading a static. Used in tests
/// below.
/*element: nonEmptyGetter:SideEffects(reads static; writes nothing)*/
get nonEmptyGetter => field;

/// Static method with no side effects. Used in tests below.
/*element: emptyMethod:SideEffects(reads nothing; writes nothing)*/
emptyMethod() {}

/// Static method with a single side effect of reading a static. Used in tests
/// below.
/*element: nonEmptyMethod:SideEffects(reads static; writes nothing)*/
nonEmptyMethod() => field;

/*element: Class.:SideEffects(reads nothing; writes nothing)*/
class Class {
  /// Instance field used in tests below.
  var field;

  /// Instance getter with no side effects. Used in tests below.
  /*element: Class.emptyGetter:SideEffects(reads nothing; writes nothing)*/
  get emptyGetter => null;

  /// Instance getter with a single side effect of reading a static. Used in
  /// tests below.
  /*element: Class.nonEmptyGetter:SideEffects(reads field; writes nothing)*/
  get nonEmptyGetter => field;

  /// Instance method with no side effects. Used in tests below.
  /*element: Class.emptyMethod:SideEffects(reads nothing; writes nothing)*/
  emptyMethod() {}

  /// Instance method with a single side effect of reading a static. Used in
  /// tests below.
  /*element: Class.nonEmptyMethod:SideEffects(reads field; writes nothing)*/
  nonEmptyMethod() => field;
}

/// Call an empty instance method. This propagates the side effects of the
/// instance method; here none.
/*element: callEmptyInstanceMethod:SideEffects(reads nothing; writes nothing)*/
callEmptyInstanceMethod(c) => c.emptyMethod();

/// Call an empty instance getter. This marks the method as having all side
/// effects.
/*element: callEmptyInstanceGetter:SideEffects(reads anything; writes anything)*/
callEmptyInstanceGetter(c) => c.emptyGetter();

/// Call a non-empty instance method. This propagates the side effects of the
/// instance method; here dependency of static properties.
/*element: callNonEmptyInstanceMethod:SideEffects(reads field; writes nothing)*/
callNonEmptyInstanceMethod(c) => c.nonEmptyMethod();

/// Call a non-empty instance getter. This marks the method as having all side
/// effects.
/*element: callNonEmptyInstanceGetter:SideEffects(reads anything; writes anything)*/
callNonEmptyInstanceGetter(c) => c.nonEmptyGetter();

/// Read an empty instance method. This propagates the side effects of the
/// instance method; here none.
/*element: readEmptyInstanceMethod:SideEffects(reads nothing; writes nothing)*/
readEmptyInstanceMethod(c) => c.emptyMethod;

/// Read an empty instance getter. This propagates the side effects of the
/// instance getter; here none.
/*element: readEmptyInstanceGetter:SideEffects(reads nothing; writes nothing)*/
readEmptyInstanceGetter(c) => c.emptyGetter;

/// Read a non-empty instance method. This propagates the side effects of the
/// instance method; here dependency of static properties.
/*element: readNonEmptyInstanceMethod:SideEffects(reads field; writes nothing)*/
readNonEmptyInstanceMethod(c) => c.nonEmptyMethod;

/// Read a non-empty instance getter. This propagates the side effects of the
/// instance getter; here dependency of static properties.
/*element: readNonEmptyInstanceGetter:SideEffects(reads field; writes nothing)*/
readNonEmptyInstanceGetter(c) => c.nonEmptyGetter;

/// Read an instance field. This adds dependency of instance properties to the
/// side effects of the method.
/*element: readInstanceField:SideEffects(reads field; writes nothing)*/
readInstanceField(c) => c.field;

/// Write to an instance field. This adds change of instance properties to the
/// side effects of the method.
/*element: writeInstanceField:SideEffects(reads nothing; writes field)*/
writeInstanceField(c) => c.field = 42;

/// Call an instance field. This marks the method as having all side effects.
/*element: callInstanceField:SideEffects(reads anything; writes anything)*/
callInstanceField(c) => c.field();

/// Read a static field. This adds dependency of static properties to the
/// side effects of the method.
/*element: readStaticField:SideEffects(reads static; writes nothing)*/
readStaticField() => field;

/// Write to a static field. This adds change of static properties to the
/// side effects of the method.
/*element: writeStaticField:SideEffects(reads nothing; writes static)*/
writeStaticField() => field = 42;

/// Call a static field. This marks the method as having all side effects.
/*element: callStaticField:SideEffects(reads anything; writes anything)*/
callStaticField() => field();

/// Read and write of a static field. This adds dependency of static properties
/// and change of static properties to the side effects of the method.
/*element: readAndWriteStaticField:SideEffects(reads static; writes static)*/
readAndWriteStaticField() {
  field = field;
}

/// Call an empty static method. This propagates the side effects of the
/// instance method; here none.
/*element: callEmptyStaticMethod:SideEffects(reads nothing; writes nothing)*/
callEmptyStaticMethod() => emptyMethod();

/// Call an empty static getter. This marks the method as having all side
/// effects.
/*element: callEmptyStaticGetter:SideEffects(reads anything; writes anything)*/
callEmptyStaticGetter() => emptyGetter();

/// Call a non-empty static method. This propagates the side effects of the
/// instance method; here dependency of static properties.
/*element: callNonEmptyStaticMethod:SideEffects(reads static; writes nothing)*/
callNonEmptyStaticMethod() => nonEmptyMethod();

/// Call a non-empty static getter. This marks the method as having all side
/// effects.
/*element: callNonEmptyStaticGetter:SideEffects(reads anything; writes anything)*/
callNonEmptyStaticGetter() => nonEmptyGetter();

/// Read an empty static method. This propagates the side effects of the
/// static method; here none.
/*element: readEmptyStaticMethod:SideEffects(reads nothing; writes nothing)*/
readEmptyStaticMethod() => emptyMethod;

/// Read an empty static getter. This propagates the side effects of the
/// static getter; here none.
/*element: readEmptyStaticGetter:SideEffects(reads nothing; writes nothing)*/
readEmptyStaticGetter() => emptyGetter;

/// Read a non-empty static method. This propagates the side effects of the
/// static method; here dependency of static properties.
/*element: readNonEmptyStaticMethod:SideEffects(reads static; writes nothing)*/
readNonEmptyStaticMethod() => nonEmptyMethod;

/// Read a non-empty static getter. This propagates the side effects of the
/// static getter; here dependency of static properties.
/*element: readNonEmptyStaticGetter:SideEffects(reads static; writes nothing)*/
readNonEmptyStaticGetter() => nonEmptyGetter;

/// Call a static method that reads an instance field. This propagates the side
/// effects of the static method; here dependency of instance properties.
/*element: callingReadInstanceField:SideEffects(reads field; writes nothing)*/
callingReadInstanceField(c) => readInstanceField(c);

/// Call a static method that writes to an instance field. This propagates the
/// side effects of the static method; here change of instance properties.
/*element: callingWriteInstanceField:SideEffects(reads nothing; writes field)*/
callingWriteInstanceField(c) => writeInstanceField(c);

/// Call a static method that calls an instance field. This propagates the side
/// effects of the static method; here all side-effects.
/*element: callingCallInstanceField:SideEffects(reads anything; writes anything)*/
callingCallInstanceField(c) => callInstanceField(c);

/// Call a static method that reads a static field. This propagates the side
/// effects of the static method; here dependency of static properties.
/*element: callingReadStaticField:SideEffects(reads static; writes nothing)*/
callingReadStaticField() => readStaticField();

/// Call a static method that writes to a static field. This propagates the
/// side effects of the static method; here change of static properties.
/*element: callingWriteStaticField:SideEffects(reads nothing; writes static)*/
callingWriteStaticField() => writeStaticField();

/// Call a static method that calls a static field. This propagates the side
/// effects of the static method; here all side-effects.
/*element: callingCallStaticField:SideEffects(reads anything; writes anything)*/
callingCallStaticField() => callStaticField();

/*element: main:SideEffects(reads anything; writes anything)*/
main() {
  var c = new Class();

  callEmptyInstanceMethod(c);
  callEmptyInstanceGetter(c);
  callNonEmptyInstanceMethod(c);
  callNonEmptyInstanceGetter(c);

  readEmptyInstanceMethod(c);
  readEmptyInstanceGetter(c);
  readNonEmptyInstanceMethod(c);
  readNonEmptyInstanceGetter(c);

  readInstanceField(c);
  writeInstanceField(c);
  callInstanceField(c);

  callEmptyStaticMethod();
  callEmptyStaticGetter();
  callNonEmptyStaticMethod();
  callNonEmptyStaticGetter();

  readEmptyStaticMethod();
  readEmptyStaticGetter();
  readNonEmptyStaticMethod();
  readNonEmptyStaticGetter();

  readStaticField();
  writeStaticField();
  callStaticField();
  readAndWriteStaticField();

  callingReadInstanceField(c);
  callingWriteInstanceField(c);
  callingCallInstanceField(c);

  callingReadStaticField();
  callingWriteStaticField();
  callingCallStaticField();
}
