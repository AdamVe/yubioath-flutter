/*
 * Copyright (C) 2023 Yubico.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import '../app/features.dart';

final actions = fido.feature('actions');

final actionsPin = actions.feature('pin');
final actionsAddFingerprint = actions.feature('addFingerprint');
final actionsReset = actions.feature('reset');
final enableEnterpriseAttestation =
    actions.feature('enableEnterpriseAttestation');

final credentials = fido.feature('credentials');

final credentialsDelete = credentials.feature('delete');

final fingerprints = fido.feature('fingerprints');

final fingerprintsEdit = fingerprints.feature('edit');
final fingerprintsDelete = fingerprints.feature('delete');

final secretNotes = fido.feature('secretNotes');
final secretNotesEdit = secretNotes.feature('edit');
final secretNotesDelete = secretNotes.feature('delete');
