// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/code_style_options.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/error_processor.dart';
import 'package:analyzer/src/analysis_options/code_style_options.dart';
import 'package:analyzer/src/dart/analysis/experiments.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/utilities_general.dart';
import 'package:analyzer/src/lint/config.dart';
import 'package:analyzer/src/lint/registry.dart';
import 'package:analyzer/src/task/options.dart';
import 'package:analyzer/src/util/yaml.dart';
import 'package:yaml/yaml.dart';

/// Apply the options in the given [optionMap] to the given analysis
/// [options].
void applyToAnalysisOptions(AnalysisOptionsImpl options, YamlMap? optionMap) {
  if (optionMap == null) {
    return;
  }
  var analyzer = optionMap.valueAt(AnalyzerOptions.analyzer);
  if (analyzer is YamlMap) {
    // Process strong mode option.
    var strongMode = analyzer.valueAt(AnalyzerOptions.strongMode);
    options.applyStrongOptions(strongMode);

    // Process filters.
    var filters = analyzer.valueAt(AnalyzerOptions.errors);
    options.errorProcessors = ErrorConfig(filters).processors;

    // Process enabled experiments.
    var experimentNames = analyzer.valueAt(AnalyzerOptions.enableExperiment);
    if (experimentNames is YamlList) {
      var enabledExperiments = <String>[];
      for (var element in experimentNames.nodes) {
        var experimentName = element.stringValue;
        if (experimentName != null) {
          enabledExperiments.add(experimentName);
        }
      }
      options.contextFeatures = FeatureSet.fromEnableFlags2(
        sdkLanguageVersion: ExperimentStatus.currentVersion,
        flags: enabledExperiments,
      );
    }

    // Process optional checks options.
    var optionalChecks = analyzer.valueAt(AnalyzerOptions.optionalChecks);
    options.applyOptionalChecks(optionalChecks);

    // Process language options.
    var language = analyzer.valueAt(AnalyzerOptions.language);
    options.applyLanguageOptions(language);

    // Process excludes.
    var excludes = analyzer.valueAt(AnalyzerOptions.exclude);
    options.applyExcludes(excludes);

    var cannotIgnore = analyzer.valueAt(AnalyzerOptions.cannotIgnore);
    options.applyUnignorables(cannotIgnore);

    // Process plugins.
    var plugins = analyzer.valueAt(AnalyzerOptions.plugins);
    options.applyPlugins(plugins);
  }

  // Process the 'code-style' option.
  var codeStyle = optionMap.valueAt(AnalyzerOptions.codeStyle);
  options.codeStyleOptions = options.buildCodeStyleOptions(codeStyle);

  var config = parseConfig(optionMap);
  if (config != null) {
    var lintRules = Registry.ruleRegistry.enabled(config);
    if (lintRules.isNotEmpty) {
      options.lint = true;
      options.lintRules = lintRules.toList();
    }
  }
}

extension on YamlNode? {
  bool? get boolValue {
    var self = this;
    if (self is YamlScalar) {
      var value = self.value;
      if (value is bool) {
        return value;
      }
    }
    return null;
  }

  String? get stringValue {
    var self = this;
    if (self is YamlScalar) {
      var value = self.value;
      if (value is String) {
        return value;
      }
    }
    return null;
  }
}

extension on AnalysisOptionsImpl {
  void applyExcludes(YamlNode? excludes) {
    if (excludes is YamlList) {
      // TODO(srawlins): Report non-String items
      excludePatterns = excludes.whereType<String>().toList();
    }
    // TODO(srawlins): Report non-List with
    // AnalysisOptionsWarningCode.INVALID_SECTION_FORMAT.
  }

  void applyLanguageOptions(YamlNode? configs) {
    if (configs is! YamlMap) {
      return;
    }
    configs.nodes.forEach((key, value) {
      if (key is YamlScalar && value is YamlScalar) {
        var feature = key.value?.toString();
        var boolValue = value.boolValue;
        if (boolValue == null) {
          return;
        }

        if (feature == AnalyzerOptions.strictCasts) {
          strictCasts = boolValue;
        }
        if (feature == AnalyzerOptions.strictInference) {
          strictInference = boolValue;
        }
        if (feature == AnalyzerOptions.strictRawTypes) {
          strictRawTypes = boolValue;
        }
      }
    });
  }

