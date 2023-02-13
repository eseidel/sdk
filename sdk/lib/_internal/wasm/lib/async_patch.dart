// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Machinery for async and await.
//
// The implementation is based on two mechanisms in the JS Promise integration:
//
// The export wrapper: Allocates a new stack and calls the wrapped export on the
// new stack, passing a suspender object as an extra first argument that
// represents the new stack.
//
// The import wrapper: Takes a suspender object as an extra first argument and
// calls the wrapped import. If the wrapped import returns a `Promise`, the
// current stack is suspended, and the `Promise` is forwarded to the
// corresponding call of the export wrapper, where execution resumes on the
// original stack. When the `Promise` is resolved, execution resumes on the
// suspended stack, with the call to the import wrapper returning the value the
// `Promise` was resolved with.
//
// The call sequence when calling an async function is:
//
// Caller
//  -> Outer (function specific, generated by `generateAsyncWrapper`)
//  -> `_asyncHelper`
//  -> `_callAsyncBridge` (imported JS function)
//  -> `_asyncBridge` (via the Promise integration export wrapper)
//  -> `_asyncBridge2` (intrinsic function)
//  -> Stub (function specific, generated by `generateAsyncWrapper`)
//  -> Inner (contains implementation, generated from async inner reference)
//
// The call sequence on await is:
//
// Function containing await
//  -> `_awaitHelper`
//  -> `_futurePromise` (via the Promise integration import wrapper)
//  -> `new Promise`
//  -> `Promise` constructor callback
//  -> `_awaitCallback`
//  -> `Future.then`
// `futurePromise` returns the newly created `Promise`, suspending the
// current execution.
//
// When the `Future` completes:
//
// `Future.then` callback
//  -> `_callResolve` (imported JS function)
//  -> `Promise` resolve function
// Resolving the `Promise` causes the suspended execution to resume.

import 'dart:_internal' show patch, scheduleCallback, unsafeCastOpaque;
import 'dart:_js_helper' show JS;

import 'dart:wasm';

part 'timer_patch.dart';

@pragma("wasm:entry-point")
Future<T> _asyncHelper<T>(WasmStructRef args) {
  Completer<T> completer = Completer();
  _callAsyncBridge(args, completer);
  return completer.future;
}

void _callAsyncBridge(WasmStructRef args, Completer<Object?> completer) =>
    // This trampoline is needed because [asyncBridge] is a function wrapped
    // by `returnPromiseOnSuspend`, and the stack-switching functionality of
    // that wrapper is implemented as part of the export adapter.
    JS<void>(
        "(args, completer) => asyncBridge(args, completer)", args, completer);

@pragma("wasm:export", "\$asyncBridge")
WasmAnyRef? _asyncBridge(
    WasmExternRef? stack, WasmStructRef args, Completer<Object?> completer) {
  try {
    Object? result = _asyncBridge2(args, stack);
    completer.complete(result);
  } catch (e, s) {
    completer.completeError(e, s);
  }
}

external Object? _asyncBridge2(WasmStructRef args, WasmExternRef? stack);

class _FutureError {
  final Object exception;
  final StackTrace stackTrace;

  _FutureError(this.exception, this.stackTrace);
}

@pragma("wasm:entry-point")
Object? _awaitHelper(Object? operand, WasmExternRef? stack) {
  // Save the existing zone in a local, and restore('_leave') upon returning. We
  // ensure that the zone will be restored in the event of an exception by
  // restoring the original zone before we throw the exception.
  _Zone current = Zone._current;
  if (operand is! Future) return operand;
  Object? result = _futurePromise(stack, operand);
  Zone._leave(current);
  if (result is _FutureError) {
    // TODO(joshualitt): `result.stackTrace` is not currently the complete stack
    // trace. We might be able to stitch together `result.stackTrace` with
    // `StackTrace.current`, but we would need to be able to handle the case
    // where `result.stackTrace` is supplied by the user and must then be exact.
    // Alternatively, we may be able to fix this when we actually generate stack
    // traces.
    Error.throwWithStackTrace(result.exception, result.stackTrace);
  }
  return result;
}

Object? _futurePromise(WasmExternRef? stack, Future<Object?> future) =>
    JS<Object?>("""new WebAssembly.Function(
            {parameters: ['externref', 'externref'], results: ['externref']},
            function(future) {
                return new Promise(function (resolve, reject) {
                    dartInstance.exports.\$awaitCallback(future, resolve);
                });
            },
            {suspending: 'first'})""", stack, future);

@pragma("wasm:export", "\$awaitCallback")
void _awaitCallback(Future<Object?> future, WasmExternRef? resolve) {
  future.then((value) {
    _callResolve(resolve, value);
  }, onError: (exception, stackTrace) {
    _callResolve(resolve, _FutureError(exception, stackTrace));
  });
}

void _callResolve(WasmExternRef? resolve, Object? result) =>
    // This trampoline is needed because [resolve] is a JS function that
    // can't be called directly from Wasm.
    JS<void>("(resolve, result) =>  resolve(result)", resolve, result);
