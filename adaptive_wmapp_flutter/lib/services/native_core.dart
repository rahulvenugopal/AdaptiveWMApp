import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeCore {
  NativeCore._() {
    _lib = _openLibrary();

    // Original EEG EDF functions (backward compatible)
    _edfOpen = _lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, IntPtr, IntPtr),
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int, int)>(
        'tn_edf_open');
    _edfPush = _lib.lookupFunction<
        Bool Function(Pointer<Void>, Pointer<Double>, IntPtr),
        bool Function(Pointer<Void>, Pointer<Double>, int)>(
        'tn_edf_push_sample');
    _edfClose = _lib.lookupFunction<
        Bool Function(Pointer<Void>),
        bool Function(Pointer<Void>)>('tn_edf_close');

    // Extended function for custom channel labels (fNIRS, LSL EEG, etc.)
    _edfOpenWithLabels = _lib.lookupFunction<
        Pointer<Void> Function(
            Pointer<Utf8>,             // path
            Pointer<Utf8>,             // subject
            Pointer<Pointer<Utf8>>,    // channel_names array
            Pointer<Pointer<Utf8>>,    // physical_dims array
            Pointer<Pointer<Utf8>>,    // prefilter_strs array
            Pointer<Pointer<Utf8>>,    // transducer_strs array
            IntPtr,                    // channel_count
            IntPtr,                    // sample_rate
        ),
        Pointer<Void> Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Pointer<Utf8>>,
            Pointer<Pointer<Utf8>>,
            Pointer<Pointer<Utf8>>,
            Pointer<Pointer<Utf8>>,
            int,
            int,
        )>('tn_edf_open_with_labels');
  }

  static final NativeCore instance = NativeCore._();

  late final DynamicLibrary _lib;
  late final Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int, int) _edfOpen;
  late final bool Function(Pointer<Void>, Pointer<Double>, int) _edfPush;
  late final bool Function(Pointer<Void>) _edfClose;
  late final Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>,
    Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>,
    int, int,
  ) _edfOpenWithLabels;

  DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libangel_eeg_core.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        return DynamicLibrary.open('rust/target/debug/libangel_eeg_core.dylib');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('rust/target/debug/libangel_eeg_core.so');
    }
    return DynamicLibrary.process();
  }

  // ─── Original EEG EDF API ───────────────────────────────────────────────

  Pointer<Void> openEdf({
    required String path,
    required String subject,
    required int channelCount,
    required int sampleRate,
  }) {
    final pathPtr = path.toNativeUtf8();
    final subjectPtr = subject.toNativeUtf8();
    try {
      return _edfOpen(pathPtr, subjectPtr, channelCount, sampleRate);
    } finally {
      calloc.free(pathPtr);
      calloc.free(subjectPtr);
    }
  }

  // ─── Extended EDF API with custom channel labels ─────────────────────────

  Pointer<Void> openEdfWithLabels({
    required String path,
    required String subject,
    required List<String> channelNames,
    required List<String> physicalDims,
    required List<String> prefilters,
    required List<String> transducers,
    required int sampleRate,
  }) {
    final n = channelNames.length;
    final pathPtr = path.toNativeUtf8();
    final subjectPtr = subject.toNativeUtf8();

    // Allocate arrays of UTF8 string pointers
    final namesPtrs = _allocStringArray(channelNames);
    final dimsPtrs = _allocStringArray(physicalDims);
    final prefilterPtrs = _allocStringArray(prefilters);
    final transducerPtrs = _allocStringArray(transducers);

    try {
      return _edfOpenWithLabels(
        pathPtr, subjectPtr,
        namesPtrs, dimsPtrs, prefilterPtrs, transducerPtrs,
        n, sampleRate,
      );
    } finally {
      calloc.free(pathPtr);
      calloc.free(subjectPtr);
      _freeStringArray(namesPtrs, n);
      _freeStringArray(dimsPtrs, n);
      _freeStringArray(prefilterPtrs, n);
      _freeStringArray(transducerPtrs, n);
    }
  }

  // ─── Shared push/close ────────────────────────────────────────────────────

  bool pushEdfSample(Pointer<Void> writer, List<double> samples) {
    if (writer == nullptr) return false;
    final ptr = calloc<Double>(samples.length);
    try {
      for (var i = 0; i < samples.length; i++) {
        ptr[i] = samples[i];
      }
      return _edfPush(writer, ptr, samples.length);
    } finally {
      calloc.free(ptr);
    }
  }

  bool closeEdf(Pointer<Void> writer) {
    if (writer == nullptr) return false;
    return _edfClose(writer);
  }

  // ─── Helper: allocate a native array of UTF-8 string pointers ────────────

  Pointer<Pointer<Utf8>> _allocStringArray(List<String> strings) {
    final arr = calloc<Pointer<Utf8>>(strings.length);
    for (var i = 0; i < strings.length; i++) {
      arr[i] = strings[i].toNativeUtf8();
    }
    return arr;
  }

  void _freeStringArray(Pointer<Pointer<Utf8>> arr, int length) {
    for (var i = 0; i < length; i++) {
      calloc.free(arr[i]);
    }
    calloc.free(arr);
  }
}
