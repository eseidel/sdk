// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

bool f<T>(T a) => a is T;

typedef bool F<R>(R a);

/*member: B.:hasThis*/
class B<S> {
  /*member: B.method:hasThis*/
  method() {
    return
        /*fields=[this],free=[this],hasThis*/
        () {
      F<S> c = f;
      return c;
    };
  }
}

main() {
  new B().method();
}
