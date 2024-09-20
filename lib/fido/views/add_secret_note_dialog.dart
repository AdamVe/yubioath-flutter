/*
 * Copyright (C) 2022-2024 Yubico.
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

// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/logging.dart';
import '../../app/message.dart';
import '../../app/models.dart';
import '../../desktop/models.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_dialog.dart';
import '../state.dart';

final _log = Logger('fido.views.add_secret_note_dialog');

class AddSecretNoteDialog extends ConsumerStatefulWidget {
  final DevicePath devicePath;

  const AddSecretNoteDialog(this.devicePath, {super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _AddSecretNoteDialogState();
}

class _AddSecretNoteDialogState extends ConsumerState<AddSecretNoteDialog>
    with SingleTickerProviderStateMixin {
  late FocusNode _secretNoteFocus;
  String _content = '';

  @override
  void dispose() {
    _secretNoteFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _secretNoteFocus = FocusNode();
  }

  void _submit() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      _log.debug('Create new note with content: $_content');
      await ref
          .read(secretNotesProvider(widget.devicePath).notifier)
          .create(_content);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showMessage(context, l10n.s_secret_note_added);
    } catch (e) {
      final String errorMessage;
      // TODO: Make this cleaner than importing desktop specific RpcError.
      if (e is RpcError) {
        errorMessage = e.message;
      } else {
        errorMessage = e.toString();
      }
      showMessage(
        context,
        l10n.l_setting_name_failed(errorMessage),
        duration: const Duration(seconds: 4),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ResponsiveDialog(
      title: Text(l10n.s_add_secret_note),
      child: Padding(
        padding: const EdgeInsets.only(top: 0, bottom: 4, right: 18, left: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                  border:
                      Border.all(color: Theme.of(context).colorScheme.primary)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: AppTextField(
                  focusNode: _secretNoteFocus,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  minLines: 4,
                  onChanged: (newContent) => _content = newContent,
                ),
              ),
            )
          ]
              .map((e) => Padding(
                    child: e,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                  ))
              .toList(),
        ),
      ),
      onCancel: () {},
      actions: [
        TextButton(
          onPressed: _submit,
          child: Text(l10n.s_save),
        )
      ],
    );
  }
}
