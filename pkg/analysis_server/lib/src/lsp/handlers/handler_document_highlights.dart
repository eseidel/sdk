// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/lsp_protocol/protocol.dart';
import 'package:analysis_server/src/domains/analysis/occurrences.dart';
import 'package:analysis_server/src/domains/analysis/occurrences_dart.dart';
import 'package:analysis_server/src/lsp/handlers/handlers.dart';
import 'package:analysis_server/src/lsp/mapping.dart';
import 'package:analysis_server/src/lsp/registration/feature_registration.dart';

typedef StaticOptions = Either2<bool, DocumentHighlightOptions>;

class DocumentHighlightsHandler extends SharedMessageHandler<
    TextDocumentPositionParams, List<DocumentHighlight>?> {
  DocumentHighlightsHandler(super.server);
  @override
  Method get handlesMessage => Method.textDocument_documentHighlight;

  @override
  LspJsonHandler<TextDocumentPositionParams> get jsonHandler =>
      TextDocumentPositionParams.jsonHandler;

  @override
  Future<ErrorOr<List<DocumentHighlight>?>> handle(
      TextDocumentPositionParams params,
      MessageInfo message,
      CancellationToken token) async {
    if (!isDartDocument(params.textDocument)) {
      return success(const []);
    }

    final pos = params.position;
    final path = pathOfDoc(params.textDocument);
    final unit = await path.mapResult(requireResolvedUnit);
    final offset = await unit.mapResult((unit) => toOffset(unit.lineInfo, pos));

    return offset.mapResult((requestedOffset) {
      final collector = OccurrencesCollectorImpl();
      addDartOccurrences(collector, unit.result.unit);

      // Find an occurrence that has an instance that spans the position.
      for (final occurrence in collector.allOccurrences) {
        bool spansRequestedPosition(int offset) {
          return offset <= requestedOffset &&
              offset + occurrence.length >= requestedOffset;
        }

        if (occurrence.offsets.any(spansRequestedPosition)) {
          return success(toHighlights(unit.result.lineInfo, occurrence));
        }
      }

      // No matches.
      return success(null);
    });
  }
}

class DocumentHighlightsRegistrations extends FeatureRegistration
    with SingleDynamicRegistration, StaticRegistration<StaticOptions> {
  DocumentHighlightsRegistrations(super.info);

  @override
  ToJsonable? get options =>
      TextDocumentRegistrationOptions(documentSelector: fullySupportedTypes);

  @override
  Method get registrationMethod => Method.textDocument_documentHighlight;

  @override
  StaticOptions get staticOptions => Either2.t1(true);

  @override
  bool get supportsDynamic => clientDynamic.documentHighlights;
}
