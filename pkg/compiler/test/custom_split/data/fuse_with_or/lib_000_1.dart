// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This file was autogenerated by the pkg/compiler/tool/graph_isomorphizer.dart.
import "package:expect/expect.dart";

import 'libImport.dart';

@pragma('dart2js:noInline')
/*member: g_000_1:member_unit=6{b4}*/
g_000_1() {
  Set<String> uniques = {};

  // f_***_1;
  f_000_1(uniques, 3);
  f_001_1(uniques, 3);
  f_010_1(uniques, 3);
  f_011_1(uniques, 3);
  f_100_1(uniques, 3);
  f_101_1(uniques, 3);
  f_110_1(uniques, 3);
  f_111_1(uniques, 3);
  Expect.equals(8, uniques.length);
}
