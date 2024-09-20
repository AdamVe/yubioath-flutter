/*
 * Copyright (C) 2022 Yubico.
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/message.dart';
import '../../app/models.dart';
import '../../app/shortcuts.dart';
import '../../app/views/action_list.dart';
import '../../app/views/app_failure_page.dart';
import '../../app/views/app_list_item.dart';
import '../../app/views/app_page.dart';
import '../../app/views/message_page.dart';
import '../../app/views/message_page_not_initialized.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../exception/no_data_exception.dart';
import '../../management/models.dart';
import '../../widgets/list_title.dart';
import '../features.dart' as features;
import '../models.dart';
import '../state.dart';
import 'actions.dart';
import 'add_secret_note_dialog.dart';
import 'key_actions.dart';
import 'pin_dialog.dart';
import 'pin_entry_form.dart';

List<Capability> _getCapabilities(YubiKeyData deviceData) => [
      Capability.fido2,
      if (deviceData.info.config.enabledCapabilities[Transport.usb]! &
              Capability.piv.value !=
          0)
        Capability.piv
    ];

class SecretNotesScreen extends ConsumerWidget {
  final YubiKeyData deviceData;

  const SecretNotesScreen(this.deviceData, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final capabilities = _getCapabilities(deviceData);
    return ref.watch(fidoStateProvider(deviceData.node.path)).when(
        loading: () => AppPage(
              title: l10n.s_secret_notes,
              capabilities: capabilities,
              centered: true,
              delayedContent: true,
              builder: (context, _) => const CircularProgressIndicator(),
            ),
        error: (error, _) {
          if (error is NoDataException) {
            return MessagePageNotInitialized(
              title: l10n.s_secret_notes,
              capabilities: capabilities,
            );
          }
          final enabled = deviceData
                  .info.config.enabledCapabilities[deviceData.node.transport] ??
              0;
          if (Capability.fido2.value & enabled == 0) {
            return MessagePage(
              title: l10n.s_secret_notes,
              capabilities: capabilities,
              header: l10n.s_fido_disabled,
              message: l10n.l_webauthn_req_fido2,
            );
          }

          return AppFailurePage(
            cause: error,
          );
        },
        data: (fidoState) {
          return fidoState.unlocked
              ? _FidoUnlockedPage(deviceData, fidoState)
              : _FidoLockedPage(deviceData, fidoState);
        });
  }
}

class _FidoLockedPage extends ConsumerWidget {
  final YubiKeyData deviceData;
  final FidoState state;

  const _FidoLockedPage(this.deviceData, this.state);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hasFeature = ref.watch(featureProvider);
    final hasActions = hasFeature(features.actions);

    final capabilities = [
      Capability.fido2,
      if (deviceData.info.config.enabledCapabilities[Transport.usb]! &
              Capability.piv.value !=
          0)
        Capability.piv
    ];

    if (!state.hasPin) {
      return MessagePage(
        actionsBuilder: (context, expanded) => [
          if (!expanded)
            ActionChip(
              label: Text(l10n.s_set_pin),
              onPressed: () async {
                await showBlurDialog(
                    context: context,
                    builder: (context) =>
                        FidoPinDialog(deviceData.node.path, state));
              },
              avatar: const Icon(Symbols.pin),
            )
        ],
        title: l10n.s_secret_notes,
        capabilities: capabilities,
        header: l10n.s_secret_notes_get_started,
        message: l10n.p_use_secret_note_desc,
        keyActionsBuilder: hasActions ? _buildActions : null,
        keyActionsBadge: fingerprintsShowActionsNotifier(state),
      );
    }

    if (state.forcePinChange) {
      return MessagePage(
        title: l10n.s_secret_notes,
        capabilities: capabilities,
        header: l10n.s_pin_change_required,
        message: l10n.l_pin_change_required_desc,
        keyActionsBuilder: hasActions ? _buildActions : null,
        keyActionsBadge: fingerprintsShowActionsNotifier(state),
        actionsBuilder: (context, expanded) => [
          if (!expanded)
            ActionChip(
              label: Text(l10n.s_change_pin),
              onPressed: () async {
                await showBlurDialog(
                    context: context,
                    builder: (context) =>
                        FidoPinDialog(deviceData.node.path, state));
              },
              avatar: const Icon(Symbols.pin),
            )
        ],
      );
    }

    return AppPage(
      title: l10n.s_secret_notes,
      capabilities: capabilities,
      keyActionsBuilder: hasActions ? _buildActions : null,
      builder: (context, _) => Column(
        children: [
          PinEntryForm(state, deviceData.node),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) =>
      secretNotesBuildActions(context, deviceData.node, state);
}

class _FidoUnlockedPage extends ConsumerStatefulWidget {
  final YubiKeyData deviceData;
  final FidoState state;

  _FidoUnlockedPage(this.deviceData, this.state)
      : super(key: ObjectKey(deviceData.node.path));

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _FidoUnlockedPageState();
}

class _FidoUnlockedPageState extends ConsumerState<_FidoUnlockedPage> {
  FidoSecretNote? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasFeature = ref.watch(featureProvider);
    final hasActions = hasFeature(features.actions);
    final capabilities = _getCapabilities(widget.deviceData);

    final data =
        ref.watch(secretNotesProvider(widget.deviceData.node.path)).asData;
    if (data == null) {
      return _buildLoadingPage(context, capabilities);
    }
    final secretNotes = data.value;
    if (secretNotes.isEmpty) {
      return MessagePage(
        actionsBuilder: (context, expanded) => [
          if (!expanded)
            ActionChip(
              label: Text(l10n.s_add_secret_note),
              onPressed: () async {
                await showBlurDialog(
                    context: context,
                    builder: (context) =>
                        AddSecretNoteDialog(widget.deviceData.node.path));
              },
              avatar: const Icon(Symbols.note_add),
            )
        ],
        title: l10n.s_secret_notes,
        capabilities: capabilities,
        header: l10n.s_secret_notes_get_started,
        message: l10n.l_add_secret_note,
        keyActionsBuilder: hasActions
            ? (context) => secretNotesBuildActions(
                context, widget.deviceData.node, widget.state)
            : null,
        keyActionsBadge: secretNotesShowActionsNotifier(widget.state),
      );
    }

    final secretNote = _selected;
    return FidoActions(
      devicePath: widget.deviceData.node.path,
      actions: (context) => {
        EscapeIntent: CallbackAction<EscapeIntent>(onInvoke: (intent) {
          if (_selected != null) {
            setState(() {
              _selected = null;
            });
          } else {
            Actions.invoke(context, intent);
          }
          return false;
        }),
        OpenIntent<FidoSecretNote>:
            CallbackAction<OpenIntent<FidoSecretNote>>(onInvoke: (intent) {
          return showBlurDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => const SizedBox() // TODO add dialog
              );
        }),
        if (hasFeature(features.secretNotesEdit))
          EditIntent<FidoSecretNote>:
              CallbackAction<EditIntent<FidoSecretNote>>(
                  onInvoke: (intent) async {
            final renamed =
                await (Actions.invoke(context, intent) as Future<dynamic>?);
            if (_selected == intent.target && renamed is FidoSecretNote) {
              setState(() {
                _selected = renamed;
              });
            }
            return renamed;
          }),
        if (hasFeature(features.secretNotesDelete))
          DeleteIntent<Fingerprint>:
              CallbackAction<DeleteIntent<FidoSecretNote>>(
                  onInvoke: (intent) async {
            final deleted =
                await (Actions.invoke(context, intent) as Future<dynamic>?);
            if (deleted == true && _selected == intent.target) {
              setState(() {
                _selected = null;
              });
            }
            return deleted;
          }),
      },
      builder: (context) => AppPage(
        title: l10n.s_secret_notes,
        capabilities: capabilities,
        detailViewBuilder: secretNote != null
            ? (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTitle(l10n.s_details),
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Card(
                        elevation: 0.0,
                        color: Theme.of(context).hoverColor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 24, horizontal: 16),
                          // TODO: Reuse from fingerprint_dialog
                          child: Column(
                            children: [
                              Text(
                                secretNote.content,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                                softWrap: true,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              const Icon(Symbols.note, size: 72),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ActionListSection.fromMenuActions(
                      context,
                      l10n.s_actions,
                      actions: buildSecretNoteActions(secretNote, l10n),
                    ),
                  ],
                )
            : null,
        keyActionsBuilder: hasActions
            ? (context) => secretNotesBuildActions(
                context, widget.deviceData.node, widget.state)
            : null,
        keyActionsBadge: fingerprintsShowActionsNotifier(widget.state),
        builder: (context, expanded) {
          // De-select if window is resized to be non-expanded.
          if (!expanded && _selected != null) {
            Timer.run(() {
              setState(() {
                _selected = null;
              });
            });
          }
          return Actions(
            actions: {
              if (expanded) ...{
                OpenIntent<FidoSecretNote>:
                    CallbackAction<OpenIntent<FidoSecretNote>>(
                        onInvoke: (intent) {
                  setState(() {
                    _selected = intent.target;
                  });
                  return null;
                }),
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: secretNotes
                      .map((fp) => _SecretNoteListItem(
                            fp,
                            expanded: expanded,
                            selected: fp == _selected,
                          ))
                      .toList()),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingPage(
          BuildContext context, List<Capability> capabilities) =>
      AppPage(
        title: AppLocalizations.of(context)!.s_secret_notes,
        capabilities: capabilities,
        centered: true,
        delayedContent: true,
        builder: (context, _) => const ColoredBox(
            color: Colors.yellow, child: CircularProgressIndicator()),
      );
}

class _SecretNoteListItem extends StatelessWidget {
  final FidoSecretNote secretNote;
  final bool selected;
  final bool expanded;

  const _SecretNoteListItem(this.secretNote,
      {required this.expanded, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AppListItem(
      secretNote,
      selected: selected,
      leading: CircleAvatar(
        foregroundColor: Theme.of(context).colorScheme.onSecondary,
        backgroundColor: Theme.of(context).colorScheme.secondary,
        child: const Icon(Symbols.note),
      ),
      title: secretNote.content,
      trailing: expanded
          ? null
          : OutlinedButton(
              onPressed: Actions.handler(context, OpenIntent(secretNote)),
              child: const Icon(Symbols.more_horiz),
            ),
      tapIntent: isDesktop && !expanded ? null : OpenIntent(secretNote),
      doubleTapIntent: isDesktop && !expanded ? OpenIntent(secretNote) : null,
      // buildPopupActions: (context) => (secretNote, AppLocalizations.of(context)!),
    );
  }
}
