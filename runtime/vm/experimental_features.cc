// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// NOTE: THIS FILE IS GENERATED. DO NOT EDIT.
//
// Instead modify 'tools/experimental_features.yaml' and run
// 'dart tools/generate_experimental_flags.dart' to update.
//
// Current version: 3.0.0

#include "vm/experimental_features.h"

#include <cstring>
#include "platform/assert.h"
#include "vm/globals.h"

namespace dart {

bool GetExperimentalFeatureDefault(ExperimentalFeature feature) {
  constexpr bool kFeatureValues[] = {
      true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true,
  };
  ASSERT(static_cast<size_t>(feature) < ARRAY_SIZE(kFeatureValues));
  return kFeatureValues[static_cast<int>(feature)];
}

const char* GetExperimentalFeatureName(ExperimentalFeature feature) {
  constexpr const char* kFeatureNames[] = {
      "nonfunction-type-aliases",
      "non-nullable",
      "extension-methods",
      "constant-update-2018",
      "control-flow-collections",
      "generic-metadata",
      "set-literals",
      "spread-collections",
      "triple-shift",
      "constructor-tearoffs",
      "enhanced-enums",
      "named-arguments-anywhere",
      "super-parameters",
      "inference-update-1",
      "unnamed-libraries",
  };
  ASSERT(static_cast<size_t>(feature) < ARRAY_SIZE(kFeatureNames));
  return kFeatureNames[static_cast<int>(feature)];
}

}  // namespace dart