  void applyOptionalChecks(YamlNode? config) {
    if (config is YamlMap) {
      config.nodes.forEach((k, v) {
        if (k is YamlScalar && v is YamlScalar) {
          var feature = k.value?.toString();
          var boolValue = v.boolValue;
          if (boolValue != null) {
            if (feature == AnalyzerOptions.chromeOsManifestChecks) {
              chromeOsManifestChecks = boolValue;
            }
          }
        }
      });
    } else if (config is YamlScalar) {
      if (config.value?.toString() == AnalyzerOptions.chromeOsManifestChecks) {
        chromeOsManifestChecks = true;
      }
    }
  }

  void applyPlugins(YamlNode? plugins) {
    var pluginName = plugins.stringValue;
    if (pluginName != null) {
      enabledPluginNames = [pluginName];
    } else if (plugins is YamlList) {
      for (var element in plugins.nodes) {
        var pluginName = element.stringValue;
        if (pluginName != null) {
          // Only the first plugin is supported.
          enabledPluginNames = [pluginName];
          return;
        }
      }
    } else if (plugins is YamlMap) {
      for (var key in plugins.nodes.keys.cast<YamlNode?>()) {
        var pluginName = key.stringValue;
        if (pluginName != null) {
          // Only the first plugin is supported.
          enabledPluginNames = [pluginName];
          return;
        }
      }
    }
  }

  void applyStrongOptions(YamlNode? config) {
    if (config is! YamlMap) {
      return;
    }
    config.nodes.forEach((k, v) {
      if (k is YamlScalar && v is YamlScalar) {
        var feature = k.value?.toString();
        var boolValue = v.boolValue;
        if (boolValue == null) {
          return;
        }

        if (feature == AnalyzerOptions.implicitCasts) {
          implicitCasts = boolValue;
        } else if (feature == AnalyzerOptions.implicitDynamic) {
          implicitDynamic = boolValue;
        } else if (feature == AnalyzerOptions.propagateLinterExceptions) {
          propagateLinterExceptions = boolValue;
        }
      }
    });
  }

  void applyUnignorables(YamlNode? cannotIgnore) {
    if (cannotIgnore is! YamlList) {
      return;
    }
    var names = <String>{};
    var stringValues = cannotIgnore.whereType<String>().toSet();
    for (var severity in AnalyzerOptions.severities) {
      if (stringValues.contains(severity)) {
        // [severity] is a marker denoting all error codes with severity
        // equal to [severity].
        stringValues.remove(severity);
        // Replace name like 'error' with error codes with this named
        // severity.
        for (var e in errorCodeValues) {
          // If the severity of [error] is also changed in this options file
          // to be [severity], we add [error] to the un-ignorable list.
          var processors =
              errorProcessors.where((processor) => processor.code == e.name);
          if (processors.isNotEmpty &&
              processors.first.severity?.displayName == severity) {
            names.add(e.name);
            continue;
          }
          // Otherwise, add [error] if its default severity is [severity].
          if (e.errorSeverity.displayName == severity) {
            names.add(e.name);
          }
        }
      }
    }
    names.addAll(stringValues.map((name) => name.toUpperCase()));
    unignorableNames = names;
  }

  CodeStyleOptions buildCodeStyleOptions(YamlNode? codeStyle) {
    var useFormatter = false;
    if (codeStyle is YamlMap) {
      var formatNode = codeStyle.valueAt(AnalyzerOptions.format);
      if (formatNode != null) {
        var formatValue = toBool(formatNode);
        if (formatValue is bool) {
          useFormatter = formatValue;
        }
      }
    }
    return CodeStyleOptionsImpl(this, useFormatter: useFormatter);
  }
}
