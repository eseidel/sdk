// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/handler/legacy/legacy_handler.dart';
import 'package:analysis_server/src/legacy_analysis_server.dart';
import 'package:analysis_server/src/plugin/plugin_manager.dart';
import 'package:analysis_server/src/provisional/completion/completion_core.dart';
import 'package:analysis_server/src/request_handler_mixin.dart';
import 'package:analysis_server/src/services/completion/completion_performance.dart';
import 'package:analysis_server/src/services/completion/dart/completion_manager.dart';
import 'package:analysis_server/src/services/completion/dart/fuzzy_filter_sort.dart';
import 'package:analysis_server/src/services/completion/dart/suggestion_builder.dart';
import 'package:analysis_server/src/services/completion/yaml/analysis_options_generator.dart';
import 'package:analysis_server/src/services/completion/yaml/fix_data_generator.dart';
import 'package:analysis_server/src/services/completion/yaml/pubspec_generator.dart';
import 'package:analysis_server/src/services/completion/yaml/yaml_completion_generator.dart';
import 'package:analyzer/src/util/file_paths.dart' as file_paths;
import 'package:analyzer/src/util/performance/operation_performance.dart';
import 'package:analyzer_plugin/protocol/protocol.dart' as plugin;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;

/// The handler for the `completion.getSuggestions2` request.
class CompletionGetSuggestions2Handler extends CompletionHandler
    with RequestHandlerMixin<LegacyAnalysisServer> {
  /// Initialize a newly created handler to be able to service requests for the
  /// [server].
  CompletionGetSuggestions2Handler(
      super.server, super.request, super.cancellationToken, super.performance);

  /// Compute completion results for the given request and append them to the
  /// stream. Clients should not call this method directly as it is
  /// automatically called when a client listens to the stream returned by
  /// [results]. Subclasses should override this method, append at least one
  /// result to the [controller], and close the controller stream once complete.
  Future<List<CompletionSuggestionBuilder>> computeSuggestions({
    required CompletionBudget budget,
    required OperationPerformanceImpl performance,
    required DartCompletionRequest request,
    Set<ElementKind>? includedElementKinds,
    Set<String>? includedElementNames,
    List<IncludedSuggestionRelevanceTag>? includedSuggestionRelevanceTags,
    NotImportedSuggestions? notImportedSuggestions,
    required bool useFilter,
  }) async {
    //
    // Allow plugins to start computing fixes.
    //
    var requestToPlugins = performance.run('askPlugins', (_) {
      return _sendRequestToPlugins(request);
    });

    //
    // Compute completions generated by server.
    //
    var suggestions = <CompletionSuggestionBuilder>[];
    await performance.runAsync('computeSuggestions', (performance) async {
      var manager = DartCompletionManager(
        budget: budget,
        includedElementKinds: includedElementKinds,
        includedElementNames: includedElementNames,
        includedSuggestionRelevanceTags: includedSuggestionRelevanceTags,
        notImportedSuggestions: notImportedSuggestions,
      );

      suggestions.addAll(
        await manager.computeSuggestions(
          request,
          performance,
          useFilter: useFilter,
        ),
      );
    });
    // TODO (danrubel) if request is obsolete (processAnalysisRequest returns
    // false) then send empty results

    //
    // Add the completions produced by plugins to the server-generated list.
    //
    if (requestToPlugins != null) {
      await performance.runAsync('waitForPlugins', (_) async {
        await _addPluginSuggestions(budget, requestToPlugins, suggestions);
      });
    }

    return suggestions;
  }

  /// Return the suggestions that should be presented in the YAML [file] at the
  /// given [offset].
  YamlCompletionResults computeYamlSuggestions(String file, int offset) {
    var provider = server.resourceProvider;
    var pathContext = provider.pathContext;
    if (file_paths.isAnalysisOptionsYaml(pathContext, file)) {
      var generator = AnalysisOptionsGenerator(provider);
      return generator.getSuggestions(file, offset);
    } else if (file_paths.isFixDataYaml(pathContext, file)) {
      var generator = FixDataGenerator(provider);
      return generator.getSuggestions(file, offset);
    } else if (file_paths.isPubspecYaml(pathContext, file)) {
      var generator = PubspecGenerator(provider, server.pubPackageService);
      return generator.getSuggestions(file, offset);
    }
    return const YamlCompletionResults.empty();
  }

  @override
  Future<void> handle() async {
    if (completionIsDisabled) {
      return;
    }

    var requestLatency = request.timeSinceRequest;
    var params = CompletionGetSuggestions2Params.fromRequest(request);
    var file = params.file;
    var offset = params.offset;

    var timeoutMilliseconds = params.timeout;
    var budget = CompletionBudget(
      timeoutMilliseconds != null
          ? Duration(milliseconds: timeoutMilliseconds)
          : server.completionState.budgetDuration,
    );

    var provider = server.resourceProvider;
    var pathContext = provider.pathContext;

    if (file.endsWith('.yaml')) {
      final suggestions = computeYamlSuggestions(file, offset);
      server.sendResponse(
        CompletionGetSuggestions2Result(
          suggestions.replacementOffset,
          suggestions.replacementLength,
          suggestions.suggestions,
          false,
        ).toResponse(request.id),
      );
      return;
    }

    if (!file_paths.isDart(pathContext, file)) {
      server.sendResponse(
        CompletionGetSuggestions2Result(offset, 0, [], false)
            .toResponse(request.id),
      );
      return;
    }

    await performance.runAsync(
      'request',
      (performance) async {
        var resolvedUnit = await performance.runAsync(
          'resolveForCompletion',
          (performance) {
            return server.resolveForCompletion(
              path: file,
              offset: offset,
              performance: performance,
            );
          },
        );
        if (resolvedUnit == null) {
          server.sendResponse(Response.fileNotAnalyzed(request, file));
          return;
        }

        if (offset < 0 || offset > resolvedUnit.content.length) {
          server.sendResponse(Response.invalidParameter(
              request,
              'params.offset',
              'Expected offset between 0 and source length inclusive,'
                  ' but found $offset'));
          return;
        }

        final completionPerformance = CompletionPerformance(
          performance: performance,
          path: file,
          requestLatency: requestLatency,
          content: resolvedUnit.content,
          offset: offset,
        );
        server.recentPerformance.completion.add(completionPerformance);

        var analysisSession = resolvedUnit.analysisSession;
        var enclosingNode = resolvedUnit.parsedUnit;

        var completionRequest = DartCompletionRequest(
          analysisSession: analysisSession,
          filePath: resolvedUnit.path,
          fileContent: resolvedUnit.content,
          unitElement: resolvedUnit.unitElement,
          enclosingNode: enclosingNode,
          offset: offset,
          dartdocDirectiveInfo:
              server.getDartdocDirectiveInfoForSession(analysisSession),
        );
        setNewRequest(completionRequest);

        var notImportedSuggestions = NotImportedSuggestions();
        var suggestionBuilders = <CompletionSuggestionBuilder>[];
        try {
          suggestionBuilders = await computeSuggestions(
            budget: budget,
            performance: performance,
            request: completionRequest,
            notImportedSuggestions: notImportedSuggestions,
            useFilter: true,
          );
        } on AbortCompletion {
          return server.sendResponse(
            CompletionGetSuggestions2Result(
              completionRequest.replacementOffset,
              completionRequest.replacementLength,
              [],
              true,
            ).toResponse(request.id),
          );
        }

        performance.run('filter', (performance) {
          performance.getDataInt('count').add(suggestionBuilders.length);
          suggestionBuilders = fuzzyFilterSort(
            pattern: completionRequest.targetPrefix,
            suggestions: suggestionBuilders,
          );
          performance.getDataInt('matchCount').add(suggestionBuilders.length);
        });

        var lengthRestricted =
            suggestionBuilders.take(params.maxResults).toList();
        completionPerformance.computedSuggestionCount =
            suggestionBuilders.length;
        completionPerformance.transmittedSuggestionCount =
            lengthRestricted.length;

        var suggestions = lengthRestricted.map((e) => e.build()).toList();

        var isIncomplete = notImportedSuggestions.isIncomplete ||
            lengthRestricted.length < suggestionBuilders.length;

        performance.run('sendResponse', (_) {
          sendResult(CompletionGetSuggestions2Result(
            completionRequest.replacementOffset,
            completionRequest.replacementLength,
            suggestions,
            isIncomplete,
          ));
        });
      },
    );
  }

  /// Send completion notification results.
  void sendCompletionNotification(
    String completionId,
    int replacementOffset,
    int replacementLength,
    List<CompletionSuggestion> results,
    String? libraryFile,
    List<IncludedSuggestionSet>? includedSuggestionSets,
    List<ElementKind>? includedElementKinds,
    List<IncludedSuggestionRelevanceTag>? includedSuggestionRelevanceTags,
  ) {
    server.sendNotification(
      CompletionResultsParams(
        completionId,
        replacementOffset,
        replacementLength,
        results,
        true,
        libraryFile: libraryFile,
        includedSuggestionSets: includedSuggestionSets,
        includedElementKinds: includedElementKinds,
        includedSuggestionRelevanceTags: includedSuggestionRelevanceTags,
      ).toNotification(),
    );
  }

  void setNewRequest(DartCompletionRequest request) {
    _abortCurrentRequest();
    server.completionState.currentRequest = request;
  }

  /// Abort the current completion request, if any.
  void _abortCurrentRequest() {
    var currentRequest = server.completionState.currentRequest;
    if (currentRequest != null) {
      currentRequest.abort();
      server.completionState.currentRequest = null;
    }
  }

  /// Add the completions produced by plugins to the server-generated list.
  Future<void> _addPluginSuggestions(
    CompletionBudget budget,
    _RequestToPlugins requestToPlugins,
    List<CompletionSuggestionBuilder> suggestionBuilders,
  ) async {
    var responses = await waitForResponses(
      requestToPlugins.futures,
      requestParameters: requestToPlugins.parameters,
      timeout: budget.left,
    );
    for (var response in responses) {
      var result = plugin.CompletionGetSuggestionsResult.fromResponse(response);
      if (result.results.isNotEmpty) {
        var completionRequest = requestToPlugins.completionRequest;
        if (completionRequest.replacementOffset != result.replacementOffset &&
            completionRequest.replacementLength != result.replacementLength) {
          server.instrumentationService
              .logError('Plugin completion-results dropped due to conflicting'
                  ' replacement offset/length: ${result.toJson()}');
          continue;
        }
        suggestionBuilders.addAll(
          result.results.map(
            (suggestion) => ValueCompletionSuggestionBuilder(suggestion),
          ),
        );
      }
    }
  }

  /// Send the completion request to plugins, so that they work in other
  /// isolates in parallel with the server isolate.
  _RequestToPlugins? _sendRequestToPlugins(
    DartCompletionRequest completionRequest,
  ) {
    var pluginRequestParameters = plugin.CompletionGetSuggestionsParams(
      completionRequest.path,
      completionRequest.offset,
    );

    return _RequestToPlugins(
      completionRequest: completionRequest,
      parameters: pluginRequestParameters,
      futures: AnalysisServer.supportsPlugins
          ? server.pluginManager.broadcastRequest(
              pluginRequestParameters,
              contextRoot: completionRequest.analysisContext.contextRoot,
            )
          : <PluginInfo, Future<plugin.Response>>{},
    );
  }
}

class _RequestToPlugins {
  final DartCompletionRequest completionRequest;
  final plugin.CompletionGetSuggestionsParams parameters;
  final Map<PluginInfo, Future<plugin.Response>> futures;

  _RequestToPlugins({
    required this.completionRequest,
    required this.parameters,
    required this.futures,
  });
}
