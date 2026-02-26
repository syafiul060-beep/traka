// ignore_for_file: require_trailing_commas
// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library;

// TODO(Lyokone): remove once we bump Flutter SDK min version to 3.3
// ignore: unnecessary_import

// import 'package:flutter/foundation.dart';


export 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebaseException;
export 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart'
    show
        ListOptions,
        FullMetadata,
        SettableMetadata,
        PutStringFormat,
        TaskState;

part 'src/firebase_storage.dart';
part 'src/list_result.dart';
part 'src/reference.dart';
part 'src/task.dart';
part 'src/task_snapshot.dart';
