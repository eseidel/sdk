// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macro/macro.dart';

@FunctionDefinitionMacro1()
/*member: topLevelFunction1:
augment void topLevelFunction1(int a, ) {
  return 42;
}*/
external void topLevelFunction1(int a);

@FunctionDefinitionMacro1()
/*member: topLevelFunction2:
augment void topLevelFunction2(int a, int b, ) {
  return 42;
}*/
external void topLevelFunction2(int a, int b);

@FunctionDefinitionMacro1()
/*member: topLevelFunction3:
augment void topLevelFunction3(int a, [int? b, ]) {
  return 42;
}*/
external void topLevelFunction3(int a, [int? b]);

@FunctionDefinitionMacro1()
/*member: topLevelFunction4:
augment void topLevelFunction4(int a, {int? b, int? c, }) {
  return 42;
}*/
external void topLevelFunction4(int a, {int? b, int? c});
